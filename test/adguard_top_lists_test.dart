// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_top_lists_bottom_sheet.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_top_lists_card.dart';

Widget buildTestApp({required Widget child}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockStats10 = AdGuardStats(
    numDnsQueries: 50000,
    numBlockedFiltering: 12000,
    numReplacedSafebrowsing: 0,
    numReplacedSafesearch: 0,
    numReplacedParental: 0,
    avgProcessingTime: 0.02,
    topQueriedDomains: List.generate(
      8,
      (i) => AdGuardTopItem(identifier: 'queried$i.com', count: 1000 - i * 50),
    ),
    topBlockedDomains: List.generate(
      10,
      (i) => AdGuardTopItem(identifier: 'blocked$i.net', count: 500 - i * 20),
    ),
    topClients: List.generate(
      6,
      (i) => AdGuardTopItem(
        identifier: '192.168.1.${10 + i}',
        count: 800 - i * 30,
      ),
    ),
    dnsQueriesTrend: const [],
    blockedFilteringTrend: const [],
    blockRatePercentage: 24.0,
  );

  group('AdGuardTopListsCard & AdGuardTopListsBottomSheet Tests', () {
    testWidgets(
      'Card displays max 5 items and View all button when items > 5',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildTestApp(child: AdGuardTopListsCard(stats: mockStats10)),
        );
        await tester.pumpAndSettle();

        // Blocked tab is initial tab (10 items)
        // Items 0 to 4 should be rendered in the card
        expect(find.byKey(const Key('agh_top_blocked_0_name')), findsOneWidget);
        expect(find.byKey(const Key('agh_top_blocked_4_name')), findsOneWidget);

        // Item 5 should NOT be rendered in the card (max 5 items)
        expect(find.byKey(const Key('agh_top_blocked_5_name')), findsNothing);

        // View all button should be visible with total count
        final viewAllBtn = find.byKey(
          const Key('agh_top_blocked_view_all_button'),
        );
        expect(viewAllBtn, findsOneWidget);
        expect(find.text('View all (10)'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping View all button opens modal bottom sheet with all entries',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildTestApp(child: AdGuardTopListsCard(stats: mockStats10)),
        );
        await tester.pumpAndSettle();

        // Tap View all button
        await tester.tap(
          find.byKey(const Key('agh_top_blocked_view_all_button')),
        );
        await tester.pumpAndSettle();

        // Bottom sheet is now open
        expect(
          find.byKey(const Key('agh_top_lists_bottom_sheet')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_top_sheet_tab_blocked')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_top_sheet_tab_queried')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_top_sheet_tab_clients')),
          findsOneWidget,
        );

        // In bottom sheet, all items from 0 to 9 are rendered
        expect(
          find.byKey(const Key('agh_sheet_top_blocked_0_name')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_sheet_top_blocked_4_name')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_sheet_top_blocked_9_name')),
          findsOneWidget,
        );

        // Rank badges #1 and #10 exist
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#10'), findsOneWidget);
      },
    );

    testWidgets('Header view all button opens bottom sheet with active tab', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(child: AdGuardTopListsCard(stats: mockStats10)),
      );
      await tester.pumpAndSettle();

      // Switch to Queried tab using its key
      await tester.tap(find.byKey(const Key('agh_top_tab_queried')));
      await tester.pumpAndSettle();

      // Tap header view all button
      await tester.tap(
        find.byKey(const Key('agh_top_lists_header_view_all_button')),
      );
      await tester.pumpAndSettle();

      // Bottom sheet opens
      expect(
        find.byKey(const Key('agh_top_lists_bottom_sheet')),
        findsOneWidget,
      );

      // Queried items exist in sheet
      expect(
        find.byKey(const Key('agh_sheet_top_queried_0_name')),
        findsOneWidget,
      );
    });

    testWidgets('Bottom sheet search field filters domains dynamically', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: AdGuardTopListsBottomSheet(
            stats: mockStats10,
            initialTabIndex: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('blocked0.net'), findsOneWidget);
      expect(find.text('blocked7.net'), findsOneWidget);

      // Enter search text
      await tester.enterText(
        find.byKey(const Key('agh_top_lists_sheet_search_field')),
        'blocked7',
      );
      await tester.pumpAndSettle();

      expect(find.text('blocked0.net'), findsNothing);
      expect(find.text('blocked7.net'), findsOneWidget);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      expect(find.text('blocked0.net'), findsOneWidget);
    });

    testWidgets('Close button dismisses the bottom sheet', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  AdGuardTopListsBottomSheet.show(context, stats: mockStats10),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('agh_top_lists_bottom_sheet')),
        findsOneWidget,
      );

      // Tap close button
      await tester.tap(
        find.byKey(const Key('agh_top_lists_sheet_close_button')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_top_lists_bottom_sheet')), findsNothing);
    });
  });
}
