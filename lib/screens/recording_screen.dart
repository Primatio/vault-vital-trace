import 'dart:io';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/camera_service.dart';
import '../services/permissions_service.dart';
import '../services/recording_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/blood_pressure_input.dart';
import '../widgets/heart_rate_graph.dart';
import '../widgets/recording_overlays.dart';
import '../widgets/status_widgets.dart';
import 'session_detail_screen.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  bool _permissionReady = false;
  String? _initError;
  bool _canOpenSettings = false;
  bool _navigatedToDetail = false;
  bool _handlingFaceLost = false;
  RecordingPhase? _lastHandledPhase;

  final _startSysController = TextEditingController();
  final _startDiaController = TextEditingController();
  final _endSysController = TextEditingController();
  final _endDiaController = TextEditingController();

  RecordingSessionController get _recording =>
      ref.read(recordingControllerProvider.notifier).controller;

  @override
  void initState() {
    super.initState();
    _startSysController.addListener(_onBpFieldsChanged);
    _startDiaController.addListener(_onBpFieldsChanged);
    _requestPermissions();
  }

  void _onBpFieldsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _startSysController.removeListener(_onBpFieldsChanged);
    _startDiaController.removeListener(_onBpFieldsChanged);
    _startSysController.dispose();
    _startDiaController.dispose();
    _endSysController.dispose();
    _endDiaController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    try {
      await AppPermissions.ensureCameraPermissions();
      if (!mounted) return;
      setState(() {
        _permissionReady = true;
        _initError = null;
      });
    } on PermissionDeniedException catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionReady = false;
        _initError = e.message;
        _canOpenSettings = e.canOpenSettings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionReady = false;
        _initError = '$e';
      });
    }
  }

  Future<bool> _onWillPop() async {
    final phase = ref.read(recordingControllerProvider).phase;
    if (phase == RecordingPhase.waitingForFace) {
      await _recording.cancelSession();
      return true;
    }
    if (phase == RecordingPhase.awaitingEndBp) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('End BP not entered'),
          content: const Text(
            'Video is already saved. Leave without end blood pressure? '
            'You can still export the session later (status will stay incomplete).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      return leave == true;
    }
    if (phase == RecordingPhase.recording ||
        phase == RecordingPhase.preparing ||
        phase == RecordingPhase.saving) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel recording?'),
          content: const Text(
            'Leaving now will discard the current session.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Cancel & leave'),
            ),
          ],
        ),
      );
      if (leave == true) {
        await _recording.cancelSession();
        return true;
      }
      return false;
    }
    return true;
  }

  Future<void> _start() async {
    final bpStart = BloodPressureInput.parse(
      _startSysController,
      _startDiaController,
    );
    if (bpStart == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid start BP (e.g. 120 / 80 mmHg).'),
        ),
      );
      return;
    }

    final draft = ref.read(sessionDraftProvider);
    await _recording.startSession(
      subjectId: draft.subjectId,
      notes: draft.notes,
      bpStart: bpStart,
    );
  }

  Future<void> _submitEndBp() async {
    final bpEnd = BloodPressureInput.parse(
      _endSysController,
      _endDiaController,
    );
    if (bpEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid end BP (e.g. 118 / 78 mmHg).'),
        ),
      );
      return;
    }
    await _recording.submitEndBloodPressure(bpEnd);
  }

  Future<void> _handleFaceLost(String message) async {
    if (_handlingFaceLost) return;
    _handlingFaceLost = true;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Face lost'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Start again'),
          ),
        ],
      ),
    );

    await _recording.acknowledgeFaceLost();
    _handlingFaceLost = false;
  }

  @override
  Widget build(BuildContext context) {
    final recording = ref.watch(recordingControllerProvider);
    final polar = ref.watch(polarStateProvider).asData?.value ??
        ref.read(polarServiceProvider).state;
    final face = ref.watch(faceOverlayProvider).asData?.value ??
        ref.read(cameraServiceProvider).faceState;
    final cameraReady = ref.watch(cameraReadyProvider).asData?.value ??
        ref.read(cameraServiceProvider).isInitialized;
    final hrHistory = ref.watch(heartRateHistoryProvider).asData?.value ??
        ref.read(polarServiceProvider).hrHistory;

    ref.listen<RecordingUiState>(recordingControllerProvider, (_, next) {
      if (next.phase == _lastHandledPhase) return;
      _lastHandledPhase = next.phase;

      if (next.phase == RecordingPhase.awaitingEndBp) {
        ref.read(sessionsListProvider.notifier).refresh();
      }

      if (next.phase == RecordingPhase.completed &&
          next.completedDirectory != null &&
          !_navigatedToDetail) {
        _navigatedToDetail = true;
        ref.read(sessionsListProvider.notifier).refresh();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final storage = ref.read(sessionStorageProvider);
          final summary = await storage.loadSessionSummary(
            Directory(next.completedDirectory!),
          );
          if (!mounted) return;
          if (summary != null) {
            navigator.pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => SessionDetailScreen(
                  summary: summary,
                  justCompleted: true,
                ),
              ),
            );
          } else {
            messenger.showSnackBar(
              const SnackBar(content: Text('Session saved')),
            );
            navigator.popUntil((route) => route.isFirst);
          }
        });
      }

      if (next.phase == RecordingPhase.faceLost && next.errorMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleFaceLost(next.errorMessage!);
        });
      }

      if (next.phase == RecordingPhase.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });

    final isRecording = recording.phase == RecordingPhase.recording;
    final isWaitingForFace = recording.phase == RecordingPhase.waitingForFace;
    final isPreparing = recording.phase == RecordingPhase.preparing;
    final isSaving = recording.phase == RecordingPhase.saving;
    final isAwaitingEndBp = recording.phase == RecordingPhase.awaitingEndBp;
    final canCancelTake =
        isWaitingForFace || isRecording || isPreparing;
    final startBp = BloodPressureInput.parse(
      _startSysController,
      _startDiaController,
    );
    final faceLockFraction = (recording.faceLockProgressMs /
            RecordingSessionController.faceLockDuration.inMilliseconds)
        .clamp(0.0, 1.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final allow = await _onWillPop();
        if (allow && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // Top navigation.
              Material(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final allow = await _onWillPop();
                                if (allow && context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'Recording',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      ConnectionStatusChip(state: polar, compact: true),
                    ],
                  ),
                ),
              ),
              // HR graph directly below navigation (~20% of screen height).
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.1,
                width: double.infinity,
                child: HeartRateGraph(
                  points: hrHistory,
                  currentBpm: polar.heartRate,
                ),
              ),
              // Remaining space — camera fills the slot above the controls.
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: _buildCameraArea(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Material(
                      color: AppColors.background,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isWaitingForFace) ...[
                              Text(
                                face.detected
                                    ? 'Hold still — locking face…'
                                    : 'Center your face to start the 30s timer',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: face.detected
                                      ? AppColors.accent
                                      : AppColors.warning,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: faceLockFraction,
                                  minHeight: 6,
                                  backgroundColor: AppColors.surfaceAlt,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => _recording.cancelSession(),
                                  child: const Text('Cancel'),
                                ),
                              ),
                            ] else if (isPreparing) ...[
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              const Text(
                                'Starting recording…',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => _recording.cancelSession(),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(
                                      color: AppColors.error,
                                    ),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                            ] else if (isRecording) ...[
                              RecordingProgressBar(
                                progress: recording.progress,
                                remainingSeconds: recording.remainingSeconds,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                face.detected
                                    ? 'Face visible — keep still'
                                    : 'Face lost — hold position!',
                                style: TextStyle(
                                  color: face.detected
                                      ? AppColors.accent
                                      : AppColors.recording,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: canCancelTake
                                      ? () => _recording.cancelSession()
                                      : null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(
                                      color: AppColors.error,
                                    ),
                                  ),
                                  child: const Text('Cancel recording'),
                                ),
                              ),
                            ] else if (isSaving) ...[
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              const Text('Saving session…'),
                            ] else if (isAwaitingEndBp) ...[
                              BloodPressureInput(
                                title: 'End blood pressure',
                                subtitle:
                                    'Take cuff BP now (after the 30s video) and enter SYS/DIA.',
                                systolicController: _endSysController,
                                diastolicController: _endDiaController,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _submitEndBp,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: const Text(
                                    'Save end BP & finish',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const StatusBanner(
                                message:
                                    'Video and Polar data are already on disk. End BP completes the session metadata.',
                                tone: BannerTone.info,
                              ),
                            ] else ...[
                              BloodPressureInput(
                                title: 'Start blood pressure',
                                subtitle:
                                    'Measure cuff BP before starting, then enter SYS/DIA.',
                                systolicController: _startSysController,
                                diastolicController: _startDiaController,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    face.detected
                                        ? Icons.face
                                        : Icons.face_retouching_off,
                                    color: face.detected
                                        ? AppColors.accent
                                        : AppColors.textSecondary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    face.detected
                                        ? 'Face in view'
                                        : 'Looking for face',
                                    style: TextStyle(
                                      color: face.detected
                                          ? AppColors.accent
                                          : AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    polar.heartRate != null
                                        ? '${polar.heartRate} bpm'
                                        : 'No HR',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: (!polar.isStreaming ||
                                          !cameraReady ||
                                          _initError != null ||
                                          startBp == null)
                                      ? null
                                      : _start,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.recording,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: const Text(
                                    'Start 30s recording',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              StatusBanner(
                                message: !polar.isStreaming
                                    ? 'Polar must be streaming before recording.'
                                    : startBp == null
                                        ? 'Enter start cuff BP (SYS/DIA) before recording.'
                                        : 'Timer starts only after your face is locked in the oval. Keep it visible for the full 30 seconds.',
                                tone: !polar.isStreaming || startBp == null
                                    ? BannerTone.warning
                                    : BannerTone.info,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraArea() {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusBanner(message: _initError!, tone: BannerTone.error),
              const SizedBox(height: 16),
              if (_canOpenSettings)
                FilledButton(
                  onPressed: () => AppPermissions.openAppSettingsPage(),
                  child: const Text('Open Settings'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _requestPermissions,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_permissionReady) {
      return const Center(child: CircularProgressIndicator());
    }

    // Keep CamerAwesome mounted stably; overlays listen to streams internally.
    return _StableCameraPreview(camera: ref.read(cameraServiceProvider));
  }
}

class _StableCameraPreview extends StatefulWidget {
  const _StableCameraPreview({required this.camera});

  final CameraService camera;

  @override
  State<_StableCameraPreview> createState() => _StableCameraPreviewState();
}

class _StableCameraPreviewState extends State<_StableCameraPreview> {
  late final SaveConfig _saveConfig = widget.camera.buildSaveConfig();

  @override
  Widget build(BuildContext context) {
    return CameraAwesomeBuilder.custom(
      saveConfig: _saveConfig,
      sensorConfig: SensorConfig.single(
        sensor: Sensor.position(SensorPosition.front),
        aspectRatio: CameraAspectRatios.ratio_4_3,
        flashMode: FlashMode.none,
      ),
      // Fill the camera slot width; height may crop within the remaining space.
      previewFit: CameraPreviewFit.fitWidth,
      onImageForAnalysis: widget.camera.processAnalysisImage,
      imageAnalysisConfig: widget.camera.analysisConfig(),
      builder: (state, preview) {
        widget.camera.attachCameraState(state);
        return _LiveFaceOverlay(camera: widget.camera);
      },
    );
  }
}

class _LiveFaceOverlay extends StatelessWidget {
  const _LiveFaceOverlay({required this.camera});

  final CameraService camera;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FaceOverlayState>(
      stream: camera.faceStream,
      initialData: camera.faceState,
      builder: (context, faceSnap) {
        final faceDetected = faceSnap.data?.detected ?? false;
        return StreamBuilder<bool>(
          stream: camera.recordingStream,
          initialData: camera.isRecordingVideo,
          builder: (context, recordingSnap) {
            final isRecording = recordingSnap.data ?? false;
            return Stack(
              fit: StackFit.expand,
              children: [
                FaceGuideOverlay(faceDetected: faceDetected),
                if (isRecording)
                  const Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.fiber_manual_record,
                          color: AppColors.recording,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'RECORDING',
                          style: TextStyle(
                            color: AppColors.recording,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
