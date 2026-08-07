import 'session_metadata.dart';

class SessionSummary {
  final SessionMetadata metadata;
  final String directoryPath;
  final bool hasVideo;
  final bool hasPolarData;
  final bool hasMetadata;
  final bool hasPreview;
  final int? videoBytes;
  final int? polarBytes;

  const SessionSummary({
    required this.metadata,
    required this.directoryPath,
    required this.hasVideo,
    required this.hasPolarData,
    required this.hasMetadata,
    this.hasPreview = false,
    this.videoBytes,
    this.polarBytes,
  });

  bool get isComplete =>
      metadata.status == SessionStatus.complete &&
      hasVideo &&
      hasPolarData &&
      hasMetadata;

  String get displayStatus {
    if (metadata.status == SessionStatus.cancelled) return 'cancelled';
    if (isComplete) return 'complete';
    return 'incomplete';
  }
}
