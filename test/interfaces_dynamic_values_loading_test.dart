// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/screens/interfaces_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_states.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState appState;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});

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

  Map<String, dynamic> createInterfacesDashboardData({
    bool includeWireless = true,
    bool includeIpv6 = false,
  }) {
    return {
      'interfaceDump': {
        'interface': [
          {
            'interface': 'lan',
            'up': true,
            'device': 'br-lan',
            'proto': 'static',
            'uptime': 7200,
            'ipv4-address': [
              {'address': '192.168.1.1', 'mask': 24},
            ],
            if (includeIpv6)
              'ipv6-address': [
                {'address': 'fd00::1', 'mask': 64},
              ],
            'stats': {
              'rx_bytes': 1048576,
              'tx_bytes': 2097152,
            },
          },
          {
            'interface': 'wan',
            'up': true,
            'device': 'eth1',
            'proto': 'dhcp',
            'uptime': 3600,
            'ipv4-address': [
              {'address': '10.0.0.15', 'mask': 24},
            ],
            'route': [
              {'target': '0.0.0.0', 'mask': 0, 'nexthop': '10.0.0.1'},
            ],
            'dns-server': ['10.0.0.1', '1.1.1.1'],
            'stats': {
              'rx_bytes': 5242880,
              'tx_bytes': 10485760,
            },
          },
        ],
      },
      'networkDevices': {
        'br-lan': {
          'stats': {'rx_bytes': 1048576, 'tx_bytes': 2097152},
        },
        'eth1': {
          'stats': {'rx_bytes': 5242880, 'tx_bytes': 10485760},
        },
      },
      'wireless': includeWireless
          ? {
              'radio0': {
                'interfaces': [
                  {
                    'section': 'wifinet0',
                    'name': 'wlan0',
                    'config': {
                      'device': 'radio0',
                      'mode': 'ap',
                      'ssid': 'Home_Wi-Fi_5G',
                      'channel': '36',
                    },
                    'iwinfo': {
                      'ssid': 'Home_Wi-Fi_5G',
                      'channel': 36,
                      'mode': 'Master',
                      'signal': -55,
                    },
                  },
                ],
              },
            }
          : <String, dynamic>{},
    };
  }

  testWidgets(
    'InterfacesScreen renders structured sections and interface cards with LuciSkeleton dynamic values while loading',
    (WidgetTester tester) async {
      appState.setDashboardDataForTesting(null);
      appState.setIsDashboardLoadingForTesting(true);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InterfacesScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Section headers should be rendered immediately
      expect(find.text('Wired'), findsOneWidget);
      expect(find.text('Switch Topology & VLANs'), findsWidgets);
      expect(find.text('Wireless'), findsWidgets);

      // Core interface card titles should be rendered
      expect(find.text('LAN'), findsOneWidget);
      expect(find.text('WAN'), findsOneWidget);
      expect(find.text('Wireless'), findsWidgets);

      // Subtitles and dynamic values should show LuciSkeleton shimmer
      expect(find.byType(LuciSkeleton), findsWidgets);

      // Expand LAN card to check details
      await tester.tap(find.text('LAN'));
      await tester.pumpAndSettle();

      // Detail labels are rendered
      expect(find.text('Device'), findsWidgets);
      expect(find.text('Uptime'), findsWidgets);
      expect(find.text('IP Address'), findsWidgets);
      expect(find.text('Gateway'), findsWidgets);
      expect(find.text('DNS'), findsWidgets);
      expect(find.text('Received'), findsWidgets);
      expect(find.text('Transmitted'), findsWidgets);

      appState.setIsDashboardLoadingForTesting(false);
    },
  );

  testWidgets(
    'InterfacesScreen dynamically renders values and adds IPv6 field when loaded',
    (WidgetTester tester) async {
      final loadedData = createInterfacesDashboardData(
        includeWireless: true,
        includeIpv6: true,
      );

      appState.setDashboardDataForTesting(loadedData);
      appState.setIsDashboardLoadingForTesting(false);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InterfacesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Interface names rendered
      expect(find.text('LAN'), findsOneWidget);
      expect(find.text('WAN'), findsOneWidget);
      expect(find.text('Home_Wi-Fi_5G'), findsOneWidget);

      // Expand LAN card
      await tester.tap(find.text('LAN'));
      await tester.pumpAndSettle();

      // Check dynamically populated IP and IPv6
      expect(find.text('192.168.1.1'), findsOneWidget);
      expect(find.text('IPv6 Address'), findsOneWidget);
      expect(find.text('fd00::1'), findsOneWidget);
    },
  );

  testWidgets(
    'InterfacesScreen handles wired-only router edge case after data loads',
    (WidgetTester tester) async {
      final loadedData = createInterfacesDashboardData(
        includeWireless: false,
        includeIpv6: false,
      );

      appState.setDashboardDataForTesting(loadedData);
      appState.setIsDashboardLoadingForTesting(false);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: InterfacesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Wired cards are rendered
      expect(find.text('LAN'), findsOneWidget);
      expect(find.text('WAN'), findsOneWidget);

      // Wireless indicates unavailable for wired-only router
      expect(find.text('Wireless Interfaces Unavailable'), findsOneWidget);
    },
  );
}
