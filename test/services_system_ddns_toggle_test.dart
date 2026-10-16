// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/main.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/modules/services_system/models/ddns_info.dart';
import 'package:yala/modules/services_system/screens/services_system_screen.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/services/mock_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('DDNS and Async Toggle Hardening Tests', () {
    test('DdnsOverview correctly parses installed state and instances', () {
      final data = {
        'ddns': {
          'global': {'is_enabled': '1'},
          'myddns_ipv4': {
            '.type': 'service',
            'enabled': '1',
            'service_name': 'cloudflare.com-v4',
            'lookup_host': 'router.example.com',
            'domain': 'router.example.com',
          },
        },
      };

      final overview = DdnsOverview.fromDashboardData(
        data,
        isReviewerMode: false,
      );
      expect(overview.isInstalled, isTrue);
      expect(overview.isGlobalEnabled, isTrue);
      expect(overview.instances.length, equals(1));
      expect(overview.instances.first.name, equals('myddns_ipv4'));
      expect(overview.instances.first.enabled, isTrue);
    });

    test(
      'AppState toggleGlobalDdns updates in-memory dashboardData immediately without bounce',
      () async {
        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_ddns',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);
        appState.setAuthServiceForTesting(MockAuthService());
        appState.setApiServiceForTesting(MockApiService());

        appState.setDashboardDataForTesting({
          'ddns': {
            'global': {'is_enabled': '1'},
            'myddns_ipv4': {
              '.type': 'service',
              'enabled': '1',
              'service_name': 'cloudflare.com-v4',
              'lookup_host': 'router.example.com',
              'domain': 'router.example.com',
            },
          },
        });

        expect(
          appState.dashboardData!['ddns']['global']['is_enabled'],
          equals('1'),
        );

        final toggleOffOk = await appState.toggleGlobalDdns(false);
        expect(toggleOffOk, isTrue);
        // Synchronously and immediately updated in in-memory dashboardData without bounce
        expect(
          appState.dashboardData!['ddns']['global']['is_enabled'],
          equals('0'),
        );

        final toggleOnOk = await appState.toggleGlobalDdns(true);
        expect(toggleOnOk, isTrue);
        expect(
          appState.dashboardData!['ddns']['global']['is_enabled'],
          equals('1'),
        );
      },
    );

    test(
      'AppState saveDdnsInstance and deleteDdnsInstance synchronously updates in-memory dashboardData',
      () async {
        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_ddns_save',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);
        appState.setAuthServiceForTesting(MockAuthService());
        appState.setApiServiceForTesting(MockApiService());

        appState.setDashboardDataForTesting(<String, dynamic>{
          'ddns': <String, dynamic>{
            'global': <String, dynamic>{'is_enabled': '1'},
            'myddns_ipv4': <String, dynamic>{
              '.type': 'service',
              'enabled': '1',
              'service_name': 'cloudflare.com-v4',
              'lookup_host': 'router.example.com',
              'domain': 'router.example.com',
            },
          },
        });

        // Update instance to disabled
        const updatedInstance = DdnsInstance(
          name: 'myddns_ipv4',
          enabled: false,
          serviceName: 'cloudflare.com-v4',
          lookupHost: 'router.example.com',
          domain: 'router.example.com',
        );
        final saveOk = await appState.saveDdnsInstance(updatedInstance);
        expect(saveOk, isTrue);
        expect(
          appState.dashboardData!['ddns']['myddns_ipv4']['enabled'],
          equals('0'),
        );

        // Delete instance
        final deleteOk = await appState.deleteDdnsInstance('myddns_ipv4');
        expect(deleteOk, isTrue);
        expect(
          appState.dashboardData!['ddns'].containsKey('myddns_ipv4'),
          isFalse,
        );
      },
    );

    testWidgets(
      'ServicesSystemScreen greys out DDNS cards and disables instance toggle when global DDNS is disabled',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final appState = AppState.instance;
        appState.setDashboardDataForTesting(<String, dynamic>{
          'ddns': <String, dynamic>{
            'global': <String, dynamic>{'is_enabled': '1'},
            'myddns_ipv4': <String, dynamic>{
              '.type': 'service',
              'enabled': '1',
              'service_name': 'cloudflare.com-v4',
              'lookup_host': 'router.example.com',
              'domain': 'router.example.com',
            },
          },
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith((ref) => appState),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ServicesSystemScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify myddns_ipv4 is visible
        expect(find.text('myddns_ipv4'), findsOneWidget);

        // Find the instance tile AnimatedOpacity
        final animatedOpacities = tester
            .widgetList<AnimatedOpacity>(
              find.byType(AnimatedOpacity),
            )
            .toList();
        expect(animatedOpacities.any((ao) => ao.opacity == 1.0), isTrue);

        // Find switches on the screen
        final switches =
            tester.widgetList<Switch>(find.byType(Switch)).toList();
        final instanceSwitch = switches.last;
        expect(instanceSwitch.value, isTrue);
        expect(instanceSwitch.onChanged, isNotNull);

        // Find "Test Config" button
        final testConfigFinder = find.widgetWithText(OutlinedButton, 'Test Config');
        expect(testConfigFinder, findsOneWidget);
        final testConfigBtn = tester.widget<OutlinedButton>(testConfigFinder);
        expect(testConfigBtn.onPressed, isNotNull);

        // NOW disable global DDNS
        appState.setDashboardDataForTesting(<String, dynamic>{
          'ddns': <String, dynamic>{
            'global': <String, dynamic>{'is_enabled': '0'},
            'myddns_ipv4': <String, dynamic>{
              '.type': 'service',
              'enabled': '1',
              'service_name': 'cloudflare.com-v4',
              'lookup_host': 'router.example.com',
              'domain': 'router.example.com',
            },
          },
        });
        await tester.pumpAndSettle();

        // AnimatedOpacity should now be 0.45 (greyed out!)
        final disabledOpacities = tester
            .widgetList<AnimatedOpacity>(
              find.byType(AnimatedOpacity),
            )
            .toList();
        expect(disabledOpacities.any((ao) => ao.opacity == 0.45), isTrue);

        // Instance switch must still have value == true, BUT onChanged == null (disabled)
        final disabledSwitches =
            tester.widgetList<Switch>(find.byType(Switch)).toList();
        final disabledInstanceSwitch = disabledSwitches.last;
        expect(disabledInstanceSwitch.value, isTrue);
        expect(disabledInstanceSwitch.onChanged, isNull);

        // Test Config button should now be disabled (onPressed == null)
        final disabledTestConfigBtn = tester.widget<OutlinedButton>(testConfigFinder);
        expect(disabledTestConfigBtn.onPressed, isNull);

        // Re-enable global DDNS
        appState.setDashboardDataForTesting(<String, dynamic>{
          'ddns': <String, dynamic>{
            'global': <String, dynamic>{'is_enabled': '1'},
            'myddns_ipv4': <String, dynamic>{
              '.type': 'service',
              'enabled': '1',
              'service_name': 'cloudflare.com-v4',
              'lookup_host': 'router.example.com',
              'domain': 'router.example.com',
            },
          },
        });
        await tester.pumpAndSettle();

        // Opacity should be back to 1.0 and switch enabled
        final reenabledOpacities = tester
            .widgetList<AnimatedOpacity>(
              find.byType(AnimatedOpacity),
            )
            .toList();
        expect(reenabledOpacities.any((ao) => ao.opacity == 1.0), isTrue);

        final reenabledSwitches =
            tester.widgetList<Switch>(find.byType(Switch)).toList();
        expect(reenabledSwitches.last.value, isTrue);
        expect(reenabledSwitches.last.onChanged, isNotNull);
      },
    );

    testWidgets(
      'Global DDNS toggle renders loading spinner on the right side and dims during in-flight validation',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_spinner_placement',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);
        appState.setAuthServiceForTesting(MockAuthService());
        appState.setApiServiceForTesting(MockApiService());

        appState.setDashboardDataForTesting(<String, dynamic>{
          'ddns': <String, dynamic>{
            'global': <String, dynamic>{'is_enabled': '1'},
            'myddns_ipv4': <String, dynamic>{
              '.type': 'service',
              'enabled': '1',
              'service_name': 'cloudflare.com-v4',
              'lookup_host': 'router.example.com',
              'domain': 'router.example.com',
            },
          },
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith((ref) => appState),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ServicesSystemScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find the global switch (first Switch on screen)
        final switchesBefore = tester.widgetList<Switch>(find.byType(Switch)).toList();
        expect(switchesBefore.length, equals(2));
        final globalSwitch = switchesBefore.first;
        expect(globalSwitch.value, isTrue);
        expect(globalSwitch.onChanged, isNotNull);

        // Before tapping, no CircularProgressIndicator should be visible near switches
        expect(find.byType(CircularProgressIndicator), findsNothing);

        // Tap the global switch to toggle it OFF
        await tester.tap(find.byType(Switch).first);
        // Pump one frame to start the in-flight validation lifecycle
        await tester.pump();

        // While in-flight:
        // 1. Loading indicator is present next to switch (indeterminate indicator)
        final spinnerFinder = find.byWidgetPredicate(
          (w) => w is CircularProgressIndicator && w.value == null,
        );
        expect(spinnerFinder, findsOneWidget);

        // 2. Loading indicator is placed on the RIGHT side of the switch
        final switchFinder = find.byType(Switch).first;
        final spinnerCenter = tester.getCenter(spinnerFinder);
        final switchCenter = tester.getCenter(switchFinder);
        expect(spinnerCenter.dx, greaterThan(switchCenter.dx),
            reason: 'Loading spinner must be to the right of the switch');

        // 3. Switch is non-clickable during validation (onChanged is null)
        final switchesInFlight = tester.widgetList<Switch>(find.byType(Switch)).toList();
        expect(switchesInFlight.first.onChanged, isNull,
            reason: 'Switch must be non-clickable during in-flight validation');

        // 4. Switch is greyed out (opacity 0.55)
        final opacities = tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity)).toList();
        expect(opacities.any((ao) => ao.opacity == 0.55), isTrue,
            reason: 'Switch must be dimmed with opacity 0.55 during in-flight validation');

        // Allow mock toggle delay to complete and settle
        await tester.pumpAndSettle();

        // After completion: spinner is gone, switch is interactive again
        expect(find.byType(CircularProgressIndicator), findsNothing);
        final switchesAfter = tester.widgetList<Switch>(find.byType(Switch)).toList();
        expect(switchesAfter.first.onChanged, isNotNull);
        expect(switchesAfter.first.value, isFalse);
      },
    );
  });
}
