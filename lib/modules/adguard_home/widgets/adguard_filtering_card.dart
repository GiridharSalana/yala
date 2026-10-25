// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';
import '../models/adguard_models.dart';

/// Card presenting high-level AdGuard Home filtering status and rules overview:
/// Global filtering state, filter list subscriptions count, and custom user rules count.
///
/// NOTE: Read-only presentation in Phase 2. Does not include interactive toggles
/// or mutation controls until filter list CRUD endpoints are integrated.
class AdGuardFilteringCard extends StatelessWidget {
  final AdGuardFilteringStatus? filtering;
  final String? filteringError;
  final bool isLoading;
  final VoidCallback? onManageFilterLists;
  final VoidCallback? onManageUserRules;

  const AdGuardFilteringCard({
    super.key,
    required this.filtering,
    this.filteringError,
    this.isLoading = false,
    this.onManageFilterLists,
    this.onManageUserRules,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Loading state when no filtering data has been fetched yet
    if (filtering == null && isLoading) {
      return Card(
        key: const Key('agh_filtering_card_loading'),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n?.aghFilteringTitle ?? 'Filtering & Rules',
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

    // Complete error / unsupported state when filtering data is completely null
    if (filtering == null) {
      if (filteringError == null) return const SizedBox.shrink();
      return Card(
        key: const Key('agh_filtering_card_error'),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: Colors.amber.shade900,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  filteringError ??
                      (l10n?.aghFilteringDegraded ??
                          'Filtering status unavailable from AdGuard Home'),
                  key: const Key('agh_filtering_degraded_text'),
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

    final isEnabled = filtering!.enabled;
    final totalLists = filtering!.filterLists.length;
    final enabledLists = filtering!.filterLists.where((f) => f.enabled).length;
    final userRulesCount = filtering!.userRules.length;
    final totalRules = filtering!.totalRulesCount;
    final isEmpty = totalLists == 0 && userRulesCount == 0;

    return Card(
      key: const Key('agh_filtering_card'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with non-interactive status chip
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.aghFilteringTitle ?? 'Filtering & Rules',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  key: const Key('agh_filtering_status_chip'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 3.0,
                  ),
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? Colors.green.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isEnabled
                          ? Colors.green
                          : colorScheme.outlineVariant,
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
                          color: isEnabled ? Colors.green : colorScheme.outline,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isEnabled
                            ? (l10n?.aghFilteringActive ?? 'Filtering Active')
                            : (l10n?.aghFilteringDisabled ??
                                  'Filtering Disabled'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isEnabled
                              ? Colors.green.shade800
                              : colorScheme.onSurfaceVariant,
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

            // Degraded banner if telemetry fetch was partially degraded
            if (filteringError != null) ...[
              Container(
                key: const Key('agh_filtering_degraded_banner'),
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700, width: 0.8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.amber.shade900,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        filteringError ??
                            (l10n?.aghFilteringDegraded ??
                                'Filtering status unavailable from AdGuard Home'),
                        key: const Key('agh_filtering_degraded_text'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Center(
                  child: Text(
                    l10n?.aghNoFilterLists ?? 'No filter lists configured',
                    key: const Key('agh_filtering_empty_message'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ] else ...[
              // Metric Tiles Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      context,
                      title: l10n?.aghFilterLists ?? 'Filter Lists',
                      value: '$enabledLists / $totalLists',
                      subtitle: onManageFilterLists != null
                          ? (l10n?.aghManageFilterLists ?? 'Manage lists')
                          : (l10n?.aghFilterListsTotal ??
                                'Active / Total lists'),
                      keyName: 'agh_filter_lists_count',
                      icon: Icons.format_list_bulleted_rounded,
                      color: colorScheme.primary,
                      onTap: onManageFilterLists,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      context,
                      title: l10n?.aghUserRules ?? 'Custom Rules',
                      value: '$userRulesCount',
                      subtitle: onManageUserRules != null
                          ? (l10n?.aghManageRules ?? 'Manage rules')
                          : null,
                      keyName: 'agh_user_rules_count',
                      icon: Icons.rule_rounded,
                      color: Colors.teal.shade700,
                      onTap: onManageUserRules,
                    ),
                  ),
                ],
              ),
              if (totalRules > 0) ...[
                const SizedBox(height: 10),
                _buildTotalRulesBanner(
                  context,
                  title: l10n?.aghTotalRules ?? 'Total Rules',
                  value: totalRules,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String title,
    required String value,
    String? subtitle,
    required String keyName,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final tileContent = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: colorScheme.outline,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            key: Key(keyName),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: tileContent,
        ),
      );
    }

    return tileContent;
  }

  Widget _buildTotalRulesBanner(
    BuildContext context, {
    required String title,
    required int value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Text(
            _formatCount(value),
            key: const Key('agh_total_rules_count'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCount(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}
