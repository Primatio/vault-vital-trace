import 'dart:convert';

enum SessionStatus { complete, incomplete, cancelled }

class RecordingSettings {
  final int? width;
  final int? height;
  final int? fps;
  final bool hrStream;
  final bool rrStream;
  final bool ecgStream;
  final bool accStream;
  final String cameraLens;
  final String resolutionPreset;

  const RecordingSettings({
    this.width,
    this.height,
    this.fps,
    this.hrStream = true,
    this.rrStream = true,
    this.ecgStream = false,
    this.accStream = false,
    this.cameraLens = 'front',
    this.resolutionPreset = 'high',
  });

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'fps': fps,
        'hr_stream': hrStream,
        'rr_stream': rrStream,
        'ecg_stream': ecgStream,
        'acc_stream': accStream,
        'camera_lens': cameraLens,
        'resolution_preset': resolutionPreset,
      };

  factory RecordingSettings.fromJson(Map<String, dynamic> json) {
    return RecordingSettings(
      width: json['width'] as int?,
      height: json['height'] as int?,
      fps: json['fps'] as int?,
      hrStream: json['hr_stream'] as bool? ?? true,
      rrStream: json['rr_stream'] as bool? ?? true,
      ecgStream: json['ecg_stream'] as bool? ?? false,
      accStream: json['acc_stream'] as bool? ?? false,
      cameraLens: json['camera_lens'] as String? ?? 'front',
      resolutionPreset: json['resolution_preset'] as String? ?? 'high',
    );
  }
}

class DeviceInfoMeta {
  final String phoneModel;
  final String osVersion;
  final String osName;
  final String appVersion;
  final String appBuild;

  const DeviceInfoMeta({
    required this.phoneModel,
    required this.osVersion,
    required this.osName,
    required this.appVersion,
    required this.appBuild,
  });

  Map<String, dynamic> toJson() => {
        'phone_model': phoneModel,
        'os_version': osVersion,
        'os_name': osName,
        'app_version': appVersion,
        'app_build': appBuild,
      };

  factory DeviceInfoMeta.fromJson(Map<String, dynamic> json) {
    return DeviceInfoMeta(
      phoneModel: json['phone_model'] as String? ?? 'unknown',
      osVersion: json['os_version'] as String? ?? 'unknown',
      osName: json['os_name'] as String? ?? 'unknown',
      appVersion: json['app_version'] as String? ?? 'unknown',
      appBuild: json['app_build'] as String? ?? 'unknown',
    );
  }
}

class PolarDeviceMeta {
  final String deviceId;
  final String? name;
  final String? firmware;
  final int? batteryLevel;

  const PolarDeviceMeta({
    required this.deviceId,
    this.name,
    this.firmware,
    this.batteryLevel,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'name': name,
        'firmware': firmware,
        'battery_level': batteryLevel,
      };

  factory PolarDeviceMeta.fromJson(Map<String, dynamic> json) {
    return PolarDeviceMeta(
      deviceId: json['device_id'] as String? ?? '',
      name: json['name'] as String?,
      firmware: json['firmware'] as String?,
      batteryLevel: json['battery_level'] as int?,
    );
  }
}

/// Schema version for metadata.json (bump when fields change).
const int metadataSchemaVersion = 1;

class SessionMetadata {
  final String sessionId;
  final String subjectId;
  final String folderName;
  final DateTime startUtc;
  final DateTime? endUtc;
  final int startMonotonicMs;
  final int? endMonotonicMs;
  final DeviceInfoMeta deviceInfo;
  final PolarDeviceMeta? polarDevice;
  final RecordingSettings recordingSettings;
  final String? notes;
  final SessionStatus status;
  final bool faceDetectedAtStart;
  final int? faceDetectionEventCount;
  final String appVersion;

  const SessionMetadata({
    required this.sessionId,
    required this.subjectId,
    required this.folderName,
    required this.startUtc,
    this.endUtc,
    required this.startMonotonicMs,
    this.endMonotonicMs,
    required this.deviceInfo,
    this.polarDevice,
    required this.recordingSettings,
    this.notes,
    this.status = SessionStatus.incomplete,
    this.faceDetectedAtStart = false,
    this.faceDetectionEventCount,
    required this.appVersion,
  });

  SessionMetadata copyWith({
    String? sessionId,
    String? subjectId,
    String? folderName,
    DateTime? startUtc,
    DateTime? endUtc,
    int? startMonotonicMs,
    int? endMonotonicMs,
    DeviceInfoMeta? deviceInfo,
    PolarDeviceMeta? polarDevice,
    RecordingSettings? recordingSettings,
    String? notes,
    SessionStatus? status,
    bool? faceDetectedAtStart,
    int? faceDetectionEventCount,
    String? appVersion,
  }) {
    return SessionMetadata(
      sessionId: sessionId ?? this.sessionId,
      subjectId: subjectId ?? this.subjectId,
      folderName: folderName ?? this.folderName,
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      startMonotonicMs: startMonotonicMs ?? this.startMonotonicMs,
      endMonotonicMs: endMonotonicMs ?? this.endMonotonicMs,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      polarDevice: polarDevice ?? this.polarDevice,
      recordingSettings: recordingSettings ?? this.recordingSettings,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      faceDetectedAtStart: faceDetectedAtStart ?? this.faceDetectedAtStart,
      faceDetectionEventCount:
          faceDetectionEventCount ?? this.faceDetectionEventCount,
      appVersion: appVersion ?? this.appVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': metadataSchemaVersion,
        'session_id': sessionId,
        'subject_id': subjectId,
        'folder_name': folderName,
        'start_utc': startUtc.toUtc().toIso8601String(),
        'end_utc': endUtc?.toUtc().toIso8601String(),
        'start_monotonic_ms': startMonotonicMs,
        'end_monotonic_ms': endMonotonicMs,
        'duration_ms': endMonotonicMs != null
            ? endMonotonicMs! - startMonotonicMs
            : null,
        'device_info': deviceInfo.toJson(),
        'polar_device': polarDevice?.toJson(),
        'recording_settings': recordingSettings.toJson(),
        'notes': notes,
        'status': status.name,
        'face_detected_at_start': faceDetectedAtStart,
        'face_detection_event_count': faceDetectionEventCount,
        'app_version': appVersion,
      };

  factory SessionMetadata.fromJson(Map<String, dynamic> json) {
    return SessionMetadata(
      sessionId: json['session_id'] as String,
      subjectId: json['subject_id'] as String? ?? '',
      folderName: json['folder_name'] as String? ?? '',
      startUtc: DateTime.parse(json['start_utc'] as String),
      endUtc: json['end_utc'] != null
          ? DateTime.parse(json['end_utc'] as String)
          : null,
      startMonotonicMs: json['start_monotonic_ms'] as int? ?? 0,
      endMonotonicMs: json['end_monotonic_ms'] as int?,
      deviceInfo: DeviceInfoMeta.fromJson(
        (json['device_info'] as Map<String, dynamic>?) ?? {},
      ),
      polarDevice: json['polar_device'] != null
          ? PolarDeviceMeta.fromJson(
              json['polar_device'] as Map<String, dynamic>,
            )
          : null,
      recordingSettings: RecordingSettings.fromJson(
        (json['recording_settings'] as Map<String, dynamic>?) ?? {},
      ),
      notes: json['notes'] as String?,
      status: SessionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SessionStatus.incomplete,
      ),
      faceDetectedAtStart: json['face_detected_at_start'] as bool? ?? false,
      faceDetectionEventCount: json['face_detection_event_count'] as int?,
      appVersion: json['app_version'] as String? ??
          (json['device_info'] as Map?)?['app_version'] as String? ??
          'unknown',
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory SessionMetadata.fromJsonString(String source) {
    return SessionMetadata.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }
}
