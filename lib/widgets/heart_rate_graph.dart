import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/polar_service.dart';
import '../theme/app_theme.dart';

/// Live heart-rate strip chart for the recording screen.
class HeartRateGraph extends StatelessWidget {
  const HeartRateGraph({
    super.key,
    required this.points,
    this.currentBpm,
    this.windowMs = PolarService.hrHistoryWindowMs,
  });

  final List<HeartRatePoint> points;
  final int? currentBpm;
  final int windowMs;

  @override
  Widget build(BuildContext context) {
    final bpm = currentBpm ?? (points.isNotEmpty ? points.last.bpm : null);

    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                const Text(
                  'Heart rate',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  bpm != null ? '$bpm' : '—',
                  style: const TextStyle(
                    color: AppColors.recording,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'bpm',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: CustomPaint(
                painter: _HeartRateGraphPainter(
                  points: points,
                  windowMs: windowMs,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeartRateGraphPainter extends CustomPainter {
  _HeartRateGraphPainter({
    required this.points,
    required this.windowMs,
  });

  final List<HeartRatePoint> points;
  final int windowMs;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    // Horizontal guide lines.
    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.length < 2) {
      _drawEmptyHint(canvas, size);
      return;
    }

    final endMs = points.last.timestampMs;
    final startMs = endMs - windowMs;
    final visible = points.where((p) => p.timestampMs >= startMs).toList();
    if (visible.length < 2) {
      _drawEmptyHint(canvas, size);
      return;
    }

    var minBpm = visible.first.bpm;
    var maxBpm = visible.first.bpm;
    for (final p in visible) {
      minBpm = math.min(minBpm, p.bpm);
      maxBpm = math.max(maxBpm, p.bpm);
    }
    // Keep a readable vertical range.
    minBpm = math.max(40, minBpm - 8);
    maxBpm = math.min(220, maxBpm + 8);
    if (maxBpm <= minBpm) {
      maxBpm = minBpm + 20;
    }

    final path = Path();
    final fillPath = Path();
    for (var i = 0; i < visible.length; i++) {
      final p = visible[i];
      final x = ((p.timestampMs - startMs) / windowMs).clamp(0.0, 1.0) *
          size.width;
      final y = (1 - ((p.bpm - minBpm) / (maxBpm - minBpm)).clamp(0.0, 1.0)) *
          size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath
      ..lineTo(
        ((visible.last.timestampMs - startMs) / windowMs).clamp(0.0, 1.0) *
            size.width,
        size.height,
      )
      ..close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          AppColors.recording.withValues(alpha: 0.35),
          AppColors.recording.withValues(alpha: 0.02),
        ],
      );
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = AppColors.recording
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Latest point marker.
    final last = visible.last;
    final lastX =
        ((last.timestampMs - startMs) / windowMs).clamp(0.0, 1.0) * size.width;
    final lastY =
        (1 - ((last.bpm - minBpm) / (maxBpm - minBpm)).clamp(0.0, 1.0)) *
            size.height;
    canvas.drawCircle(
      Offset(lastX, lastY),
      3.5,
      Paint()..color = AppColors.recording,
    );
  }

  void _drawEmptyHint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Waiting for Polar HR…',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _HeartRateGraphPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.windowMs != windowMs;
  }
}
