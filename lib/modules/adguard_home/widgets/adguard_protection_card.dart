// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';
import '../models/adguard_models.dart';
import 'adguard_pause_dialog.dart';

/// Card presenting AdGuard Home tri-state protection status and controls
/// (Enable, Pause with duration presets, Disable).
class AdGuardProtectionCard extends StatelessWidget {
  final AdGuardStatus? status;
  final bool isMutating;
  final String? actionError;
  final Future<void> Function({required bool enabled, Duration? duration})
      onSetProtection;

  const AdGuardProtectionCard({
    super.key,
    required this.status,
    required this.isMutating,
    this.actionError,
    required this.onSetProtection,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final protectionState = status?.protectionState ?? AdGuardProtectionState.disabled;
    final isEnabled = protectionState == AdGuardProtectionState.enabled;
    final isPaused = protectionState == AdGuardProtectionState.paused;

    final Color stateColor = isEnabled
        ? Colors.green
        : (isPaused ? Colors.amber.shade800 : colorScheme.error);

    final String stateLabel = isEnabled
        ? (l10n?.aghProtectionEnabled ?? 'Protection Enabled')
        : (isPaused
            ? (l10n?.aghProtectionPaused ?? 'Protection Paused')
            : (l10n?.aghProtectionDisabled ?? 'Protection Disabled'));

    String? pauseTimeText;
    if (isPaused && status?.pauseDurationMs != null && status!.pauseDurationMs > 0) {
      final totalSeconds = (status!.pauseDurationMs / 1000).round();
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      final timeStr = minutes > 60
          ? '${minutes ~/ 60}h ${minutes % 60}m'
          : (minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s');
      pauseTimeText = l10n?.aghRemainingTime(timeStr) ?? 'Remaining: $timeStr';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with tri-state status indicator
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.aghProtectionTitle ?? 'Protection',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isMutating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    key: const Key('agh_protection_toggle_switch'),
                    value: isEnabled,
                    onChanged: (val) {
                      onSetProtection(enabled: val);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (!isEnabled) ...[
              // Tri-state banner container (shown when paused or disabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: stateColor.withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPaused
                          ? Icons.pause_circle_outline
                          : Icons.cancel_outlined,
                      size: 18,
                      color: stateColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stateLabel,
                            key: const Key('agh_protection_state_label'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: stateColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (pauseTimeText != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              pauseTimeText,
                              key: const Key('agh_protection_pause_time'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: stateColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Pause action button
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('agh_protection_pause_button'),
                    icon: const Icon(Icons.pause_rounded, size: 16),
                    label: Text(l10n?.aghActionPause ?? 'Pause...'),
                    onPressed: isMutating
                        ? null
                        : () async {
                            final duration = await AdGuardPauseDialog.show(context);
                            if (duration != null) {
                              await onSetProtection(
                                enabled: false,
                                duration: duration,
                              );
                            }
                          },
                  ),
                ),
              ],
            ),
            if (actionError != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('agh_protection_error_banner'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        actionError!,
                        key: const Key('agh_protection_error_text'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
