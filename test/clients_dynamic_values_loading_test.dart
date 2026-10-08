// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/models/client.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/screens/clients_screen.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/services/mock_auth_service.dart';
import 'package:yala/services/router_service.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/state/controllers/client_controller.dart';
import 'package:yala/widgets/luci_loading_states.dart';

class MockLoadingClientController extends ClientController {
  final Completer<List<Client>> completer;

  MockLoadingClientController(this.completer)
      : super(
          apiServiceRef: () => MockApiService(),
          authServiceRef: () => MockAuthService(),
          routerServiceRef: () => RouterService(isReviewerMode: false),
          reviewerModeRef: () => false,
          executeRouterCommandOutput: (cmd, args) async => null,
          processDhcpLeases: (raw) => raw,
        );

  @override
  Future<List<Client>> fetchClientsForSelectedRouter() => completer.future;

  @override
  Future<List<Client>> fetchAggregatedClients({
    void Function(List<Client>)? onIncrementalUpdate,
  }) => completer.future;
}

class MockClientControllerWithFixedClients extends ClientController {
  final List<Client> fixedClients;

  MockClientControllerWithFixedClients(this.fixedClients)
      : super(
          apiServiceRef: () => MockApiService(),
          authServiceRef: () => MockAuthService(),
          routerServiceRef: () => RouterService(isReviewerMode: false),
          reviewerModeRef: () => false,
          executeRouterCommandOutput: (cmd, args) async => null,
          processDhcpLeases: (raw) => raw,
        );

  @override
  Future<List<Client>> fetchClientsForSelectedRouter() async => fixedClients;

  @override
  Future<List<Client>> fetchAggregatedClients({
    void Function(List<Client>)? onIncrementalUpdate,
  }) async => fixedClients;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState appState;
  late RouterService routerService;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'has_seen_restricted_clients_tooltip': true,
    });

    appState = AppState.instance;
    routerService = RouterService(isReviewerMode: true);

    final r1 = model.Router(
      id: 'dynamic_clients_router_1',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: 'password',
      useHttps: false,
      name: 'Router 1',
    );
    await routerService.clearAllRouters();
    await routerService.addRouter(r1);
    await routerService.selectRouter(r1.id);
  });

  testWidgets(
    'ClientsScreen renders Search Bar, Filter Chips, Summary Row with LuciSkeleton counts during loading',
    (tester) async {
      final completer = Completer<List<Client>>();
      final controller = MockLoadingClientController(completer);

      final prevController = appState.clientControllerForTesting;
      appState.clientControllerForTesting = controller;
      appState.clients = [];

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('en')],
            home: ClientsScreen(isTabActive: false),
          ),
        ),
      );

      // First frame: Clients are still loading
      await tester.pump();

      // 1. Verify real Search Bar shell is present
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);

      // 2. Verify real Filter Chips are present
      expect(find.text('Active Connected Only'), findsOneWidget);
      expect(find.text('Show Dumb AP Clients'), findsOneWidget);

      // 3. Verify category summary items are present with labels
      expect(find.text('Total: '), findsOneWidget);
      expect(find.text('Wired: '), findsOneWidget);
      expect(find.text('Wireless: '), findsOneWidget);
      expect(find.text('Banned: '), findsOneWidget);

      // 4. Verify LuciSkeleton is used for counts and card skeletons
      expect(find.byType(LuciSkeleton), findsWidgets);
      expect(find.byType(LuciListItemSkeleton), findsWidgets);

      // Teardown
      await tester.pumpWidget(const SizedBox());
      completer.complete([]);
      appState.clientControllerForTesting = prevController;
    },
  );

  testWidgets(
    'ClientsScreen dynamically populates counts and does NOT show Current Speed on client cards',
    (tester) async {
      final client = Client(
        ipAddress: '192.168.1.55',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Pixel-9-Pro',
        isConnected: true,
        connectionType: ConnectionType.wireless,
        signalDbm: -55,
        noiseDbm: -95,
        rxBytes: 1048576,
        txBytes: 2097152,
        rxSpeed: 500000,
        txSpeed: 250000,
      );

      final controller = MockClientControllerWithFixedClients([client]);

      final prevController = appState.clientControllerForTesting;
      appState.clientControllerForTesting = controller;
      appState.clients = [client];

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('en')],
            home: ClientsScreen(isTabActive: true),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify client is rendered
      expect(find.text('Pixel-9-Pro'), findsOneWidget);

      // Verify summary counts are populated dynamically
      expect(find.text('1'), findsWidgets); // Total: 1, Wireless: 1

      // Expand card
      await tester.tap(find.text('Pixel-9-Pro'));
      await tester.pumpAndSettle();

      // Verify "Current Speed" is strictly REMOVED
      expect(find.text('Current Speed'), findsNothing);
      expect(find.textContaining('↓ 500'), findsNothing);
      expect(find.textContaining('↑ 250'), findsNothing);

      // Verify other legitimate rows are present
      expect(find.text('Signal'), findsOneWidget);
      expect(find.text('Session Transfer'), findsOneWidget);

      // Teardown
      await tester.pumpWidget(const SizedBox());
      appState.clientControllerForTesting = prevController;
    },
  );
}
