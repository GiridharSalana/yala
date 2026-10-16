// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';

/// Modal dialog offering duration presets and custom date/time selection to pause AdGuard Home protection.
class AdGuardPauseDialog extends StatelessWidget {
  const AdGuardPauseDialog({super.key});

  static Future<Duration?> show(BuildContext context) {
    return showDialog<Duration>(
      context: context,
      builder: (context) => const AdGuardPauseDialog(),
    );
  }

  Future<void> _handleCustomDuration(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final initialDate = now.add(const Duration(hours: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: l10n?.aghPauseCustomSelectDate ?? 'Select pause end date',
    );

    if (pickedDate == null || !context.mounted) return;

    final initialTime = TimeOfDay.fromDateTime(initialDate);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: l10n?.aghPauseCustomSelectTime ?? 'Select pause end time',
    );

    if (pickedTime == null || !context.mounted) return;

    final targetDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final duration = targetDateTime.difference(DateTime.now());
    if (duration.inSeconds <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.aghPauseCustomFutureError ??
                  'Pause end time must be in the future.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      Navigator.of(context).pop(duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final presets = <({String label, Duration duration, Key key})>[
      (
        label: l10n?.aghPause15Min ?? 'Pause for 15 minutes',
        duration: const Duration(minutes: 15),
        key: const Key('agh_pause_15m_option'),
      ),
      (
        label: l10n?.aghPause30Min ?? 'Pause for 30 minutes',
        duration: const Duration(minutes: 30),
        key: const Key('agh_pause_30m_option'),
      ),
      (
        label: l10n?.aghPause1Hour ?? 'Pause for 1 hour',
        duration: const Duration(hours: 1),
        key: const Key('agh_pause_1h_option'),
      ),
      (
        label: l10n?.aghPause24Hours ?? 'Pause for 24 hours',
        duration: const Duration(hours: 24),
        key: const Key('agh_pause_24h_option'),
      ),
    ];

    return AlertDialog(
      title: Text(l10n?.aghPauseTitle ?? 'Pause Protection'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...presets.map((preset) {
              return ListTile(
                key: preset.key,
                leading: const Icon(Icons.timer_outlined),
                title: Text(preset.label),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => Navigator.of(context).pop(preset.duration),
              );
            }),
            const Divider(height: 16),
            ListTile(
              key: const Key('agh_pause_custom_option'),
              leading: const Icon(Icons.edit_calendar_outlined),
              title: Text(l10n?.aghPauseCustom ?? 'Custom date & time...'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => _handleCustomDuration(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
      ],
    );
  }
}
