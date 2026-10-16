// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';
import '../models/adguard_models.dart';
import '../utils/adguard_web_url_helper.dart';

/// Card presenting high-level daemon status, version, listening ports,
/// and web interface link for AdGuard Home.
class AdGuardStatusCard extends StatelessWidget {
  final AdGuardStatus? status;
  final String routerHost;
  final bool isReviewerMode;
  final bool useHttps;

  const AdGuardStatusCard({
    super.key,
    required this.status,
    required this.routerHost,
    this.isReviewerMode = false,
    this.useHttps = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isRunning = status?.running ?? false;
    final version = status?.version ?? '—';
    final dnsPort = status?.dnsPort ?? 53;
    final httpPort = status?.httpPort ?? 3000;
    final dnsAddresses = (status?.dnsAddresses != null && status!.dnsAddresses.isNotEmpty)
        ? status!.dnsAddresses.join(', ')
        : '0.0.0.0';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Icon, Title, and Running Status Chip
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AdGuard Home',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 3.0,
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRunning ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isRunning
                            ? (l10n?.aghStatusRunning ?? 'Running')
                            : (l10n?.aghStatusStopped ?? 'Stopped'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isRunning ? Colors.green.shade800 : Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Metadata rows: Version, DNS Listener, Web UI Port
            _buildMetaRow(
              context,
              label: l10n?.aghVersion ?? 'Version',
              value: version,
              valueKey: const Key('agh_status_version'),
            ),
            const SizedBox(height: 8),
            _buildMetaRow(
              context,
              label: l10n?.aghDnsAddresses ?? 'DNS Addresses',
              value: '$dnsAddresses : $dnsPort',
              valueKey: const Key('agh_status_dns_listener'),
            ),
            const SizedBox(height: 8),
            _buildMetaRow(
              context,
              label: l10n?.aghHttpPort ?? 'Web Port',
              value: '$httpPort',
              valueKey: const Key('agh_status_http_port'),
            ),
            const SizedBox(height: 14),

            // Open Web Interface Action
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('agh_open_web_ui_button'),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(l10n?.aghWebInterface ?? 'Open Web Interface'),
                onPressed: () {
                  AdGuardWebUrlHelper.launchWebInterface(
                    context: context,
                    isReviewerMode: isReviewerMode,
                    host: routerHost,
                    port: httpPort,
                    useHttps: useHttps,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(
    BuildContext context, {
    required String label,
    required String value,
    Key? valueKey,
    int? maxLines,
  }) {
    final theme = Theme.of(context);
    final textWidget = Text(
      value,
      key: valueKey,
      textAlign: TextAlign.end,
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: maxLines != null
              ? Tooltip(
                  message: value,
                  child: textWidget,
                )
              : textWidget,
        ),
      ],
    );
  }
}
