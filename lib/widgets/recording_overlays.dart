import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FaceGuideOverlay extends StatelessWidget {
  const FaceGuideOverlay({
    super.key,
    required this.faceDetected,
  });

  final bool faceDetected;

  @override
  Widget build(BuildContext context) {
    final color = faceDetected ? AppColors.accent : Colors.white70;

    return IgnorePointer(
      child: Center(
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(160),
              border: Border.all(color: color, width: 2.5),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  faceDetected ? 'Face detected' : 'Center your face',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    shadows: const [
                      Shadow(blurRadius: 8, color: Colors.black54),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RecordingProgressBar extends StatelessWidget {
  const RecordingProgressBar({
    super.key,
    required this.progress,
    required this.remainingSeconds,
  });

  final double progress;
  final int remainingSeconds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.surfaceAlt,
            color: AppColors.recording,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${remainingSeconds}s remaining',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
