/// Unified Polar sample row for CSV export.
class PolarSample {
  /// Milliseconds relative to session start (device monotonic clock).
  final int timestampMs;

  /// Absolute UTC wall-clock at sample capture (optional).
  final DateTime? utc;

  final int? hrBpm;
  final int? rrMs;
  final int? ecgUv;
  final int? accX;
  final int? accY;
  final int? accZ;

  const PolarSample({
    required this.timestampMs,
    this.utc,
    this.hrBpm,
    this.rrMs,
    this.ecgUv,
    this.accX,
    this.accY,
    this.accZ,
  });

  static const csvHeader =
      'timestamp_ms,utc,hr_bpm,rr_ms,ecg_uv,acc_x,acc_y,acc_z';

  String toCsvRow() {
    return [
      timestampMs,
      utc?.toUtc().toIso8601String() ?? '',
      hrBpm ?? '',
      rrMs ?? '',
      ecgUv ?? '',
      accX ?? '',
      accY ?? '',
      accZ ?? '',
    ].join(',');
  }
}

class FaceTrackingEvent {
  final int timestampMs;
  final bool faceDetected;
  final int faceCount;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double? headEulerY;
  final double? headEulerZ;

  const FaceTrackingEvent({
    required this.timestampMs,
    required this.faceDetected,
    required this.faceCount,
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.headEulerY,
    this.headEulerZ,
  });

  Map<String, dynamic> toJson() => {
        'timestamp_ms': timestampMs,
        'face_detected': faceDetected,
        'face_count': faceCount,
        'smiling_probability': smilingProbability,
        'left_eye_open_probability': leftEyeOpenProbability,
        'right_eye_open_probability': rightEyeOpenProbability,
        'head_euler_y': headEulerY,
        'head_euler_z': headEulerZ,
      };
}
