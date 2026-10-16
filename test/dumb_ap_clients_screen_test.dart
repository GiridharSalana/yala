// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yala/models/client.dart';
import 'package:yala/screens/clients_screen.dart';
import 'package:yala/widgets/luci_app_bar.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets(
    'ClientsScreen preserves Show Dumb AP Clients option permanently',
    (WidgetTester tester) async {
      final appState = AppState.instance;
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

      // "Show Dumb AP Clients" is always visible so it never disappears on any device
      expect(find.text('Show Dumb AP Clients'), findsOneWidget);
      // "Dumb AP" summary item should NOT be present
      expect(find.text('Dumb AP: '), findsNothing);
      // AppBar antenna icon should NOT be present
      expect(
        find.descendant(
          of: find.byType(LuciAppBar),
          matching: find.byIcon(Icons.settings_input_antenna_outlined),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LuciAppBar),
          matching: find.byIcon(Icons.settings_input_antenna_rounded),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'ClientsScreen displays Dumb AP options when a Dumb AP client is present',
    (WidgetTester tester) async {
      final appState = AppState.instance;
      appState.clients = [
        Client(
          ipAddress: '10.0.0.10',
          macAddress: 'AA:11:11:11:11:11',
          hostname: 'Main-Desktop',
          isConnected: true,
          connectionType: ConnectionType.wired,
        ),
        Client(
          ipAddress: '10.0.0.20',
          macAddress: 'AA:22:22:22:22:22',
          hostname: 'AP-Phone',
          isConnected: true,
          connectionType: ConnectionType.wireless,
          isDumbApClient: true,
          apName: 'Archer C60',
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ClientsScreen())),
      );

      await tester.pumpAndSettle();

      // "Show Dumb AP Clients" should be visible
      expect(find.text('Show Dumb AP Clients'), findsOneWidget);
      // "Dumb AP" summary item should NOT be visible (separate section removed)
      expect(find.text('Dumb AP: '), findsNothing);
      // Both Main-Desktop and AP-Phone are visible in Total (since _showDumbApClients defaults to true)
      expect(find.text('Main-Desktop'), findsOneWidget);
      expect(find.text('AP-Phone'), findsOneWidget);
      // Badge pill should be displayed
      expect(find.text('Dumb AP • Archer C60'), findsOneWidget);

      // Verify AppBar does NOT have the antenna icon
      expect(
        find.descendant(
          of: find.byType(LuciAppBar),
          matching: find.byIcon(Icons.settings_input_antenna_outlined),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LuciAppBar),
          matching: find.byIcon(Icons.settings_input_antenna_rounded),
        ),
        findsNothing,
      );

      // Tap "Show Dumb AP Clients" chip to hide Dumb AP clients
      await tester.tap(find.text('Show Dumb AP Clients'));
      await tester.pumpAndSettle();

      // Main-Desktop should remain visible
      expect(find.text('Main-Desktop'), findsOneWidget);
      // AP-Phone should be filtered out
      expect(find.text('AP-Phone'), findsNothing);

      // Tap "Show Dumb AP Clients" chip again to re-enable Dumb AP clients
      await tester.tap(find.text('Show Dumb AP Clients'));
      await tester.pumpAndSettle();

      // Both should be visible again
      expect(find.text('Main-Desktop'), findsOneWidget);
      expect(find.text('AP-Phone'), findsOneWidget);
    },
  );

  testWidgets(
    'ClientsScreen displays empty state when Dumb AP clients are hidden and no router clients exist',
    (WidgetTester tester) async {
      final appState = AppState.instance;
      appState.requestedClientCategoryFilter = ClientCategoryFilter.all;
      appState.clients = [
        Client(
          ipAddress: '10.0.0.20',
          macAddress: 'AA:22:22:22:22:22',
          hostname: 'AP-Phone',
          isConnected: true,
          connectionType: ConnectionType.wireless,
          isDumbApClient: true,
          apName: 'Archer C60',
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ClientsScreen())),
      );

      await tester.pumpAndSettle();

      // Initially AP-Phone is visible
      expect(find.text('AP-Phone'), findsOneWidget);

      // Toggle off Show Dumb AP Clients
      await tester.tap(find.text('Show Dumb AP Clients'));
      await tester.pumpAndSettle();

      // AP-Phone is hidden and empty state is shown
      expect(find.text('AP-Phone'), findsNothing);
      expect(find.text('No Active Clients Found'), findsOneWidget);
    },
  );

  testWidgets(
    'stale Dumb AP wired client does not display Wired pill, but displays Dumb AP pill',
    (WidgetTester tester) async {
      final appState = AppState.instance;
      appState.requestedClientCategoryFilter = ClientCategoryFilter.all;
      appState.clients = [
        Client(
          ipAddress: '192.168.1.132',
          macAddress: '92:61:E9:EC:B2:50',
          hostname: 'ncxNP2',
          isConnected: true,
          connectionType: ConnectionType.wired,
          neighState: NeighborReachability.stale,
          isDumbApClient: true,
          apName: 'ncxTest-192',
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ClientsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "Dumb AP • ncxTest-192" pill should be present
      expect(find.text('Dumb AP • ncxTest-192'), findsOneWidget);
      // "Wired (LAN Port)" pill must NOT be displayed for stale Dumb AP client
      expect(find.text('Wired (LAN Port)'), findsNothing);
      expect(find.text('Wired'), findsNothing);

      // Verify Wired section count is 0 and tapping Wired hides stale client
      expect(find.text('Wired: '), findsOneWidget);
      await tester.tap(find.text('Wired: '));
      await tester.pumpAndSettle();
      expect(find.text('ncxNP2'), findsNothing);
    },
  );

  testWidgets(
    'reachable Dumb AP wired client displays both Wired pill and Dumb AP pill',
    (WidgetTester tester) async {
      final appState = AppState.instance;
      appState.requestedClientCategoryFilter = ClientCategoryFilter.all;
      appState.clients = [
        Client(
          ipAddress: '10.0.0.5',
          macAddress: '2C:BE:EB:62:28:DC',
          hostname: 'ncxLinux',
          isConnected: true,
          connectionType: ConnectionType.wired,
          neighState: NeighborReachability.reachable,
          isDumbApClient: true,
          apName: 'ncxRouter',
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ClientsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both pills must be present for active/reachable wired Dumb AP client
      expect(find.text('Dumb AP • ncxRouter'), findsOneWidget);
      expect(find.text('Wired (LAN Port)'), findsOneWidget);

      // Verify Wired section includes the reachable Dumb AP client
      await tester.tap(find.text('Wired: '));
      await tester.pumpAndSettle();
      expect(find.text('ncxLinux'), findsOneWidget);
    },
  );

  testWidgets(
    'Dumb AP client card hides Ban Client and Static Lease buttons while showing Pause Access',
    (WidgetTester tester) async {
      final appState = AppState.instance;
      appState.requestedClientCategoryFilter = ClientCategoryFilter.all;
      appState.clients = [
        Client(
          ipAddress: '192.168.1.132',
          macAddress: '92:61:E9:EC:B2:50',
          hostname: 'ncxNP2',
          isConnected: true,
          connectionType: ConnectionType.wired,
          neighState: NeighborReachability.stale,
          isDumbApClient: true,
          apName: 'ncxTest-192',
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ClientsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap card to expand client details and action buttons
      await tester.tap(find.text('ncxNP2'));
      await tester.pumpAndSettle();

      // Action buttons verification:
      // Ban Client and Static Lease must NOT be shown for Dumb AP client
      expect(find.text('Ban Client'), findsNothing);
      expect(find.text('Static Lease'), findsNothing);
      expect(find.text('Edit Static Lease'), findsNothing);
      expect(find.text('Remove Lease'), findsNothing);

      // Pause Access MUST be shown
      expect(find.text('Pause Access'), findsOneWidget);
    },
  );

  testWidgets(
    'Show Dumb AP Clients chip displays count badge context-aware of Active Connected Only',
    (WidgetTester tester) async {
      final appState = AppState.instance;
      appState.requestedClientCategoryFilter = ClientCategoryFilter.all;
      appState.clients = [
        Client(
          ipAddress: '10.0.0.10',
          macAddress: 'AA:11:11:11:11:11',
          hostname: 'Main-Desktop',
          isConnected: true,
          connectionType: ConnectionType.wired,
        ),
        Client(
          ipAddress: '10.0.0.20',
          macAddress: 'AA:22:22:22:22:22',
          hostname: 'AP-Phone-Active',
          isConnected: true,
          connectionType: ConnectionType.wireless,
          isDumbApClient: true,
          apName: 'Archer C60',
        ),
        Client(
          ipAddress: '10.0.0.30',
          macAddress: 'AA:33:33:33:33:33',
          hostname: 'AP-Laptop-Inactive',
          isConnected: false,
          connectionType: ConnectionType.wireless,
          isDumbApClient: true,
          apName: 'Archer C60',
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ClientsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chipFinder = find.widgetWithText(InkWell, 'Show Dumb AP Clients');

      // Initially, "Active Connected Only" is false:
      // Total Dumb AP clients is 2 (AP-Phone-Active + AP-Laptop-Inactive)
      expect(find.text('Show Dumb AP Clients'), findsOneWidget);
      expect(
        find.descendant(of: chipFinder, matching: find.text('2')),
        findsOneWidget,
      );

      // Tap "Active Connected Only" chip to enable it
      await tester.tap(find.text('Active Connected Only'));
      await tester.pumpAndSettle();

      // Now "Active Connected Only" is true:
      // Badge count must dynamically update to 1 (only AP-Phone-Active is connected)
      expect(
        find.descendant(of: chipFinder, matching: find.text('1')),
        findsOneWidget,
      );

      // Tap "Show Dumb AP Clients" chip to toggle off while active connected is on
      await tester.tap(find.text('Show Dumb AP Clients'));
      await tester.pumpAndSettle();

      // Badge still shows 1 (informing user that 1 dumb AP client is hidden)
      expect(
        find.descendant(of: chipFinder, matching: find.text('1')),
        findsOneWidget,
      );

      // Tap "Active Connected Only" chip to toggle it back off
      await tester.tap(find.text('Active Connected Only'));
      await tester.pumpAndSettle();

      // Badge dynamically updates back to 2
      expect(
        find.descendant(of: chipFinder, matching: find.text('2')),
        findsOneWidget,
      );
    },
  );
}
