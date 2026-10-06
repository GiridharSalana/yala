// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/models/router_temperature.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/screens/dashboard_screen.dart';
import 'package:yet_another_luci_app/screens/more_screen.dart';
import 'package:yet_another_luci_app/screens/clients_screen.dart';
import 'package:yet_another_luci_app/modules/package_manager/screens/package_manager_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/rpc_permissions_dialog.dart';
import 'package:yet_another_luci_app/modules/sqm/widgets/sqm_install_card.dart';
import 'package:yet_another_luci_app/modules/sqm/widgets/sqm_install_dialog.dart';

RouterCapabilities createCompleteCaps() {
  return RouterCapabilities(
    routerId: 'test-router',
    ubusObjects: const {'uci', 'system', 'luci-rpc', 'file', 'iwinfo'},
    ubusMethods: const {
      'uci': ['get', 'set', 'commit'],
      'system': ['info', 'reboot'],
      'luci-rpc': ['getWirelessDevices'],
      'file': ['read', 'stat', 'exec'],
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

  group('RouterCapabilities RPC Check Logic', () {
    test('Correctly identifies missing RPC modules and permissions', () {
      final incompleteCaps = RouterCapabilities(
        routerId: 'test-router',
        ubusObjects: const {'uci', 'system'},
        ubusMethods: const {
          'uci': ['get', 'set'],
          'system': ['info'],
          'file': ['read'], // missing 'exec'
        },
        packageEngine: PackageManagerEngine.opkg,
        firewallBackend: FirewallBackend.fw4,
        networkModel: NetworkModel.dsa,
        releaseVersion: 'OpenWrt 23.05.3',
        boardName: 'test-board',
        probedAt: DateTime.now(),
      );

      expect(incompleteCaps.hasFileExec, isFalse);
      expect(incompleteCaps.hasLuciRpc, isFalse);
      expect(incompleteCaps.isRpcComplete, isFalse);
    });

    test('Correctly identifies complete RPC capability', () {
      final completeCaps = createCompleteCaps();

      expect(completeCaps.hasFileExec, isTrue);
      expect(completeCaps.hasLuciRpc, isTrue);
      expect(completeCaps.isRpcComplete, isTrue);
    });

    test('Correctly handles wildcard * in ubusObjects and ubusMethods', () {
      final wildcardCaps = RouterCapabilities(
        routerId: 'wildcard-router',
        ubusObjects: const {'*'},
        ubusMethods: const {
          '*': ['*'],
        },
        uciPermissions: const {
          '*': ['*'],
        },
        packageEngine: PackageManagerEngine.apk,
        firewallBackend: FirewallBackend.fw4,
        networkModel: NetworkModel.dsa,
        releaseVersion: 'OpenWrt SNAPSHOT',
        boardName: 'test-board',
        probedAt: DateTime.now(),
      );

      expect(wildcardCaps.hasObject('file'), isTrue);
      expect(wildcardCaps.hasObject('luci-rpc'), isTrue);
      expect(wildcardCaps.hasObject('iwinfo'), isTrue);
      expect(wildcardCaps.hasFileExec, isTrue);
      expect(wildcardCaps.hasLuciRpc, isTrue);
      expect(wildcardCaps.hasUciWriteAccess, isTrue);
      expect(wildcardCaps.isRpcComplete, isTrue);
    });

    test(
      'Correctly identifies stock OpenWrt standard LuCI ACL permissions (from session.access)',
      () {
        final stockLuciCaps = RouterCapabilities(
          routerId: 'stock-openwrt',
          ubusObjects: const {
            'dsl',
            'file',
            'fingerprint',
            'hostapd.*',
            'iwinfo',
            'log',
            'luci',
            'luci-rpc',
            'network',
            'network.device',
            'network.interface',
            'rc',
            'service',
            'session',
            'system',
            'uci',
          },
          ubusMethods: const {
            'file': ['read', 'write', 'list', 'remove', 'exec', 'stat'],
            'iwinfo': [
              'assoclist',
              'countrylist',
              'freqlist',
              'txpowerlist',
              'scan',
              'info',
            ],
            'luci-rpc': [
              'getBoardJSON',
              'getHostHints',
              'getNetworkDevices',
              'getWirelessDevices',
              'getDHCPLeases',
              'getDUIDHints',
            ],
            'system': ['board', 'info', 'validate_firmware_image', 'reboot'],
            'uci': [
              'get',
              'set',
              'commit',
              'changes',
              'add',
              'apply',
              'confirm',
              'delete',
              'order',
              'rename',
            ],
          },
          uciPermissions: const {
            'attendedsysupgrade': ['read', 'write'],
            'dhcp': ['read', 'write'],
            'dropbear': ['read', 'write'],
            'firewall': ['read', 'write'],
            'fstab': ['read', 'write'],
            'luci': ['read', 'write'],
            'network': ['read', 'write'],
            'system': ['read', 'write'],
            'uhttpd': ['read', 'write'],
            'wireless': ['read', 'write'],
          },
          packageEngine: PackageManagerEngine.apk,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.dsa,
          releaseVersion: 'OpenWrt 24.10.0',
          boardName: 'stock-board',
          probedAt: DateTime.now(),
        );

        expect(stockLuciCaps.hasFileExec, isTrue);
        expect(stockLuciCaps.hasLuciRpc, isTrue);
        expect(stockLuciCaps.hasUciWriteAccess, isTrue);
        expect(stockLuciCaps.isRpcComplete, isTrue);
      },
    );

    test('Serializes and deserializes uciPermissions correctly', () {
      final original = RouterCapabilities(
        routerId: 'test-serial',
        ubusObjects: const {'file', 'uci'},
        ubusMethods: const {
          'file': ['exec'],
        },
        uciPermissions: const {
          'network': ['read', 'write'],
          'wireless': ['read'],
        },
        packageEngine: PackageManagerEngine.opkg,
        firewallBackend: FirewallBackend.fw4,
        networkModel: NetworkModel.dsa,
        releaseVersion: 'OpenWrt 23.05.3',
        boardName: 'test-board',
        probedAt: DateTime.now(),
      );

      final json = original.toJson();
      final recovered = RouterCapabilities.fromJson(json);

      expect(recovered.uciPermissions.containsKey('network'), isTrue);
      expect(recovered.uciPermissions['network'], contains('write'));
      expect(recovered.uciPermissions['wireless'], contains('read'));
      expect(recovered.hasUciWriteAccess, isTrue);
    });
  });

  group('RpcPermissionsDialog Widget Tests', () {
    testWidgets('Renders all security restriction details and action buttons', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => RpcPermissionsDialog.show(
                  context,
                  actionName: 'Reboot Router',
                ),
                child: const Text('Trigger Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open the dialog
      await tester.tap(find.text('Trigger Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog presence and lock icon
      expect(find.byType(RpcPermissionsDialog), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

      // Verify manual SSH command section
      expect(find.text('Manual SSH Command'), findsOneWidget);
      expect(find.text('Copy Command'), findsOneWidget);

      // Verify action buttons
      expect(find.text('Fix Automatically'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Renders custom message when provided', (tester) async {
      const customMsg = 'Custom restriction notice for testing purposes.';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => RpcPermissionsDialog.show(
                  context,
                  actionName: 'Special Action',
                  customMessage: customMsg,
                ),
                child: const Text('Trigger Custom Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Custom Dialog'));
      await tester.pumpAndSettle();

      expect(find.text(customMsg), findsOneWidget);
    });
  });

  group('SQM Widget Permission Restriction Visuals', () {
    testWidgets(
      'SqmInstallCard renders Fix Permissions button when RPC is missing',
      (tester) async {
        final incompleteCaps = RouterCapabilities(
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
        AppState.instance.setCapabilitiesForTesting(incompleteCaps);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SqmInstallCard(isInstalling: false, onInstallTap: () {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify permission banner text and lock icon
        expect(find.text('Fix Permissions to Install'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
      },
    );

    testWidgets(
      'SqmInstallCard renders zero permission cues when RPC permissions are complete',
      (tester) async {
        final completeCaps = createCompleteCaps();
        AppState.instance.setCapabilitiesForTesting(completeCaps);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SqmInstallCard(isInstalling: false, onInstallTap: () {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify NO permission banner and NO lock icons
        expect(find.text('Fix Permissions to Install'), findsNothing);
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

        // Verify standard install button
        expect(find.text('Install SQM'), findsOneWidget);
        expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'SqmInstallDialog renders top banner and disabled choices when RPC is missing',
      (tester) async {
        final incompleteCaps = RouterCapabilities(
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
        AppState.instance.setCapabilitiesForTesting(incompleteCaps);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (ctx) => const SqmInstallDialog(),
                    ),
                    child: const Text('Open SQM Dialog'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open SQM Dialog'));
        await tester.pumpAndSettle();

        // Verify the banner warns about required permissions
        expect(find.text('Fix Permissions'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
      },
    );

    testWidgets(
      'SqmInstallDialog renders zero permission cues when RPC permissions are complete',
      (tester) async {
        final completeCaps = createCompleteCaps();
        AppState.instance.setCapabilitiesForTesting(completeCaps);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (ctx) => const SqmInstallDialog(),
                    ),
                    child: const Text('Open SQM Dialog'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open SQM Dialog'));
        await tester.pumpAndSettle();

        // Verify NO permission banner and NO lock icons
        expect(find.text('Fix Permissions'), findsNothing);
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

        // Verify standard install button
        expect(find.text('Install Now'), findsOneWidget);
      },
    );
  });

  group('DashboardScreen & MoreScreen Zero Visual Cues Audit', () {
    testWidgets(
      'DashboardScreen renders zero permission restriction cues when RPC permissions are complete',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router',
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
        appState.setCapabilitiesForTesting(createCompleteCaps());
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

        // Verify NO permission warning cards or notices
        expect(find.text('Missing RPC Packages'), findsNothing);
        expect(find.text('RPC Permissions Required'), findsNothing);
        expect(find.text('Permissions Required'), findsNothing);
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

        // Verify normal quick action icons are rendered in full
        expect(find.byIcon(Icons.restart_alt), findsOneWidget);
        expect(find.byIcon(Icons.cleaning_services), findsOneWidget);
      },
    );

    testWidgets(
      'MoreScreen renders zero permission restriction cues when RPC permissions are complete',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(createCompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: MoreScreen())),
        );
        await tester.pumpAndSettle();

        // Verify zero lock icons and zero restriction badges
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
        expect(find.text('Permissions Required'), findsNothing);
        expect(find.textContaining('RPC permissions required'), findsNothing);
      },
    );
  });

  group('ClientsScreen & PackageManagerScreen Visual Cues Audit', () {
    testWidgets(
      'ClientsScreen client action buttons show RPC tooltip when RPC is missing',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final appState = AppState.instance;
        await appState.routerService?.clearAllRouters();

        final incompleteCaps = RouterCapabilities(
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
        appState.setCapabilitiesForTesting(incompleteCaps);
        appState.clients = [
          Client(
            ipAddress: '10.0.0.10',
            macAddress: 'AA:11:11:11:11:11',
            hostname: 'Main-Desktop',
            isConnected: true,
            connectionType: ConnectionType.wired,
          ),
        ];

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // Tap client to expand
        await tester.tap(find.text('Main-Desktop'));
        await tester.pumpAndSettle();

        // Verify restricted tooltip is present
        expect(find.byTooltip('Requires router RPC permissions'), findsWidgets);
      },
    );

    testWidgets(
      'ClientsScreen client action buttons render zero restriction cues when RPC permissions are complete',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final appState = AppState.instance;
        await appState.routerService?.clearAllRouters();
        appState.setCapabilitiesForTesting(createCompleteCaps());
        appState.clients = [
          Client(
            ipAddress: '10.0.0.10',
            macAddress: 'AA:11:11:11:11:11',
            hostname: 'Main-Desktop',
            isConnected: true,
            connectionType: ConnectionType.wired,
          ),
        ];

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // Tap client to expand
        await tester.tap(find.text('Main-Desktop'));
        await tester.pumpAndSettle();

        // Verify NO restricted tooltip is present
        expect(find.byTooltip('Requires router RPC permissions'), findsNothing);
      },
    );

    testWidgets(
      'PackageManagerScreen toolbar shows lock icon and warning banner when RPC is missing',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final appState = AppState.instance;

        final incompleteCaps = RouterCapabilities(
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
        appState.setCapabilitiesForTesting(incompleteCaps);

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: PackageManagerScreen())),
        );
        await tester.pumpAndSettle();

        // Verify top warning banner is present
        expect(find.text('Permissions Required'), findsOneWidget);
        // Verify toolbar buttons have lock icons
        expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
      },
    );

    testWidgets(
      'PackageManagerScreen renders zero permission restriction cues when RPC permissions are complete',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(createCompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: PackageManagerScreen())),
        );
        await tester.pumpAndSettle();

        // Verify top warning banner is NOT present
        expect(find.text('Permissions Required'), findsNothing);
        // Verify toolbar buttons do NOT have lock icons
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
        // Verify standard toolbar icons
        expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
        expect(find.byIcon(Icons.add_box_outlined), findsOneWidget);
      },
    );
  });

  group('Router Capabilities & Edge Cases Audit', () {
    test(
      'Router with iwinfo (alternative RPC provider) + file.exec is considered RPC complete',
      () {
        final iwinfoCaps = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: const {'uci', 'system', 'iwinfo', 'file'},
          ubusMethods: const {
            'uci': ['get', 'set'],
            'system': ['info'],
            'iwinfo': ['info', 'scan'],
            'file': ['exec', 'read'],
          },
          packageEngine: PackageManagerEngine.opkg,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.dsa,
          releaseVersion: 'OpenWrt 23.05.3',
          boardName: 'test-board',
          probedAt: DateTime.now(),
        );

        expect(iwinfoCaps.hasLuciRpc, isTrue);
        expect(iwinfoCaps.hasFileExec, isTrue);
        expect(iwinfoCaps.isRpcComplete, isTrue);

        AppState.instance.setCapabilitiesForTesting(iwinfoCaps);
        expect(AppState.instance.isMissingRpcPackages, isFalse);
      },
    );

    test(
      'Network failure during capability probe (probeFailed=true) does NOT trigger false visual cues',
      () {
        final failedProbeCaps = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: const {},
          ubusMethods: const {},
          packageEngine: PackageManagerEngine.none,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.dsa,
          releaseVersion: 'OpenWrt',
          boardName: 'unknown',
          probedAt: DateTime.now(),
          probeFailed: true,
          lastProbeError: 'Connection refused',
        );

        AppState.instance.setCapabilitiesForTesting(failedProbeCaps);
        expect(AppState.instance.isMissingRpcPackages, isFalse);
      },
    );

    test(
      'Empty ubusObjects (fresh load / connecting) does NOT trigger false visual cues',
      () {
        final freshCaps = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: const {},
          ubusMethods: const {},
          packageEngine: PackageManagerEngine.none,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.dsa,
          releaseVersion: 'OpenWrt',
          boardName: 'unknown',
          probedAt: DateTime.now(),
        );

        AppState.instance.setCapabilitiesForTesting(freshCaps);
        expect(AppState.instance.isMissingRpcPackages, isFalse);
      },
    );

    test('Null capabilities does NOT trigger false visual cues', () {
      AppState.instance.setCapabilitiesForTesting(null);
      expect(AppState.instance.isMissingRpcPackages, isFalse);
    });
  });
}
