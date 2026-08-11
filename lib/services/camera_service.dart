import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/polar_sample.dart';
import '../utils/mlkit_utils.dart';
import '../utils/monotonic_clock.dart';

class FaceOverlayState {
  final bool detected;
  final int faceCount;
  final Rect? boundingBox;

  const FaceOverlayState({
    this.detected = false,
    this.faceCount = 0,
    this.boundingBox,
  });
}

/// Bridges CamerAwesome (widget-owned camera) with face detection + video control.
class CameraService {
  CameraService() {
    // Lean detector: presence only — classification is expensive.
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: false,
        enableTracking: true,
        enableLandmarks: false,
        enableContours: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.2,
      ),
    );
  }

  FaceDetector? _faceDetector;
  bool _isBusy = false;
  bool _isRecordingVideo = false;
  bool _cameraReady = false;
  bool _audioMuteRequested = false;
  int? _sessionStartMonotonicMs;
  String? _currentVideoPath;

  VideoCameraState? _videoState;
  VideoRecordingCameraState? _recordingState;

  final List<FaceTrackingEvent> _faceEvents = [];
  final _faceController = StreamController<FaceOverlayState>.broadcast();
  final _readyController = StreamController<bool>.broadcast();
  final _recordingController = StreamController<bool>.broadcast();
  FaceOverlayState _faceState = const FaceOverlayState();

  /// Tuned for preview smoothness + concurrent analysis.
  static const analysisMaxFps = 4;
  static const analysisWidth = 250;
  static const faceEventMinIntervalMs = 250;

  bool get isInitialized => _cameraReady;
  bool get isRecordingVideo => _isRecordingVideo;
  FaceOverlayState get faceState => _faceState;
  String? get currentVideoPath => _currentVideoPath;

  Stream<FaceOverlayState> get faceStream async* {
    yield _faceState;
    yield* _faceController.stream;
  }

  Stream<bool> get readyStream async* {
    yield _cameraReady;
    yield* _readyController.stream;
  }

  Stream<bool> get recordingStream async* {
    yield _isRecordingVideo;
    yield* _recordingController.stream;
  }

  /// Shared analysis config for CamerAwesome (keep in sync with detector load).
  AnalysisConfig analysisConfig() {
    return AnalysisConfig(
      androidOptions: const AndroidAnalysisOptions.nv21(width: analysisWidth),
      maxFramesPerSecond: analysisMaxFps.toDouble(),
      autoStart: true,
    );
  }

  /// Called from [CameraAwesomeBuilder] whenever the camera state changes.
  void attachCameraState(CameraState state) {
    state.when(
      onPreparingCamera: (_) {
        _videoState = null;
        _recordingState = null;
        _setReady(false);
      },
      onVideoMode: (videoState) {
        _videoState = videoState;
        _recordingState = null;
        _setReady(true);
        _requestMuteAudio(videoState);
      },
      onVideoRecordingMode: (recordingState) {
        _recordingState = recordingState;
        _videoState = null;
        _setReady(true);
      },
      onPhotoMode: (_) {},
      onPreviewMode: (_) {},
      onAnalysisOnlyMode: (_) {},
    );
  }

  /// Mute mic once camera is ready.
  ///
  /// CamerAwesome iOS never completes [VideoCameraState.enableAudio], so we
  /// must not await it. The native side still applies the flag.
  void _requestMuteAudio(VideoCameraState videoState) {
    if (_audioMuteRequested) return;
    _audioMuteRequested = true;
    unawaited(videoState.enableAudio(false));
  }

  void _setReady(bool ready) {
    if (_cameraReady == ready) return;
    _cameraReady = ready;
    if (!_readyController.isClosed) {
      _readyController.add(ready);
    }
  }

  void _setRecording(bool recording) {
    if (_isRecordingVideo == recording) return;
    _isRecordingVideo = recording;
    if (!_recordingController.isClosed) {
      _recordingController.add(recording);
    }
  }

  Future<void> processAnalysisImage(AnalysisImage image) async {
    // Drop frames while a previous inference is in flight.
    if (_isBusy || _faceDetector == null) return;
    _isBusy = true;
    try {
      final input = image.toInputImage();
      final faces = await _faceDetector!.processImage(input);
      final primary = faces.isNotEmpty ? faces.first : null;
      final detected = faces.isNotEmpty;

      final next = FaceOverlayState(
        detected: detected,
        faceCount: faces.length,
        boundingBox: primary?.boundingBox,
      );

      // Avoid flooding listeners when state is unchanged.
      if (next.detected != _faceState.detected ||
          next.faceCount != _faceState.faceCount) {
        _faceState = next;
        if (!_faceController.isClosed) {
          _faceController.add(_faceState);
        }
      } else {
        _faceState = next;
      }

      if (_sessionStartMonotonicMs != null) {
        final ts = MonotonicClock.nowMs() - _sessionStartMonotonicMs!;
        if (_faceEvents.isEmpty ||
            ts - _faceEvents.last.timestampMs >= faceEventMinIntervalMs) {
          _faceEvents.add(
            FaceTrackingEvent(
              timestampMs: ts,
              faceDetected: detected,
              faceCount: faces.length,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    } finally {
      _isBusy = false;
    }
  }

  void beginFaceEventBuffer({required int startMonotonicMs}) {
    _faceEvents.clear();
    _sessionStartMonotonicMs = startMonotonicMs;
  }

  List<FaceTrackingEvent> endFaceEventBuffer() {
    final copy = List<FaceTrackingEvent>.from(_faceEvents);
    _faceEvents.clear();
    _sessionStartMonotonicMs = null;
    return copy;
  }

  Future<CaptureRequest> _buildVideoRequest(List<Sensor> sensors) async {
    final dir = await getTemporaryDirectory();
    final filePath = p.join(
      dir.path,
      'vault_rppg_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    return SingleCaptureRequest(filePath, sensors.first);
  }

  SaveConfig buildSaveConfig() {
    return SaveConfig.video(
      pathBuilder: _buildVideoRequest,
      mirrorFrontCamera: true,
      videoOptions: VideoOptions(
        enableAudio: false,
        // HD is enough for rPPG and much lighter than "highest".
        quality: VideoRecordingQuality.hd,
        ios: CupertinoVideoOptions(
          fps: 30,
          codec: CupertinoCodecType.h264,
          fileType: CupertinoFileType.mpeg4,
        ),
        android: AndroidVideoOptions(
          bitrate: 4_000_000,
          fallbackStrategy: QualityFallbackStrategy.lower,
        ),
      ),
    );
  }

  Future<void> startVideoRecording() async {
    if (_isRecordingVideo) return;

    // Wait briefly if the builder hasn't attached VideoCameraState yet.
    var videoState = _videoState;
    for (var i = 0; i < 40 && videoState == null; i++) {
      await Future.delayed(const Duration(milliseconds: 25));
      videoState = _videoState;
    }
    if (videoState == null) {
      throw StateError('Camera not ready for video recording');
    }

    // Do NOT call enableAudio() here: CamerAwesome's iOS
    // setRecordingAudioMode never invokes its completion handler, so
    // awaiting it hangs forever. Audio is already disabled via SaveConfig.
    final request = await videoState.startRecording();
    _currentVideoPath = request.path;
    _setRecording(true);

    for (var i = 0; i < 40 && _recordingState == null; i++) {
      await Future.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<String?> stopVideoRecording() async {
    if (!_isRecordingVideo) return _currentVideoPath;

    final recordingState = _recordingState;
    if (recordingState == null) {
      await CamerawesomePlugin.stopRecordingVideo();
      _setRecording(false);
      return _currentVideoPath;
    }

    final completer = Completer<String?>();
    await recordingState.stopRecording(
      onVideo: (request) {
        _currentVideoPath = request.path;
        if (!completer.isCompleted) completer.complete(request.path);
      },
      onVideoFailed: (exception) {
        if (!completer.isCompleted) completer.completeError(exception);
      },
    );

    final path = await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => _currentVideoPath,
    );
    _setRecording(false);
    return path;
  }

  Future<void> cancelVideoRecording() async {
    if (!_isRecordingVideo && _recordingState == null) {
      await _deleteCurrentVideo();
      return;
    }

    try {
      final path = await stopVideoRecording();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Cancel recording error: $e');
      await _deleteCurrentVideo();
    } finally {
      _setRecording(false);
      _currentVideoPath = null;
    }
  }

  Future<void> _deleteCurrentVideo() async {
    final path = _currentVideoPath;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    _currentVideoPath = null;
  }

  Future<void> dispose() async {
    await _faceDetector?.close();
    _faceDetector = null;
    _videoState = null;
    _recordingState = null;
    _audioMuteRequested = false;
    _setRecording(false);
    _cameraReady = false;
    _faceState = const FaceOverlayState();
  }

  Future<void> closeStreams() async {
    await dispose();
    await _faceController.close();
    await _readyController.close();
    await _recordingController.close();
  }
}
