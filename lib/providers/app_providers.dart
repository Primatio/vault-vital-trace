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

final heartRateHistoryProvider = StreamProvider<List<HeartRatePoint>>((ref) {
  final service = ref.watch(polarServiceProvider);
  return service.hrHistoryStream;
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

final cameraReadyProvider = StreamProvider<bool>((ref) {
  final camera = ref.watch(cameraServiceProvider);
  return camera.readyStream;
});

/// Bridges [RecordingSessionController] emissions into Riverpod 3 [Notifier] state
/// so countdown ticks always rebuild the UI.
class RecordingSessionNotifier extends Notifier<RecordingUiState> {
  late final RecordingSessionController _controller;

  RecordingSessionController get controller => _controller;

  @override
  RecordingUiState build() {
    _controller = RecordingSessionController(
      polarService: ref.watch(polarServiceProvider),
      cameraService: ref.watch(cameraServiceProvider),
      storage: ref.watch(sessionStorageProvider),
      onStateChanged: (next) => state = next,
    );
    ref.onDispose(_controller.dispose);
    return _controller.state;
  }
}

final recordingControllerProvider =
    NotifierProvider<RecordingSessionNotifier, RecordingUiState>(
  RecordingSessionNotifier.new,
);

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
