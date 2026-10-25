// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';
import '../models/adguard_models.dart';

/// Card presenting host process telemetry (PID, CPU %, VSZ, and Estimated RAM).
///
/// NOTE: Memory is strictly labeled as "Estimated RAM" derived from process
/// memory percentage, never claiming raw kernel RSS measurements.
class AdGuardProcessCard extends StatelessWidget {
  final AdGuardProcessTelemetry? telemetry;
  final String? processError;

  const AdGuardProcessCard({
    super.key,
    required this.telemetry,
    this.processError,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (telemetry == null) {
      if (processError == null) return const SizedBox.shrink();
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n?.aghProcessUnavailable ??
                      'Process telemetry unavailable via LuCI RPC',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pid = telemetry!.pid;
    final cpuStr = '${telemetry!.cpuPercent.toStringAsFixed(1)}%';
    final vszMb = '${telemetry!.vszMb.toStringAsFixed(1)} MB';
    final estimatedRamStr = telemetry!.estimatedRamMb != null
        ? '${telemetry!.estimatedRamMb!.toStringAsFixed(1)} MB (${telemetry!.memPercent.toStringAsFixed(1)}%)'
        : '${telemetry!.memPercent.toStringAsFixed(1)}%';

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
                  Icons.memory_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.aghProcessTelemetry ?? 'Process Telemetry',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Metadata rows
            _buildRow(
              context,
              label: l10n?.aghPid ?? 'PID',
              value: pid,
              keyName: 'agh_process_pid',
            ),
            const SizedBox(height: 8),
            _buildRow(
              context,
              label: l10n?.aghCpuUsage ?? 'CPU Usage',
              value: cpuStr,
              keyName: 'agh_process_cpu',
            ),
            const SizedBox(height: 8),
            _buildRow(
              context,
              label: l10n?.aghVsz ?? 'VSZ',
              value: vszMb,
              keyName: 'agh_process_vsz',
            ),
            const SizedBox(height: 8),

            // Prominently labeled Estimated RAM with explicit tooltip
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.aghEstimatedRam ?? 'Estimated RAM',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message:
                          l10n?.aghEstimatedRamTooltip ??
                          'Calculated from process memory percentage; not kernel RSS',
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Text(
                  estimatedRamStr,
                  key: const Key('agh_process_estimated_ram'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required String label,
    required String value,
    required String keyName,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          key: Key(keyName),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
