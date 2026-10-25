// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';

/// Card providing OpenWrt procd / init service lifecycle management
/// (Start, Stop, Restart) for AdGuard Home.
///
/// Dispatches strictly through the controller's service operations. Contains
/// zero shell commands, zero init-script paths, and zero package installation logic.
class AdGuardServiceCard extends StatelessWidget {
  final bool isRunning;
  final bool isManageable;
  final bool isManaging;
  final String? actionError;
  final bool? isAutostartEnabled;
  final Future<void> Function(bool enabled)? onToggleAutostart;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onRestart;

  const AdGuardServiceCard({
    super.key,
    required this.isRunning,
    required this.isManageable,
    required this.isManaging,
    this.actionError,
    this.isAutostartEnabled,
    this.onToggleAutostart,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  Future<void> _confirmAndExecute(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() action,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n?.actionConfirm ?? 'Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await action();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.settings_applications_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.aghServiceManagement ?? 'Service Management',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isRunning
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isRunning ? Colors.green : Colors.red,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    isRunning
                        ? (l10n?.aghStatusRunning ?? 'Running')
                        : (l10n?.aghStatusStopped ?? 'Stopped'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isRunning
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            if (actionError != null) ...[
              Container(
                key: const Key('agh_service_error_banner'),
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                        key: const Key('agh_service_error_text'),
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

            if (!isManageable) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n?.aghServiceNotManageable ??
                            'Service is not manageable on this router',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Action Buttons: Start, Stop, Restart
              if (isManaging)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Row(
                  children: [
                    if (!isRunning)
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('agh_service_start_button'),
                          icon: const Icon(Icons.play_arrow_rounded, size: 16),
                          label: Text(l10n?.aghActionStart ?? 'Start'),
                          onPressed: () => onStart(),
                        ),
                      ),
                    if (isRunning) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('agh_service_stop_button'),
                          icon: const Icon(Icons.stop_rounded, size: 16),
                          label: Text(l10n?.aghActionStop ?? 'Stop'),
                          onPressed: () => _confirmAndExecute(
                            context,
                            title:
                                l10n?.aghServiceConfirmStopTitle ??
                                'Stop AdGuard Home Service?',
                            message:
                                l10n?.aghServiceConfirmStopMessage ??
                                'Stopping the service will disable DNS resolution if AdGuard Home is your primary DNS listener. Continue?',
                            action: onStop,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          key: const Key('agh_service_restart_button'),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(l10n?.aghActionRestart ?? 'Restart'),
                          onPressed: () => _confirmAndExecute(
                            context,
                            title:
                                l10n?.aghServiceConfirmRestartTitle ??
                                'Restart AdGuard Home Service?',
                            message:
                                l10n?.aghServiceConfirmRestartMessage ??
                                'Restarting the service will temporarily interrupt DNS queries. Continue?',
                            action: onRestart,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              if (isAutostartEnabled != null && onToggleAutostart != null) ...[
                const Divider(height: 24),
                SwitchListTile(
                  key: const Key('agh_service_autostart_switch'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    l10n?.aghServiceAutostart ?? 'Autostart on boot',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    l10n?.aghServiceAutostartSubtitle ??
                        'Automatically start AdGuard Home on router boot',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: isAutostartEnabled!,
                  onChanged: isManaging ? null : (v) => onToggleAutostart!(v),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
