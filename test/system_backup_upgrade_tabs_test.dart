// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

Widget _buildTestHarness({
  required Size screenSize,
  required TextScaler textScaler,
  required Locale locale,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(size: screenSize, textScaler: textScaler),
      child: Scaffold(body: _TestNavigationHost()),
    ),
  );
}

class _TestNavigationHost extends StatefulWidget {
  @override
  State<_TestNavigationHost> createState() => _TestNavigationHostState();
}

class _TestNavigationHostState extends State<_TestNavigationHost>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildNavigationTab({
    required IconData icon,
    required String label,
    required double tabHeight,
    required bool isTablet,
  }) {
    return Tab(
      height: tabHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: isTablet
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(height: 3),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final textScaler = mediaQuery.textScaler;
    final isTablet = screenWidth >= 600;

    const double headerVerticalPadding = 4.0;
    final double tabHeight;
    if (isTablet) {
      tabHeight = (textScaler.scale(12.0) * 1.3 * 2 + 20.0).clamp(52.0, 76.0);
    } else {
      final textHeight = textScaler.scale(11.0) * 1.18 * 3;
      tabHeight = (16.0 + 4.0 + textHeight + 10.0).clamp(72.0, 120.0);
    }
    final headerHeight = tabHeight + (headerVerticalPadding * 2);

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _TestSliverTabBarDelegate(
            height: headerHeight,
            child: Container(
              color: theme.scaffoldBackgroundColor,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: headerVerticalPadding,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _controller,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: LuciColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  tabs: [
                    _buildNavigationTab(
                      icon: Icons.system_update_alt,
                      label:
                          l10n?.sysUpgradeSectionFlash ??
                          'Flash New Firmware Image',
                      tabHeight: tabHeight,
                      isTablet: isTablet,
                    ),
                    _buildNavigationTab(
                      icon: Icons.archive_outlined,
                      label:
                          l10n?.sysUpgradeSectionBackup ?? 'Backup & Restore',
                      tabHeight: tabHeight,
                      isTablet: isTablet,
                    ),
                    _buildNavigationTab(
                      icon: Icons.tune_rounded,
                      label:
                          l10n?.sysUpgradeMtdBlockSection ??
                          'MTD Block Partitions',
                      tabHeight: tabHeight,
                      isTablet: isTablet,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverFillRemaining(
          child: TabBarView(
            controller: _controller,
            children: const [
              Center(child: Text('Flash')),
              Center(child: Text('Backup')),
              Center(child: Text('MTD')),
            ],
          ),
        ),
      ],
    );
  }
}

class _TestSliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _TestSliverTabBarDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_TestSliverTabBarDelegate oldDelegate) {
    return true;
  }
}

void main() {
  group('System Backup & Upgrade Navigation Tabs Resilience Tests', () {
    const screenSizes = [
      Size(320, 640), // Ultra narrow compact
      Size(360, 780), // Standard small phone
      Size(390, 844), // Modern mainstream phone (matching user screenshot)
      Size(412, 915), // Large Android phone
      Size(600, 960), // Foldable/small tablet
      Size(800, 1280), // Medium tablet
      Size(1280, 800), // Landscape tablet
    ];

    const fontScales = [
      TextScaler.linear(0.85),
      TextScaler.linear(1.0),
      TextScaler.linear(1.15),
      TextScaler.linear(1.3),
      TextScaler.linear(1.5),
      TextScaler.linear(1.8),
    ];

    const locales = AppLocalizations.supportedLocales;

    testWidgets('Renders cleanly on modern phone (390x844) with default font', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestHarness(
          screenSize: const Size(390, 844),
          textScaler: const TextScaler.linear(1.0),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(3));
      expect(find.text('Flash New Firmware Image'), findsOneWidget);
      expect(find.text('Backup & Restore'), findsOneWidget);
      expect(find.text('MTD Block Partitions'), findsOneWidget);
    });

    testWidgets('Handles ultra-narrow screen (320x640) with 1.3x text scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestHarness(
          screenSize: const Size(320, 640),
          textScaler: const TextScaler.linear(1.3),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Tab), findsNWidgets(3));
    });

    testWidgets(
      'Handles large accessibility font scale (1.8x) without overflow',
      (tester) async {
        await tester.pumpWidget(
          _buildTestHarness(
            screenSize: const Size(412, 915),
            textScaler: const TextScaler.linear(1.8),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(Tab), findsNWidgets(3));
      },
    );

    testWidgets('Tablet breakpoint (>=600px) activates horizontal Row layout', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestHarness(
          screenSize: const Size(800, 1280),
          textScaler: const TextScaler.linear(1.0),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // In tablet mode, each tab contains a Row with an Icon and a Text widget
      final tabWidgets = tester.widgetList<Tab>(find.byType(Tab));
      expect(tabWidgets.length, 3);
      for (final tab in tabWidgets) {
        final padding = tab.child as Padding;
        expect(padding.child, isA<Row>());
      }
    });

    testWidgets('Phone mode (<600px) activates vertical Column layout', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestHarness(
          screenSize: const Size(390, 844),
          textScaler: const TextScaler.linear(1.0),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final tabWidgets = tester.widgetList<Tab>(find.byType(Tab));
      expect(tabWidgets.length, 3);
      for (final tab in tabWidgets) {
        final padding = tab.child as Padding;
        expect(padding.child, isA<Column>());
      }
    });

    testWidgets('Renders zero overflow errors across all 9 supported locales', (
      tester,
    ) async {
      for (final loc in locales) {
        await tester.pumpWidget(
          _buildTestHarness(
            screenSize: const Size(360, 780),
            textScaler: const TextScaler.linear(1.15),
            locale: loc,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Locale ${loc.languageCode} failed layout check',
        );
      }
    });

    testWidgets('Exhaustive matrix sweep: screen sizes x font scales', (
      tester,
    ) async {
      for (final size in screenSizes) {
        for (final scale in fontScales) {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(
            _buildTestHarness(
              screenSize: size,
              textScaler: scale,
              locale: const Locale('en'),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'Failed at size: $size, scale: $scale',
          );
        }
      }
      await tester.binding.setSurfaceSize(null);
    });
  });
}
