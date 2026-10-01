// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/screens/login_screen.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/screens/settings_screen.dart';
import 'package:yet_another_luci_app/screens/splash_screen.dart';
import 'package:yet_another_luci_app/screens/onboarding_screen.dart';

import 'package:yet_another_luci_app/models/router_capabilities.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'package:yet_another_luci_app/widgets/luci_toast.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Modern Android Edge-to-Edge System Bar Integration
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Register YALA's GPLv3 copyleft license and copyright attributions in Flutter LicenseRegistry
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['yet_another_luci_app (yala)'],
      '''Yet Another LuCI App (yala)
Original work Copyright (C) 2025-2026 cogwheel0
Modifications Copyright (C) 2026 @nightcodex7

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.''',
    );
  });

  // Low-RAM & Smooth Scrolling Optimization: Cap image memory cache (30MB max, 100 entries max)
  PaintingBinding.instance.imageCache.maximumSizeBytes = 30 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;

  // Enable semantics early so AccessibilityNodeInfo reports scrollable to OEM screenshot engines immediately
  SemanticsBinding.instance.ensureSemantics();

  runApp(const ProviderScope(child: LuCIApp()));
}

/// Standardized scroll behavior ensuring native long/autoscroll screenshot engine compatibility
/// across all Android OEMs (Xiaomi MIUI/HyperOS, Samsung OneUI, Oppo ColorOS, Vivo FuntouchOS, Stock Android 12+).
class LuciScrollBehavior extends MaterialScrollBehavior {
  const LuciScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Disable stretching overscroll effect so OEM screenshot stitching engines
    // (Xiaomi HyperOS/MIUI, Samsung OneUI, ColorOS) do not encounter pixel warping/distortion at boundaries.
    return child;
  }
}

final appStateProvider = ChangeNotifierProvider<AppState>(
  (ref) => AppState.instance,
);

final routerCapabilitiesProvider = Provider<RouterCapabilities?>((ref) {
  return ref.watch(appStateProvider).capabilities;
});

class LuCIApp extends ConsumerWidget {
  const LuCIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appStateProvider.select((s) => s.themeMode));
    final themePalette = ref.watch(
      appStateProvider.select((s) => s.themePalette),
    );
    final appLocale = ref.watch(appStateProvider.select((s) => s.locale));
    final useDynamicTheme = themePalette == AppThemePalette.dynamicTheme;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightTheme = LuciTheme.buildLightTheme(
          dynamicColorScheme: useDynamicTheme
              ? (lightDynamic ?? LuciTheme.fallbackDynamicLight)
              : null,
          palette: themePalette,
        );
        final darkTheme = LuciTheme.buildDarkTheme(
          dynamicColorScheme: useDynamicTheme
              ? (darkDynamic ?? LuciTheme.fallbackDynamicDark)
              : null,
          palette: themePalette,
        );

        return MaterialApp(
          navigatorKey: LuciToastManager.navigatorKey,
          title: 'Yet Another LuCI App',
          restorationScopeId: 'root_luci_app',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const LuciScrollBehavior(),
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            // Accessibility large font support clamped within safe bounds [0.85, 1.45]
            // Allows 45% larger font size while preventing UI destruction on dense network management views
            final clampedTextScaler = mediaQuery.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.45,
            );
            return MediaQuery(
              data: mediaQuery.copyWith(textScaler: clampedTextScaler),
              child: child ?? const SizedBox.shrink(),
            );
          },
          locale: appLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale == null) return const Locale('en');
            if (locale.languageCode == 'pt') {
              if (locale.countryCode == 'BR') {
                return const Locale('pt', 'BR');
              }
              return const Locale('pt');
            }
            if (locale.languageCode == 'zh') {
              return const Locale('zh');
            }
            for (final supported in supportedLocales) {
              if (supported.languageCode == locale.languageCode &&
                  supported.countryCode == null) {
                return supported;
              }
            }
            // English is the fallback as well as base
            return const Locale('en');
          },
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => const SplashScreen(),
            '/onboarding': (context) => const OnboardingScreen(),
            '/login': (context) => const LoginScreen(),
            '/': (context) => const MainScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
        );
      },
    );
  }
}
