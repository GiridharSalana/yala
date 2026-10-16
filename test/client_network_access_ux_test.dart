// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/models/client.dart';
import 'package:yala/models/network_access_policy.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/services/client_policy_schedule_service.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/utils/client_naming_helper.dart';
import 'package:yala/utils/self_device_guard.dart';
import 'package:yala/widgets/device_network_access_card.dart';

Widget _wrapWidget({
  required Widget child,
  required AppState appState,
}) {
  return ProviderScope(
    overrides: [
      appStateProvider.overrideWith((ref) => appState),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

Client _createTestClient({
  String mac = 'AA:BB:CC:DD:EE:01',
  String ip = '192.168.1.150',
  String name = 'Test Phone',
}) {
  return Client(
    macAddress: mac,
    ipAddress: ip,
    hostname: name,
    connectionType: ConnectionType.wireless,
    isConnected: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (MethodCall methodCall) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          if (methodCall.method == 'write') {
            return null;
          }
          return null;
        });
  });

  late AppState appState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ClientPolicyScheduleService.instance.init();
    MockApiService.resetMockState();
    SelfDeviceGuard.setMockLocalAddresses({});

    appState = AppState.instance;
    await appState.setReviewerMode(true);
    appState.setApiServiceForTesting(MockApiService());
    appState.setCapabilitiesForTesting(RouterCapabilities.mock());
    appState.setDashboardDataForTesting({});
  });

  group('Milestone 4 — DeviceNetworkAccessCard UX Tests', () {
    testWidgets('1. Displays Network Access section with master and protocol switches in ALLOWED state', (
      tester,
    ) async {
      final client = _createTestClient();

      await tester.pumpWidget(
        _wrapWidget(
          appState: appState,
          child: DeviceNetworkAccessCard(client: client),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Network Access'), findsOneWidget);
      expect(find.text('Internet Access'), findsOneWidget);
      expect(find.text('IPv4 Internet'), findsOneWidget);
      expect(find.text('IPv6 Internet'), findsOneWidget);
      expect(find.text('ALLOWED'), findsOneWidget);

      // Verify all 3 switches are on
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(3));
      for (final s in tester.widgetList<Switch>(switches)) {
        expect(s.value, isTrue);
      }
    });

    testWidgets('2. Master block overrides and disables IPv4 and IPv6 toggles with truthful notice', (
      tester,
    ) async {
      final client = _createTestClient(mac: '11:22:33:44:55:66');

      // Set initial state to blocked
      await tester.runAsync(() async {
        await appState.setDeviceNetworkAccessPolicy(
          policy: NetworkAccessPolicy.blocked(client.macAddress),
        );
      });

      await tester.pumpWidget(
        _wrapWidget(
          appState: appState,
          child: DeviceNetworkAccessCard(client: client),
        ),
      );
      await tester.pumpAndSettle();

      // Status pill should say BLOCKED
      expect(find.text('BLOCKED'), findsOneWidget);

      // Master switch should be off
      final switchWidgets = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switchWidgets.first.value, isFalse);

      // Sub switches (IPv4 & IPv6) should be disabled when master is blocked
      expect(switchWidgets[1].onChanged, isNull);
      expect(switchWidgets[2].onChanged, isNull);

      // Explanatory global block notice should be visible
      expect(
        find.text(
          'Global internet access is blocked. IPv4 and IPv6 traffic are both blocked.',
        ),
        findsOneWidget,
      );

      // Schedule options should be visible when blocked
      expect(find.text('Access Duration'), findsOneWidget);
      expect(find.text('Always'), findsNWidgets(2));
      expect(find.text('+1h'), findsOneWidget);
    });

    testWidgets('3. Selective protocol blocking (IPv4 allowed, IPv6 blocked) shows [IPv6 BLOCKED] and truthful banner', (
      tester,
    ) async {
      final client = _createTestClient(mac: '22:33:44:55:66:77');

      // Policy: IPv4 allowed, IPv6 blocked
      await tester.runAsync(() async {
        await appState.setDeviceNetworkAccessPolicy(
          policy: NetworkAccessPolicy(
            targetMac: client.macAddress,
            internetAccess: true,
            ipv4Access: true,
            ipv6Access: false,
          ),
        );
      });

      await tester.pumpWidget(
        _wrapWidget(
          appState: appState,
          child: DeviceNetworkAccessCard(client: client),
        ),
      );
      await tester.pumpAndSettle();

      // Status pill is IPv6 BLOCKED
      expect(find.text('IPv6 BLOCKED'), findsOneWidget);

      // Master is allowed
      final switchWidgets = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switchWidgets[0].value, isTrue);
      // IPv4 is allowed
      expect(switchWidgets[1].value, isTrue);
      // IPv6 is blocked
      expect(switchWidgets[2].value, isFalse);

      // Truthful notice that local communication remains active
      expect(
        find.text(
          'Blocking IPv6 Internet stops public IPv6 web access. Local communication on your home network remains active.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('4. Capability gating: IPv6 toggle disabled with notice when supportsIpv6InternetFirewall is false', (
      tester,
    ) async {
      final client = _createTestClient(mac: '33:44:55:66:77:88');

      // Configure router capabilities without IPv6 internet support
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          appState: appState,
          child: DeviceNetworkAccessCard(client: client),
        ),
      );
      await tester.pumpAndSettle();

      // Notice should be visible
      expect(
        find.text('IPv6 Internet is not configured on this router.'),
        findsOneWidget,
      );

      // IPv6 switch must be disabled
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches[2].onChanged, isNull);
    });

    testWidgets('5. SelfDeviceGuard intercepts attempt to block managing device MAC', (
      tester,
    ) async {
      const managingMac = 'EE:FF:11:22:33:44';
      final client = _createTestClient(mac: managingMac);

      // Mock this device as managing device
      SelfDeviceGuard.setMockLocalAddresses({
        ClientNamingHelper.normalizeMac(managingMac),
      });

      await tester.pumpWidget(
        _wrapWidget(
          appState: appState,
          child: DeviceNetworkAccessCard(client: client),
        ),
      );
      await tester.pumpAndSettle();

      // Try toggling master switch to blocked
      final masterSwitch = find.byType(Switch).first;
      await tester.tap(masterSwitch);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Guardrail warning dialog should appear
      expect(find.text('Managing Device Warning'), findsOneWidget);
      expect(find.text('Cancel (Recommended)'), findsOneWidget);

      // Cancel the action
      await tester.tap(find.text('Cancel (Recommended)'));
      await tester.pumpAndSettle();

      // Policy should NOT be blocked
      final currentPolicy = appState.getDeviceNetworkAccessPolicy(managingMac);
      expect(currentPolicy.isEffectivelyBlocked, isFalse);
    });

    testWidgets('6. Non-destructive legacy rule recognition reflects blocked state in card', (
      tester,
    ) async {
      const targetMac = 'AA:BB:CC:99:88:77';
      final client = _createTestClient(mac: targetMac);

      // Simulate live dashboard data containing legacy nointernet_wireless_clients rule
      appState.setDashboardDataForTesting({
        'uciFirewallConfig': {
          'values': {
            'defaults': {
              '.type': 'defaults',
              'input': 'ACCEPT',
              'output': 'ACCEPT',
              'forward': 'REJECT',
            },
            'lan': {
              '.type': 'zone',
              'name': 'lan',
              'input': 'ACCEPT',
              'output': 'ACCEPT',
              'forward': 'ACCEPT',
              'network': ['lan'],
            },
            'legacy_rule': {
              '.type': 'rule',
              '.name': 'nointernet_wireless_clients',
              'name': 'nointernet_wireless_clients',
              'src': 'lan',
              'dest': 'wan',
              'src_mac': [targetMac],
              'target': 'REJECT',
              'enabled': '1',
            },
          },
        },
      });

      // AppState policy inspection detects legacy rule
      final policy = appState.getDeviceNetworkAccessPolicy(targetMac);
      expect(policy.isEffectivelyBlocked, isTrue);

      await tester.pumpWidget(
        _wrapWidget(
          appState: appState,
          child: DeviceNetworkAccessCard(client: client),
        ),
      );
      await tester.pumpAndSettle();

      // Card immediately displays BLOCKED without mutating or deleting the legacy rule
      expect(find.text('BLOCKED'), findsOneWidget);
      final switchWidgets = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switchWidgets.first.value, isFalse);
    });

    testWidgets('7. Schedule persistence, expiry evaluation, and stale record protection', (
      tester,
    ) async {
      const mac = '44:55:66:77:88:99';
      final futureExpiry = DateTime.now().add(const Duration(hours: 2));

      // Save schedule
      final scheduledPolicy = NetworkAccessPolicy.blocked(
        mac,
        scheduleExpiry: futureExpiry,
      );
      await tester.runAsync(() async {
        await appState.setDeviceNetworkAccessPolicy(policy: scheduledPolicy);
      });

      // Verify persistent storage
      expect(ClientPolicyScheduleService.instance.getExpiry(mac), isNotNull);
      final stored = ClientPolicyScheduleService.instance.getSchedule(mac);
      expect(stored?.targetMac, equals(ClientNamingHelper.normalizeMac(mac)));
      expect(stored?.isExpired, isFalse);

      // Simulate expired schedule in storage
      final pastExpiry = DateTime.now().subtract(const Duration(minutes: 5));
      await tester.runAsync(() async {
        await ClientPolicyScheduleService.instance.saveSchedule(
          policy: scheduledPolicy.copyWith(scheduleExpiry: pastExpiry),
        );
      });

      final expiredStored = ClientPolicyScheduleService.instance.getSchedule(mac);
      expect(expiredStored?.isExpired, isTrue);

      // Call checkExpiredDevicePolicies()
      await tester.runAsync(() async {
        await appState.checkExpiredDevicePolicies();
      });

      // Should automatically unblock the device
      final policyAfterExpiry = appState.getDeviceNetworkAccessPolicy(mac);
      expect(policyAfterExpiry.isEffectivelyBlocked, isFalse);
    });

    testWidgets('8. Synchronization between quick Pause/Resume and NetworkAccessPolicy', (
      tester,
    ) async {
      const mac = '55:66:77:88:99:AA';

      // 1. Pause via pauseClientInternet
      await tester.runAsync(() async {
        final pauseSuccess = await appState.pauseClientInternet(
          mac,
          pause: true,
        );
        expect(pauseSuccess, isTrue);
      });

      // AppState.isInternetPaused should be true
      expect(appState.isInternetPaused(mac), isTrue);

      // getDeviceNetworkAccessPolicy should be effectively blocked
      expect(
        appState.getDeviceNetworkAccessPolicy(mac).isEffectivelyBlocked,
        isTrue,
      );

      // 2. Resume via setDeviceNetworkAccessPolicy
      await tester.runAsync(() async {
        final unblockSuccess = await appState.setDeviceNetworkAccessPolicy(
          policy: NetworkAccessPolicy.unrestricted(mac),
        );
        expect(unblockSuccess, isTrue);
      });

      // AppState.isInternetPaused should be false
      expect(appState.isInternetPaused(mac), isFalse);
      expect(
        appState.getDeviceNetworkAccessPolicy(mac).isEffectivelyBlocked,
        isFalse,
      );
    });

    testWidgets('9. showAsBottomSheet renders popup with IPv4, IPv6, and full internet switches', (
      tester,
    ) async {
      final client = _createTestClient(mac: '55:66:77:88:99:AA');

      await tester.pumpWidget(
        _wrapWidget(
          appState: appState,
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => DeviceNetworkAccessCard.showAsBottomSheet(
                  context,
                  client: client,
                ),
                child: const Text('Open Access Sheet'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the button to open bottom sheet
      await tester.tap(find.text('Open Access Sheet'));
      await tester.pumpAndSettle();

      // Verify bottom sheet contents
      expect(find.text('Network Access'), findsOneWidget);
      expect(find.text('Internet Access'), findsOneWidget);
      expect(find.text('IPv4 Internet'), findsOneWidget);
      expect(find.text('IPv6 Internet'), findsOneWidget);
      expect(find.text('ALLOWED'), findsOneWidget);

      // Verify quick action button at the bottom of sheet
      expect(find.text('Pause Access'), findsOneWidget);

      // Verify close button
      final closeBtn = find.byIcon(Icons.close_rounded);
      expect(closeBtn, findsOneWidget);

      // Tap close button to dismiss sheet
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // Sheet should be dismissed
      expect(find.text('Network Access'), findsNothing);
    });
  });
}
