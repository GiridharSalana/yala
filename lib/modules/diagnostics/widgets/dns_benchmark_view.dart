// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/luci_design_system.dart';
import '../controllers/dns_benchmark_controller.dart';
import '../models/dns_benchmark_models.dart';

class DnsBenchmarkView extends ConsumerStatefulWidget {
  const DnsBenchmarkView({super.key});

  @override
  ConsumerState<DnsBenchmarkView> createState() => _DnsBenchmarkViewState();
}

class _DnsBenchmarkViewState extends ConsumerState<DnsBenchmarkView> {
  late final TextEditingController _customIpController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(dnsBenchmarkControllerProvider);
    _customIpController = TextEditingController(text: state.customDnsIp);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dnsBenchmarkControllerProvider.notifier).discoverRouterDns();
    });
  }

  @override
  void dispose() {
    _customIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dnsBenchmarkControllerProvider);
    final controller = ref.read(dnsBenchmarkControllerProvider.notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isTested = state.lastRunTimestamp != null;
    final fastestId = state.fastestProvider?.provider.id;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Vantage Point & Protocol Selector
          _buildVantageSelector(context, state, controller),
          const SizedBox(height: LuciSpacing.md),

          // 2. Action Button (Run / Cancel) - Positioned ABOVE Current Router DNS per user requirement
          if (state.isRunning)
            OutlinedButton.icon(
              onPressed: () => controller.cancelBenchmark(),
              icon: const Icon(Icons.cancel_rounded),
              label: const Text('Cancel DNS Benchmark'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: LuciCardStyles.standardRadius,
                ),
              ),
            )
          else
            FilledButton.icon(
              onPressed: () => controller.startBenchmark(),
              icon: const Icon(Icons.timer_outlined),
              label: Text(
                isTested ? 'Run DNS Benchmark Again' : 'Run DNS Benchmark',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: LuciCardStyles.standardRadius,
                ),
              ),
            ),
          const SizedBox(height: LuciSpacing.md),

          // 3. Custom DNS Resolver Card (Toggleable; user input required)
          _buildCustomDnsCard(context, state, controller),
          const SizedBox(height: LuciSpacing.md),

          // 4. Current Router DNS Card (Pinned baseline comparator)
          _buildRouterDnsCard(context, state),
          const SizedBox(height: LuciSpacing.md),

          // 5. Section Header & Sorting Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PUBLIC DNS RESOLVERS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isTested ? 'Lowest latency' : 'A-Z',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LuciSpacing.sm),

          // 6. Public & Custom Providers List (A-Z pre-test; ascending latency post-test)
          ...state.publicResults.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isFastest = isTested && item.provider.id == fastestId;
            final rank = (isTested && item.status.hasValidLatency)
                ? (index + 1)
                : null;
            return _buildProviderCard(
              context,
              item: item,
              rank: rank,
              isFastest: isFastest,
              isActive:
                  state.isRunning && state.activeProviderId == item.provider.id,
            );
          }),
          const SizedBox(height: LuciSpacing.md),

          // 7. Methodology & Fair Comparison Disclaimer
          Container(
            padding: const EdgeInsets.all(LuciSpacing.md),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: LuciCardStyles.standardRadius,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: LuciSpacing.xs),
                    Text(
                      'Fair Comparison & Protocol Notice',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LuciSpacing.xs),
                Text(
                  '• Query protocol: ${state.protocol.label} for controlled domain lookups.\n'
                  '• Latency reflects the median response time under current network conditions.\n'
                  '• "Fastest measured in this test" highlights low network RTT, but overall DNS choice should also consider privacy policies, malware blocking, parental controls, and DNSSEC validation.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (state.lastRunTimestamp != null) ...[
                  const Divider(height: 16),
                  Text(
                    'Last tested: ${state.lastRunTimestamp!.toLocal().toString().split('.').first}',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVantageSelector(
    BuildContext context,
    DnsBenchmarkState state,
    DnsBenchmarkController controller,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(LuciSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TEST VANTAGE POINT',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                state.protocol.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: LuciSpacing.xs),
          SegmentedButton<DnsVantagePoint>(
            segments: const [
              ButtonSegment(
                value: DnsVantagePoint.clientDevice,
                label: Text('From This Device (Wi-Fi)'),
                icon: Icon(Icons.phone_android_rounded, size: 16),
              ),
              ButtonSegment(
                value: DnsVantagePoint.router,
                label: Text('From Router (WAN)'),
                icon: Icon(Icons.router_rounded, size: 16),
              ),
            ],
            selected: {state.vantagePoint},
            onSelectionChanged: state.isRunning
                ? null
                : (set) => controller.setVantagePoint(set.first),
          ),
          const SizedBox(height: LuciSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    state.vantagePoint == DnsVantagePoint.clientDevice
                        ? 'Measures end-to-end response time experienced by your phone.'
                        : 'Measures direct router-to-server latency (ideal for choosing upstream DNS in router settings).',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomDnsCard(
    BuildContext context,
    DnsBenchmarkState state,
    DnsBenchmarkController controller,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = state.isCustomDnsEnabled;
    final ipText = _customIpController.text.trim();
    final isValidIp =
        ipText.isNotEmpty && InternetAddress.tryParse(ipText) != null;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isEnabled
              ? colorScheme.primary.withValues(alpha: 0.6)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isEnabled ? 1.5 : 1.0,
        ),
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: isEnabled,
            onChanged: state.isRunning
                ? null
                : (val) {
                    controller.toggleCustomDns(val);
                  },
            secondary: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isEnabled
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 18,
                color: isEnabled
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            title: const Text(
              'Custom DNS Resolver',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              'Benchmark your own DNS server alongside public providers',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: LuciSpacing.md,
              vertical: 2,
            ),
          ),
          if (isEnabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(LuciSpacing.md),
              child: TextField(
                controller: _customIpController,
                enabled: !state.isRunning,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'DNS Server IP Address',
                  hintText: 'e.g. 1.1.1.2 or 94.140.14.14',
                  isDense: true,
                  prefixIcon: const Icon(Icons.dns_rounded, size: 18),
                  errorText: ipText.isNotEmpty && !isValidIp
                      ? 'Enter a valid IPv4 or IPv6 address'
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (val) {
                  controller.updateCustomDns(val);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRouterDnsCard(BuildContext context, DnsBenchmarkState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rResult = state.routerResult;
    final config = state.routerDnsConfig;

    final hasLatency =
        rResult != null &&
        rResult.status.hasValidLatency &&
        rResult.medianLatencyMs != null;

    final noteText = state.vantagePoint == DnsVantagePoint.clientDevice
        ? 'Local cache response via ${config?.localEndpoint ?? 'router'}'
        : 'Direct upstream lookup from router';

    return Container(
      padding: const EdgeInsets.all(LuciSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.router_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: LuciSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Router DNS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        config?.localEndpoint ?? 'Resolving router config...',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (hasLatency)
                Text(
                  '${rResult.medianLatencyMs!.toStringAsFixed(1)} ms',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.primary,
                  ),
                )
              else if (rResult?.status == DnsBenchmarkStatus.testing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _buildStatusChip(
                  context,
                  rResult?.status ?? DnsBenchmarkStatus.untested,
                ),
            ],
          ),
          const SizedBox(height: LuciSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  config?.isLocalForwarder == true
                      ? Icons.alt_route_rounded
                      : Icons.public_rounded,
                  size: 14,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    config?.details != null
                        ? '${config!.details} • $noteText'
                        : noteText,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(
    BuildContext context, {
    required DnsBenchmarkResult item,
    required int? rank,
    required bool isFastest,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasLatency =
        item.status.hasValidLatency && item.medianLatencyMs != null;
    final isCustom = item.provider.id == 'custom_dns';

    return Container(
      margin: const EdgeInsets.only(bottom: LuciSpacing.sm),
      padding: const EdgeInsets.all(LuciSpacing.sm + 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(
          color: isFastest
              ? Colors.green.shade600
              : (isActive
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.4)),
          width: isFastest || isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Rank badge or bullet
              if (rank != null)
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: LuciSpacing.sm),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isFastest
                        ? Colors.green.shade600
                        : colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isFastest ? Colors.white : colorScheme.onSurface,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.provider.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'CUSTOM',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        if (isFastest) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Fastest measured in this test',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${item.provider.primaryServer} • ${item.provider.description}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LuciSpacing.sm),
              // Latency or Status
              if (hasLatency)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${item.medianLatencyMs!.toStringAsFixed(1)} ms',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isFastest
                            ? Colors.green.shade700
                            : colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${item.successfulQueries}/${item.totalQueries} ok',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              else if (item.status == DnsBenchmarkStatus.testing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _buildStatusChip(context, item.status),
            ],
          ),
          if (item.errorMessage != null && !hasLatency) ...[
            const SizedBox(height: 4),
            Text(
              item.errorMessage!,
              style: TextStyle(fontSize: 10, color: colorScheme.error),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, DnsBenchmarkStatus status) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color bg;
    Color fg;

    switch (status) {
      case DnsBenchmarkStatus.untested:
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.onSurfaceVariant;
        break;
      case DnsBenchmarkStatus.testing:
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        break;
      case DnsBenchmarkStatus.success:
      case DnsBenchmarkStatus.partial:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        break;
      case DnsBenchmarkStatus.timeout:
      case DnsBenchmarkStatus.refused:
      case DnsBenchmarkStatus.unreachable:
      case DnsBenchmarkStatus.serverError:
        bg = colorScheme.errorContainer;
        fg = colorScheme.onErrorContainer;
        break;
      case DnsBenchmarkStatus.unsupported:
      case DnsBenchmarkStatus.configRequired:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
