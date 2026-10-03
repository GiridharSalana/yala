// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/screens/main_screen.dart';
import 'package:yala/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});

  group('Adaptive Bottom Navigation Bar Tests', () {
    setUp(() async {
      final appState = AppState.instance;
      await appState.setReviewerMode(true);
      appState.markReviewerNoticeShown();
    });
    testWidgets(
      'shouldUseMultiLineNav returns false for short English single-line labels',
      (WidgetTester tester) async {
        late bool resultShort;
        late bool resultStandard;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                // In Ahem test font (where every char is 1em = 11px wide):
                // Short 4-5 char labels fit easily in 72px slot
                resultShort = MainScreen.shouldUseMultiLineNav(
                  context: context,
                  slotWidth: 72.0,
                  labels: const ['Home', 'Logs', 'Wi-Fi', 'Apps', 'More'],
                  textScaler: TextScaler.noScaling,
                );
                // Standard labels fit in proportional slot without wrapping
                resultStandard = MainScreen.shouldUseMultiLineNav(
                  context: context,
                  slotWidth: 120.0,
                  labels: const [
                    'Interfaces',
                    'Clients',
                    'Dashboard',
                    'Wireless',
                    'More',
                  ],
                  textScaler: TextScaler.noScaling,
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(resultShort, isFalse);
        expect(resultStandard, isFalse);
      },
    );

    testWidgets(
      'shouldUseMultiLineNav returns true for long multi-line Russian labels',
      (WidgetTester tester) async {
        late bool result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                result = MainScreen.shouldUseMultiLineNav(
                  context: context,
                  slotWidth: 120.0,
                  labels: const [
                    'Интерфейсы',
                    'Клиенты',
                    'Панель управления',
                    'Беспроводная сеть',
                    'Ещё',
                  ],
                  textScaler: TextScaler.noScaling,
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(result, isTrue);
      },
    );

    testWidgets(
      'shouldUseMultiLineNav returns true for long Spanish labels (Panel de control)',
      (WidgetTester tester) async {
        late bool result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                result = MainScreen.shouldUseMultiLineNav(
                  context: context,
                  slotWidth: 120.0,
                  labels: const [
                    'Interfaces',
                    'Clientes',
                    'Panel de control',
                    'Inalámbrico',
                    'Más',
                  ],
                  textScaler: TextScaler.noScaling,
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(result, isTrue);
      },
    );

    testWidgets(
      'shouldUseMultiLineNav returns true for French labels (Tableau de bord)',
      (WidgetTester tester) async {
        late bool result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                result = MainScreen.shouldUseMultiLineNav(
                  context: context,
                  slotWidth: 120.0,
                  labels: const [
                    'Interfaces',
                    'Clients',
                    'Tableau de bord',
                    'Sans fil',
                    'Plus',
                  ],
                  textScaler: TextScaler.noScaling,
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(result, isTrue);
      },
    );

    testWidgets(
      'shouldUseMultiLineNav returns true when accessibility textScaler causes wrapping',
      (WidgetTester tester) async {
        late bool result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                result = MainScreen.shouldUseMultiLineNav(
                  context: context,
                  slotWidth: 120.0,
                  labels: const [
                    'Interfaces',
                    'Clients',
                    'Dashboard',
                    'Wireless',
                    'More',
                  ],
                  textScaler: const TextScaler.linear(1.6), // large text scale
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(result, isTrue);
      },
    );

    testWidgets(
      'Edge case: handles zero or negative slotWidth safely without throwing',
      (WidgetTester tester) async {
        late bool resultZero;
        late bool resultNegative;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                resultZero = MainScreen.shouldUseMultiLineNav(
                  context: context,
                  slotWidth: 0,
                  labels: const ['Dashboard'],
                  textScaler: TextScaler.noScaling,
                );
                resultNegative = MainScreen.shouldUseMultiLineNav(
                  context: context,
                  slotWidth: -10,
                  labels: const ['Dashboard'],
                  textScaler: TextScaler.noScaling,
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(resultZero, isFalse);
        expect(resultNegative, isFalse);
      },
    );

    testWidgets('Edge case: handles empty label list safely', (
      WidgetTester tester,
    ) async {
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = MainScreen.shouldUseMultiLineNav(
                context: context,
                slotWidth: 72.0,
                labels: const [],
                textScaler: TextScaler.noScaling,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result, isFalse);
    });

    testWidgets(
      'Wide viewport allows long labels to fit in single-line shrunk mode',
      (WidgetTester tester) async {
        late bool result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                result = MainScreen.shouldUseMultiLineNav(
                  context: context,
                  slotWidth: 200.0, // wide slot
                  labels: const [
                    'Interfaces',
                    'Clients',
                    'Dashboard',
                    'Wireless',
                    'More',
                  ],
                  textScaler: TextScaler.noScaling,
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(result, isFalse);
      },
    );

    testWidgets(
      'MainScreen renders compact single-line bottom bar in English on wide phone slot',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(590, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MainScreen(initialTab: 4), // More tab
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify phone bottom bar is rendered (not tablet NavigationRail)
        expect(find.byType(NavigationRail), findsNothing);
        expect(find.text('Interfaces'), findsOneWidget);
        expect(find.text('Clients'), findsOneWidget);
        expect(find.text('Dashboard'), findsOneWidget);

        final dashboardText = tester.widget<Text>(find.text('Dashboard'));
        expect(dashboardText.maxLines, 1);

        // Verify no exceptions or overflows were thrown
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'MainScreen adaptively expands bottom bar to multi-line mode with long German labels',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(590, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              locale: Locale('de'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MainScreen(initialTab: 4),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationRail), findsNothing);
        // "Schnittstellen" (14 chars) forces multi-line mode
        expect(find.text('Schnittstellen'), findsOneWidget);
        expect(find.text('Übersicht'), findsOneWidget);

        final dashboardText = tester.widget<Text>(find.text('Übersicht'));
        expect(dashboardText.maxLines, 2);

        // Verify no exceptions or overflows were thrown
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'MainScreen adaptively expands bottom bar to multi-line mode on standard phone width',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              locale: Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MainScreen(initialTab: 4),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationRail), findsNothing);
        expect(find.text('Панель'), findsOneWidget);

        final dashboardText = tester.widget<Text>(find.text('Панель'));
        expect(dashboardText.maxLines, 2);

        // Verify no exceptions or overflows were thrown
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'MainScreen adaptively expands bottom bar to multi-line mode with high text scaling in English',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(590, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(590, 800),
                  textScaler: TextScaler.linear(1.6),
                ),
                child: const MainScreen(initialTab: 4),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationRail), findsNothing);
        final dashboardText = tester.widget<Text>(find.text('Dashboard'));
        expect(dashboardText.maxLines, 2);

        // Verify no exceptions or overflows were thrown
        expect(tester.takeException(), isNull);
      },
    );
  });
}
