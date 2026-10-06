// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/system_monitoring/models/router_temperature.dart';
import 'package:yet_another_luci_app/screens/dashboard_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_states.dart';

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
    Map<String, dynamic>? sysInfo,
    RouterTemperature? temperature,
  }) {
    return {
      'sysInfo': sysInfo ?? {
        'uptime': 3600,
        'memory': {'total': 256000000, 'free': 128000000, 'buffered': 10000000},
        'load': [0.29, 0.20, 0.25],
        'cpu': {'usage': 15.0},
      },
      'boardInfo': {
        'hostname': 'OpenWrt-Router',
        'model': 'TP-Link Archer C60 v3',
        'release': {'version': '25.12.1'},
      },
      'temperature': ?temperature,
      'wireless': <String, dynamic>{},
      'clients': <Map<String, dynamic>>[],
    };
  }

  testWidgets(
    'DashboardScreen renders System Vitals and Connected Clients labels with LuciSkeleton values during loading state',
    (WidgetTester tester) async {
      // Simulate loading state: dashboardData is null, isDashboardLoading is true
      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: false),
      );
      appState.setDashboardDataForTesting(null);
      appState.setIsDashboardLoadingForTesting(true);
      appState.clientControllerForTesting?.resetState();

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pump();

      // System Vitals labels should be rendered
      expect(find.text('CPU Usage'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);
      expect(find.text('Load Average'), findsOneWidget);
      expect(find.text('Uptime'), findsOneWidget);

      // Temperature field should NOT be rendered while loading
      expect(find.text('Temperature'), findsNothing);

      // Connected Clients labels should be rendered
      expect(find.text('Wired Clients'), findsOneWidget);
      expect(find.text('Wireless Clients'), findsOneWidget);

      // Animated loading placeholders (LuciSkeleton) should be rendered for the values
      expect(find.byType(LuciSkeleton), findsWidgets);

      appState.setIsDashboardLoadingForTesting(false);
    },
  );

  testWidgets(
    'DashboardScreen dynamically displays values when data loads without temperature, omitting temperature field',
    (WidgetTester tester) async {
      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: false),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(
          sysInfo: {
            'uptime': 45120, // 12h 32m
            'memory': {'total': 100000000, 'free': 42000000, 'buffered': 0}, // 58%
            'load': [0.29, 0.20, 0.15],
            'cpu': {'usage': 15.0},
          },
          temperature: RouterTemperature.unavailable(
            hasPhysicalSensors: false,
            isHandlerInstalled: false,
          ),
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      // Dynamic values should be visible
      expect(find.text('15%'), findsOneWidget);
      expect(find.text('58%'), findsOneWidget);
      expect(find.text('0.29'), findsOneWidget);
      expect(find.text('12h 32m'), findsOneWidget);

      // Temperature field must NOT exist
      expect(find.text('Temperature'), findsNothing);
    },
  );

  testWidgets(
    'DashboardScreen dynamically adds Temperature field when router has valid thermal data',
    (WidgetTester tester) async {
      final mockTemp = RouterTemperature.mock();

      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: false),
      );
      appState.setDashboardDataForTesting(
        createDashboardData(
          sysInfo: {
            'uptime': 45120,
            'memory': {'total': 100000000, 'free': 42000000, 'buffered': 0},
            'load': [0.29, 0.20, 0.15],
            'cpu': {'usage': 15.0},
          },
          temperature: mockTemp,
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      // System Vitals values
      expect(find.text('15%'), findsOneWidget);
      expect(find.text('58%'), findsOneWidget);
      expect(find.text('0.29'), findsOneWidget);
      expect(find.text('12h 32m'), findsOneWidget);

      // Temperature field dynamically added
      expect(find.text('Temperature'), findsOneWidget);
      expect(
        find.text(mockTemp.formattedTemperatureForUnit('celsius')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'DashboardScreen dynamically displays client counts once clients are loaded',
    (WidgetTester tester) async {
      appState.setDashboardPreferencesForTesting(
        DashboardPreferences(dismissTemperaturePrompt: false),
      );
      appState.setDashboardDataForTesting(createDashboardData());

      // Set mock clients via AppState setter
      appState.clients = [
        Client(
          ipAddress: '192.168.1.101',
          macAddress: '00:11:22:33:44:01',
          hostname: 'PC-Wired',
          connectionType: ConnectionType.wired,
          isConnected: true,
        ),
        Client(
          ipAddress: '192.168.1.102',
          macAddress: '00:11:22:33:44:02',
          hostname: 'Phone-Wireless1',
          connectionType: ConnectionType.wireless,
          isConnected: true,
        ),
        Client(
          ipAddress: '192.168.1.103',
          macAddress: '00:11:22:33:44:03',
          hostname: 'Phone-Wireless2',
          connectionType: ConnectionType.wireless,
          isConnected: true,
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DashboardScreen())),
      );
      await tester.pumpAndSettle();

      // 1 Wired Client, 2 Wireless Clients
      expect(find.text('1 Connected'), findsOneWidget);
      expect(find.text('2 Connected'), findsOneWidget);
    },
  );
}
