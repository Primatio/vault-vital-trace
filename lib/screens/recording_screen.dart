import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/permissions_service.dart';
import '../services/recording_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_overlays.dart';
import '../widgets/status_widgets.dart';
import 'session_detail_screen.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  bool _initializing = true;
  String? _initError;
  bool _canOpenSettings = false;
  bool _navigatedToDetail = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _initError = null;
      _canOpenSettings = false;
    });
    try {
      await ref.read(recordingControllerProvider).prepareCamera();
      if (!mounted) return;
      setState(() => _initializing = false);
    } on PermissionDeniedException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _initError = e.message;
        _canOpenSettings = e.canOpenSettings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _initError = '$e';
      });
    }
  }

  Future<bool> _onWillPop() async {
    final phase = ref.read(recordingControllerProvider).state.phase;
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
        await ref.read(recordingControllerProvider).cancelSession();
        return true;
      }
      return false;
    }
    return true;
  }

  Future<void> _start() async {
    final draft = ref.read(sessionDraftProvider);
    final face = ref.read(cameraServiceProvider).faceState;
    if (!face.detected) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No face detected'),
          content: const Text(
            'For rPPG quality, center your face in the oval before recording. Start anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Wait'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await ref.read(recordingControllerProvider).startSession(
          subjectId: draft.subjectId,
          notes: draft.notes,
        );
  }

  @override
  Widget build(BuildContext context) {
    final recordingAsync = ref.watch(recordingStateProvider);
    final recording = recordingAsync.asData?.value ??
        ref.read(recordingControllerProvider).state;
    final polar = ref.watch(polarStateProvider).asData?.value ??
        ref.read(polarServiceProvider).state;
    final face = ref.watch(faceOverlayProvider).asData?.value ??
        ref.read(cameraServiceProvider).faceState;
    final camera = ref.watch(cameraServiceProvider);

    ref.listen<AsyncValue<RecordingUiState>>(recordingStateProvider, (
      prev,
      next,
    ) {
      final state = next.asData?.value;
      if (state == null) return;

      if (state.phase == RecordingPhase.completed &&
          state.completedDirectory != null &&
          !_navigatedToDetail) {
        _navigatedToDetail = true;
        ref.read(sessionsListProvider.notifier).refresh();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final storage = ref.read(sessionStorageProvider);
          final summary = await storage.loadSessionSummary(
            Directory(state.completedDirectory!),
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

      if (state.phase == RecordingPhase.error && state.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage!)),
        );
      }
    });

    final isRecording = recording.phase == RecordingPhase.recording;
    final isBusy = recording.phase == RecordingPhase.preparing ||
        recording.phase == RecordingPhase.saving;

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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: isRecording || isBusy
                          ? null
                          : () async {
                              final allow = await _onWillPop();
                              if (allow && context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
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
              Expanded(
                child: _buildPreview(
                  controller: camera.controller,
                  initializing: _initializing,
                  initError: _initError,
                  canOpenSettings: _canOpenSettings,
                  faceDetected: face.detected,
                  isRecording: isRecording,
                  onRetry: _initCamera,
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                color: AppColors.background,
                child: Column(
                  children: [
                    if (isRecording ||
                        recording.phase == RecordingPhase.preparing) ...[
                      RecordingProgressBar(
                        progress: recording.progress,
                        remainingSeconds: recording.remainingSeconds,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: isBusy
                            ? null
                            : () => ref
                                .read(recordingControllerProvider)
                                .cancelSession(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                        child: const Text('Cancel recording'),
                      ),
                    ] else if (recording.phase == RecordingPhase.saving) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text('Saving session…'),
                    ] else ...[
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
                            face.detected ? 'Face ready' : 'Waiting for face',
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
                                  _initializing ||
                                  _initError != null)
                              ? null
                              : _start,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.recording,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
                      if (!polar.isStreaming) ...[
                        const SizedBox(height: 10),
                        const StatusBanner(
                          message: 'Polar must be streaming before recording.',
                          tone: BannerTone.warning,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview({
    required CameraController? controller,
    required bool initializing,
    required String? initError,
    required bool canOpenSettings,
    required bool faceDetected,
    required bool isRecording,
    required VoidCallback onRetry,
  }) {
    if (initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusBanner(
                message: initError,
                tone: BannerTone.error,
              ),
              const SizedBox(height: 16),
              if (canOpenSettings)
                FilledButton(
                  onPressed: () => AppPermissions.openAppSettingsPage(),
                  child: const Text('Open Settings'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Text(
          'Camera unavailable',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: CameraPreview(controller),
        ),
        if (!isRecording) FaceGuideOverlay(faceDetected: faceDetected),
        if (isRecording)
          const Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fiber_manual_record, color: AppColors.recording),
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
  }
}
