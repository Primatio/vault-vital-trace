import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/camera_service.dart';
import '../services/polar_service.dart';
import '../services/recording_session_controller.dart';
import '../services/session_storage_service.dart';
import '../models/session_summary.dart';

final sessionStorageProvider = Provider<SessionStorageService>((ref) {
  return SessionStorageService();
});

final polarServiceProvider = Provider<PolarService>((ref) {
  final service = PolarService();
  ref.onDispose(service.dispose);
  return service;
});

final polarStateProvider = StreamProvider<PolarLiveState>((ref) {
  final service = ref.watch(polarServiceProvider);
  return service.stateStream;
});

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(service.closeStreams);
  return service;
});

final faceOverlayProvider = StreamProvider<FaceOverlayState>((ref) {
  final camera = ref.watch(cameraServiceProvider);
  return camera.faceStream;
});

final recordingControllerProvider = Provider<RecordingSessionController>((ref) {
  final controller = RecordingSessionController(
    polarService: ref.watch(polarServiceProvider),
    cameraService: ref.watch(cameraServiceProvider),
    storage: ref.watch(sessionStorageProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final recordingStateProvider = StreamProvider<RecordingUiState>((ref) {
  final controller = ref.watch(recordingControllerProvider);
  return controller.stateStream;
});

final sessionsListProvider =
    AsyncNotifierProvider<SessionsListNotifier, List<SessionSummary>>(
  SessionsListNotifier.new,
);

class SessionsListNotifier extends AsyncNotifier<List<SessionSummary>> {
  @override
  Future<List<SessionSummary>> build() {
    return ref.read(sessionStorageProvider).listSessions();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(sessionStorageProvider).listSessions(),
    );
  }

  Future<void> deleteSession(String directoryPath) async {
    await ref.read(sessionStorageProvider).deleteSession(directoryPath);
    await refresh();
  }
}

/// Draft fields for a new session (subject ID + notes).
class SessionDraft {
  final String subjectId;
  final String notes;

  const SessionDraft({this.subjectId = '', this.notes = ''});

  SessionDraft copyWith({String? subjectId, String? notes}) {
    return SessionDraft(
      subjectId: subjectId ?? this.subjectId,
      notes: notes ?? this.notes,
    );
  }
}

class SessionDraftNotifier extends Notifier<SessionDraft> {
  @override
  SessionDraft build() => const SessionDraft();

  void setSubjectId(String value) =>
      state = state.copyWith(subjectId: value);

  void setNotes(String value) => state = state.copyWith(notes: value);

  void reset() => state = const SessionDraft();
}

final sessionDraftProvider =
    NotifierProvider<SessionDraftNotifier, SessionDraft>(
  SessionDraftNotifier.new,
);
