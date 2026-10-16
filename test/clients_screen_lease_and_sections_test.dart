import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/client.dart';
import 'package:yala/screens/clients_screen.dart';
import 'package:yala/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppState.instance.clients = [];
    AppState.instance.bannedWirelessMacs.clear();
    AppState.instance.pausedInternetMacs.clear();
  });

  group('ClientsScreen Sections and Filters', () {
    final clientsList = [
      Client(
        ipAddress: '192.168.1.100',
        macAddress: '11:22:33:44:55:66',
        hostname: 'Router-Wired-Client',
        isConnected: true,
        connectionType: ConnectionType.wired,
        isDumbApClient: false,
      ),
      Client(
        ipAddress: '192.168.1.101',
        macAddress: '22:33:44:55:66:77',
        hostname: 'Router-Wireless-Client',
        isConnected: true,
        connectionType: ConnectionType.wireless,
        isDumbApClient: false,
      ),
      Client(
        ipAddress: '192.168.1.102',
        macAddress: '33:44:55:66:77:88',
        hostname: 'DumbAp-Wireless-Client',
        isConnected: true,
        connectionType: ConnectionType.wireless,
        isDumbApClient: true,
        apName: 'Secondary-AP',
      ),
      Client(
        ipAddress: '192.168.1.103',
        macAddress: '44:55:66:77:88:99',
        hostname: 'Offline-Router-Client',
        isConnected: false,
        connectionType: ConnectionType.wireless,
        isDumbApClient: false,
      ),
      Client(
        ipAddress: '192.168.1.104',
        macAddress: '55:66:77:88:99:AA',
        hostname: 'Banned-Client',
        isConnected: true,
        connectionType: ConnectionType.wireless,
        isDumbApClient: false,
      ),
    ];

    testWidgets(
      'renders Total, Wired, Wireless, Banned summary sections and omits Dumb AP section',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.clients = clientsList;
        appState.bannedWirelessMacs.add('55:66:77:88:99:AA');

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // 4 summary categories must be present
        expect(find.text('Total: '), findsOneWidget);
        expect(find.text('Wired: '), findsOneWidget);
        expect(find.text('Wireless: '), findsOneWidget);
        expect(find.text('Banned: '), findsOneWidget);

        // Dumb AP section must NOT exist in the summary bar
        expect(find.text('Dumb AP: '), findsNothing);

        // Verification of counts:
        // Total (excluding banned): Router-Wired + Router-Wireless + DumbAp-Wireless + Offline-Router = 4
        expect(find.text('4'), findsWidgets);
        // Wired: Router-Wired = 1
        expect(find.text('1'), findsWidgets);
        // Wireless: Router-Wireless + DumbAp-Wireless = 2
        expect(find.text('3'), findsWidgets);
      },
    );

    testWidgets(
      'toggling Active Connected Only applies filter without changing section',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.clients = clientsList;

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // Initially Offline-Router-Client is visible in Total
        expect(find.text('Offline-Router-Client'), findsOneWidget);

        // Tap "Active Connected Only" filter chip
        await tester.tap(find.text('Active Connected Only'));
        await tester.pumpAndSettle();

        // Offline client is now hidden
        expect(find.text('Offline-Router-Client'), findsNothing);
        // Connected clients remain visible
        expect(find.text('Router-Wired-Client'), findsOneWidget);
        expect(find.text('Router-Wireless-Client'), findsOneWidget);
        expect(find.text('DumbAp-Wireless-Client'), findsOneWidget);

        // Switch to Wired section
        await tester.tap(find.text('Wired: '));
        await tester.pumpAndSettle();

        expect(find.text('Router-Wired-Client'), findsOneWidget);
        expect(find.text('Router-Wireless-Client'), findsNothing);
      },
    );

    testWidgets(
      'toggling Show Dumb AP Clients applies filter across Wired and Wireless without changing section',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.clients = clientsList;

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // Switch to Wireless section
        await tester.tap(find.text('Wireless: '));
        await tester.pumpAndSettle();

        // Initially both Router-Wireless and DumbAp-Wireless are visible (as _showDumbApClients is true by default)
        expect(find.text('Router-Wireless-Client'), findsOneWidget);
        expect(find.text('DumbAp-Wireless-Client'), findsOneWidget);

        // Tap "Show Dumb AP Clients" filter chip to toggle off
        await tester.tap(find.text('Show Dumb AP Clients'));
        await tester.pumpAndSettle();

        // Dumb AP client is filtered out; still on Wireless section
        expect(find.text('Router-Wireless-Client'), findsOneWidget);
        expect(find.text('DumbAp-Wireless-Client'), findsNothing);
      },
    );

    testWidgets(
      'card renders Static badge and Remove Lease button for static clients',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        final staticClient = Client(
          ipAddress: '192.168.1.50',
          macAddress: 'AA:BB:CC:DD:EE:FF',
          hostname: 'Server-Box',
          isConnected: true,
          connectionType: ConnectionType.wired,
          isStaticLease: true,
          staticLeaseName: 'Server-Box',
        );

        appState.clients = [staticClient];

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // "Static" badge should be visible
        expect(find.text('STATIC'), findsOneWidget);

        // Tap to expand card
        await tester.tap(find.text('Server-Box'));
        await tester.pumpAndSettle();

        // "Remove Lease" button should be visible
        expect(find.text('Remove Lease'), findsOneWidget);

        // Tap "Remove Lease" button to open confirmation dialog
        await tester.tap(find.text('Remove Lease'));
        await tester.pumpAndSettle();

        expect(find.text('Remove Static Lease'), findsOneWidget);
      },
    );

    test('clientHasActiveWiredBadge correctly evaluates wired badge logic', () {
      final staleDumbAp = Client(
        ipAddress: '192.168.1.132',
        macAddress: 'AA:11:11:11:11:11',
        hostname: 'stale-ap-client',
        isConnected: true,
        connectionType: ConnectionType.wired,
        neighState: NeighborReachability.stale,
        isDumbApClient: true,
      );
      final failedDumbAp = Client(
        ipAddress: '192.168.1.133',
        macAddress: 'AA:22:22:22:22:22',
        hostname: 'failed-ap-client',
        isConnected: true,
        connectionType: ConnectionType.wired,
        neighState: NeighborReachability.failed,
        isDumbApClient: true,
      );
      final reachableDumbAp = Client(
        ipAddress: '192.168.1.134',
        macAddress: 'AA:33:33:33:33:33',
        hostname: 'reachable-ap-client',
        isConnected: true,
        connectionType: ConnectionType.wired,
        neighState: NeighborReachability.reachable,
        isDumbApClient: true,
      );
      final wirelessDumbAp = Client(
        ipAddress: '192.168.1.135',
        macAddress: 'AA:44:44:44:44:44',
        hostname: 'wireless-ap-client',
        isConnected: true,
        connectionType: ConnectionType.wireless,
        neighState: NeighborReachability.reachable,
        isDumbApClient: true,
      );
      final regularRouterWired = Client(
        ipAddress: '192.168.1.136',
        macAddress: 'AA:55:55:55:55:55',
        hostname: 'router-wired-client',
        isConnected: true,
        connectionType: ConnectionType.wired,
      );
      final regularRouterDisconnected = Client(
        ipAddress: '192.168.1.137',
        macAddress: 'AA:66:66:66:66:66',
        hostname: 'router-disconnected-client',
        isConnected: false,
        connectionType: ConnectionType.wired,
      );

      expect(clientHasActiveWiredBadge(staleDumbAp), isFalse);
      expect(clientHasActiveWiredBadge(failedDumbAp), isFalse);
      expect(clientHasActiveWiredBadge(reachableDumbAp), isTrue);
      expect(clientHasActiveWiredBadge(wirelessDumbAp), isFalse);
      expect(clientHasActiveWiredBadge(regularRouterWired), isTrue);
      expect(clientHasActiveWiredBadge(regularRouterDisconnected), isFalse);
    });

    testWidgets(
      'stale Dumb AP wired client is excluded from Wired section and wiredCount even when Active Connected filter is off',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        final regularWired = Client(
          ipAddress: '192.168.1.10',
          macAddress: '11:11:11:11:11:11',
          hostname: 'Main-PC',
          isConnected: true,
          connectionType: ConnectionType.wired,
          isDumbApClient: false,
        );
        final staleDumbApWired = Client(
          ipAddress: '192.168.1.20',
          macAddress: '22:22:22:22:22:22',
          hostname: 'Stale-DumbAP-Client',
          isConnected: true,
          connectionType: ConnectionType.wired,
          neighState: NeighborReachability.stale,
          isDumbApClient: true,
          apName: 'LivingRoom-AP',
        );
        final reachableDumbApWired = Client(
          ipAddress: '192.168.1.30',
          macAddress: '33:33:33:33:33:33',
          hostname: 'Reachable-DumbAP-Client',
          isConnected: true,
          connectionType: ConnectionType.wired,
          neighState: NeighborReachability.reachable,
          isDumbApClient: true,
          apName: 'LivingRoom-AP',
        );

        appState.clients = [
          regularWired,
          staleDumbApWired,
          reachableDumbApWired,
        ];

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // Total count = 3 (all three are active)
        // Wired count = 2 (Main-PC + Reachable-DumbAP-Client; Stale-DumbAP-Client is excluded because no wired badge)
        expect(find.text('Total: '), findsOneWidget);
        expect(find.text('Wired: '), findsOneWidget);

        // Tap Wired section
        await tester.tap(find.text('Wired: '));
        await tester.pumpAndSettle();

        // Main-PC and Reachable-DumbAP-Client should be visible in Wired
        expect(find.text('Main-PC'), findsOneWidget);
        expect(find.text('Reachable-DumbAP-Client'), findsOneWidget);
        // Stale-DumbAP-Client must NOT be in Wired section
        expect(find.text('Stale-DumbAP-Client'), findsNothing);

        // Toggle OFF "Active Connected Only" filter
        await tester.tap(find.text('Active Connected Only'));
        await tester.pumpAndSettle();

        // Even with Active Connected Only off, Stale-DumbAP-Client must NOT show in Wired section!
        expect(find.text('Main-PC'), findsOneWidget);
        expect(find.text('Reachable-DumbAP-Client'), findsOneWidget);
        expect(find.text('Stale-DumbAP-Client'), findsNothing);

        // Switch to Total section: all 3 should be visible
        await tester.tap(find.text('Total: '));
        await tester.pumpAndSettle();

        expect(find.text('Main-PC'), findsOneWidget);
        expect(find.text('Reachable-DumbAP-Client'), findsOneWidget);
        expect(find.text('Stale-DumbAP-Client'), findsOneWidget);
      },
    );

    testWidgets(
      'non-active wired client is excluded from Wired section and wiredCount even when Active Connected filter is off',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        final activeWired = Client(
          ipAddress: '192.168.1.10',
          macAddress: '11:11:11:11:11:11',
          hostname: 'Active-Wired-PC',
          isConnected: true,
          connectionType: ConnectionType.wired,
          isDumbApClient: false,
        );
        final offlineWired = Client(
          ipAddress: '192.168.1.20',
          macAddress: '22:22:22:22:22:22',
          hostname: 'Offline-Wired-PC',
          isConnected: false,
          connectionType: ConnectionType.wired,
          isDumbApClient: false,
        );
        final wifiClient = Client(
          ipAddress: '192.168.1.30',
          macAddress: '33:33:33:33:33:33',
          hostname: 'WiFi-Phone',
          isConnected: true,
          connectionType: ConnectionType.wireless,
          isDumbApClient: false,
        );

        appState.clients = [
          activeWired,
          offlineWired,
          wifiClient,
        ];

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // By default, _showOnlyActiveConnected is false.
        // Total = 3 (activeWired + offlineWired + wifiClient), Wired = 1 (activeWired only!)
        expect(find.text('Total: '), findsOneWidget);
        expect(find.text('Wired: '), findsOneWidget);

        // Tap Wired section while _showOnlyActiveConnected is FALSE
        await tester.tap(find.text('Wired: '));
        await tester.pumpAndSettle();

        // Even though _showOnlyActiveConnected is false, non-active wired clients
        // must NOT be included in the Wired section!
        expect(find.text('Active-Wired-PC'), findsOneWidget);
        expect(find.text('Offline-Wired-PC'), findsNothing);
        expect(find.text('WiFi-Phone'), findsNothing);

        // Toggle ON "Active Connected Only" filter
        await tester.tap(find.text('Active Connected Only'));
        await tester.pumpAndSettle();

        // With Active Connected Only ON, Wired section still shows activeWired only
        expect(find.text('Active-Wired-PC'), findsOneWidget);
        expect(find.text('Offline-Wired-PC'), findsNothing);
        expect(find.text('WiFi-Phone'), findsNothing);

        // Toggle OFF "Active Connected Only" filter (back to false)
        await tester.tap(find.text('Active Connected Only'));
        await tester.pumpAndSettle();

        // Wired section still excludes Offline-Wired-PC
        expect(find.text('Active-Wired-PC'), findsOneWidget);
        expect(find.text('Offline-Wired-PC'), findsNothing);

        // Switch to Total section: all 3 should be visible
        await tester.tap(find.text('Total: '));
        await tester.pumpAndSettle();

        expect(find.text('Active-Wired-PC'), findsOneWidget);
        expect(find.text('Offline-Wired-PC'), findsOneWidget);
        expect(find.text('WiFi-Phone'), findsOneWidget);
      },
    );
  });
}
