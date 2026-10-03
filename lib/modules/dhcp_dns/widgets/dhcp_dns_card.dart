// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import '../models/dhcp_dns_info.dart';

class DhcpDnsCard extends ConsumerWidget {
  const DhcpDnsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final overview = DhcpDnsOverview.fromDashboardData(appState.dashboardData);
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.dns_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n?.dhcpDnsTitle ?? 'DHCP & DNS Server',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n != null
                        ? l10n.dhcpDnsDomainSuffix(
                            overview.dnsConfig.localDomain,
                          )
                        : '.${overview.dnsConfig.localDomain} Domain',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: l10n?.dhcpDnsActiveLeases ?? 'Active Leases',
                    value: '${overview.activeLeases.length}',
                    icon: Icons.badge_outlined,
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: l10n?.dhcpDnsStaticMappings ?? 'Static Mappings',
                    value: '${overview.staticMappings.length}',
                    icon: Icons.pin_drop_outlined,
                    color: Colors.teal,
                  ),
                ),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: l10n?.dhcpDnsForwarders ?? 'DNS Forwarders',
                    value:
                        overview.dnsConfig.upstreamDnsServers.firstOrNull ??
                        '1.1.1.1',
                    icon: Icons.public_outlined,
                    color: Colors.indigo,
                  ),
                ),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: l10n?.dhcpCardDnsRebind ?? 'DNS Rebind',
                    value: overview.dnsConfig.rebindProtection
                        ? (l10n?.statusEnabled ?? 'ON')
                        : (l10n?.statusDisabled ?? 'OFF'),
                    icon: Icons.verified_user_outlined,
                    color: overview.dnsConfig.rebindProtection
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 10,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
