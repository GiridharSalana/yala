// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/design/luci_theme.dart';
import 'package:yala/services/secure_storage_service.dart';
import 'package:yala/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await AppState.instance.initializationFuture;
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Startup Theme & Preferences Pre-Hydration Tests', () {
    test(
      'AppState.preHydrate successfully pre-populates dynamic theme from SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues({
          'appThemePalette': 'dynamicTheme',
          'useDynamicTheme': true,
          'themeMode': 'dark',
          'app_locale': 'pt_BR',
        });

        final prefs = await SharedPreferences.getInstance();
        await AppState.preHydrate(prefs: prefs);

        final appState = AppState.instance;
        expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
        expect(appState.useDynamicTheme, isTrue);
        expect(appState.themeMode, equals(ThemeMode.dark));
        expect(appState.locale, equals(const Locale('pt', 'BR')));
      },
    );

    test('AppState.preHydrate restores YALA Amber when configured', () async {
      SharedPreferences.setMockInitialValues({
        'appThemePalette': 'amber',
        'useDynamicTheme': false,
        'themeMode': 'light',
        'app_locale': 'en',
      });

      final prefs = await SharedPreferences.getInstance();
      await AppState.preHydrate(prefs: prefs);

      final appState = AppState.instance;
      expect(appState.themePalette, equals(AppThemePalette.amber));
      expect(appState.useDynamicTheme, isFalse);
      expect(appState.themeMode, equals(ThemeMode.light));
      expect(appState.locale, equals(const Locale('en')));
    });

    test(
      'AppState.preHydrate migrates legacy palette from SecureStorageService when SharedPreferences is empty',
      () async {
        SharedPreferences.setMockInitialValues({});
        final secureStorage = SecureStorageService();
        await secureStorage.writeValue('appThemePalette', 'dynamicTheme');
        await secureStorage.writeValue('themeMode', 'dark');
        await secureStorage.writeValue('app_locale', 'zh');

        final prefs = await SharedPreferences.getInstance();
        await AppState.preHydrate(prefs: prefs);

        final appState = AppState.instance;
        expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
        expect(appState.useDynamicTheme, isTrue);
        expect(appState.themeMode, equals(ThemeMode.dark));
        expect(appState.locale, equals(const Locale('zh')));

        // Verify it was cached into SharedPreferences for future instantaneous startup
        expect(prefs.getString('appThemePalette'), equals('dynamicTheme'));
        expect(prefs.getBool('useDynamicTheme'), isTrue);
        expect(prefs.getString('themeMode'), equals('dark'));
        expect(prefs.getString('app_locale'), equals('zh'));
      },
    );

    test(
      'setThemePalette persists to both memory and SharedPreferences synchronously',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await AppState.preHydrate(prefs: prefs);

        final appState = AppState.instance;
        await appState.setThemePalette(AppThemePalette.dynamicTheme);

        expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
        expect(appState.useDynamicTheme, isTrue);
        expect(prefs.getString('appThemePalette'), equals('dynamicTheme'));
        expect(prefs.getBool('useDynamicTheme'), isTrue);
      },
    );

    test(
      'Pre-hydrated dynamic palette builds Material You theme without amber accents on Frame 1',
      () async {
        SharedPreferences.setMockInitialValues({
          'appThemePalette': 'dynamicTheme',
          'useDynamicTheme': true,
        });
        final prefs = await SharedPreferences.getInstance();
        await AppState.preHydrate(prefs: prefs);

        final appState = AppState.instance;
        expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));

        // Build theme as LuCIApp does on Frame 1
        final lightTheme = LuciTheme.buildLightTheme(
          dynamicColorScheme: LuciTheme.fallbackDynamicLight,
          palette: appState.themePalette,
        );
        final darkTheme = LuciTheme.buildDarkTheme(
          dynamicColorScheme: LuciTheme.fallbackDynamicDark,
          palette: appState.themePalette,
        );

        // Verify that neither theme uses YALA Amber primary
        expect(
          lightTheme.colorScheme.primary,
          isNot(equals(LuciTheme.amberPrimaryLight)),
        );
        expect(
          darkTheme.colorScheme.primary,
          isNot(equals(LuciTheme.amberPrimaryDark)),
        );
      },
    );
  });
}
