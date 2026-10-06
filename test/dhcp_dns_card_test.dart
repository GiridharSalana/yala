// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/dhcp_dns/widgets/dhcp_dns_card.dart';
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
      id: 'test_router_dhcp_dns',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: 'password',
      useHttps: false,
    );
    await appState.routerService?.addRouter(testRouter);
    await appState.routerService?.selectRouter(testRouter.id);
  });

  Widget buildTestWidget({
    Size size = const Size(360, 640),
    double textScale = 1.0,
  }) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: const Center(
              child: SizedBox(
                width: 360,
                child: DhcpDnsCard(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'DhcpDnsCard renders single-line header, domain badge, and 4 metrics cleanly in standard viewport',
    (WidgetTester tester) async {
      appState.setDashboardPreferencesForTesting(DashboardPreferences());
      appState.setDashboardDataForTesting({
        'dhcp': {
          'values': {
            'cfg01': {
              '.type': 'dnsmasq',
              'domain': 'lan',
              'rebind_protection': '1',
              'server': ['ISP Default (Dynamic DNS)'],
            },
          },
        },
        'dhcpLeases': [
          {
            'hostname': 'Phone',
            'ipaddr': '192.168.1.100',
            'macaddr': 'AA:BB:CC:DD:EE:01',
            'expires': 3600,
          },
          {
            'hostname': 'Laptop',
            'ipaddr': '192.168.1.101',
            'macaddr': 'AA:BB:CC:DD:EE:02',
            'expires': 3600,
          },
        ],
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Verify title and domain badge
      expect(find.text('DHCP & DNS Management'), findsOneWidget);
      expect(find.text('.lan'), findsOneWidget);

      // Verify metrics
      expect(find.text('Active Leases'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      expect(find.text('Static Mappings'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      expect(find.text('DNS Forwarders'), findsOneWidget);
      expect(find.text('ISP Default'), findsOneWidget);
      expect(find.textContaining('(Dynamic DNS)'), findsNothing);

      expect(find.text('DNS Rebind'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'DhcpDnsCard formats custom single and multiple DNS forwarders accurately',
    (WidgetTester tester) async {
      // Test single custom DNS IP
      appState.setDashboardPreferencesForTesting(DashboardPreferences());
      appState.setDashboardDataForTesting({
        'dhcp': {
          'values': {
            'cfg01': {
              '.type': 'dnsmasq',
              'domain': 'lan',
              'rebind_protection': '0',
              'server': ['1.1.1.1'],
            },
          },
        },
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('1.1.1.1'), findsOneWidget);
      expect(find.text('DISABLED'), findsOneWidget);

      // Test multiple DNS servers
      appState.setDashboardDataForTesting({
        'dhcp': {
          'values': {
            'cfg01': {
              '.type': 'dnsmasq',
              'domain': 'home.arpa',
              'rebind_protection': '1',
              'server': ['1.1.1.1', '8.8.8.8', '9.9.9.9'],
            },
          },
        },
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('.home.arpa'), findsOneWidget);
      expect(find.text('1.1.1.1 (+2)'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'DhcpDnsCard adapts to 2x2 grid when font scaling is enlarged or screen width is narrow',
    (WidgetTester tester) async {
      appState.setDashboardPreferencesForTesting(DashboardPreferences());
      appState.setDashboardDataForTesting({
        'dhcp': {
          'values': {
            'cfg01': {
              '.type': 'dnsmasq',
              'domain': 'lan',
              'rebind_protection': '1',
            },
          },
        },
        'dhcpLeases': [],
      });

      // Large accessibility font scale (1.5x)
      await tester.pumpWidget(
        buildTestWidget(
          size: const Size(360, 640),
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DHCP & DNS Management'), findsOneWidget);
      expect(find.text('.lan'), findsOneWidget);
      expect(find.text('Active Leases'), findsOneWidget);
      expect(find.text('Static Mappings'), findsOneWidget);
      expect(find.text('DNS Forwarders'), findsOneWidget);
      expect(find.text('DNS Rebind'), findsOneWidget);

      // In 2x2 grid, active leases and DNS forwarders should be vertically stacked (leases higher on Y axis)
      final leasesPos = tester.getCenter(find.text('Active Leases'));
      final forwarderPos = tester.getCenter(find.text('DNS Forwarders'));
      expect(
        leasesPos.dy < forwarderPos.dy,
        isTrue,
        reason: 'Active Leases should be in top row and DNS Forwarders in bottom row in 2x2 grid',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'DhcpDnsCard displays skeleton placeholders cleanly while loading without data',
    (WidgetTester tester) async {
      appState.setDashboardDataForTesting(null);
      appState.setIsDashboardLoadingForTesting(true);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(LuciSkeleton), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
