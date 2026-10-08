// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/design/luci_theme.dart';
import 'package:yala/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('Theme mode and theme palette are preserved across logout', () async {
    final appState = AppState.instance;

    // Set custom theme mode and dynamic theme palette
    await appState.setThemeMode(ThemeMode.dark);
    await appState.setThemePalette(AppThemePalette.dynamicTheme);

    expect(appState.themeMode, equals(ThemeMode.dark));
    expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
    expect(appState.useDynamicTheme, isTrue);

    // Perform logout
    await appState.logout();

    // Verify theme and palette were NOT wiped to default system / amber
    expect(appState.themeMode, equals(ThemeMode.dark));
    expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
    expect(appState.useDynamicTheme, isTrue);
  });

  test('Theme mode and theme palette are preserved across reviewer mode toggles', () async {
    final appState = AppState.instance;

    await appState.setThemeMode(ThemeMode.light);
    await appState.setThemePalette(AppThemePalette.dynamicTheme);

    expect(appState.themeMode, equals(ThemeMode.light));
    expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));

    // Enable reviewer mode
    await appState.setReviewerMode(true);
    expect(appState.themeMode, equals(ThemeMode.light));
    expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));

    // Disable reviewer mode
    await appState.setReviewerMode(false);
    expect(appState.themeMode, equals(ThemeMode.light));
    expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));

    // Logout
    await appState.logout();
    expect(appState.themeMode, equals(ThemeMode.light));
    expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
  });
}
