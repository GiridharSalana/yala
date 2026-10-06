// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../models/sqm_overview.dart';
import 'sqm_flow_offloading_dialog.dart';

/// Card showing the SQM daemon service running/enabled status and service controls.
class SqmStatusCard extends ConsumerStatefulWidget {
  final SqmOverview overview;
  final VoidCallback onRefresh;

  const SqmStatusCard({
    super.key,
    required this.overview,
    required this.onRefresh,
  });

  @override
  ConsumerState<SqmStatusCard> createState() => _SqmStatusCardState();
}

class _SqmStatusCardState extends ConsumerState<SqmStatusCard> {
  bool _isToggling = false;

  Future<void> _toggleService(bool enable) async {
    if (_isToggling) return;

    if (enable && widget.overview.hasAnyFlowOffloading) {
      final proceed = await showFlowOffloadingWarningDialog(context, ref: ref);
      if (proceed != true || !mounted) {
        return;
      }
    }

    if (!mounted) return;

    setState(() => _isToggling = true);

    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    const actionKey = 'sqm_service_toggle';

    if (mounted) {
      context.showToastLoading(
        enable
            ? (l10n?.modSqmEnablingService ?? 'Enabling SQM service...')
            : (l10n?.modSqmDisablingService ?? 'Disabling SQM service...'),
        actionKey: actionKey,
      );
    }

    final success = await appState.toggleSqmService(enable);

    if (mounted) {
      setState(() => _isToggling = false);
      if (success) {
        context.showToastSuccess(
          enable
              ? (l10n?.modSqmServiceEnabledToast ??
                    'SQM service started and enabled.')
              : (l10n?.modSqmServiceDisabledToast ?? 'SQM service stopped.'),
          actionKey: actionKey,
        );
        widget.onRefresh();
      } else {
        context.showToastError(
          l10n?.modSqmServiceToggleFailed ?? 'Failed to update SQM service.',
          actionKey: actionKey,
        );
      }
    }
  }

  Future<void> _restartService() async {
    if (_isToggling) return;
    setState(() => _isToggling = true);

    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    const actionKey = 'sqm_service_restart';

    if (mounted) {
      context.showToastLoading(
        l10n?.modSqmRestartingService ?? 'Restarting SQM...',
        actionKey: actionKey,
      );
    }

    final success = await appState.manageServiceAction(
      'sqm',
      'restart',
      context: mounted ? context : null,
    );

    if (mounted) {
      setState(() => _isToggling = false);
      if (success) {
        context.showToastSuccess(
          l10n?.modSqmServiceRestartedToast ?? 'SQM service restarted.',
          actionKey: actionKey,
        );
        widget.onRefresh();
      } else {
        context.showToastError(
          l10n?.modSqmServiceRestartFailed ?? 'Failed to restart SQM.',
          actionKey: actionKey,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isRunning = widget.overview.isServiceRunning;
    final isEnabled = widget.overview.isServiceEnabled;

    final statusColor = isRunning
        ? LuciStatusColors.connected
        : (isEnabled ? LuciStatusColors.warning : LuciStatusColors.inactive);

    final statusText = isRunning
        ? (l10n?.modSqmStatusRunning ?? 'Running')
        : (isEnabled
              ? (l10n?.modSqmStatusStoppedEnabled ??
                    'Stopped (Enabled at boot)')
              : (l10n?.modSqmStatusDisabled ?? 'Disabled'));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.modSqmServiceControlTitle ?? 'SQM Daemon Service',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isToggling)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: isRunning,
                    onChanged: (val) => _toggleService(val),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEnabled
                      ? (l10n?.modSqmBootEnabled ??
                            'Starts automatically at boot')
                      : (l10n?.modSqmBootDisabled ?? 'Manual start only'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton.icon(
                  onPressed: _isToggling ? null : _restartService,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(
                    l10n?.modSqmBtnRestartService ?? 'Restart',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
