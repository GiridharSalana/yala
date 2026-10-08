// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/models/dashboard_preferences.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/modules/system_monitoring/models/router_temperature.dart';
import 'package:yala/screens/dashboard_screen.dart';
import 'package:yala/screens/more_screen.dart';
import 'package:yala/screens/settings_screen.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/widgets/luci_toast.dart';
import 'package:yala/widgets/rpc_permissions_dialog.dart';

RouterCapabilities _createIncompleteCaps() {
  return RouterCapabilities(
    routerId: 'test-router',
    ubusObjects: const {'uci'},
    ubusMethods: const {
      'file': ['read'],
    },
    packageEngine: PackageManagerEngine.opkg,
    firewallBackend: FirewallBackend.fw4,
    networkModel: NetworkModel.dsa,
    releaseVersion: 'OpenWrt 23.05.3',
    boardName: 'test-board',
    probedAt: DateTime.now(),
  );
}

RouterCapabilities _createCompleteCaps() {
  return RouterCapabilities(
    routerId: 'test-router',
    ubusObjects: const {
      'system',
      'luci-rpc',
      'network.interface',
      'iwinfo',
      'file',
      'service',
      'rc',
      'uci',
      'opkg',
      'fw4',
    },
    ubusMethods: const {
      'system': ['info', 'board', 'reboot'],
      'luci-rpc': ['getInitList', 'getWirelessDevices'],
      'file': ['read', 'stat', 'exec'],
    },
    uciPermissions: const {
      '*': ['read', 'write'],
    },
    packageEngine: PackageManagerEngine.opkg,
    firewallBackend: FirewallBackend.fw4,
    networkModel: NetworkModel.dsa,
    releaseVersion: 'OpenWrt 23.05.3',
    boardName: 'test-board',
    probedAt: DateTime.now(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('Permanent RPC Management in MoreScreen', () {
    testWidgets(
      'MoreScreen displays RPC & Permissions tile with Setup badge when RPC is missing',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createIncompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: MoreScreen())),
        );
        await tester.pumpAndSettle();

        // RPC & Permissions tile should be visible permanently under Device Management
        expect(find.text('RPC & Permissions'), findsOneWidget);
        expect(find.text('Setup or repair router RPC access'), findsOneWidget);
        expect(find.text('Setup'), findsOneWidget);

        // Tap the tile to verify it opens RpcPermissionsDialog
        await tester.tap(find.text('RPC & Permissions'));
        await tester.pumpAndSettle();

        expect(find.byType(RpcPermissionsDialog), findsOneWidget);
        expect(find.text('Permission Required'), findsOneWidget);
        expect(find.text('Fix Automatically'), findsOneWidget);
        expect(find.text('Manual SSH Command'), findsOneWidget);
      },
    );

    testWidgets(
      'MoreScreen displays RPC & Permissions tile with Ready badge when RPC is complete',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createCompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: MoreScreen())),
        );
        await tester.pumpAndSettle();

        expect(find.text('RPC & Permissions'), findsOneWidget);
        expect(
          find.text('Manage router RPC permissions and modules'),
          findsOneWidget,
        );
        expect(find.text('Ready'), findsOneWidget);

        // Tap the tile to verify it opens verified state in RpcPermissionsDialog
        await tester.tap(find.text('RPC & Permissions'));
        await tester.pumpAndSettle();

        expect(find.byType(RpcPermissionsDialog), findsOneWidget);
        expect(
          find.text(
            'Router RPC modules and backend execution permissions are verified and functioning properly.',
          ),
          findsOneWidget,
        );
        expect(find.text('Re-verify / Repair'), findsOneWidget);
        expect(find.text('Manual Setup / Verification Script'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Re-verify / Repair pops dialog and shows Permissions Verified toast without timing out',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createCompleteCaps());

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: LuciToastManager.navigatorKey,
            home: const ProviderScope(child: MoreScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('RPC & Permissions'));
        await tester.pumpAndSettle();

        expect(find.byType(RpcPermissionsDialog), findsOneWidget);

        // Tap Re-verify / Repair
        await tester.tap(find.text('Re-verify / Repair'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Dialog should be popped
        expect(find.byType(RpcPermissionsDialog), findsNothing);

        // Success toast should be displayed
        expect(find.text('Permissions Verified'), findsOneWidget);
        expect(
          find.text('RPC modules and permissions are active.'),
          findsOneWidget,
        );

        // Fast forward past the toast display duration (e.g. 5s)
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // Verify that "Operation Timed Out" was NEVER shown
        expect(find.text('Operation Timed Out'), findsNothing);
      },
    );
  });

  group('Permanent RPC Status in SettingsScreen', () {
    testWidgets(
      'SettingsScreen capabilities tile shows RPC Status and manage button',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createCompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SettingsScreen())),
        );
        await tester.pumpAndSettle();

        // Capabilities tile should show RPC Status: READY
        expect(find.text('RPC Status: '), findsOneWidget);
        expect(find.text('READY'), findsOneWidget);
        expect(find.text('Manage'), findsOneWidget);
        expect(
          find.text('RPC permissions & execution modules verified'),
          findsOneWidget,
        );

        // Tap Manage button opens dialog
        await tester.tap(find.text('Manage'));
        await tester.pumpAndSettle();

        expect(find.byType(RpcPermissionsDialog), findsOneWidget);
      },
    );

    testWidgets(
      'SettingsScreen capabilities tile shows SETUP REQUIRED and Auto-Fix when missing',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createIncompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SettingsScreen())),
        );
        await tester.pumpAndSettle();

        expect(find.text('RPC Status: '), findsOneWidget);
        expect(find.text('SETUP REQUIRED'), findsOneWidget);
        expect(find.text('Auto-Fix'), findsOneWidget);
        expect(
          find.text(
            'Missing RPC permissions may restrict advanced router management features',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('DashboardScreen Banner Dismissal without Lingering Chips', () {
    testWidgets(
      'Dismissing RPC warning removes banner completely from Dashboard',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_incomplete',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);

        appState.setDashboardPreferencesForTesting(
          DashboardPreferences(showQuickActions: true),
        );
        appState.setCapabilitiesForTesting(_createIncompleteCaps());
        appState.setDashboardDataForTesting({
          'sysInfo': {
            'uptime': 3600,
            'memory': {
              'total': 256000000,
              'free': 128000000,
              'buffered': 10000000,
            },
            'load': [0.15, 0.20, 0.25],
          },
          'boardInfo': {
            'hostname': 'OpenWrt-Router',
            'model': 'Test Hardware',
            'release': {'version': '23.05.2'},
          },
          'temperature': RouterTemperature.unavailable(
            hasPhysicalSensors: false,
            isHandlerInstalled: false,
            reason:
                'Thermal sensors are not supported on this router hardware.',
          ),
          'wireless': <String, dynamic>{},
          'clients': <Map<String, dynamic>>[],
        });

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: DashboardScreen())),
        );
        await tester.pumpAndSettle();

        // Banner should initially be visible
        expect(find.text('LuCI RPC Package Required'), findsOneWidget);
        expect(find.byTooltip('Dismiss'), findsOneWidget);

        // Dismiss the banner
        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pumpAndSettle();

        // Ensure banner is gone AND no compact notice chip remains in Dashboard
        expect(find.text('LuCI RPC Package Required'), findsNothing);
        expect(find.text('Missing RPC Packages'), findsNothing);
        expect(find.text('RPC Permissions Required'), findsNothing);
        expect(find.text('Fix Permissions'), findsNothing);
      },
    );
  });
}
