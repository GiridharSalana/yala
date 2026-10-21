// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/json_export/json_export_screen.dart';
import 'package:yet_another_luci_app/screens/settings_screen.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          return null;
        });
  });

  setUp(() {
    final appState = AppState.instance;
    appState.setApiServiceForTesting(MockApiService());
    appState.setDashboardTabActive(false);
    appState.cancelThroughputTimer();
  });

  tearDown(() {
    AppState.instance.cancelThroughputTimer();
  });

  group('JsonExportScreen Localization Tests', () {
    testWidgets('Renders in English with default strings', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState.instance;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('en'),
            home: JsonExportScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Export Configuration'), findsOneWidget);
      expect(find.text('INDIVIDUAL EXPORTS'), findsOneWidget);
      expect(find.text('ALL-IN-ONE'), findsOneWidget);
      expect(find.text('DDNS Entries'), findsOneWidget);
      expect(find.text('Static DHCP Leases'), findsOneWidget);
      expect(find.text('Firewall Rules'), findsOneWidget);
      expect(find.text('Export All (JSON)'), findsWidgets);
    });

    testWidgets('Renders localized strings in German (de)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState.instance;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('de'),
            home: JsonExportScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Konfiguration exportieren'), findsOneWidget);
      expect(find.text('EINZELNE EXPORTE'), findsOneWidget);
      expect(find.text('KOMPLETTER EXPORT'), findsOneWidget);
      expect(find.text('DDNS-Einträge'), findsOneWidget);
      expect(find.text('Statische DHCP-Leases'), findsOneWidget);
      expect(find.text('Firewall-Regeln'), findsOneWidget);
      expect(find.text('Alles exportieren (JSON)'), findsWidgets);
    });

    testWidgets('Renders localized strings in Spanish (es)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState.instance;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: JsonExportScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Exportar configuración'), findsOneWidget);
      expect(find.text('EXPORTACIONES INDIVIDUALES'), findsOneWidget);
      expect(find.text('TODO EN UNO'), findsOneWidget);
      expect(find.text('Entradas DDNS'), findsOneWidget);
      expect(find.text('Concesiones estáticas DHCP'), findsOneWidget);
      expect(find.text('Reglas de cortafuegos'), findsOneWidget);
      expect(find.text('Exportar todo (JSON)'), findsWidgets);
    });
  });

  group('SettingsScreen Data Management Tile Localization', () {
    testWidgets(
      'Settings screen displays localized export config tile and navigates to JsonExportScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final appState = AppState.instance;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const MaterialApp(
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('de'),
              home: SettingsScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Check German section and tile titles
        expect(find.text('DATENVERWALTUNG'), findsOneWidget);
        expect(find.text('Konfiguration exportieren (JSON)'), findsOneWidget);

        // Tap tile to open JsonExportScreen
        await tester.tap(find.text('Konfiguration exportieren (JSON)'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(find.byType(JsonExportScreen), findsOneWidget);
        expect(find.text('EINZELNE EXPORTE'), findsOneWidget);
      },
    );
  });
}
