// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/widgets/luci_collapsible_card.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import '../models/firewall_info.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

class FirewallSecurityScreen extends ConsumerStatefulWidget {
  const FirewallSecurityScreen({super.key});

  @override
  ConsumerState<FirewallSecurityScreen> createState() =>
      _FirewallSecurityScreenState();
}

class _FirewallSecurityScreenState
    extends ConsumerState<FirewallSecurityScreen> {
  /// Stores staged enable/disable toggles for modified custom firewall rules.
  /// Format: {sectionKey: desiredEnabledStatus}
  final Map<String, bool> _stagedCustomRuleStates = {};
  bool _isSaving = false;

  bool get _hasUnsavedChanges => _stagedCustomRuleStates.isNotEmpty;

  void _toggleCustomRuleState(FirewallCustomRule rule, bool newValue) {
    setState(() {
      if (newValue == rule.enabled) {
        _stagedCustomRuleStates.remove(rule.sectionKey);
      } else {
        _stagedCustomRuleStates[rule.sectionKey] = newValue;
      }
    });
  }

  void _discardChanges() {
    setState(() {
      _stagedCustomRuleStates.clear();
    });
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      context.showToastInfo(
        'Changes Discarded',
        subtitle: l10n?.firewallDiscardedCustomRules ??
            'Discarded all unsaved firewall custom rule changes.',
      );
    }
  }

  Future<bool> _showConfirmAndDiscardDialog() async {
    return LuciGuardrail.confirmUnsavedChanges(
      context,
      unsavedCount: _stagedCustomRuleStates.length,
      itemLabel: 'firewall rule(s)',
    );
  }

  Future<void> _confirmAndDiscardChanges() async {
    final confirm = await _showConfirmAndDiscardDialog();
    if (confirm) {
      _discardChanges();
    }
  }

  Future<bool> _saveChanges() async {
    if (!_hasUnsavedChanges || _isSaving) return true;

    setState(() {
      _isSaving = true;
    });

    final appState = ref.read(appStateProvider);
    final modifiedEntries = Map<String, bool>.from(_stagedCustomRuleStates);
    final succeededRules = <String>[];
    final failedRules = <String>[];

    const actionKey = 'save_firewall_rules';
    if (mounted) {
      context.showToastLoading(
        'Saving Changes',
        subtitle:
            'Saving ${modifiedEntries.length} firewall custom rule change(s)...',
        actionKey: actionKey,
      );
    }

    try {
      for (final entry in modifiedEntries.entries) {
        if (!mounted) break;
        final sectionKey = entry.key;
        final targetEnabled = entry.value;

        final success = await appState.updateFirewallCustomRuleStatus(
          sectionKey,
          targetEnabled,
          context: mounted ? context : null,
        );

        if (success) {
          succeededRules.add(sectionKey);
        } else {
          failedRules.add(sectionKey);
        }
      }
    } catch (e) {
      if (mounted) {
        context.showToastError(
          'Firewall Save Error',
          subtitle: e.toString().replaceAll('Exception: ', ''),
          actionKey: actionKey,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          for (final secKey in succeededRules) {
            _stagedCustomRuleStates.remove(secKey);
          }
          _isSaving = false;
        });
      }
    }

    await appState.fetchDashboardData();

    if (!mounted) return failedRules.isEmpty;

    if (failedRules.isEmpty) {
      context.showToastSuccess(
        'Firewall Saved',
        subtitle:
            'Successfully updated ${succeededRules.length} firewall custom rule(s).',
        actionKey: actionKey,
      );
      return true;
    } else {
      final l10n = AppLocalizations.of(context);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Text(
            l10n?.firewallRuleSaveWarning ?? 'Firewall Rule Save Warning',
          ),
          content: SingleChildScrollView(
            child: Text(
              'Updated ${succeededRules.length} rule(s), but failed to update ${failedRules.length} rule(s):\n\n'
              '${failedRules.join(", ")}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n?.actionConfirm ?? 'OK'),
            ),
          ],
        ),
      );
      return false;
    }
  }

  Future<bool?> _showUnsavedChangesDialog() async {
    final l10n = AppLocalizations.of(context);
    final action = await LuciGuardrail.confirmSaveOrDiscardChanges(
      context,
      count: _stagedCustomRuleStates.length,
      itemLabel: 'firewall rule change(s)',
      title: l10n?.firewallUnsavedCustomRulesTitle ??
          'Unsaved Firewall Rule Changes',
    );

    if (action == 'discard') {
      _discardChanges();
      return true;
    } else if (action == 'save') {
      final saved = await _saveChanges();
      return saved;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final capabilities = appState.capabilities;
    final backend = capabilities?.firewallBackend ?? FirewallBackend.fw4;
    final uciFirewall = appState.dashboardData?['uciFirewallConfig'];

    final overview = FirewallOverview.fromUciData(
      uciFirewall,
      backend: backend,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final l10n = AppLocalizations.of(context);
    final titlePrefix = l10n?.firewallTitle ?? 'Firewall & Security';
    return PopScope(
      canPop: !_hasUnsavedChanges && !_isSaving,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldLeave = await _showUnsavedChangesDialog();
        if (shouldLeave == true && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '$titlePrefix (${backend == FirewallBackend.fw4 ? "fw4 / nftables" : "fw3 / iptables"})',
          ),
          actions: [
            if (_hasUnsavedChanges)
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: l10n?.btnRevert ?? 'Discard Changes',
                onPressed: _isSaving ? null : _confirmAndDiscardChanges,
              ),
            if (_hasUnsavedChanges)
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: l10n?.btnApplyChanges ?? 'Save Changes',
                onPressed: _isSaving ? null : () => _saveChanges(),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await appState.fetchDashboardData();
          },
          child: !overview.isAvailable
              ? _buildUnavailableView(context, ref, overview)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
                  children: [
                    _buildSectionHeader(
                      context,
                      l10n?.firewallGlobalPoliciesTitle ??
                          'Global Default Policies',
                      Icons.shield_outlined,
                    ),
                    const SizedBox(height: 8),
                    _buildDefaultPoliciesCard(context, overview.defaultPolicy),
                    const SizedBox(height: 16),
                    _buildSectionHeader(
                      context,
                      l10n?.firewallZonesOverviewTitle ??
                          'Firewall Zones Overview',
                      Icons.layers_outlined,
                    ),
                    const SizedBox(height: 8),
                    ...overview.zones.map(
                      (zone) => _buildZoneCard(context, zone),
                    ),
                    const SizedBox(height: 16),
                    LuciCollapsibleCard(
                      title:
                          l10n?.zoneForwardingTitle ??
                          'Inter-Zone Forwarding Rules',
                      count: overview.forwardings.length,
                      subtitle:
                          '${overview.forwardings.length} inter-zone policies',
                      icon: Icons.alt_route_outlined,
                      iconColor: Colors.blue,
                      childBuilder: (ctx) =>
                          _buildForwardingsCard(context, overview.forwardings),
                    ),
                    const SizedBox(height: 16),
                    LuciCollapsibleCard(
                      title:
                          l10n?.portForwardsTitle ??
                          'Port Forwarding / Redirects',
                      count: overview.portForwards.length,
                      subtitle:
                          '${overview.portForwards.length} port forward rules',
                      icon: Icons.import_export_outlined,
                      iconColor: Colors.orange,
                      childBuilder: (ctx) => _buildPortForwardingsList(
                        context,
                        overview.portForwards,
                      ),
                    ),
                    const SizedBox(height: 16),
                    LuciCollapsibleCard(
                      title: l10n?.customRulesTitle ?? 'Custom Security Rules',
                      count: overview.customRules.length,
                      subtitle: '${overview.customRules.length} custom rules',
                      icon: Icons.rule_outlined,
                      iconColor: Colors.teal,
                      childBuilder: (ctx) =>
                          _buildCustomRulesList(context, overview.customRules),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
        ),
        bottomNavigationBar: _hasUnsavedChanges
            ? _buildUnsavedChangesBottomBar(context)
            : null,
      ),
    );
  }

  Widget _buildUnavailableView(
    BuildContext context,
    WidgetRef ref,
    FirewallOverview overview,
  ) {
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Firewall Configuration Unavailable',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              overview.errorMessage ??
                  'The firewall configuration could not be loaded or parsed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => appState.redetectCapabilities(),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                AppLocalizations.of(context)?.firewallReprobeCapabilities ??
                    'Re-probe Capabilities',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    int maxLines = 2,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: maxLines,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultPoliciesCard(
    BuildContext context,
    FirewallDefaultPolicy def,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildPolicyRow('Default Input', def.input),
            const Divider(),
            _buildPolicyRow('Default Output', def.output),
            const Divider(),
            _buildPolicyRow('Default Forward', def.forward),
            const Divider(),
            _buildPolicyRow(
              'SYN Flood Protection',
              def.synFlood ? 'ENABLED' : 'DISABLED',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneCard(BuildContext context, FirewallZone zone) {
    final theme = Theme.of(context);
    final isWan = zone.name.toLowerCase().contains('wan');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isWan ? Icons.public : Icons.router,
                      color: isWan ? Colors.red : theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Zone: ${zone.name.toUpperCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                if (zone.masquerade)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'MASQUERADE (NAT)',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Covered Networks: ${zone.networks.join(", ")}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCompactRuleTile('Input', zone.input),
                _buildCompactRuleTile('Output', zone.output),
                _buildCompactRuleTile('Forward', zone.forward),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForwardingsCard(
    BuildContext context,
    List<FirewallForwarding> forwardings,
  ) {
    if (forwardings.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            l10n?.firewallNoZoneRules ?? 'No zone forwarding rules configured.',
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: forwardings.map((fwd) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Chip(
                    label: Text(
                      fwd.srcZone.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.0),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.grey,
                    ),
                  ),
                  Chip(
                    label: Text(
                      fwd.destZone.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPortForwardingsList(
    BuildContext context,
    List<FirewallPortForwarding> pfs,
  ) {
    if (pfs.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            l10n?.firewallNoPortRules ?? 'No port forwarding rules active.',
          ),
        ),
      );
    }

    return Column(
      children: pfs.map((pf) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.compare_arrows)),
            title: Text(
              pf.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${pf.srcZone.toUpperCase()}:${pf.srcPort} ➔ ${pf.destIp}:${pf.destPort} (${pf.proto.toUpperCase()})',
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCustomRulesList(
    BuildContext context,
    List<FirewallCustomRule> rules,
  ) {
    if (rules.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No custom security rules defined (default zone policies active).',
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Column(
      children: rules.map((r) {
        final isStaged = _stagedCustomRuleStates.containsKey(r.sectionKey);
        final currentEnabled =
            _stagedCustomRuleStates[r.sectionKey] ?? r.enabled;
        final policyColor = _getPolicyColor(r.target);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isStaged
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.12)
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: isStaged
                  ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                  : null,
            ),
            child: ListTile(
              leading: Icon(
                currentEnabled ? Icons.check_circle : Icons.pause_circle_filled,
                color: currentEnabled
                    ? LuciStatusColors.connected
                    : Colors.grey,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isStaged) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.amber.shade700,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'STAGED',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                isStaged
                    ? '${r.srcZone.toUpperCase()} ➔ ${r.destZone.toUpperCase()} • Original: ${r.enabled ? "ENABLED" : "DISABLED"}'
                    : '${r.srcZone.toUpperCase()} ➔ ${r.destZone.toUpperCase()}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: policyColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: r.isUnrecognizedTarget
                          ? Border.all(color: Colors.amber.shade700, width: 1)
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (r.isUnrecognizedTarget) ...[
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 12,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          r.target,
                          style: TextStyle(
                            color: r.isUnrecognizedTarget
                                ? Colors.amber.shade800
                                : policyColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: currentEnabled,
                    onChanged: _isSaving
                        ? null
                        : (newValue) => _toggleCustomRuleState(r, newValue),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPolicyRow(String title, String policy) {
    final color = _getPolicyColor(policy);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              policy,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRuleTile(String label, String policy) {
    final color = _getPolicyColor(policy);
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          policy,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Color _getPolicyColor(String policy) {
    switch (policy.toUpperCase()) {
      case 'ACCEPT':
      case 'ENABLED':
        return LuciStatusColors.connected;
      case 'REJECT':
        return Colors.orange;
      case 'DROP':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  Widget _buildUnsavedChangesBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final count = _stagedCustomRuleStates.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Icon(Icons.edit_note, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count rule(s) modified',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: _isSaving ? null : _confirmAndDiscardChanges,
              child: Text(
                AppLocalizations.of(context)?.actionDiscard ?? 'Discard',
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isSaving ? null : () => _saveChanges(),
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(AppLocalizations.of(context)?.actionSave ?? 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
