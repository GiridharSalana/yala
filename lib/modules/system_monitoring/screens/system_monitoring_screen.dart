// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yala/main.dart';
import '../models/router_temperature.dart';
import '../models/system_metrics.dart';
import '../widgets/add_rpc_handler_dialog.dart';
import 'package:yala/l10n/app_localizations.dart';

class SystemMonitoringScreen extends ConsumerWidget {
  const SystemMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final sysInfo = appState.dashboardData?['sysInfo'] as Map<String, dynamic>?;
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final metrics = SystemMetrics.fromSysInfo(
      sysInfo,
      boardInfo: boardInfo,
      temperature: appState.dashboardData?['temperature'],
    );

    final hostname = boardInfo?['hostname']?.toString() ?? 'Router';
    final model = boardInfo?['model']?.toString() ?? 'OpenWrt Router';

    final tempUnit = appState.dashboardPreferences.temperatureUnit;

    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n?.sysMonTitle ?? 'System Monitoring'),
            Text(
              '$hostname ($model)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await appState.fetchDashboardData();
        },
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildMetricDetailCard(
              context,
              title: l10n?.sysMonCpuStatus ?? 'CPU Status',
              icon: Icons.memory_outlined,
              color: Colors.orange,
              children: [
                _buildInfoRow(
                  l10n?.sysMonEstimatedUsage ?? 'Estimated Usage',
                  '${metrics.cpuUsagePercent.toStringAsFixed(1)}%',
                ),
                _buildInfoRow(
                  l10n?.sysMon1MinLoad ?? '1 Min Load',
                  metrics.load1m.toStringAsFixed(2),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetricDetailCard(
              context,
              title: l10n?.sysMonRamMemory ?? 'RAM Memory',
              icon: Icons.pie_chart_outline,
              color: Colors.blue,
              children: [
                _buildInfoRow(
                  l10n?.sysMonUsagePercent ?? 'Usage Percent',
                  '${metrics.memoryUsagePercent.toStringAsFixed(1)}%',
                ),
                _buildInfoRow(
                  l10n?.sysMonUsedMemory ?? 'Used Memory',
                  _formatBytes(metrics.usedMemoryBytes),
                ),
                _buildInfoRow(
                  l10n?.sysMonFreeMemory ?? 'Free Memory',
                  _formatBytes(metrics.freeMemoryBytes),
                ),
                _buildInfoRow(
                  l10n?.sysMonBuffered ?? 'Buffered',
                  _formatBytes(metrics.bufferedMemoryBytes),
                ),
                _buildInfoRow(
                  l10n?.sysMonCached ?? 'Cached',
                  _formatBytes(metrics.cachedMemoryBytes),
                ),
                _buildInfoRow(
                  l10n?.sysMonTotalMemory ?? 'Total Memory',
                  _formatBytes(metrics.totalMemoryBytes),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetricDetailCard(
              context,
              title: l10n?.sysMonLoadAverage ?? 'Load Average',
              icon: Icons.speed_outlined,
              color: Colors.purple,
              children: [
                _buildInfoRow(
                  l10n?.sysMon1MinLoad ?? '1 Minute',
                  metrics.load1m.toStringAsFixed(2),
                ),
                _buildInfoRow(
                  l10n?.sysMon5MinLoad ?? '5 Minutes',
                  metrics.load5m.toStringAsFixed(2),
                ),
                _buildInfoRow(
                  l10n?.sysMon15MinLoad ?? '15 Minutes',
                  metrics.load15m.toStringAsFixed(2),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetricDetailCard(
              context,
              title: l10n?.sysMonSystemUptime ?? 'System Uptime',
              icon: Icons.timer_outlined,
              color: Colors.green,
              children: [
                _buildInfoRow(
                  l10n?.sysMonUptime ?? 'Uptime',
                  metrics.formattedUptime,
                ),
                _buildInfoRow(
                  l10n?.sysMonTotalSeconds ?? 'Total Seconds',
                  '${metrics.uptimeSeconds} s',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildThermalCard(context, ref, metrics, tempUnit),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricDetailCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildThermalCard(
    BuildContext context,
    WidgetRef ref,
    SystemMetrics metrics,
    String tempUnit,
  ) {
    final l10n = AppLocalizations.of(context);
    final temp = metrics.temperature;
    final isSupported =
        temp != null && temp.isSupported && temp.mainTemperature != null;
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    if (!isSupported) {
      final needsHandler = temp?.needsNativeHandler ?? false;
      final badgeLabel = needsHandler
          ? (l10n?.sysMonRpcHandlerMissing ?? 'RPC Handler Missing')
          : (l10n?.sysMonUnsupportedHardware ?? 'Unsupported Hardware');

      final Color badgeBg;
      final Color badgeTextColor;
      final Color badgeDotColor;
      final BoxBorder badgeBorder;

      if (needsHandler) {
        if (isDark) {
          badgeBg = Colors.amber.withValues(alpha: 0.15);
          badgeTextColor = Colors.amber.shade300;
          badgeDotColor = Colors.amber.shade400;
          badgeBorder = Border.all(
            color: Colors.amber.withValues(alpha: 0.3),
            width: 1,
          );
        } else {
          badgeBg = const Color(0xFFFEF3C7); // warm amber-100
          badgeTextColor = const Color(
            0xFF92400E,
          ); // rich amber-800 (high contrast)
          badgeDotColor = const Color(0xFFD97706); // amber-600
          badgeBorder = Border.all(
            color: const Color(0xFFFDE68A), // amber-200
            width: 1,
          );
        }
      } else {
        if (isDark) {
          badgeBg = theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          );
          badgeTextColor = theme.colorScheme.onSurface.withValues(alpha: 0.7);
          badgeDotColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
          badgeBorder = Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          );
        } else {
          badgeBg = const Color(0xFFF1F5F9); // slate-100
          badgeTextColor = const Color(0xFF475569); // slate-600
          badgeDotColor = const Color(0xFF94A3B8); // slate-400
          badgeBorder = Border.all(
            color: const Color(0xFFE2E8F0), // slate-200
            width: 1,
          );
        }
      }

      final descriptionText = needsHandler
          ? (l10n?.sysMonNeedsHandlerDesc ??
                'Hardware thermal sensors are physically present on this router, but the lightweight native OpenWrt RPC handler (/usr/libexec/rpcd/luci.temp-status) or ACL permission is missing.')
          : (temp?.errorMessage ??
                (l10n?.sysMonUnsupportedHardwareDesc ??
                    'This router does not possess physical hardware thermal sensors or diodes (common on MIPS-based architectures such as QCA956x and virtualized environments). Hardware temperature monitoring is unsupported on this device.'));

      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.thermostat_outlined,
                    color: needsHandler
                        ? (isDark
                              ? Colors.amber.shade300
                              : const Color(0xFFD97706))
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n?.sysMonRouterTemp ?? 'Router Temperature',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(20),
                      border: badgeBorder,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: badgeDotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          badgeLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: badgeTextColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    needsHandler
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    size: 20,
                    color: needsHandler
                        ? (isDark
                              ? Colors.amber.shade300
                              : const Color(0xFFD97706))
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      descriptionText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.8,
                        ),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              if (needsHandler) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _showAddRpcHandlerDialog(context, ref),
                    icon: const Icon(Icons.build_circle_outlined, size: 18),
                    label: Text(
                      l10n?.sysMonBtnAddRpcHandler ?? 'Add Native RPC Handler',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final status = temp.status;
    final statusColor = status.color(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.thermostat_outlined, color: statusColor, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n?.sysMonThermalTemp ?? 'Thermal & Temperature',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isDark ? 0.15 : 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(
                        alpha: isDark ? 0.35 : 0.25,
                      ),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        status.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(
              l10n?.sysMonOperatingTemp ?? 'Operating Temperature',
              temp.formattedTemperatureForUnit(tempUnit, precise: true),
            ),
            if (temp.sensors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  l10n?.sysMonSensorBreakdown(temp.sensors.length) ??
                      'Sensor Breakdown (${temp.sensors.length})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (final sensor in temp.sensors)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sensor.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              sensor.id,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: sensor.status
                              .color(context)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          sensor.formattedValueForUnit(tempUnit),
                          style: TextStyle(
                            color: sensor.status.color(context),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showAddRpcHandlerDialog(BuildContext context, WidgetRef ref) {
    AddRpcHandlerDialog.show(context);
  }
}
