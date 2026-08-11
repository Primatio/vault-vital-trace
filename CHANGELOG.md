# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-08-11

First public academic release.

### Added

- Flutter collector for synchronized ~30 s facial video + Polar H10 (HR / RR / ECG)
- Operator-entered cuff blood pressure (SYS/DIA) before and after each take
- ML Kit face gating for the full recording window
- Local session storage (`video.mp4`, `polar_data.csv`, `metadata.json`, `face_tracking.json`)
- Explicit export/share only (no automatic cloud upload)
- Offline scripts for sync validation and BPM comparison (`scripts/`)
- Apache License 2.0, `NOTICE`, `CITATION.cff`
- Ethics / LGPD / CEP guidance in the README

[0.1.0]: https://github.com/Primatio/vault-vital-trace/releases/tag/v0.1.0
