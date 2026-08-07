# Vault rPPG Collector — Data Format

Schema version embedded in `metadata.json` as `schema_version` (currently **1**).

## Session directory

```
session_YYYYMMDD_HHMMSS_<subjectID>/
├── video.mp4              # Front-camera recording (~30 s)
├── polar_data.csv         # Polar H10 samples
├── metadata.json          # Session + device + sync metadata
└── face_tracking.json     # Face-detection events (best-effort)
```

Folder names use the device local clock for the `YYYYMMDD_HHMMSS` segment; absolute times inside `metadata.json` are UTC.

## metadata.json

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | int | Format version |
| `session_id` | string | Same as folder name by default |
| `subject_id` | string | Operator-entered subject identifier |
| `folder_name` | string | On-disk directory basename |
| `start_utc` / `end_utc` | ISO-8601 | Wall-clock UTC |
| `start_monotonic_ms` / `end_monotonic_ms` | int | Device monotonic clock (ms since process start) |
| `duration_ms` | int \| null | `end_monotonic_ms - start_monotonic_ms` |
| `device_info` | object | Phone model, OS, app version/build |
| `polar_device` | object | Device ID, name, firmware, battery |
| `recording_settings` | object | Resolution, FPS target, which streams were active |
| `notes` | string \| null | Free-text notes |
| `status` | string | `complete` \| `incomplete` \| `cancelled` |
| `face_detected_at_start` | bool | ML Kit face present at recording start |
| `face_detection_event_count` | int \| null | Rows in `face_tracking.json` |
| `app_version` | string | App semver |

### recording_settings

```json
{
  "width": 1280,
  "height": 720,
  "fps": 30,
  "hr_stream": true,
  "rr_stream": true,
  "ecg_stream": true,
  "acc_stream": false,
  "camera_lens": "front",
  "resolution_preset": "high"
}
```

## polar_data.csv

Header:

```
timestamp_ms,utc,hr_bpm,rr_ms,ecg_uv,acc_x,acc_y,acc_z
```

| Column | Unit | Notes |
|--------|------|-------|
| `timestamp_ms` | ms | Relative to session `start_monotonic_ms` |
| `utc` | ISO-8601 | Wall clock at sample capture (may be empty) |
| `hr_bpm` | bpm | From HR stream |
| `rr_ms` | ms | RR interval when present (may be on its own row) |
| `ecg_uv` | µV | ECG sample (~130 Hz when streaming) |
| `acc_x/y/z` | mG | Optional accelerometer |

Rows are **heterogeneous**: a row may populate only ECG, only HR, or HR+RR. Empty fields are left blank. Sort by `timestamp_ms` for chronological order (ECG arrives much denser than HR).

## face_tracking.json

```json
{
  "event_count": 1,
  "events": [
    {
      "timestamp_ms": 0,
      "face_detected": true,
      "face_count": 1,
      "smiling_probability": 0.1,
      "left_eye_open_probability": 0.9,
      "right_eye_open_probability": 0.9,
      "head_euler_y": 2.1,
      "head_euler_z": -1.4
    }
  ]
}
```

**Platform note:** The Flutter `camera` plugin cannot run an ML image stream concurrently with video encoding on most devices. Continuous face detection runs on the live preview; at recording start the app seeds a face event and records `face_detected_at_start`. Richer mid-recording face tracks are a post-MVP item (e.g. CameraX analysis use-case or offline video pass).

## Synchronization guidance for ML engineers

1. Treat `timestamp_ms == 0` as the intended video/sensor sync epoch.
2. Video length should be ≈ `duration_ms` (typically ~30000 ms).
3. Prefer ECG when `ecg_stream` is true; otherwise derive HRV features from `rr_ms`.
4. If sub-frame alignment is required, cross-correlate ECG/HR with rPPG estimates offline and apply a constant offset.

## Privacy

Sessions are stored only in the app documents directory until an operator uses **Export / Share**. No automatic Google Bucket upload is performed in the MVP app; upload is an external step after export.
