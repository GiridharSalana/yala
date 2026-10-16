// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';
import '../models/adguard_models.dart';
import 'adguard_top_lists_bottom_sheet.dart';

/// Card displaying Top Blocked Domains, Top Queried Domains, and Top Clients.
class AdGuardTopListsCard extends StatefulWidget {
  final AdGuardStats? stats;

  const AdGuardTopListsCard({
    super.key,
    required this.stats,
  });

  @override
  State<AdGuardTopListsCard> createState() => _AdGuardTopListsCardState();
}

class _AdGuardTopListsCardState extends State<AdGuardTopListsCard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openFullListSheet(BuildContext context) {
    AdGuardTopListsBottomSheet.show(
      context,
      stats: widget.stats,
      initialTabIndex: _tabController.index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final topBlocked = widget.stats?.topBlockedDomains ?? const [];
    final topQueried = widget.stats?.topQueriedDomains ?? const [];
    final topClients = widget.stats?.topClients ?? const [];

    final allEmpty = topBlocked.isEmpty && topQueried.isEmpty && topClients.isEmpty;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.leaderboard_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.aghTopLists ?? 'Top Activity',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!allEmpty) ...[
                  IconButton(
                    key: const Key('agh_top_lists_header_view_all_button'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    tooltip: l10n?.aghTopLists ?? 'View all',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openFullListSheet(context),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              isScrollable: false,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              tabs: [
                Tab(
                  key: const Key('agh_top_tab_blocked'),
                  text: l10n?.aghTopBlocked ?? 'Blocked',
                ),
                Tab(
                  key: const Key('agh_top_tab_queried'),
                  text: l10n?.aghTopQueried ?? 'Queried',
                ),
                Tab(
                  key: const Key('agh_top_tab_clients'),
                  text: l10n?.aghTopClients ?? 'Clients',
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: allEmpty ? 160 : 230,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildList(
                    context,
                    items: topBlocked.map((e) => (name: e.identifier, count: e.count)).toList(),
                    emptyMessage: l10n?.aghNoData ?? 'No data available',
                    keyPrefix: 'agh_top_blocked',
                    barColor: Colors.red.shade400,
                  ),
                  _buildList(
                    context,
                    items: topQueried.map((e) => (name: e.identifier, count: e.count)).toList(),
                    emptyMessage: l10n?.aghNoData ?? 'No data available',
                    keyPrefix: 'agh_top_queried',
                    barColor: colorScheme.primary,
                  ),
                  _buildList(
                    context,
                    items: topClients.map((e) => (name: e.identifier, count: e.count)).toList(),
                    emptyMessage: l10n?.aghNoData ?? 'No data available',
                    keyPrefix: 'agh_top_clients',
                    barColor: Colors.teal.shade400,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    required List<({String name, int count})> items,
    required String emptyMessage,
    required String keyPrefix,
    required Color barColor,
  }) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insights_outlined,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 8),
              Text(
                emptyMessage,
                key: Key('${keyPrefix}_empty'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final displayedItems = items.take(5).toList();
    final hasMore = items.length > 5;
    final maxCount = items.fold<int>(1, (max, item) => item.count > max ? item.count : max);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: ListView.separated(
            physics: const ClampingScrollPhysics(),
            itemCount: displayedItems.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = displayedItems[index];
              final fraction = (item.count / maxCount).clamp(0.0, 1.0);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            key: Key('${keyPrefix}_${index}_name'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.count}',
                          key: Key('${keyPrefix}_${index}_count'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: fraction,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (hasMore) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: SizedBox(
              height: 30,
              child: TextButton.icon(
                key: Key('${keyPrefix}_view_all_button'),
                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                label: Text(
                  AppLocalizations.of(context)?.aghViewAllWithCount(items.length) ??
                      'View all (${items.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _openFullListSheet(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
