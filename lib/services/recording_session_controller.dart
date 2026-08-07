import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import '../models/polar_sample.dart';
import '../models/session_metadata.dart';
import '../utils/monotonic_clock.dart';
import 'camera_service.dart';
import 'permissions_service.dart';
import 'polar_service.dart';
import 'session_storage_service.dart';

enum RecordingPhase {
  idle,
  preparing,
  recording,
  saving,
  completed,
  cancelled,
  error,
}

class RecordingUiState {
  final RecordingPhase phase;
  final int remainingSeconds;
  final double progress;
  final String? errorMessage;
  final SessionMetadata? completedMetadata;
  final String? completedDirectory;
  final bool faceDetected;
  final int? heartRate;

  const RecordingUiState({
    this.phase = RecordingPhase.idle,
    this.remainingSeconds = 30,
    this.progress = 0,
    this.errorMessage,
    this.completedMetadata,
    this.completedDirectory,
    this.faceDetected = false,
    this.heartRate,
  });

  RecordingUiState copyWith({
    RecordingPhase? phase,
    int? remainingSeconds,
    double? progress,
    String? errorMessage,
    SessionMetadata? completedMetadata,
    String? completedDirectory,
    bool? faceDetected,
    int? heartRate,
    bool clearError = false,
  }) {
    return RecordingUiState(
      phase: phase ?? this.phase,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      completedMetadata: completedMetadata ?? this.completedMetadata,
      completedDirectory: completedDirectory ?? this.completedDirectory,
      faceDetected: faceDetected ?? this.faceDetected,
      heartRate: heartRate ?? this.heartRate,
    );
  }
}

/// Orchestrates synchronized 30s video + Polar recording.
class RecordingSessionController {
  RecordingSessionController({
    required this.polarService,
    required this.cameraService,
    required this.storage,
  });

  final PolarService polarService;
  final CameraService cameraService;
  final SessionStorageService storage;

  static const recordingDuration = Duration(seconds: 30);

  final _stateController = StreamController<RecordingUiState>.broadcast();
  RecordingUiState _state = const RecordingUiState();

  Timer? _countdownTimer;
  DateTime? _startUtc;
  int? _startMonotonicMs;
  String? _subjectId;
  String? _notes;
  Directory? _sessionDir;
  String? _folderName;

  Stream<RecordingUiState> get stateStream async* {
    yield _state;
    yield* _stateController.stream;
  }

  RecordingUiState get state => _state;

  void _emit(RecordingUiState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  Future<void> prepareCamera() async {
    await AppPermissions.ensureCameraPermissions();
    await cameraService.initialize();
  }

  /// Starts a fixed 30-second synchronized recording session.
  Future<void> startSession({
    required String subjectId,
    String? notes,
  }) async {
    if (_state.phase == RecordingPhase.recording ||
        _state.phase == RecordingPhase.saving) {
      return;
    }

    if (!polarService.state.isStreaming) {
      _emit(
        _state.copyWith(
          phase: RecordingPhase.error,
          errorMessage: 'Polar H10 must be connected and streaming',
        ),
      );
      return;
    }

    if (!cameraService.isInitialized) {
      _emit(
        _state.copyWith(
          phase: RecordingPhase.error,
          errorMessage: 'Camera is not ready',
        ),
      );
      return;
    }

    _subjectId = subjectId.trim().isEmpty ? 'unknown' : subjectId.trim();
    _notes = notes?.trim().isEmpty == true ? null : notes?.trim();

    _emit(
      _state.copyWith(
        phase: RecordingPhase.preparing,
        remainingSeconds: recordingDuration.inSeconds,
        progress: 0,
        clearError: true,
        faceDetected: cameraService.faceState.detected,
        heartRate: polarService.state.heartRate,
      ),
    );

    try {
      _startUtc = DateTime.now().toUtc();
      _startMonotonicMs = MonotonicClock.nowMs();
      _folderName = storage.buildFolderName(
        startUtc: _startUtc!,
        subjectId: _subjectId!,
      );
      _sessionDir = await storage.createSessionDirectory(_folderName!);

      // Capture face presence at the sync point before video encode starts
      // (camera plugin cannot run image-stream analysis during video recording).
      final faceAtStart = cameraService.faceState.detected;
      cameraService.beginFaceEventBuffer(startMonotonicMs: _startMonotonicMs!);
      // Seed one face event at t≈0 for alignment / quality checks.
      cameraService.seedFaceEvent(
        FaceTrackingEvent(
          timestampMs: 0,
          faceDetected: faceAtStart,
          faceCount: faceAtStart ? 1 : 0,
        ),
      );

      // Sync point: start buffering Polar, then video.
      polarService.beginRecordingBuffer(startMonotonicMs: _startMonotonicMs!);
      await cameraService.startVideoRecording();

      await _hapticStart();

      _emit(
        _state.copyWith(
          phase: RecordingPhase.recording,
          remainingSeconds: recordingDuration.inSeconds,
          progress: 0,
          faceDetected: faceAtStart,
          heartRate: polarService.state.heartRate,
        ),
      );

      _startCountdown();
    } catch (e) {
      polarService.discardRecordingBuffer();
      cameraService.endFaceEventBuffer();
      _emit(
        _state.copyWith(
          phase: RecordingPhase.error,
          errorMessage: 'Failed to start recording: $e',
        ),
      );
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    final totalMs = recordingDuration.inMilliseconds;
    final startedAt = DateTime.now();

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) async {
      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final remainingMs = (totalMs - elapsed).clamp(0, totalMs);
      final remainingSec = (remainingMs / 1000).ceil();
      final progress = (elapsed / totalMs).clamp(0.0, 1.0);

      _emit(
        _state.copyWith(
          remainingSeconds: remainingSec,
          progress: progress,
          heartRate: polarService.state.heartRate,
          // During video encode, face stream is paused — keep last known.
          faceDetected: cameraService.faceState.detected,
        ),
      );

      if (elapsed >= totalMs) {
        timer.cancel();
        await _finish(cancelled: false);
      }
    });
  }

  Future<void> cancelSession() async {
    if (_state.phase != RecordingPhase.recording &&
        _state.phase != RecordingPhase.preparing) {
      return;
    }
    _countdownTimer?.cancel();
    await _finish(cancelled: true);
  }

  Future<void> _finish({required bool cancelled}) async {
    _countdownTimer?.cancel();
    _emit(_state.copyWith(phase: RecordingPhase.saving));

    try {
      final endUtc = DateTime.now().toUtc();
      final endMonotonic = MonotonicClock.nowMs();

      XFilePath? videoPath;
      if (cancelled) {
        await cameraService.cancelVideoRecording();
        polarService.discardRecordingBuffer();
        cameraService.endFaceEventBuffer();
      } else {
        final video = await cameraService.stopVideoRecording();
        videoPath = video == null ? null : XFilePath(video.path);
      }

      final polarSamples =
          cancelled ? <PolarSample>[] : polarService.endRecordingBuffer();
      final faceEvents =
          cancelled ? <FaceTrackingEvent>[] : cameraService.endFaceEventBuffer();

      if (cancelled) {
        if (_sessionDir != null && await _sessionDir!.exists()) {
          await _sessionDir!.delete(recursive: true);
        }
        await _hapticStop();
        _emit(
          const RecordingUiState(phase: RecordingPhase.cancelled),
        );
        return;
      }

      final polarState = polarService.state;
      final previewSize = cameraService.controller?.value.previewSize;
      final deviceInfo = await AppPermissions.collectDeviceInfo();

      final metadata = SessionMetadata(
        sessionId: _folderName ?? 'unknown',
        subjectId: _subjectId ?? 'unknown',
        folderName: _folderName ?? '',
        startUtc: _startUtc ?? endUtc,
        endUtc: endUtc,
        startMonotonicMs: _startMonotonicMs ?? endMonotonic,
        endMonotonicMs: endMonotonic,
        deviceInfo: deviceInfo,
        polarDevice: PolarDeviceMeta(
          deviceId: polarState.deviceId ?? '',
          name: polarState.deviceName,
          firmware: polarState.firmware,
          batteryLevel: polarState.batteryLevel,
        ),
        recordingSettings: RecordingSettings(
          width: previewSize?.height.toInt(),
          height: previewSize?.width.toInt(),
          fps: 30,
          hrStream: polarState.hrStreaming,
          rrStream: polarState.hrStreaming,
          ecgStream: polarState.ecgStreaming,
          accStream: polarState.accStreaming,
          cameraLens: 'front',
          resolutionPreset: 'high',
        ),
        notes: _notes,
        status: SessionStatus.complete,
        faceDetectedAtStart: faceEvents.isNotEmpty
            ? faceEvents.first.faceDetected
            : cameraService.faceState.detected,
        faceDetectionEventCount: faceEvents.length,
        appVersion: deviceInfo.appVersion,
      );

      final finalized = metadata;

      if (_sessionDir == null) {
        throw StateError('Session directory missing');
      }

      if (videoPath != null) {
        await storage.moveVideoIntoSession(
          dir: _sessionDir!,
          sourcePath: videoPath.path,
        );
      }

      await storage.writePolarCsv(_sessionDir!, polarSamples);
      await storage.writeFaceTracking(_sessionDir!, faceEvents);
      await storage.writeMetadata(_sessionDir!, finalized);

      await _hapticStop();

      _emit(
        RecordingUiState(
          phase: RecordingPhase.completed,
          remainingSeconds: 0,
          progress: 1,
          completedMetadata: finalized,
          completedDirectory: _sessionDir!.path,
        ),
      );
    } catch (e, st) {
      debugPrint('Finish session error: $e\n$st');
      _emit(
        _state.copyWith(
          phase: RecordingPhase.error,
          errorMessage: 'Failed to save session: $e',
        ),
      );
    }
  }

  Future<void> _hapticStart() async {
    try {
      await HapticFeedback.mediumImpact();
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: 80);
      }
    } catch (_) {}
  }

  Future<void> _hapticStop() async {
    try {
      await HapticFeedback.heavyImpact();
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: 120);
      }
    } catch (_) {}
  }

  void reset() {
    _countdownTimer?.cancel();
    _emit(const RecordingUiState());
  }

  void dispose() {
    _countdownTimer?.cancel();
    _stateController.close();
  }
}

/// Tiny helper to avoid importing camera XFile in this file's public API.
class XFilePath {
  final String path;
  const XFilePath(this.path);
}
