// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/screens/login_screen.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/widgets/language_picker_dialog.dart';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.instance;
    await appState.setLocale(null);
    for (final r in List.of(appState.routers)) {
      await appState.removeRouter(r.id);
    }
  });

  testWidgets(
    'LoginScreen displays compact, self-explanatory language selector toggle',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LoginScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify LanguageSelectorBadge is present on LoginScreen and inside SingleChildScrollView
      expect(find.byType(LanguageSelectorBadge), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(LanguageSelectorBadge),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('login_language_selector_button')),
        findsOneWidget,
      );

      // 2. Verify self-explanatory translation icon
      expect(find.byIcon(Icons.translate_rounded), findsOneWidget);

      // 3. Verify dropdown indicator and default language code (EN)
      expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);

      // 4. Tap the language selector badge to open the dialog
      await tester.tap(
        find.byKey(const ValueKey('login_language_selector_button')),
      );
      await tester.pumpAndSettle();

      // 5. Verify the dialog title and key language options are rendered
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Русский'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);

      // 6. Scroll to and verify Bahasa Indonesia
      final idOptionFinder = find.text('Bahasa Indonesia');
      await tester.scrollUntilVisible(
        idOptionFinder,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(idOptionFinder, findsOneWidget);

      // 7. Select "Bahasa Indonesia"
      await tester.tap(idOptionFinder);
      await tester.pumpAndSettle();

      // 8. Verify dialog dismissed
      expect(find.text('Language'), findsNothing);
    },
  );

  testWidgets(
    'Selecting language updates locale in AppState and updates toggle label',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, child) {
              final locale = ref.watch(
                appStateProvider.select((s) => s.locale),
              );
              return MaterialApp(
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const LoginScreen(),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open language dialog
      await tester.tap(
        find.byKey(const ValueKey('login_language_selector_button')),
      );
      await tester.pumpAndSettle();

      // Scroll to and tap Bahasa Indonesia
      final idOptionFinder = find.text('Bahasa Indonesia');
      await tester.scrollUntilVisible(
        idOptionFinder,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(idOptionFinder);
      await tester.pumpAndSettle();

      // Verify AppState locale updated to Indonesian
      final appState = container.read(appStateProvider);
      expect(appState.locale?.languageCode, equals('id'));

      // Verify toggle badge now displays ID
      expect(find.text('ID'), findsOneWidget);
    },
  );

  testWidgets(
    'LoginScreen renders cleanly without overflow under French locale and large text scaling (1.45x)',
    (WidgetTester tester) async {
      // Compact mobile viewport (360x740) with 1.45x text scaling
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Add test router profiles to test chip wrap layout
      final appState = container.read(appStateProvider);
      await appState.addRouter(
        model.Router(
          id: 'router-1',
          name: 'ncxRouter',
          ipAddress: '10.0.0.1',
          username: 'root',
          password: 'password123',
          useHttps: false,
        ),
      );
      await appState.addRouter(
        model.Router(
          id: 'router-2',
          name: 'ncxTestRouter',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password123',
          useHttps: false,
        ),
      );
      await appState.setLocale(const Locale('fr'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('fr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.45)),
              child: const LoginScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // No overflow exceptions
      expect(tester.takeException(), isNull);

      // Verify language toggle displays FR and is non-floating (inside SingleChildScrollView)
      expect(find.text('FR'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(LanguageSelectorBadge),
        ),
        findsOneWidget,
      );

      // Both routers should be visible as chips without horizontal clipping
      expect(find.widgetWithText(ChoiceChip, 'ncxRouter'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'ncxTestRouter'), findsOneWidget);

      // Form fields should be present and valid
      expect(
        find.byKey(const ValueKey('login_profile_name_field')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('login_ip_field')), findsOneWidget);
    },
  );

  testWidgets(
    'Selecting Chinese updates locale in AppState and updates toggle label to ZH',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, child) {
              final locale = ref.watch(
                appStateProvider.select((s) => s.locale),
              );
              return MaterialApp(
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const LoginScreen(),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open language dialog
      await tester.tap(
        find.byKey(const ValueKey('login_language_selector_button')),
      );
      await tester.pumpAndSettle();

      // Scroll to and tap 简体中文
      final zhOptionFinder = find.text('简体中文');
      await tester.scrollUntilVisible(
        zhOptionFinder,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(zhOptionFinder, findsOneWidget);
      await tester.tap(zhOptionFinder);
      await tester.pumpAndSettle();

      // Verify AppState locale updated to Chinese
      final appState = container.read(appStateProvider);
      expect(appState.locale?.languageCode, equals('zh'));

      // Verify toggle badge now displays ZH
      expect(find.text('ZH'), findsOneWidget);
    },
  );

  testWidgets(
    'LoginScreen renders cleanly without overflow under Chinese locale and large text scaling (1.45x)',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final appState = container.read(appStateProvider);
      await appState.addRouter(
        model.Router(
          id: 'router-1',
          name: 'ncxRouter',
          ipAddress: '10.0.0.1',
          username: 'root',
          password: 'password123',
          useHttps: false,
        ),
      );
      await appState.setLocale(const Locale('zh'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.45)),
              child: const LoginScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ZH'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(LanguageSelectorBadge),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('LanguageSelectorBadge and dialog display BETA badge', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify LocalizationBetaBadge is present within LanguageSelectorBadge
    expect(
      find.descendant(
        of: find.byType(LanguageSelectorBadge),
        matching: find.byType(LocalizationBetaBadge),
      ),
      findsOneWidget,
    );
    expect(find.text('BETA'), findsOneWidget);

    // 2. Open dialog
    await tester.tap(
      find.byKey(const ValueKey('login_language_selector_button')),
    );
    await tester.pumpAndSettle();

    // 3. Verify dialog header also displays LocalizationBetaBadge
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(LocalizationBetaBadge),
      ),
      findsOneWidget,
    );
  });
}
