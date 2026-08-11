#!/usr/bin/env python3
"""
Primatio rPPG - Timestamp Synchronization Validator
--------------------------------------------------
Evaluates alignment between video-derived pulse signal and Polar H10 ground truth.
"""

import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd
import cv2
from scipy import signal
from scipy.stats import pearsonr
import matplotlib.pyplot as plt


def load_metadata(session_dir: Path) -> dict:
    meta_path = session_dir / "metadata.json"
    if meta_path.exists():
        with open(meta_path) as f:
            return json.load(f)
    return {}


def load_polar_data(session_dir: Path) -> pd.DataFrame:
    csv_path = session_dir / "polar_data.csv"
    if not csv_path.exists():
        raise FileNotFoundError(f"polar_data.csv not found in {session_dir}")

    df = pd.read_csv(csv_path)

    # Normalize column names (case-insensitive)
    df.columns = [c.lower().strip() for c in df.columns]

    if "timestamp_ms" not in df.columns:
        raise ValueError("polar_data.csv must contain a 'timestamp_ms' column")

    return df


def extract_ground_truth(df: pd.DataFrame, target_fs: float = 30.0):
    """
    Returns a 1D signal resampled to approximately target_fs (Hz)
    Priority: ecg_uv > rr_ms > hr_bpm
    """
    t = df["timestamp_ms"].values.astype(float) / 1000.0  # seconds

    if "ecg_uv" in df.columns and df["ecg_uv"].notna().sum() > 10:
        sig = df["ecg_uv"].values.astype(float)
        name = "ECG"
    elif "rr_ms" in df.columns and df["rr_ms"].notna().sum() > 5:
        # Convert RR intervals into a rough pulse-like signal
        # Better: just use HR for now if only RR available
        if "hr_bpm" in df.columns:
            sig = df["hr_bpm"].ffill().values.astype(float)
            name = "HR (from RR)"
        else:
            sig = df["rr_ms"].ffill().values.astype(float)
            name = "RR"
    elif "hr_bpm" in df.columns:
        sig = df["hr_bpm"].ffill().values.astype(float)
        name = "HR"
    else:
        raise ValueError("No usable physiological column found (ecg_uv / rr_ms / hr_bpm)")

    # Remove NaNs
    mask = ~np.isnan(sig)
    t = t[mask]
    sig = sig[mask]

    # Resample to uniform grid
    if len(t) < 10:
        raise ValueError("Too few valid Polar samples")

    duration = t[-1] - t[0]
    n_samples = int(duration * target_fs)
    t_uniform = np.linspace(t[0], t[-1], max(n_samples, 2))
    sig_uniform = np.interp(t_uniform, t, sig)

    return t_uniform, sig_uniform, name


def extract_rppg_from_video(video_path: Path, target_fs: float = 30.0):
    """
    Very simple green-channel average rPPG (good enough for sync check).
    For better results, replace with POS/CHROM later.
    """
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 30.0

    frames = []
    timestamps = []

    frame_idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Convert to RGB
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # Simple center crop as face proxy (improve later with face detection)
        h, w, _ = rgb.shape
        cy, cx = h // 2, w // 2
        size = min(h, w) // 3
        roi = rgb[cy - size:cy + size, cx - size:cx + size]

        # Average of green channel
        green_mean = roi[:, :, 1].mean()
        frames.append(green_mean)
        timestamps.append(frame_idx / fps)
        frame_idx += 1

    cap.release()

    t = np.array(timestamps)
    sig = np.array(frames, dtype=float)

    if len(sig) < 10:
        raise ValueError("Too few video frames for rPPG extraction")

    # Bandpass filter (0.7 – 3.5 Hz ≈ 42–210 bpm)
    sos = signal.butter(3, [0.7, 3.5], btype="bandpass", fs=fps, output="sos")
    sig_f = signal.sosfiltfilt(sos, sig)

    # Resample to target_fs if needed
    if abs(fps - target_fs) > 1:
        n_samples = int(t[-1] * target_fs)
        t_new = np.linspace(0, t[-1], max(n_samples, 2))
        sig_f = np.interp(t_new, t, sig_f)
        t = t_new

    return t, sig_f, fps


def find_best_lag(sig_video, sig_gt, fs: float, max_lag_sec: float = 2.0):
    """
    Returns best lag in seconds (positive = video is delayed relative to GT)
    and the maximum correlation value.
    """
    # Ensure same length
    min_len = min(len(sig_video), len(sig_gt))
    a = sig_video[:min_len]
    b = sig_gt[:min_len]

    # Normalize
    a = (a - a.mean()) / (a.std() + 1e-8)
    b = (b - b.mean()) / (b.std() + 1e-8)

    max_lag_samples = int(max_lag_sec * fs)
    correlation = signal.correlate(a, b, mode="full")
    lags = signal.correlation_lags(len(a), len(b), mode="full")

    # Restrict search range
    mask = (lags >= -max_lag_samples) & (lags <= max_lag_samples)
    correlation = correlation[mask]
    lags = lags[mask]

    best_idx = np.argmax(correlation)
    best_lag_samples = lags[best_idx]
    best_corr = correlation[best_idx] / len(a)  # approximate normalization

    best_lag_sec = best_lag_samples / fs
    return best_lag_sec, best_corr


def compute_windowed_lags(sig_video, sig_gt, fs: float, window_sec: float = 10.0):
    """Estimate lag in sliding windows to detect drift."""
    window = int(window_sec * fs)
    step = max(window // 2, 1)
    lags = []
    centers = []

    for start in range(0, min(len(sig_video), len(sig_gt)) - window, step):
        end = start + window
        lag, _ = find_best_lag(sig_video[start:end], sig_gt[start:end], fs, max_lag_sec=1.0)
        lags.append(lag)
        centers.append((start + end) / 2 / fs)

    return np.array(centers), np.array(lags)


def plot_diagnostics(t_v, sig_v, t_gt, sig_gt, lag_sec, corr, window_centers, window_lags, out_path: Path):
    fig, axes = plt.subplots(3, 1, figsize=(12, 10), sharex=False)

    # 1. Raw signals (first 15 seconds)
    ax = axes[0]
    max_t = 15
    mask_v = t_v <= max_t
    mask_gt = t_gt <= max_t
    ax.plot(t_v[mask_v], sig_v[mask_v], label="Video rPPG", alpha=0.8)
    ax.plot(t_gt[mask_gt], sig_gt[mask_gt], label="Polar GT", alpha=0.8)
    ax.set_title(f"Signals (first {max_t}s) — estimated lag = {lag_sec*1000:.1f} ms | corr = {corr:.3f}")
    ax.legend()
    ax.set_ylabel("Amplitude")

    # 2. Aligned signals
    ax = axes[1]
    # Shift video
    t_v_shifted = t_v - lag_sec
    ax.plot(t_v_shifted[mask_v], sig_v[mask_v], label="Video (aligned)", alpha=0.8)
    ax.plot(t_gt[mask_gt], sig_gt[mask_gt], label="Polar GT", alpha=0.8)
    ax.set_title("After alignment")
    ax.legend()
    ax.set_ylabel("Amplitude")

    # 3. Lag over time (drift)
    ax = axes[2]
    if len(window_lags) > 0:
        ax.plot(window_centers, window_lags * 1000, "o-", label="Windowed lag")
        ax.axhline(lag_sec * 1000, color="red", linestyle="--", label="Global lag")
        ax.set_ylabel("Lag (ms)")
        ax.set_xlabel("Time (s)")
        ax.set_title("Lag stability across recording (drift check)")
        ax.legend()
    else:
        ax.text(0.5, 0.5, "Not enough data for windowed analysis", ha="center")

    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    plt.close()
    print(f"Saved diagnostic plot → {out_path}")


def main():
    parser = argparse.ArgumentParser(description="Validate video ↔ Polar timestamp synchronization")
    parser.add_argument("session_dir", type=str, help="Path to session folder")
    parser.add_argument("--fs", type=float, default=30.0, help="Target sampling frequency (Hz)")
    parser.add_argument("--max-lag", type=float, default=2.0, help="Maximum lag to search (seconds)")
    args = parser.parse_args()

    session_dir = Path(args.session_dir)
    if not session_dir.exists():
        raise FileNotFoundError(session_dir)

    print(f"\n=== Validating session: {session_dir.name} ===\n")

    # Load data
    meta = load_metadata(session_dir)
    if meta:
        print(f"Metadata keys: {', '.join(sorted(meta.keys())[:12])}")
    polar_df = load_polar_data(session_dir)
    video_path = session_dir / "video.mp4"
    if not video_path.exists():
        raise FileNotFoundError("video.mp4 not found")

    # Extract signals
    print("Extracting Polar ground truth...")
    t_gt, sig_gt, gt_name = extract_ground_truth(polar_df, target_fs=args.fs)
    print(f"  → Using {gt_name} ({len(sig_gt)} samples)")

    print("Extracting simple rPPG from video (green channel)...")
    t_v, sig_v, video_fps = extract_rppg_from_video(video_path, target_fs=args.fs)
    print(f"  → Video FPS: {video_fps:.2f} | samples: {len(sig_v)}")

    # Global lag
    print("\nComputing optimal lag via cross-correlation...")
    lag_sec, corr = find_best_lag(sig_v, sig_gt, fs=args.fs, max_lag_sec=args.max_lag)

    print(f"\nResults:")
    print(f"  Best lag          : {lag_sec*1000:+.1f} ms")
    print(f"  Peak correlation  : {corr:.4f}")

    # Drift analysis
    print("\nChecking lag stability (windowed)...")
    centers, window_lags = compute_windowed_lags(sig_v, sig_gt, fs=args.fs, window_sec=8.0)
    if len(window_lags) > 1:
        drift = np.std(window_lags) * 1000
        print(f"  Lag std across windows: {drift:.1f} ms")
        print(f"  Min / Max lag         : {window_lags.min()*1000:.1f} / {window_lags.max()*1000:.1f} ms")
    else:
        drift = None
        print("  Not enough data for reliable drift estimate")

    # Interpretation
    print("\n--- Interpretation ---")
    abs_lag = abs(lag_sec) * 1000
    if abs_lag < 50 and (drift is None or drift < 30):
        print("✅ EXCELLENT synchronization")
    elif abs_lag < 150 and (drift is None or drift < 60):
        print("✔️  GOOD / Usable for training")
    elif abs_lag < 300:
        print("⚠️  ACCEPTABLE but should be improved")
    else:
        print("❌ POOR – investigate timestamping logic")

    # Plot
    out_plot = session_dir / "sync_diagnostic.png"
    plot_diagnostics(t_v, sig_v, t_gt, sig_gt, lag_sec, corr, centers, window_lags, out_plot)

    # Save numeric summary
    summary = {
        "session": session_dir.name,
        "lag_ms": float(lag_sec * 1000),
        "correlation": float(corr),
        "lag_std_ms": float(drift) if drift is not None else None,
        "gt_signal": gt_name,
        "video_fps": float(video_fps),
    }
    summary_path = session_dir / "sync_summary.json"
    with open(summary_path, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"\nSaved summary → {summary_path}")


if __name__ == "__main__":
    main()
