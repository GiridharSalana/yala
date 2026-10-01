// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/screens/dashboard_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

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
      id: 'test_router_device_info',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: 'password',
      useHttps: false,
    );
    await appState.routerService?.addRouter(testRouter);
    await appState.routerService?.selectRouter(testRouter.id);
  });

  testWidgets(
    'DashboardScreen Device Info Card maintains side-by-side full-width layout across normal and large font scales',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appState.setDashboardPreferencesForTesting(DashboardPreferences());
      appState.setDashboardDataForTesting({
        'boardInfo': {
          'model': 'Linksys EA8300 (Dallas)',
          'release': {'distribution': 'OpenWrt', 'version': '25.12.5'},
        },
        'sysInfo': {
          'load': [0.1, 0.1, 0.1],
          'memory': {'total': 1000, 'free': 500, 'buffered': 100},
          'uptime': 3600,
        },
        'wireless': <String, dynamic>{},
        'clients': <Map<String, dynamic>>[],
      });

      for (final scale in [1.0, 1.35, 1.6, 2.0]) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 640),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const DashboardScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Model'), findsOneWidget);
        expect(find.text('Linksys EA8300 (Dallas)'), findsOneWidget);
        expect(find.text('OpenWrt'), findsOneWidget);
        expect(find.text('25.12.5'), findsOneWidget);

        // Verify horizontal position: Model is on the left, OpenWrt is on the right
        final modelCenter = tester.getCenter(
          find.text('Linksys EA8300 (Dallas)'),
        );
        final versionCenter = tester.getCenter(find.text('25.12.5'));
        expect(
          modelCenter.dx < versionCenter.dx,
          isTrue,
          reason:
              'Model should be on the left and version on the right at scale $scale',
        );

        // Verify card spans full available screen width (360 - 32 = 328)
        final cardFinder = find.ancestor(
          of: find.text('Linksys EA8300 (Dallas)'),
          matching: find.byType(Card),
        );
        expect(cardFinder, findsOneWidget);
        final cardSize = tester.getSize(cardFinder);
        expect(
          cardSize.width,
          greaterThan(320),
          reason:
              'Card should span full available screen width at scale $scale',
        );

        expect(tester.takeException(), isNull);
      }
    },
  );
}
