// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/models/client.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/modules/wireless_management/screens/wifi_access_control_screen.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/utils/self_device_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    SelfDeviceGuard.setMockLocalAddresses({'192.168.1.50', '00:11:22:33:44:55'});
    await AppState.instance.initializationFuture;
  });

  tearDown(() {
    SelfDeviceGuard.setMockLocalAddresses(null);
  });

  group('WifiAccessControlScreen Dropdown Loading Performance Tests', () {
    testWidgets(
      'Instantly renders connected client dropdown from cached state without blocking with a spinner',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test-router-1',
          name: 'Primary Router',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'secret',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);

        // Seed cached clients into AppState
        final testClient1 = Client(
          ipAddress: '192.168.1.101',
          macAddress: 'AA:BB:CC:11:22:33',
          hostname: 'Pixel-8-Pro',
          connectionType: ConnectionType.wireless,
          isConnected: true,
        );
        final testClient2 = Client(
          ipAddress: '192.168.1.102',
          macAddress: 'DD:EE:FF:44:55:66',
          hostname: 'Living-Room-TV',
          connectionType: ConnectionType.wired,
          isConnected: true,
        );

        appState.clients = [testClient1, testClient2];

        // Pump the screen into the widget tree
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: WifiAccessControlScreen(),
            ),
          ),
        );

        // Frame 0 verify: the dropdown MUST be rendered immediately from cached state,
        // without showing a blocking CircularProgressIndicator.
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason:
              'Dropdown should NOT be blocked by CircularProgressIndicator when cached clients exist',
        );

        // Verify DropdownButtonFormField is present immediately
        expect(
          find.byType(DropdownButtonFormField<Client>),
          findsOneWidget,
        );

        // Let async background refresh settle
        await tester.pumpAndSettle();

        // Verify dropdown is still present
        expect(
          find.byType(DropdownButtonFormField<Client>),
          findsOneWidget,
        );

        // Tap dropdown to open it
        await tester.tap(find.byType(DropdownButtonFormField<Client>));
        await tester.pumpAndSettle();

        // Verify items appear in menu
        expect(find.text('Pixel-8-Pro (AA:BB:CC:11:22:33)'), findsWidgets);
        expect(find.text('Living-Room-TV (DD:EE:FF:44:55:66)'), findsWidgets);

        // Select an item from the dropdown
        await tester.tap(find.text('Pixel-8-Pro (AA:BB:CC:11:22:33)').last);
        await tester.pumpAndSettle();

        // Verify text field was populated with selected MAC
        expect(find.text('AA:BB:CC:11:22:33'), findsWidgets);
      },
    );

    testWidgets(
      'Aggregated clients including Dumb AP clients are preserved in the selector',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test-router-main',
          name: 'Main Router',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'secret',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);

        // Include a client connected to a secondary Dumb AP
        final dumbApClient = Client(
          ipAddress: '192.168.1.205',
          macAddress: 'EE:EE:EE:55:55:55',
          hostname: 'Bedroom-Smart-Speaker',
          connectionType: ConnectionType.wireless,
          isConnected: true,
          isDumbApClient: true,
          apName: 'Bedroom-AP',
        );

        appState.clients = [dumbApClient];

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: WifiAccessControlScreen(),
            ),
          ),
        );

        // Verify immediately renders without blocking
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(DropdownButtonFormField<Client>), findsOneWidget);

        await tester.pumpAndSettle();

        // Open dropdown and ensure Dumb AP client is present
        await tester.tap(find.byType(DropdownButtonFormField<Client>));
        await tester.pumpAndSettle();

        expect(
          find.text('Bedroom-Smart-Speaker (EE:EE:EE:55:55:55)'),
          findsWidgets,
        );
      },
    );
  });
}
