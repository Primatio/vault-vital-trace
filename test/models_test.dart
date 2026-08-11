import 'package:flutter_test/flutter_test.dart';
import 'package:vault_rppg_collector/models/polar_sample.dart';
import 'package:vault_rppg_collector/models/session_metadata.dart';

void main() {
  test('PolarSample CSV row encoding', () {
    final sample = PolarSample(
      timestampMs: 12,
      utc: DateTime.utc(2026, 8, 6, 15, 30),
      hrBpm: 72,
      rrMs: 833,
      ecgUv: -120,
    );
    expect(
      sample.toCsvRow(),
      '12,2026-08-06T15:30:00.000Z,72,833,-120,,,',
    );
  });

  test('SessionMetadata round-trip', () {
    final meta = SessionMetadata(
      sessionId: 'session_20260806_153000_subj01',
      subjectId: 'subj01',
      folderName: 'session_20260806_153000_subj01',
      startUtc: DateTime.utc(2026, 8, 6, 15, 30),
      endUtc: DateTime.utc(2026, 8, 6, 15, 30, 30),
      startMonotonicMs: 1000,
      endMonotonicMs: 31000,
      deviceInfo: const DeviceInfoMeta(
        phoneModel: 'Pixel 8',
        osVersion: 'Android 15',
        osName: 'Android',
        appVersion: '1.0.0',
        appBuild: '1',
      ),
      polarDevice: const PolarDeviceMeta(
        deviceId: 'ABC123',
        name: 'Polar H10',
        firmware: '3.1.0',
        batteryLevel: 80,
      ),
      recordingSettings: const RecordingSettings(
        width: 1280,
        height: 720,
        fps: 30,
        hrStream: true,
        rrStream: true,
        ecgStream: true,
      ),
      notes: 'lab lighting',
      status: SessionStatus.complete,
      faceDetectedAtStart: true,
      faceDetectionEventCount: 1,
      appVersion: '1.0.0',
      bloodPressure: const SessionBloodPressure(
        start: BloodPressureReading(systolicMmhg: 120, diastolicMmhg: 80),
        end: BloodPressureReading(systolicMmhg: 118, diastolicMmhg: 78),
      ),
    );

    final restored = SessionMetadata.fromJsonString(meta.toJsonString());
    expect(restored.subjectId, 'subj01');
    expect(restored.recordingSettings.ecgStream, isTrue);
    expect(restored.polarDevice?.deviceId, 'ABC123');
    expect(restored.status, SessionStatus.complete);
    expect(restored.bloodPressure.start?.systolicMmhg, 120);
    expect(restored.bloodPressure.end?.diastolicMmhg, 78);
  });

  test('BloodPressureReading plausibility', () {
    expect(
      const BloodPressureReading(systolicMmhg: 120, diastolicMmhg: 80)
          .isPlausible,
      isTrue,
    );
    expect(
      const BloodPressureReading(systolicMmhg: 80, diastolicMmhg: 120)
          .isPlausible,
      isFalse,
    );
  });
}
