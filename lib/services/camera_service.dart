import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/polar_sample.dart';
import '../utils/monotonic_clock.dart';

class FaceOverlayState {
  final bool detected;
  final int faceCount;
  final Rect? boundingBox;
  final Size? imageSize;
  final InputImageRotation? rotation;

  const FaceOverlayState({
    this.detected = false,
    this.faceCount = 0,
    this.boundingBox,
    this.imageSize,
    this.rotation,
  });

  FaceOverlayState copyWith({
    bool? detected,
    int? faceCount,
    Rect? boundingBox,
    Size? imageSize,
    InputImageRotation? rotation,
  }) {
    return FaceOverlayState(
      detected: detected ?? this.detected,
      faceCount: faceCount ?? this.faceCount,
      boundingBox: boundingBox ?? this.boundingBox,
      imageSize: imageSize ?? this.imageSize,
      rotation: rotation ?? this.rotation,
    );
  }
}

class CameraService {
  CameraController? _controller;
  FaceDetector? _faceDetector;
  bool _isStreaming = false;
  bool _isBusy = false;
  bool _isRecordingVideo = false;
  int? _sessionStartMonotonicMs;
  final List<FaceTrackingEvent> _faceEvents = [];

  final _faceController = StreamController<FaceOverlayState>.broadcast();
  FaceOverlayState _faceState = const FaceOverlayState();

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isRecordingVideo => _isRecordingVideo;
  Stream<FaceOverlayState> get faceStream async* {
    yield _faceState;
    yield* _faceController.stream;
  }
  FaceOverlayState get faceState => _faceState;
  List<FaceTrackingEvent> get faceEvents =>
      List<FaceTrackingEvent>.unmodifiable(_faceEvents);

  Future<CameraDescription> _frontCamera() async {
    final cameras = await availableCameras();
    return cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
  }

  Future<void> initialize({
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    await dispose();

    final camera = await _frontCamera();
    final controller = CameraController(
      camera,
      preset,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await controller.initialize();
    _controller = controller;

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );

    await startFaceStream();
  }

  Future<void> startFaceStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isStreaming || _isRecordingVideo) return;

    _isStreaming = true;
    await controller.startImageStream(_processCameraImage);
  }

  Future<void> stopFaceStream() async {
    final controller = _controller;
    if (!_isStreaming) return;
    _isStreaming = false;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  void beginFaceEventBuffer({required int startMonotonicMs}) {
    _faceEvents.clear();
    _sessionStartMonotonicMs = startMonotonicMs;
  }

  void seedFaceEvent(FaceTrackingEvent event) {
    _faceEvents.add(event);
  }

  List<FaceTrackingEvent> endFaceEventBuffer() {
    final copy = List<FaceTrackingEvent>.from(_faceEvents);
    _faceEvents.clear();
    _sessionStartMonotonicMs = null;
    return copy;
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || _faceDetector == null || _controller == null) return;
    _isBusy = true;

    try {
      final input = _inputImageFromCameraImage(image);
      if (input == null) return;

      final faces = await _faceDetector!.processImage(input);
      final primary = faces.isNotEmpty ? faces.first : null;

      _faceState = FaceOverlayState(
        detected: faces.isNotEmpty,
        faceCount: faces.length,
        boundingBox: primary?.boundingBox,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: input.metadata?.rotation,
      );
      _faceController.add(_faceState);

      if (_sessionStartMonotonicMs != null) {
        final ts = MonotonicClock.nowMs() - _sessionStartMonotonicMs!;
        _faceEvents.add(
          FaceTrackingEvent(
            timestampMs: ts,
            faceDetected: faces.isNotEmpty,
            faceCount: faces.length,
            smilingProbability: primary?.smilingProbability,
            leftEyeOpenProbability: primary?.leftEyeOpenProbability,
            rightEyeOpenProbability: primary?.rightEyeOpenProbability,
            headEulerY: primary?.headEulerAngleY,
            headEulerZ: primary?.headEulerAngleZ,
          ),
        );
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    } finally {
      _isBusy = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;

    final sensorOrientation = controller.description.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      // Front camera preview is mirrored; sensor orientation is still used.
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Stops the ML image stream (required by camera plugin), then starts video.
  Future<void> startVideoRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera not ready');
    }
    if (_isRecordingVideo) return;

    await stopFaceStream();
    await controller.startVideoRecording();
    _isRecordingVideo = true;
  }

  Future<XFile?> stopVideoRecording() async {
    final controller = _controller;
    if (controller == null || !_isRecordingVideo) return null;

    final file = await controller.stopVideoRecording();
    _isRecordingVideo = false;

    // Resume face detection for subsequent takes.
    await startFaceStream();
    return file;
  }

  Future<void> cancelVideoRecording() async {
    final controller = _controller;
    if (controller == null || !_isRecordingVideo) return;
    try {
      final file = await controller.stopVideoRecording();
      final f = File(file.path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (e) {
      debugPrint('Cancel recording error: $e');
    } finally {
      _isRecordingVideo = false;
      await startFaceStream();
    }
  }

  Size? get previewSize {
    final value = _controller?.value;
    if (value == null || !value.isInitialized) return null;
    return value.previewSize;
  }

  int? get previewWidth =>
      _controller?.value.previewSize?.height.toInt(); // portrait swap
  int? get previewHeight => _controller?.value.previewSize?.width.toInt();

  Future<void> dispose() async {
    await stopFaceStream();
    await _faceDetector?.close();
    _faceDetector = null;
    await _controller?.dispose();
    _controller = null;
    _isRecordingVideo = false;
    _faceState = const FaceOverlayState();
  }

  Future<void> closeStreams() async {
    await dispose();
    await _faceController.close();
  }
}
