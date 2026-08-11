import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/session_metadata.dart';
import '../theme/app_theme.dart';

/// Compact SYS/DIA mmHg entry used before and after the 30s take.
class BloodPressureInput extends StatelessWidget {
  const BloodPressureInput({
    super.key,
    required this.title,
    required this.systolicController,
    required this.diastolicController,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final TextEditingController systolicController;
  final TextEditingController diastolicController;

  static BloodPressureReading? parse(
    TextEditingController systolic,
    TextEditingController diastolic,
  ) {
    final sys = int.tryParse(systolic.text.trim());
    final dia = int.tryParse(diastolic.text.trim());
    if (sys == null || dia == null) return null;
    final reading = BloodPressureReading(
      systolicMmhg: sys,
      diastolicMmhg: dia,
    );
    return reading.isPlausible ? reading : null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: systolicController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'SYS',
                  hintText: '120',
                  suffixText: 'mmHg',
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '/',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: diastolicController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'DIA',
                  hintText: '80',
                  suffixText: 'mmHg',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
