# Script: Plot BPM from Video (rPPG) vs Polar Ground Truth

**Project:** Primatio rPPG Collector  
**Purpose:** Extract heart rate (BPM) over time from the recorded video using a simple rPPG method and compare it with the Polar H10 ground truth.  
**Language:** Python 3.10+  

---

## 1. Goal

Given a session folder, this script:

1. Extracts a pulse signal (rPPG) from the video
2. Estimates BPM in sliding windows
3. Loads the Polar BPM / HR data
4. Plots both curves over time for visual comparison

Useful for:
- Quick visual quality check of a recording
- Seeing how well the video tracks heart rate changes
- Debugging lighting / motion / face presence issues

---

## 2. Expected Session Structure

```
session_YYYYMMDD_HHMMSS_subjectID/
├── video.mp4
├── polar_data.csv
└── metadata.json          # optional
```

### Expected columns in `polar_data.csv`
- `timestamp_ms` (required)
- `hr_bpm` (preferred)
- or `rr_ms` / `ecg_uv` (will be converted)

---

## 3. Dependencies

```bash
pip install numpy pandas scipy opencv-python matplotlib
```

---

## 4. Full Script

Save as `plot_bpm.py`:

```python
#!/usr/bin/env python3
"""
Primatio rPPG - Plot BPM from Video vs Polar
--------------------------------------------
Extracts heart rate over time from video (simple rPPG)
and compares it with Polar H10 ground truth.
"""

import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd
import cv2
from scipy import signal
import matplotlib.pyplot as plt


def load_polar_hr(session_dir: Path):
    """Load Polar HR data and return time (seconds) + bpm arrays."""
    csv_path = session_dir / "polar_data.csv"
    if not csv_path.exists():
        raise FileNotFoundError(f"polar_data.csv not found in {session_dir}")

    df = pd.read_csv(csv_path)
    df.columns = [c.lower().strip() for c in df.columns]

    if "timestamp_ms" not in df.columns:
        raise ValueError("polar_data.csv must contain 'timestamp_ms'")

    t = df["timestamp_ms"].values.astype(float) / 1000.0  # seconds

    if "hr_bpm" in df.columns and df["hr_bpm"].notna().sum() > 5:
        hr = df["hr_bpm"].values.astype(float)
    elif "rr_ms" in df.columns and df["rr_ms"].notna().sum() > 5:
        # Convert RR intervals (ms) to instantaneous HR
        rr = df["rr_ms"].values.astype(float)
        hr = np.where(rr > 0, 60000.0 / rr, np.nan)
    else:
        raise ValueError("No usable HR column found (hr_bpm or rr_ms)")

    # Clean
    mask = ~np.isnan(hr) & (hr > 30) & (hr < 220)
    return t[mask], hr[mask]


def extract_green_signal(video_path: Path):
    """
    Extract average green channel from center ROI of each frame.
    Returns timestamps (s) and raw green signal.
    """
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 1:
        fps = 30.0

    green_values = []
    times = []
    frame_idx = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Center ROI (simple face proxy)
        h, w = frame.shape[:2]
        cy, cx = h // 2, w // 2
        size = min(h, w) // 3
        roi = frame[cy-size:cy+size, cx-size:cx+size]

        # Green channel mean (OpenCV is BGR)
        green_mean = roi[:, :, 1].mean()
        green_values.append(green_mean)
        times.append(frame_idx / fps)
        frame_idx += 1

    cap.release()
    return np.array(times), np.array(green_values, dtype=float), fps


def bandpass_filter(sig, fs, low=0.75, high=3.5):
    """Bandpass filter (0.75–3.5 Hz ≈ 45–210 bpm)."""
    sos = signal.butter(3, [low, high], btype="bandpass", fs=fs, output="sos")
    return signal.sosfiltfilt(sos, sig)


def estimate_bpm_sliding(sig, fs, window_sec=8.0, step_sec=1.0):
    """
    Estimate BPM in sliding windows using FFT peak.
    Returns center times and BPM values.
    """
    window = int(window_sec * fs)
    step = int(step_sec * fs)
    times = []
    bpms = []

    for start in range(0, len(sig) - window, step):
        segment = sig[start:start+window]
        segment = segment - segment.mean()

        # FFT
        n = len(segment)
        freqs = np.fft.rfftfreq(n, d=1/fs)
        fft_mag = np.abs(np.fft.rfft(segment))

        # Restrict to plausible HR band
        mask = (freqs >= 0.75) & (freqs <= 3.5)
        if not np.any(mask):
            continue

        peak_freq = freqs[mask][np.argmax(fft_mag[mask])]
        bpm = peak_freq * 60.0

        center_time = (start + window/2) / fs
        times.append(center_time)
        bpms.append(bpm)

    return np.array(times), np.array(bpms)


def plot_results(t_video, bpm_video, t_polar, hr_polar, session_name, out_path: Path):
    fig, axes = plt.subplots(2, 1, figsize=(12, 8), sharex=True)

    # Top: BPM comparison
    ax = axes[0]
    ax.plot(t_video, bpm_video, "b-", linewidth=2, label="Video rPPG (estimated)")
    ax.plot(t_polar, hr_polar, "r-", alpha=0.7, linewidth=1.5, label="Polar H10")
    ax.set_ylabel("Heart Rate (BPM)")
    ax.set_title(f"BPM over time — {session_name}")
    ax.legend(loc="upper right")
    ax.grid(True, alpha=0.3)
    ax.set_ylim(40, 180)

    # Bottom: difference
    ax = axes[1]
    # Interpolate Polar to video times for difference
    if len(t_polar) > 2 and len(t_video) > 2:
        hr_polar_interp = np.interp(t_video, t_polar, hr_polar)
        diff = bpm_video - hr_polar_interp
        ax.plot(t_video, diff, "k-", alpha=0.8)
        ax.axhline(0, color="gray", linestyle="--")
        ax.set_ylabel("Difference (Video - Polar) BPM")
        ax.set_xlabel("Time (seconds)")
        ax.grid(True, alpha=0.3)

        mae = np.mean(np.abs(diff))
        ax.set_title(f"Error over time (MAE = {mae:.1f} BPM)")
    else:
        ax.text(0.5, 0.5, "Not enough data to compute difference", ha="center", va="center")

    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    plt.close()
    print(f"Saved plot → {out_path}")


def main():
    parser = argparse.ArgumentParser(description="Plot BPM from video (rPPG) vs Polar")
    parser.add_argument("session_dir", type=str, help="Path to session folder")
    parser.add_argument("--window", type=float, default=8.0, help="Sliding window size in seconds")
    parser.add_argument("--step", type=float, default=1.0, help="Step between windows in seconds")
    args = parser.parse_args()

    session_dir = Path(args.session_dir)
    if not session_dir.exists():
        raise FileNotFoundError(session_dir)

    print(f"\n=== Plotting BPM for: {session_dir.name} ===\n")

    video_path = session_dir / "video.mp4"
    if not video_path.exists():
        raise FileNotFoundError("video.mp4 not found")

    # 1. Polar ground truth
    print("Loading Polar HR...")
    t_polar, hr_polar = load_polar_hr(session_dir)
    print(f"  → {len(hr_polar)} Polar samples | mean HR: {np.nanmean(hr_polar):.1f} BPM")

    # 2. Video rPPG
    print("Extracting green signal from video...")
    t_raw, green, fps = extract_green_signal(video_path)
    print(f"  → Video FPS: {fps:.2f} | frames: {len(green)}")

    print("Filtering signal...")
    green_f = bandpass_filter(green, fs=fps)

    print(f"Estimating BPM (window={args.window}s, step={args.step}s)...")
    t_bpm, bpm_video = estimate_bpm_sliding(
        green_f, fs=fps,
        window_sec=args.window,
        step_sec=args.step
    )
    print(f"  → {len(bpm_video)} BPM estimates | mean: {np.nanmean(bpm_video):.1f} BPM")

    # 3. Plot
    out_path = session_dir / "bpm_comparison.png"
    plot_results(t_bpm, bpm_video, t_polar, hr_polar, session_dir.name, out_path)

    # Quick stats
    if len(t_polar) > 5 and len(t_bpm) > 5:
        hr_interp = np.interp(t_bpm, t_polar, hr_polar)
        mae = np.mean(np.abs(bpm_video - hr_interp))
        print(f"\nMean Absolute Error (Video vs Polar): {mae:.2f} BPM")

    print("\nDone.")


if __name__ == "__main__":
    main()
```

---

## 5. How to Run

```bash
python plot_bpm.py /path/to/session_20260808_143022_subject01
```

Optional parameters:

```bash
python plot_bpm.py ./my_session --window 10 --step 2
```

- `--window`: size of the sliding window in seconds (default 8s)
- `--step`: how often to compute a new BPM value (default 1s)

---

## 6. Output

- Console: mean HR from Polar and from video + MAE
- Image: `bpm_comparison.png` with two plots:
  1. BPM curves (Video rPPG vs Polar)
  2. Error (difference) over time

---

## 7. Tips

- For better results, keep the face well-lit and as still as possible.
- The current method uses a simple center ROI + green channel. It works reasonably well for clean recordings.
- Later we can improve it with:
  - Real face detection (MediaPipe / OpenCV DNN)
  - Better rPPG methods (POS, CHROM, POS)
  - Adaptive filtering

---

**Created for Primatio R&D – August 2026**
