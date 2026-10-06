// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/screens/settings_screen.dart';
import 'package:yet_another_luci_app/services/update_checker_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F-Droid Compliance & Bundled Fonts', () {
    tearDown(() {
      AppConfig.debugIsFdroidBuild = null;
    });

    test('All 18 Geist and Geist Mono font weights and OFL.txt exist in assets', () async {
      final fontFiles = [
        'assets/fonts/Geist-Thin.ttf',
        'assets/fonts/Geist-ExtraLight.ttf',
        'assets/fonts/Geist-Light.ttf',
        'assets/fonts/Geist-Regular.ttf',
        'assets/fonts/Geist-Medium.ttf',
        'assets/fonts/Geist-SemiBold.ttf',
        'assets/fonts/Geist-Bold.ttf',
        'assets/fonts/Geist-ExtraBold.ttf',
        'assets/fonts/Geist-Black.ttf',
        'assets/fonts/GeistMono-Thin.ttf',
        'assets/fonts/GeistMono-ExtraLight.ttf',
        'assets/fonts/GeistMono-Light.ttf',
        'assets/fonts/GeistMono-Regular.ttf',
        'assets/fonts/GeistMono-Medium.ttf',
        'assets/fonts/GeistMono-SemiBold.ttf',
        'assets/fonts/GeistMono-Bold.ttf',
        'assets/fonts/GeistMono-ExtraBold.ttf',
        'assets/fonts/GeistMono-Black.ttf',
      ];

      for (final fontFile in fontFiles) {
        final byteData = await rootBundle.load(fontFile);
        expect(
          byteData.lengthInBytes,
          greaterThan(10000),
          reason: 'Font $fontFile must be a non-empty TTF file',
        );
      }

      final licenseString = await rootBundle.loadString('assets/fonts/OFL.txt');
      expect(licenseString, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(licenseString, contains('The Geist Project Authors'));
    });

    test('GoogleFonts config allowRuntimeFetching can be disabled for offline compliance', () {
      GoogleFonts.config.allowRuntimeFetching = false;
      expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    });

    test('AppConfig.isFdroidBuild defaults to false and respects debugIsFdroidBuild override', () {
      AppConfig.debugIsFdroidBuild = null;
      expect(AppConfig.isFdroidBuild, isFalse);

      AppConfig.debugIsFdroidBuild = true;
      expect(AppConfig.isFdroidBuild, isTrue);

      AppConfig.debugIsFdroidBuild = false;
      expect(AppConfig.isFdroidBuild, isFalse);
    });

    testWidgets('Update checker is visible when isFdroidBuild is false', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({});
      AppConfig.debugIsFdroidBuild = false;
      final appState = AppState.instance;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final updateTile = find.text('Check for Updates');
      await tester.scrollUntilVisible(
        updateTile,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('APP UPDATES'), findsOneWidget);
      expect(updateTile, findsOneWidget);
    });

    testWidgets('Update checker is completely hidden when isFdroidBuild is true', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({});
      AppConfig.debugIsFdroidBuild = true;
      final appState = AppState.instance;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('APP UPDATES'), findsNothing);
      expect(find.text('Check for Updates'), findsNothing);
    });

    testWidgets('UpdateCheckerService.checkForUpdates no-ops when isFdroidBuild is true', (tester) async {
      AppConfig.debugIsFdroidBuild = true;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Test')),
        ),
      );
      final context = tester.element(find.text('Test'));

      // Should return immediately without displaying progress dialog or throwing
      await UpdateCheckerService.checkForUpdates(context);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
