// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/system_monitoring/models/router_temperature.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/screens/system_monitoring_screen.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/widgets/add_rpc_handler_dialog.dart';
import 'package:yet_another_luci_app/screens/dashboard_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState appState;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'hint_dismissed_rpc_missing_warning': true,
    });

    appState = AppState.instance;
    final testRouter = model.Router(
      id: 'test_router',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: 'password',
      useHttps: false,
    );
    await appState.routerService?.addRouter(testRouter);
    await appState.routerService?.selectRouter(testRouter.id);
  });

  Map<String, dynamic> createDashboardData({
    required RouterTemperature temperature,
  }) {
    return {
      'sysInfo': {
        'uptime': 3600,
        'memory': {'total': 256000000, 'free': 128000000, 'buffered': 10000000},
        'load': [0.15, 0.20, 0.25],
      },
      'boardInfo': {
        'hostname': 'OpenWrt-Router',
        'model': 'Test Hardware',
        'release': {'version': '23.05.2'},
      },
      'temperature': temperature,
      'wireless': <String, dynamic>{},
      'clients': <Map<String, dynamic>>[],
    };
  }

  testWidgets(
    'DashboardScreen does NOT show temperature prompt pill when router hardware is unsupported (no sensors)',
    (WidgetTester tester) async {
      final unsupportedTemp = RouterTemperature.unavailable(
        hasPhysicalSensors: false,
        isHandlerInstalled: false,
        reason: 'Thermal sensors are not supported on this router hardware.',
      );

      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: false),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(temperature: unsupportedTemp),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Temp Script Missing'), findsNothing);
      expect(find.byIcon(Icons.thermostat_outlined), findsNothing);
    },
  );

  testWidgets(
    'DashboardScreen does NOT show temperature prompt pill when temperature monitoring is already supported and active',
    (WidgetTester tester) async {
      final activeTemp = RouterTemperature.mock();

      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: false),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(temperature: activeTemp),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Temp Script Missing'), findsNothing);
    },
  );

  testWidgets(
    'DashboardScreen DOES show temperature prompt pill when hardware sensors exist but script is missing',
    (WidgetTester tester) async {
      final needsHandlerTemp = RouterTemperature.unavailable(
        hasPhysicalSensors: true,
        isHandlerInstalled: false,
        reason:
            'Hardware thermal sensors detected, but native OpenWrt RPC handler is not installed.',
      );

      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: false),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(temperature: needsHandlerTemp),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Temp Script Missing'), findsOneWidget);
      expect(find.byIcon(Icons.thermostat_outlined), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping the temperature prompt pill opens the AddRpcHandlerDialog',
    (WidgetTester tester) async {
      final needsHandlerTemp = RouterTemperature.unavailable(
        hasPhysicalSensors: true,
        isHandlerInstalled: false,
      );

      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: false),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(temperature: needsHandlerTemp),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      final pillFinder = find.text('Temp Script Missing');
      expect(pillFinder, findsOneWidget);

      await tester.tap(pillFinder);
      await tester.pumpAndSettle();

      expect(find.byType(AddRpcHandlerDialog), findsOneWidget);
      expect(find.text('Enable Temperature'), findsOneWidget);
      expect(find.text('Install Automatically'), findsOneWidget);
      expect(find.text("Don't Show Again"), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping the dismiss ✕ button permanently dismisses the prompt and saves preference',
    (WidgetTester tester) async {
      final needsHandlerTemp = RouterTemperature.unavailable(
        hasPhysicalSensors: true,
        isHandlerInstalled: false,
      );

      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: false),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(temperature: needsHandlerTemp),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Temp Script Missing'), findsOneWidget);

      final closeButtonFinder = find.byIcon(Icons.close_rounded);
      expect(closeButtonFinder, findsOneWidget);

      await tester.tap(closeButtonFinder);
      await tester.pumpAndSettle();

      expect(appState.dashboardPreferences.dismissTemperaturePrompt, isTrue);
      expect(find.text('Temp Script Missing'), findsNothing);
    },
  );

  testWidgets(
    'DashboardScreen does NOT show temperature prompt pill when dismissTemperaturePrompt is true',
    (WidgetTester tester) async {
      final needsHandlerTemp = RouterTemperature.unavailable(
        hasPhysicalSensors: true,
        isHandlerInstalled: false,
      );

      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: true),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(temperature: needsHandlerTemp),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Temp Script Missing'), findsNothing);
    },
  );

  testWidgets(
    'DashboardScreen does NOT show temperature prompt pill when showTemperature preference is false',
    (WidgetTester tester) async {
      final needsHandlerTemp = RouterTemperature.unavailable(
        hasPhysicalSensors: true,
        isHandlerInstalled: false,
      );

      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(
          showTemperature: false,
          dismissTemperaturePrompt: false,
        ),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(temperature: needsHandlerTemp),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Temp Script Missing'), findsNothing);
    },
  );

  testWidgets(
    'SystemMonitoringScreen thermal card remains visible and non-dismissible even when dismissTemperaturePrompt is true',
    (WidgetTester tester) async {
      final needsHandlerTemp = RouterTemperature.unavailable(
        hasPhysicalSensors: true,
        isHandlerInstalled: false,
      );

      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: true),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(temperature: needsHandlerTemp),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SystemMonitoringScreen())),
      );
      await tester.scrollUntilVisible(find.text('RPC Handler Missing'), 300);
      await tester.pumpAndSettle();

      expect(find.text('RPC Handler Missing'), findsOneWidget);
      expect(find.text('Add Native RPC Handler'), findsOneWidget);
    },
  );
}
