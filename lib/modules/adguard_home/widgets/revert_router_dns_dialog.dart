// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';

/// Modal dialog confirming removal of router upstream DNS forwarding to AdGuard Home.
///
/// Implements Phase 3 invariants:
/// - Explicit confirmation guarded by preflight rule targeting and ambiguity validation.
/// - Clear destination display showing the exact rule to remove and remaining upstream resolvers.
/// - Immediate pre-mutation revalidation ensuring configuration hasn't changed.
/// - 30-second automatic kernel rollback watchdog feedback.
class RevertRouterDnsDialog extends StatefulWidget {
  final AdGuardController controller;
  final String routerId;
  final AdGuardDnsRevertPreflightResult? initialPreflight;

  const RevertRouterDnsDialog({
    super.key,
    required this.controller,
    required this.routerId,
    this.initialPreflight,
  });

  static Future<bool?> show(
    BuildContext context, {
    required AdGuardController controller,
    required String routerId,
    AdGuardDnsRevertPreflightResult? initialPreflight,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => RevertRouterDnsDialog(
        controller: controller,
        routerId: routerId,
        initialPreflight: initialPreflight,
      ),
    );
  }

  @override
  State<RevertRouterDnsDialog> createState() => _RevertRouterDnsDialogState();
}

class _RevertRouterDnsDialogState extends State<RevertRouterDnsDialog> {
  bool _isLoadingPreflight = true;
  AdGuardDnsRevertPreflightResult? _preflight;
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
      final res = await widget.controller.preflightRevertRouterDns();
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

  Future<void> _applyRevert() async {
    if (_preflight == null ||
        !_preflight!.canProceed ||
        _preflight!.targetRule == null) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    setState(() {
      _isApplying = true;
      _currentStep = l10n?.aghRevertDnsRemoving ?? 'Removing DNS forwarding…';
    });

    final res = await widget.controller.revertRouterDns(
      targetForwarder: _preflight!.targetRule!,
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
      key: const Key('agh_revert_dns_dialog'),
      title: Row(
        children: [
          Icon(Icons.delete_sweep_outlined, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n?.aghRevertDnsTitle ?? 'Remove Router DNS Forwarding',
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

    if (!p.canProceed) {
      return _buildPreflightErrorView(context, p);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Description
        Text(
          l10n?.aghRevertDnsDescription ??
              'Remove AdGuard Home forwarding rule from router dnsmasq. Dnsmasq will stop routing queries to AdGuard Home.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),

        // Rule to Remove container
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n?.aghRevertDnsRuleToRemove ?? 'Rule to Remove',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'dnsmasq server',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                p.targetRule ?? '',
                key: const Key('agh_revert_dns_target_text'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Remaining Upstreams container
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
              Text(
                l10n?.aghRevertDnsRemainingUpstreams ?? 'Remaining Upstreams',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                p.remainingServers.isNotEmpty
                    ? p.remainingServers.join(', ')
                    : 'None (ISP/WAN Default)',
                key: const Key('agh_revert_dns_remaining_text'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Warnings if no remaining resolvers
        if (p.remainingServers.isEmpty) ...[
          Container(
            key: const Key('agh_revert_dns_no_remaining_warning'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
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
                  child: Text(
                    l10n?.aghRevertDnsNoRemainingWarning ??
                        'No remaining upstream resolvers configured. Dnsmasq will fall back to ISP-assigned DNS from WAN interface.',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 30-Second Rollback Watchdog Box
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.security, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n?.aghConfigureDnsRollbackNotice ??
                      'Protected by 30-second automatic router rollback watchdog.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreflightErrorView(
    BuildContext context,
    AdGuardDnsRevertPreflightResult p,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String errorMessage;
    Key errorKey;

    if (p.isMissing) {
      errorMessage =
          l10n?.aghRevertDnsMissingError ??
          'No active dnsmasq forwarder rule targeting this AdGuard Home instance was found.';
      errorKey = const Key('agh_revert_dns_missing_error');
    } else if (p.isAmbiguous) {
      errorMessage =
          l10n?.aghRevertDnsAmbiguousError ??
          'Multiple ambiguous forwarding rules targeting AdGuard Home were found. Please verify router settings in LuCI.';
      errorKey = const Key('agh_revert_dns_ambiguous_error');
    } else {
      errorMessage = p.failureReason ?? 'Cannot remove DNS forwarding.';
      errorKey = const Key('agh_revert_dns_generic_error');
    }

    return Container(
      key: errorKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colorScheme.error, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  errorMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (p.currentServers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${l10n?.aghConfigureDnsCurrentUpstreams ?? 'Current Upstreams'}: ${p.currentServers.join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer.withValues(
                        alpha: 0.8,
                      ),
                      fontFamily: 'monospace',
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

  Widget _buildResultView(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final res = _result!;

    IconData icon;
    Color iconColor;
    String statusTitle;

    switch (res.status) {
      case AdGuardDnsConfigStatus.success:
        icon = Icons.check_circle_outline;
        iconColor = Colors.green;
        statusTitle =
            l10n?.aghRevertDnsSuccess ??
            'Router DNS forwarding removed successfully.';
        break;
      case AdGuardDnsConfigStatus.rolledBack:
        icon = Icons.history;
        iconColor = Colors.orange;
        statusTitle =
            l10n?.aghConfigureDnsRolledBack ??
            'Router reachability check failed. 30-second rollback watchdog restored previous configuration.';
        break;
      case AdGuardDnsConfigStatus.ambiguous:
        icon = Icons.help_outline;
        iconColor = Colors.amber;
        statusTitle =
            l10n?.aghConfigureDnsAmbiguous ??
            'Configuration was applied, but confirmation response was ambiguous.';
        break;
      case AdGuardDnsConfigStatus.failed:
        icon = Icons.error_outline;
        iconColor = colorScheme.error;
        statusTitle = res.message.isNotEmpty
            ? res.message
            : (l10n?.aghRevertDnsFailedTitle ?? 'Failed to Remove Forwarding');
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 48),
        const SizedBox(height: 12),
        Text(
          statusTitle,
          textAlign: TextAlign.center,
          key: const Key('agh_revert_dns_result_title'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (res.isSuccess && res.appliedServers.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${l10n?.aghRevertDnsRemainingUpstreams ?? 'Remaining Upstreams'}: ${res.appliedServers.join(', ')}',
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
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
          TextButton(
            key: const Key('agh_revert_dns_retry_btn'),
            onPressed: _loadPreflight,
            child: const Text('Retry'),
          ),
        FilledButton(
          key: const Key('agh_revert_dns_done_btn'),
          onPressed: () => Navigator.of(context).pop(_result!.isSuccess),
          child: Text(l10n?.actionClose ?? 'Done'),
        ),
      ];
    }

    if (_preflight != null && !_preflight!.canProceed) {
      return [
        FilledButton(
          key: const Key('agh_cancel_revert_dns_btn'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n?.actionClose ?? 'Close'),
        ),
      ];
    }

    return [
      TextButton(
        key: const Key('agh_cancel_revert_dns_btn'),
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(l10n?.actionCancel ?? 'Cancel'),
      ),
      FilledButton(
        key: const Key('agh_confirm_revert_dns_btn'),
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: (_preflight?.canProceed == true) ? _applyRevert : null,
        child: Text(l10n?.aghRevertDnsActionRemove ?? 'Remove Forwarding'),
      ),
    ];
  }
}
