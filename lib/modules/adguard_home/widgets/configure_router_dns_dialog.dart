// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';

/// Modal dialog confirming router upstream DNS orchestration with AdGuard Home.
///
/// Implements Milestone E2 invariants:
/// - Explicit confirmation guarded by preflight loop and destination validation.
/// - Clear destination display deriving target strictly from [AdGuardStatus.dnsPort].
/// - Choice between Exclusive Forwarding (outage risk) and Fallback Retention (bypass risk).
/// - 30-second automatic kernel rollback watchdog feedback.
class ConfigureRouterDnsDialog extends StatefulWidget {
  final AdGuardController controller;
  final String routerId;
  final AdGuardDnsPreflightResult? initialPreflight;

  const ConfigureRouterDnsDialog({
    super.key,
    required this.controller,
    required this.routerId,
    this.initialPreflight,
  });

  static Future<bool?> show(
    BuildContext context, {
    required AdGuardController controller,
    required String routerId,
    AdGuardDnsPreflightResult? initialPreflight,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConfigureRouterDnsDialog(
        controller: controller,
        routerId: routerId,
        initialPreflight: initialPreflight,
      ),
    );
  }

  @override
  State<ConfigureRouterDnsDialog> createState() =>
      _ConfigureRouterDnsDialogState();
}

class _ConfigureRouterDnsDialogState extends State<ConfigureRouterDnsDialog> {
  bool _isLoadingPreflight = true;
  AdGuardDnsPreflightResult? _preflight;
  bool _preserveFallback = false;
  bool _isApplying = false;
  String _currentStep = '';
  AdGuardDnsConfigResult? _result;

  @override
  void initState() {
    super.initState();
    if (widget.initialPreflight != null) {
      _preflight = widget.initialPreflight;
      _isLoadingPreflight = false;
    } else {
      _loadPreflight();
    }
  }

  Future<void> _loadPreflight() async {
    setState(() {
      _isLoadingPreflight = true;
      _result = null;
    });
    try {
      final res = await widget.controller.preflightRouterDnsConfiguration();
      if (mounted) {
        setState(() {
          _preflight = res;
          _isLoadingPreflight = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPreflight = false;
        });
      }
    }
  }

  Future<void> _applyConfiguration() async {
    if (_preflight == null || !_preflight!.canProceed) return;

    final l10n = AppLocalizations.of(context);
    setState(() {
      _isApplying = true;
      _currentStep = l10n?.aghConfigureDnsApplying ?? 'Applying configuration…';
    });

    final res = await widget.controller.configureRouterDns(
      preserveExistingAsFallback: _preserveFallback,
      targetForwarder: _preflight!.targetForwarder,
    );

    if (mounted) {
      setState(() {
        _isApplying = false;
        _result = res;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.alt_route, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n?.aghConfigureDnsTitle ?? 'Configure Router DNS Forwarding',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(child: _buildContent(context)),
      ),
      actions: _buildActions(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoadingPreflight) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              l10n?.aghConfigureDnsChecking ?? 'Checking DNS configuration…',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_isApplying) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _currentStep,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n?.aghConfigureDnsRollbackNotice ??
                  'Protected by 30-second automatic router rollback watchdog.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_result != null) {
      return _buildResultView(context);
    }

    final p = _preflight!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Description
        Text(
          l10n?.aghConfigureDnsDescription ??
              'Route router upstream DNS queries through AdGuard Home.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),

        // Destination details card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
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
                    l10n?.aghConfigureDnsTarget ?? 'DNS Destination',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: p.isExternal
                          ? colorScheme.secondaryContainer
                          : colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p.isExternal ? 'External Host' : 'Local Router',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                p.targetForwarder,
                key: const Key('agh_dns_target_forwarder_text'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Warnings / Errors
        if (p.loopDetected) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.loopReason ??
                        (l10n?.aghConfigureDnsLoopError ??
                            'Cannot configure: Forwarding loop detected.'),
                    key: const Key('agh_dns_loop_error_text'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (p.portConflict) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.portConflictReason ??
                        (l10n?.aghConfigureDnsConflictError ??
                            'Cannot configure: Port collision between AdGuard and dnsmasq.'),
                    key: const Key('agh_dns_conflict_error_text'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (p.isHostname) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.aghConfigureDnsHostnameWarning ??
                        'Warning: Destination is a hostname. Using a static IP is recommended to prevent bootstrap resolution failures.',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (!p.loopDetected && !p.portConflict) ...[
          () {
            final advisoryWarnings = p.warnings.where((w) {
              if (p.loopDetected && w == p.loopReason) return false;
              if (p.portConflict && w == p.portConflictReason) return false;
              if (p.isHostname &&
                  (w.toLowerCase().contains('hostname') ||
                      w == l10n?.aghConfigureDnsHostnameWarning)) {
                return false;
              }
              return true;
            }).toList();

            if (advisoryWarnings.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Container(
                key: const Key('agh_dns_advisory_warning_card'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final w in advisoryWarnings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                w,
                                key: const Key('agh_dns_advisory_warning_text'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }(),
        ],

        if (p.canProceed) ...[
          Text(
            'Forwarding Strategy:',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),

          // Strategy Radio Group
          RadioGroup<bool>(
            groupValue: _preserveFallback,
            onChanged: (v) {
              if (v != null) setState(() => _preserveFallback = v);
            },
            child: Column(
              children: [
                // Strategy Radio 1: Exclusive
                RadioListTile<bool>(
                  value: false,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n?.aghConfigureDnsModeExclusive ??
                        'Exclusive Forwarding',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.aghConfigureDnsModeExclusiveDesc ??
                            'Route all router DNS queries exclusively to AdGuard Home.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n?.aghConfigureDnsModeExclusiveWarning ??
                            'Outage Risk: If AdGuard Home becomes unreachable, DNS resolution will fail until restored.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 12),

                // Strategy Radio 2: Fallback Retention
                RadioListTile<bool>(
                  value: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n?.aghConfigureDnsModeFallback ?? 'Fallback Retention',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.aghConfigureDnsModeFallbackDesc ??
                            'Keep existing resolvers as secondary fallbacks alongside AdGuard Home.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n?.aghConfigureDnsModeFallbackWarning ??
                            'Bypass Risk: Dnsmasq may query fallbacks concurrently, allowing some traffic to bypass AdGuard.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Rollback Watchdog Notice
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.aghConfigureDnsRollbackNotice ??
                        'Protected by 30-second automatic router rollback watchdog.',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultView(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final res = _result!;

    IconData icon;
    Color iconColor;
    String statusTitle;

    if (res.isSuccess) {
      icon = Icons.check_circle_outline;
      iconColor = Colors.green;
      statusTitle =
          l10n?.aghConfigureDnsSuccess ??
          'Router DNS forwarding configured successfully.';
    } else if (res.isRolledBack) {
      icon = Icons.history;
      iconColor = Colors.orange;
      statusTitle =
          l10n?.aghConfigureDnsRolledBack ??
          'Router reachability check failed. Rollback watchdog restored configuration.';
    } else if (res.isAmbiguous) {
      icon = Icons.help_outline;
      iconColor = Colors.amber;
      statusTitle =
          l10n?.aghConfigureDnsAmbiguous ??
          'Configuration outcome was ambiguous. Please check router status.';
    } else {
      icon = Icons.error_outline;
      iconColor = colorScheme.error;
      statusTitle = res.message;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 48),
        const SizedBox(height: 12),
        Text(
          statusTitle,
          textAlign: TextAlign.center,
          key: const Key('agh_dns_config_result_title'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (res.appliedServers.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${l10n?.aghConfigureDnsNewUpstreams ?? 'New Upstreams'}: ${res.appliedServers.join(', ')}',
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
        if (res.isSuccess && _preflight != null) ...[
          () {
            final resultWarnings = _preflight!.warnings.where((w) {
              if (_preflight!.loopDetected && w == _preflight!.loopReason) {
                return false;
              }
              if (_preflight!.portConflict &&
                  w == _preflight!.portConflictReason) {
                return false;
              }
              return true;
            }).toList();

            if (resultWarnings.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Container(
                key: const Key('agh_dns_result_advisory_card'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final w in resultWarnings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                w,
                                key: const Key(
                                  'agh_dns_result_advisory_warning_text',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }(),
        ],
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_isApplying) {
      return const [];
    }

    if (_result != null) {
      return [
        if (!_result!.isSuccess)
          TextButton(onPressed: _loadPreflight, child: const Text('Retry')),
        FilledButton(
          key: const Key('agh_dns_config_done_btn'),
          onPressed: () => Navigator.of(context).pop(_result!.isSuccess),
          child: Text(l10n?.actionClose ?? 'Done'),
        ),
      ];
    }

    return [
      TextButton(
        key: const Key('agh_cancel_dns_btn'),
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(l10n?.actionCancel ?? 'Cancel'),
      ),
      FilledButton(
        key: const Key('agh_apply_dns_btn'),
        onPressed: (_preflight?.canProceed == true)
            ? _applyConfiguration
            : null,
        child: Text(l10n?.aghConfigureDnsActionApply ?? 'Apply Configuration'),
      ),
    ];
  }
}
