# Vault rPPG Collector

Primatio internal R&D project #001 — Flutter app for synchronized collection of facial video and Polar H10 physiological ground truth for remote photoplethysmography (rPPG) research.

See [`spec.md`](spec.md) for the full product specification and [`docs/DATA_FORMAT.md`](docs/DATA_FORMAT.md) for the on-disk dataset schema.

## Features (MVP)

- Scan / connect to **Polar H10** over BLE
- Live **HR**, **RR-intervals**, and **ECG** (~130 Hz) when the device exposes them
- Front-camera preview with **ML Kit face detection** (required before / at start of a take)
- Fixed **30-second** synchronized recording (video + Polar CSV + metadata)
- Local session library with review, export/share, and delete
- Data stays on device until explicitly exported

## Requirements

- Flutter stable (3.38+ / Dart 3.10+)
- **Android 10+** (API 29) or **iOS 15.5+**
- Polar H10 chest strap (firmware **≥ 3.0.35** recommended for ECG)
- Physical device with BLE (simulators cannot exercise Polar)

## Getting started

```bash
flutter pub get
flutter run
```

### iOS

```bash
cd ios && pod install && cd ..
flutter run -d <ios-device>
```

Bluetooth, camera, and microphone usage strings are already in `ios/Runner/Info.plist`. Deployment target is iOS 15.5+ (required by Google ML Kit).

### Android

Permissions for camera, Bluetooth scan/connect, and (legacy) location are declared in `android/app/src/main/AndroidManifest.xml`. `minSdk` is 29.

## Typical collection flow

1. Open **Connect Polar** → Scan → select your H10 → wait until HR is streaming
2. **New Session** → enter Subject ID (+ optional notes)
3. Center face in the oval → **Start 30s recording**
4. Keep the app in the foreground until the countdown finishes
5. Review the session → **Export / Share** into your training pipeline / bucket upload workflow

## Session folder layout

```
session_YYYYMMDD_HHMMSS_subjectID/
├── video.mp4
├── polar_data.csv
├── metadata.json
└── face_tracking.json
```

Details: [docs/DATA_FORMAT.md](docs/DATA_FORMAT.md).

## Synchronization

At the recording start boundary the app records:

- Wall-clock UTC (`start_utc` / `end_utc`)
- Device monotonic milliseconds (`start_monotonic_ms` / `end_monotonic_ms`)

Every Polar CSV row uses `timestamp_ms` relative to that monotonic start. Expected alignment for MVP is on the order of **50–100 ms**; offline refinement can use ECG / HR signal features if needed.

## Architecture

| Layer | Choice |
|-------|--------|
| UI / state | Flutter + Riverpod |
| Camera | `camera` |
| Face detection | `google_mlkit_face_detection` |
| Polar BLE | `polar` (official SDK wrapper) |
| Storage | `path_provider` + session folders under app documents |

## Privacy

No authentication and no automatic cloud upload in MVP. Sessions remain in the app sandbox until the operator shares them.

## Open decisions (from spec)

ECG vs HR+RR priority, resolution/FPS trade-offs, minimum signal-quality gates, and anonymization policy — see section 10 of `spec.md`.

## License

Internal Primatio R&D — not published to pub.dev (`publish_to: none`).
