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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;
          if (maxW <= 0 || maxH <= 0) {
            return const SizedBox.shrink();
          }

          // Keep oval inside the camera slot with proportional padding.
          final padX = (maxW * 0.12).clamp(12.0, 36.0);
          final padY = (maxH * 0.08).clamp(8.0, 28.0);
          final availableW = maxW - padX * 2;
          final availableH = maxH - padY * 2;
          const aspect = 3 / 4; // width / height

          late final double ovalW;
          late final double ovalH;
          if (availableW / availableH > aspect) {
            ovalH = availableH;
            ovalW = ovalH * aspect;
          } else {
            ovalW = availableW;
            ovalH = ovalW / aspect;
          }

          return Center(
            child: Container(
              width: ovalW,
              height: ovalH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ovalW / 2),
                border: Border.all(color: color, width: 2.5),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: (ovalH * 0.08).clamp(8.0, 18.0)),
                  child: Text(
                    faceDetected ? 'Face detected' : 'Center your face',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: (ovalW * 0.045).clamp(11.0, 14.0),
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
