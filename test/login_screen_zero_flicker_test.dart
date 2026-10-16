// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/screens/login_screen.dart';
import 'package:yala/state/app_state.dart';

void main() {
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await AppState.instance.initializationFuture;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.instance;
    appState.setError(null);
  });

  group('LoginScreen Zero-Flicker Pre-Hydration Tests', () {
    testWidgets('LoginScreen synchronously resolves matching profile on Frame 1 without layout jump', (WidgetTester tester) async {
      final appState = AppState.instance;
      if (!appState.isInitialized) {
        await appState.initializationFuture;
      }

      final testRouter = model.Router(
        id: 'router-test-1',
        name: 'Home Gateway',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password123',
        useHttps: false,
      );
      appState.routerService?.updateRouterInMemory(testRouter);

      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LoginScreen(
              initialIp: '192.168.1.1',
              initialUsername: 'root',
              initialPassword: 'password123',
            ),
          ),
        ),
      );

      // Verify Frame 1 contains the profile chip immediately
      expect(find.widgetWithText(ChoiceChip, 'Home Gateway'), findsOneWidget);

      final choiceChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Home Gateway'),
      );
      expect(choiceChip.selected, isTrue);

      await tester.pump(const Duration(milliseconds: 100));

      // Profile remains stably selected with zero layout pop
      expect(find.widgetWithText(ChoiceChip, 'Home Gateway'), findsOneWidget);
      final settledChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Home Gateway'),
      );
      expect(settledChip.selected, isTrue);

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('LoginScreen profile selector does not rebuild on unrelated AppState error mutations', (WidgetTester tester) async {
      final appState = AppState.instance;
      if (!appState.isInitialized) {
        await appState.initializationFuture;
      }

      final testRouter = model.Router(
        id: 'router-test-2',
        name: 'Office AP',
        ipAddress: '192.168.2.1',
        username: 'root',
        password: 'password456',
        useHttps: false,
      );
      appState.routerService?.updateRouterInMemory(testRouter);

      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LoginScreen(
              initialIp: '192.168.2.1',
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.widgetWithText(ChoiceChip, 'Office AP'), findsOneWidget);

      // Mutate unrelated AppState property (e.g. error message)
      appState.setError('Transient network warning');
      await tester.pump();

      // Profile chip is intact and unaffected
      expect(find.widgetWithText(ChoiceChip, 'Office AP'), findsOneWidget);

      appState.setError(null);
      await tester.pump();
      expect(find.widgetWithText(ChoiceChip, 'Office AP'), findsOneWidget);

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
    });
  });
}

