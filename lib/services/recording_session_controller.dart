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
  /// Armed: waiting for a stable face before the 30s clock starts.
  waitingForFace,
  preparing,
  recording,
  saving,
  /// Video saved; operator must enter end cuff BP before session is complete.
  awaitingEndBp,
  completed,
  cancelled,
  faceLost,
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
  final int faceLockProgressMs;

  const RecordingUiState({
    this.phase = RecordingPhase.idle,
    this.remainingSeconds = 30,
    this.progress = 0,
    this.errorMessage,
    this.completedMetadata,
    this.completedDirectory,
    this.faceDetected = false,
    this.heartRate,
    this.faceLockProgressMs = 0,
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
    int? faceLockProgressMs,
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
      faceLockProgressMs: faceLockProgressMs ?? this.faceLockProgressMs,
    );
  }
}

/// Orchestrates synchronized 30s video + Polar recording with live face gating.
class RecordingSessionController {
  RecordingSessionController({
    required this.polarService,
    required this.cameraService,
    required this.storage,
    this.onStateChanged,
  });

  final PolarService polarService;
  final CameraService cameraService;
  final SessionStorageService storage;
  void Function(RecordingUiState state)? onStateChanged;

  static const recordingDuration = Duration(seconds: 30);

  /// Face must stay visible this long before the 30s take begins.
  static const faceLockDuration = Duration(milliseconds: 600);

  /// Face must be missing this long before the take is discarded.
  static const faceLostGrace = Duration(milliseconds: 800);

  RecordingUiState _state = const RecordingUiState();

  Timer? _countdownTimer;
  Timer? _faceLockTimer;
  Timer? _faceWatchTimer;
  StreamSubscription<FaceOverlayState>? _faceSub;
  DateTime? _faceLostSince;
  DateTime? _faceVisibleSince;
  DateTime? _countdownStartedAt;
  bool _aborting = false;
  bool _startingTake = false;

  DateTime? _startUtc;
  int? _startMonotonicMs;
  String? _subjectId;
  String? _notes;
  BloodPressureReading? _bpStart;
  Directory? _sessionDir;
  String? _folderName;
  SessionMetadata? _pendingMetadata;

  RecordingUiState get state => _state;

  void _emit(RecordingUiState next) {
    _state = next;
    onStateChanged?.call(next);
  }

  /// Arms a session. The 30s clock starts only after a stable face lock.
  Future<void> startSession({
    required String subjectId,
    String? notes,
    required BloodPressureReading bpStart,
  }) async {
    if (_state.phase == RecordingPhase.recording ||
        _state.phase == RecordingPhase.saving ||
        _state.phase == RecordingPhase.preparing ||
        _state.phase == RecordingPhase.waitingForFace ||
        _state.phase == RecordingPhase.awaitingEndBp) {
      return;
    }

    if (!bpStart.isPlausible) {
      _emit(
        _state.copyWith(
          phase: RecordingPhase.error,
          errorMessage:
              'Enter a valid start blood pressure (e.g. 120/80 mmHg).',
        ),
      );
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
    _bpStart = bpStart;
    _pendingMetadata = null;
    _aborting = false;
    _startingTake = false;
    _faceLostSince = null;
    _countdownStartedAt = null;
    _faceVisibleSince =
        cameraService.faceState.detected ? DateTime.now() : null;

    _emit(
      _state.copyWith(
        phase: RecordingPhase.waitingForFace,
        remainingSeconds: recordingDuration.inSeconds,
        progress: 0,
        faceLockProgressMs: 0,
        clearError: true,
        faceDetected: cameraService.faceState.detected,
        heartRate: polarService.state.heartRate,
      ),
    );

    _startFaceLockWatcher();
  }

  void _startFaceLockWatcher() {
    _faceSub?.cancel();
    _faceLockTimer?.cancel();

    // Poll so lock progress advances even when face state stops emitting.
    _faceLockTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_state.phase != RecordingPhase.waitingForFace || _startingTake) {
        return;
      }

      final detected = cameraService.faceState.detected;
      if (!detected) {
        if (_faceVisibleSince != null || _state.faceDetected) {
          _faceVisibleSince = null;
          _emit(
            _state.copyWith(
              faceDetected: false,
              faceLockProgressMs: 0,
              heartRate: polarService.state.heartRate,
            ),
          );
        }
        return;
      }

      _faceVisibleSince ??= DateTime.now();
      final held = DateTime.now().difference(_faceVisibleSince!);
      _emit(
        _state.copyWith(
          faceDetected: true,
          faceLockProgressMs: held.inMilliseconds.clamp(
            0,
            faceLockDuration.inMilliseconds,
          ),
          heartRate: polarService.state.heartRate,
        ),
      );

      if (held >= faceLockDuration) {
        _faceLockTimer?.cancel();
        _faceLockTimer = null;
        unawaited(_beginTimedRecording());
      }
    });
  }

  Future<void> _beginTimedRecording() async {
    if (_startingTake || _state.phase != RecordingPhase.waitingForFace) {
      return;
    }
    _startingTake = true;
    _faceLockTimer?.cancel();
    _faceLockTimer = null;
    await _faceSub?.cancel();
    _faceSub = null;

    _emit(
      _state.copyWith(
        phase: RecordingPhase.preparing,
        faceDetected: true,
        faceLockProgressMs: faceLockDuration.inMilliseconds,
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

      // Sync epoch = first frame of the timed take (face already locked).
      cameraService.beginFaceEventBuffer(startMonotonicMs: _startMonotonicMs!);
      polarService.beginRecordingBuffer(startMonotonicMs: _startMonotonicMs!);

      await cameraService.startVideoRecording().timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw TimeoutException('Camera recording start timed out'),
      );

      // Never block the 30s clock on haptics.
      unawaited(_hapticStart());

      _emit(
        _state.copyWith(
          phase: RecordingPhase.recording,
          remainingSeconds: recordingDuration.inSeconds,
          progress: 0,
          faceDetected: true,
          heartRate: polarService.state.heartRate,
        ),
      );

      _listenForFaceDuringRecording();
      _startCountdown();
    } catch (e) {
      await _cleanupFailedStart();
      _emit(
        _state.copyWith(
          phase: RecordingPhase.error,
          errorMessage: 'Failed to start recording: $e',
        ),
      );
    } finally {
      _startingTake = false;
    }
  }

  void _listenForFaceDuringRecording() {
    _faceSub?.cancel();
    _faceSub = null;
    _faceWatchTimer?.cancel();
    _faceLostSince = null;

    // Poll face presence: the face stream only emits on changes, so a
    // continuous "face out" would never re-trigger the grace check.
    _faceWatchTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_state.phase != RecordingPhase.recording || _aborting) return;

      final detected = cameraService.faceState.detected;
      if (detected != _state.faceDetected) {
        _emit(_state.copyWith(faceDetected: detected));
      }

      if (detected) {
        _faceLostSince = null;
        return;
      }

      _faceLostSince ??= DateTime.now();
      if (DateTime.now().difference(_faceLostSince!) >= faceLostGrace) {
        unawaited(_abortDueToFaceLost());
      }
    });
  }

  Future<void> _abortDueToFaceLost() async {
    if (_aborting) return;
    if (_state.phase != RecordingPhase.recording) return;
    _aborting = true;

    _countdownTimer?.cancel();
    _faceWatchTimer?.cancel();
    _faceWatchTimer = null;
    await _faceSub?.cancel();
    _faceSub = null;

    _emit(
      _state.copyWith(
        phase: RecordingPhase.saving,
        faceDetected: false,
      ),
    );

    try {
      await cameraService.cancelVideoRecording();
      polarService.discardRecordingBuffer();
      cameraService.endFaceEventBuffer();
      if (_sessionDir != null && await _sessionDir!.exists()) {
        await _sessionDir!.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Face-lost cleanup error: $e');
    }

    await _hapticStop();

    _emit(
      const RecordingUiState(
        phase: RecordingPhase.faceLost,
        errorMessage:
            'Face left the frame. Recording discarded — keep your face visible and start again.',
      ),
    );
    _aborting = false;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    final totalMs = recordingDuration.inMilliseconds;
    _countdownStartedAt = DateTime.now();

    void tick() {
      if (_aborting || _state.phase != RecordingPhase.recording) {
        _countdownTimer?.cancel();
        return;
      }

      final startedAt = _countdownStartedAt;
      if (startedAt == null) return;

      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final remainingSec =
          (recordingDuration.inSeconds - (elapsed ~/ 1000)).clamp(0, 30);
      final progress = (elapsed / totalMs).clamp(0.0, 1.0);

      _emit(
        _state.copyWith(
          remainingSeconds: remainingSec,
          progress: progress,
          heartRate: polarService.state.heartRate,
          faceDetected: cameraService.faceState.detected,
        ),
      );

      if (elapsed >= totalMs) {
        _countdownTimer?.cancel();
        unawaited(_finish(cancelled: false));
      }
    }

    tick();
    _countdownTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => tick(),
    );
  }

  Future<void> cancelSession() async {
    if (_state.phase != RecordingPhase.recording &&
        _state.phase != RecordingPhase.preparing &&
        _state.phase != RecordingPhase.waitingForFace) {
      return;
    }

    _countdownTimer?.cancel();
    _faceLockTimer?.cancel();
    _faceLockTimer = null;
    _faceWatchTimer?.cancel();
    _faceWatchTimer = null;
    await _faceSub?.cancel();
    _faceSub = null;

    if (_state.phase == RecordingPhase.waitingForFace) {
      _faceVisibleSince = null;
      _emit(
        RecordingUiState(
          phase: RecordingPhase.idle,
          faceDetected: cameraService.faceState.detected,
          heartRate: polarService.state.heartRate,
        ),
      );
      return;
    }

    await _finish(cancelled: true);
  }

  Future<void> _cleanupFailedStart() async {
    _countdownTimer?.cancel();
    _faceLockTimer?.cancel();
    _faceLockTimer = null;
    _faceWatchTimer?.cancel();
    _faceWatchTimer = null;
    await _faceSub?.cancel();
    _faceSub = null;
    polarService.discardRecordingBuffer();
    cameraService.endFaceEventBuffer();
    try {
      await cameraService.cancelVideoRecording();
    } catch (_) {}
    if (_sessionDir != null && await _sessionDir!.exists()) {
      await _sessionDir!.delete(recursive: true);
    }
  }

  Future<void> _finish({required bool cancelled}) async {
    if (_aborting) return;
    _countdownTimer?.cancel();
    _faceWatchTimer?.cancel();
    _faceWatchTimer = null;
    await _faceSub?.cancel();
    _faceSub = null;
    _emit(_state.copyWith(phase: RecordingPhase.saving));

    try {
      final endUtc = DateTime.now().toUtc();
      final endMonotonic = MonotonicClock.nowMs();

      String? videoPath;
      if (cancelled) {
        await cameraService.cancelVideoRecording();
        polarService.discardRecordingBuffer();
        cameraService.endFaceEventBuffer();
      } else {
        videoPath = await cameraService.stopVideoRecording();
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
        _emit(const RecordingUiState(phase: RecordingPhase.cancelled));
        return;
      }

      final faceLostEvents = faceEvents.where((e) => !e.faceDetected).length;
      if (faceEvents.isNotEmpty &&
          faceLostEvents > faceEvents.length * 0.25) {
        if (videoPath != null) {
          final f = File(videoPath);
          if (await f.exists()) await f.delete();
        }
        if (_sessionDir != null && await _sessionDir!.exists()) {
          await _sessionDir!.delete(recursive: true);
        }
        _emit(
          const RecordingUiState(
            phase: RecordingPhase.faceLost,
            errorMessage:
                'Face was not visible for enough of the recording. Please start again.',
          ),
        );
        return;
      }

      final polarState = polarService.state;
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
          fps: 30,
          hrStream: polarState.hrStreaming,
          rrStream: polarState.hrStreaming,
          ecgStream: polarState.ecgStreaming,
          accStream: polarState.accStreaming,
          cameraLens: 'front',
          resolutionPreset: 'hd',
        ),
        notes: _notes,
        // Incomplete until end cuff BP is entered.
        status: SessionStatus.incomplete,
        faceDetectedAtStart: true,
        faceDetectionEventCount: faceEvents.length,
        appVersion: deviceInfo.appVersion,
        bloodPressure: SessionBloodPressure(start: _bpStart),
      );

      if (_sessionDir == null) {
        throw StateError('Session directory missing');
      }

      if (videoPath != null) {
        await storage.moveVideoIntoSession(
          dir: _sessionDir!,
          sourcePath: videoPath,
        );
      }

      await storage.writePolarCsv(_sessionDir!, polarSamples);
      await storage.writeFaceTracking(_sessionDir!, faceEvents);
      await storage.writeMetadata(_sessionDir!, metadata);

      await _hapticStop();

      _pendingMetadata = metadata;
      _emit(
        RecordingUiState(
          phase: RecordingPhase.awaitingEndBp,
          remainingSeconds: 0,
          progress: 1,
          completedMetadata: metadata,
          completedDirectory: _sessionDir!.path,
          faceDetected: cameraService.faceState.detected,
          heartRate: polarService.state.heartRate,
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

  /// Persists end cuff BP and marks the session complete.
  Future<void> submitEndBloodPressure(BloodPressureReading bpEnd) async {
    if (_state.phase != RecordingPhase.awaitingEndBp) return;
    if (!bpEnd.isPlausible) {
      _emit(
        _state.copyWith(
          errorMessage:
              'Enter a valid end blood pressure (e.g. 120/80 mmHg).',
        ),
      );
      return;
    }

    final pending = _pendingMetadata;
    final dir = _sessionDir;
    if (pending == null || dir == null) {
      _emit(
        _state.copyWith(
          phase: RecordingPhase.error,
          errorMessage: 'Session data missing; cannot save end BP.',
        ),
      );
      return;
    }

    final complete = pending.copyWith(
      status: SessionStatus.complete,
      bloodPressure: SessionBloodPressure(
        start: pending.bloodPressure.start ?? _bpStart,
        end: bpEnd,
      ),
    );

    try {
      await storage.writeMetadata(dir, complete);
      _pendingMetadata = complete;
      _emit(
        RecordingUiState(
          phase: RecordingPhase.completed,
          remainingSeconds: 0,
          progress: 1,
          completedMetadata: complete,
          completedDirectory: dir.path,
        ),
      );
    } catch (e) {
      _emit(
        _state.copyWith(
          phase: RecordingPhase.error,
          errorMessage: 'Failed to save end blood pressure: $e',
        ),
      );
    }
  }

  Future<void> acknowledgeFaceLost() async {
    if (_state.phase == RecordingPhase.faceLost) {
      _emit(
        RecordingUiState(
          phase: RecordingPhase.idle,
          faceDetected: cameraService.faceState.detected,
          heartRate: polarService.state.heartRate,
        ),
      );
    }
  }

  Future<void> _hapticStart() async {
    try {
      await HapticFeedback.mediumImpact()
          .timeout(const Duration(milliseconds: 300));
      if (await Vibration.hasVibrator()
          .timeout(const Duration(milliseconds: 300), onTimeout: () => false)) {
        await Vibration.vibrate(duration: 80)
            .timeout(const Duration(milliseconds: 500));
      }
    } catch (_) {}
  }

  Future<void> _hapticStop() async {
    try {
      await HapticFeedback.heavyImpact()
          .timeout(const Duration(milliseconds: 300));
      if (await Vibration.hasVibrator()
          .timeout(const Duration(milliseconds: 300), onTimeout: () => false)) {
        await Vibration.vibrate(duration: 120)
            .timeout(const Duration(milliseconds: 500));
      }
    } catch (_) {}
  }

  void reset() {
    _countdownTimer?.cancel();
    _faceLockTimer?.cancel();
    _faceLockTimer = null;
    _faceWatchTimer?.cancel();
    _faceWatchTimer = null;
    _faceSub?.cancel();
    _faceSub = null;
    _faceVisibleSince = null;
    _countdownStartedAt = null;
    _emit(const RecordingUiState());
  }

  void dispose() {
    _countdownTimer?.cancel();
    _faceLockTimer?.cancel();
    _faceWatchTimer?.cancel();
    _faceSub?.cancel();
    onStateChanged = null;
  }
}
