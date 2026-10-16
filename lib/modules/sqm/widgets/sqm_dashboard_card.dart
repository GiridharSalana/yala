// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/models/client.dart';
import '../controllers/sqm_controller.dart';
import '../models/sqm_telemetry.dart';
import '../screens/sqm_screen.dart';

/// Compact glanceable dashboard card summarizing SQM status and cached telemetry.
///
/// Strictly observes cached state from [sqmControllerProvider].
/// NEVER starts live telemetry polling, creates timers, or invokes `tc` or RPCs.
/// Gracefully collapses to `const SizedBox.shrink()` when SQM is not installed,
/// inactive, or unconfigured.
class SqmDashboardCard extends ConsumerWidget {
  final String? routerId;
  final VoidCallback? onTap;

  const SqmDashboardCard({
    super.key,
    this.routerId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveRouterId = routerId ??
        ref.watch(appStateProvider).selectedRouter?.id ??
        'default';

    final state = ref.watch(sqmControllerProvider(effectiveRouterId));

    // Visibility gate: strictly hide when SQM is not installed, inactive, or unconfigured
    final bool isVisible = state.isInstalled &&
        state.operatingState != SqmOperatingState.notInstalled &&
        state.operatingState != SqmOperatingState.inactive &&
        state.queues.isNotEmpty;

    if (!isVisible) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final primaryQueue = state.primaryQueue;
    final primaryInterface = primaryQueue?.interface ?? '';
    final primaryQdisc = (primaryQueue?.qdisc ?? '').toUpperCase();

    // Operating state chip presentation
    final Color statusColor;
    final String statusText;
    switch (state.operatingState) {
      case SqmOperatingState.active:
        statusColor = Colors.green;
        statusText = l10n?.modSqmOperatingStateActive ?? 'Active';
        break;
      case SqmOperatingState.flowOffloadingConflict:
        statusColor = Colors.amber.shade800;
        statusText =
            l10n?.modSqmOperatingStateConflict ?? 'Offloading Conflict';
        break;
      case SqmOperatingState.telemetryUnavailable:
      case SqmOperatingState.tcCommandUnavailable:
        statusColor = colorScheme.outline;
        statusText =
            l10n?.modSqmOperatingStateTelemetryUnavailable ?? 'Telemetry N/A';
        break;
      default:
        statusColor = colorScheme.outline;
        statusText = l10n?.modSqmOperatingStateInactive ?? 'Inactive';
        break;
    }

    // Cached telemetry (if available)
    final telemetry = state.primaryTelemetry;
    final prevTelemetry = primaryInterface.isNotEmpty
        ? state.previousTelemetryByInterface[primaryInterface]
        : null;

    // Configured bandwidth string
    final String bandwidthText;
    if (primaryQueue != null &&
        (primaryQueue.download > 0 || primaryQueue.upload > 0)) {
      final dlStr = (primaryQueue.download / 1000.0).toStringAsFixed(
        primaryQueue.download % 1000 == 0 ? 0 : 1,
      );
      final ulStr = (primaryQueue.upload / 1000.0).toStringAsFixed(
        primaryQueue.upload % 1000 == 0 ? 0 : 1,
      );
      bandwidthText = '↓$dlStr / ↑$ulStr M';
    } else {
      bandwidthText = '0 / 0 M';
    }

    // Backlog text & color
    final String backlogText;
    final Color? backlogColor;
    if (telemetry != null) {
      if (telemetry.hasBacklog) {
        if (telemetry.backlogBytes > 0) {
          backlogText =
              '${telemetry.backlogPackets} pkts (${Client.formatBytes(telemetry.backlogBytes)})';
        } else {
          backlogText = '${telemetry.backlogPackets} pkts';
        }
        backlogColor = Colors.orange.shade800;
      } else {
        backlogText = l10n?.modSqmTelemetryBacklogClean ?? '0 pkts (Clean)';
        backlogColor = Colors.green.shade700;
      }
    } else {
      backlogText = '—';
      backlogColor = null;
    }

    // Cumulative drops text
    final String dropsText;
    final bool hasRecentDrops =
        telemetry != null && telemetry.hasRecentDropActivity(prevTelemetry);
    if (telemetry != null) {
      if (telemetry.sentPackets > 0 && telemetry.droppedPackets > 0) {
        dropsText =
            '${telemetry.droppedPackets} (${telemetry.dropRatePercent.toStringAsFixed(1)}%)';
      } else {
        dropsText = '${telemetry.droppedPackets}';
      }
    } else {
      dropsText = '—';
    }

    return Card(
      key: const Key('sqm_dashboard_card'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap ??
            () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SqmScreen(
                    routerId: effectiveRouterId,
                  ),
                ),
              );
            },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Icon + Title + Status Chip
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.speed_outlined,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.modSqmName ?? 'Smart Queue Management (SQM)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7.0,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusText,
                          key: const Key('sqm_dashboard_card_status_chip'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Interface and Qdisc info
              Text(
                '$primaryInterface • $primaryQdisc',
                key: const Key('sqm_dashboard_card_interface_qdisc'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),

              // Offloading Conflict Warning Banner (if applicable)
              if (state.operatingState ==
                  SqmOperatingState.flowOffloadingConflict) ...[
                const SizedBox(height: 8),
                Container(
                  key: const Key('sqm_dashboard_card_conflict_banner'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.shade900.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n?.modSqmFlowOffloadWarningBanner ??
                              'Flow offloading is active in Firewall. Forwarded traffic will bypass SQM queue shaping.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade900,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Glanceable Metrics Row (3 Columns)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem(
                    context,
                    label: l10n?.modSqmDashboardRateLimits ?? 'Rate Limits',
                    value: bandwidthText,
                    keyName: 'sqm_dashboard_card_bandwidth',
                  ),
                  _buildStatItem(
                    context,
                    label: l10n?.modSqmTelemetryBacklogLabel ?? 'Backlog',
                    value: backlogText,
                    keyName: 'sqm_dashboard_card_backlog',
                    valueColor: backlogColor,
                  ),
                  _buildStatItem(
                    context,
                    label: l10n?.modSqmTelemetryCumulativeDropsLabel ?? 'Drops',
                    value: dropsText,
                    keyName: 'sqm_dashboard_card_drops',
                    valueColor: hasRecentDrops ? Colors.amber.shade900 : null,
                  ),
                ],
              ),

              // Recent Drop Activity Badge (if sample delta detected)
              if (hasRecentDrops) ...[
                const SizedBox(height: 8),
                Container(
                  key: const Key('sqm_dashboard_card_recent_drops_badge'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.amber.shade900.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 12,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n?.modSqmTelemetryRecentDropsBadge ??
                            'Recent Drop Activity',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade900,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    required String keyName,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          key: Key(keyName),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor ?? colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
