import 'package:flutter/material.dart';

import '../services/polar_service.dart';
import '../theme/app_theme.dart';

class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip({
    super.key,
    required this.state,
    this.compact = false,
  });

  final PolarLiveState? state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final (label, color) = _labelAndColor(s);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (s?.heartRate != null && s!.isStreaming) ...[
            const SizedBox(width: 8),
            Text(
              '${s.heartRate} bpm',
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.9),
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  (String, Color) _labelAndColor(PolarLiveState? s) {
    if (s == null) {
      return ('Polar offline', AppColors.disconnected);
    }
    switch (s.connectionState) {
      case PolarConnectionState.streaming:
        return ('Polar streaming', AppColors.connected);
      case PolarConnectionState.connected:
        return ('Polar connected', AppColors.connected);
      case PolarConnectionState.connecting:
        return ('Connecting…', AppColors.warning);
      case PolarConnectionState.scanning:
        return ('Scanning…', AppColors.warning);
      case PolarConnectionState.error:
        return ('Polar error', AppColors.error);
      case PolarConnectionState.disconnected:
        return ('Polar offline', AppColors.disconnected);
    }
  }
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.tone = BannerTone.info,
  });

  final String message;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      BannerTone.info => AppColors.accent,
      BannerTone.warning => AppColors.warning,
      BannerTone.error => AppColors.error,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontSize: 13, height: 1.35),
      ),
    );
  }
}

enum BannerTone { info, warning, error }
