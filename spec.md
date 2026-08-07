# Spec: rPPG Data Collection App  
**Project Codename:** Vault rPPG Collector  
**Company:** Primatio  
**Type:** Internal R&D Project #001  
**Status:** Draft v1.0  
**Last Updated:** 2026-08-06  
**Author:** Felipe Andrade - CEO / R&D  

---

## 1. Overview

### 1.1 Goal
Build a mobile application (Flutter) that enables high-quality, synchronized collection of:
- 30-second facial video recordings
- Ground-truth physiological signals from a **Polar H10** chest strap (ECG, RR-intervals, Heart Rate)
- Upload consolidated data to a Google Bucket

The resulting paired data will be used to train and evaluate remote photoplethysmography (rPPG) machine learning models.

### 1.2 Business Context
This is Primatio’s first formal R&D project. The objective is both technical (produce a usable data collection tool) and organizational (establish good engineering practices, documentation culture, and iterative delivery for future R&D initiatives).

### 1.3 Success Criteria
- Produce synchronized video + Polar H10 recordings of sufficient quality for rPPG research.
- App is stable enough for internal use and small-scale external data collection.
- Clear data format and documentation that allows future ML engineers to consume the datasets easily.
- Project delivered with proper version control, documentation, and post-mortem.

---

## 2. Scope

### 2.1 In Scope (MVP)
- Flutter app for Android and iOS
- Camera preview + 30-second video recording (front camera preferred)
- Face tracking (While the camera is recording, process the live camera stream and detect faces continuously. Use google_mlkit_face_detection)
- Bluetooth Low Energy connection to Polar H10
- Streaming and recording of:
  - Heart Rate (BPM)
  - RR-intervals
  - ECG (130 Hz) — preferred
- Local storage of video + synchronized sensor data
- Basic session metadata (timestamp, device info, notes, subject ID)
- Simple UI for starting/stopping sessions and reviewing recorded files before uploading
- Export Upload share of session data

### 2.2 Out of Scope (MVP)
- Real-time rPPG inference
- Multi-subject management / database
- Support for other sensors (beyond Polar H10)
- Automated quality scoring of recordings
- User authentication

### 2.3 Future Considerations (Post-MVP)
- ROI guidance
- Quality metrics (motion, lighting, signal quality)
- Cloud sync + dataset management dashboard
- Batch export and anonymization tools

---

## 3. User Personas & Stories

### Primary User
**Researcher / Data Collector** at Primatio (or partner labs)
- Needs reliable, repeatable data collection
- Wants minimal friction during sessions
- Needs clear indication that data is being recorded correctly

### Key User Stories
1. As a researcher, I want to connect to a Polar H10 so that I have accurate ground-truth ECG/HR data.
2. As a researcher, I want to record exactly 30 seconds of face video synchronized with the Polar data.
3. As a researcher, I want to add a subject ID and optional notes to each session.
4. As a researcher, I want to review the list of recorded sessions and verify that both video and sensor files exist.
5. As a researcher, I want to export a complete session folder so I can transfer it to our training pipeline.

---

## 4. Functional Requirements

### 4.1 Device Connection
- Scan for nearby Polar devices
- Connect to Polar H10 by device ID
- Display connection status, battery level, and signal quality indicators
- Handle disconnection and reconnection gracefully
- Support streaming of HR, RR-intervals, and ECG

### 4.2 Recording Session
- Start recording only when:
  - Polar H10 is connected and streaming
  - Camera is ready
- Record simultaneously:
  - Video (front camera, configurable resolution/FPS)
  - Polar data streams with high-resolution timestamps
- Fixed duration: **30 seconds** (with visual countdown)
- Option to cancel mid-recording
- Visual and haptic feedback when recording starts/stops

### 4.3 Data Storage
Each session must produce a folder containing:
```
session_YYYYMMDD_HHMMSS_subjectID/
├── video.mp4
├── polar_data.csv          # or .json / .parquet
├── metadata.json
└── (optional) preview.jpg
```

**metadata.json** should include:
- Session ID / UUID
- Subject ID
- Start/end timestamps (UTC + device monotonic time)
- Device info (phone model, OS version, app version)
- Polar H10 device ID and firmware (if available)
- Recording settings (resolution, FPS, which streams were active)
- Free-text notes
- App version

### 4.4 Data Format – polar_data
Recommended columns (CSV):
- `timestamp_ms` (relative to session start or absolute UTC)
- `hr_bpm`
- `rr_ms` (when available)
- `ecg_uv` (when ECG is streamed)
- `acc_x`, `acc_y`, `acc_z` (optional)

High sampling rate for ECG (~130 Hz) is desirable.

### 4.5 Session Management
- List of past sessions with status (complete / incomplete)
- Ability to delete sessions
- Ability to share/export a session folder (share sheet or file picker)

---

## 5. Non-Functional Requirements

| Category          | Requirement                                      | Priority |
|-------------------|--------------------------------------------------|----------|
| Reliability       | No data loss on normal app backgrounding         | High     |
| Synchronization   | Video and sensor data aligned within ~50-100 ms  | High     |
| Performance       | Smooth camera preview + BLE streaming for 30s    | High     |
| Battery           | Reasonable consumption during short sessions     | Medium   |
| Compatibility     | Android 10+ and iOS 14+                          | High     |
| Usability         | Can be operated by non-engineers after short training | High |
| Privacy           | Data stays on device until explicitly exported   | High     |

---

## 6. Technical Architecture

### 6.1 Recommended Stack
- **Framework:** Flutter (stable channel)
- **Language:** Dart
- **Camera:** `camera` or `camera_awesome`
- **Polar Integration:** `polar` package (wrapper around official Polar BLE SDK)
- **State Management:** Riverpod or Bloc (team preference)
- **Local Storage:** `path_provider` + direct file I/O
- **Permissions:** `permission_handler`
- **UUID / Metadata:** `uuid`, `package_info_plus`, `device_info_plus`

### 6.2 High-Level Flow
```
[UI] → Start Session
        ↓
[Connect Polar H10] ←→ BLE Stream (HR / RR / ECG)
        ↓
[Initialize Camera]
        ↓
[Start Simultaneous Recording] → Timer 30s
        ↓
[Stop Recording] → Save video.mp4 + polar_data + metadata.json
        ↓
[Session Complete] → Show success + option to export
```

### 6.3 Synchronization Strategy
- Record monotonic clock timestamp at the exact moment recording starts.
- Attach high-resolution timestamps to every Polar sample.
- Store both wall-clock (UTC) and monotonic timestamps in metadata.
- Post-processing (outside the app) can refine alignment if needed using signal characteristics.

---

## 7. UI / UX Outline (MVP)

### Screens
1. **Home / Sessions List**
   - List of previous recordings
   - “New Session” button
   - Connection status indicator

2. **Device Connection**
   - Scan / Select Polar H10
   - Show battery and live HR once connected

3. **Recording Screen**
   - Full-screen camera preview (face guidance overlay optional)
   - Live HR / connection status
   - Big “Start Recording” button
   - Countdown (30 → 0)
   - Progress bar + cancel option

4. **Session Detail / Review**
   - Metadata
   - File list and sizes
   - Export / Share / Delete actions

### Design Principles
- Minimal, clean, research-tool aesthetic
- High contrast status indicators (connected / recording / error)
- Prevent accidental exits during recording

---

## 8. Risks & Mitigations

| Risk                              | Impact | Likelihood | Mitigation |
|-----------------------------------|--------|------------|----------|
| Poor time synchronization         | High   | Medium     | Careful timestamping + documentation of expected accuracy |
| Polar BLE instability             | High   | Medium     | Robust reconnection logic + clear UI feedback |
| Camera permission / focus issues  | Medium | Medium     | Thorough testing on multiple devices |
| iOS background restrictions       | Medium | Medium     | Keep app in foreground during recording |
| Data format changes later         | Medium | Low        | Version the metadata schema |

---

## 9. Milestones (Suggested)

| Phase | Deliverable                              | Target |
|-------|------------------------------------------|--------|
| 0     | Project setup + repository + this spec   | Week 1 |
| 1     | Polar H10 connection + live HR streaming | Week 2 |
| 2     | Camera preview + 30s video recording     | Week 3 |
| 3     | Synchronized recording + local storage   | Week 4 |
| 4     | Session list, metadata, export           | Week 5 |
| 5     | Internal testing + polish + documentation| Week 6 |
| 6     | First real data collection sessions      | Week 7+ |

---

## 10. Open Questions

1. Do we prioritize ECG streaming or is HR + RR enough for the first dataset?
2. Preferred video resolution / FPS trade-off (quality vs file size)?
3. Should we enforce a minimum signal quality before allowing recording to start?
4. Any specific subject anonymization requirements from the start?
5. Target number of subjects / hours of data for the first internal dataset?

---

## 11. Definition of Done (MVP)

- [ ] App connects reliably to Polar H10 and streams HR + RR (and ECG if feasible)
- [ ] Records exactly ~30 seconds of video + sensor data
- [ ] Produces well-structured session folders with metadata
- [ ] Works on at least one recent Android and one recent iOS device
- [ ] Basic session list and export functionality
- [ ] README + data format documentation
- [ ] Internal demo completed successfully

---

**Next Step:** Review this specification with the team, resolve open questions, and create the Flutter project repository.  

*This document is living and should be updated as decisions are made during the R&D process.*
