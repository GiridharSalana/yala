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
import 'package:yala/modules/wireless_management/models/wireless_info.dart';
import 'package:yala/modules/wireless_management/screens/wireless_management_screen.dart';
import 'package:yala/modules/wireless_management/widgets/wireless_interface_card.dart';
import 'package:yala/screens/interfaces_screen.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/services/mock_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('Wireless Radio & Interface Toggle UX Tests', () {
    test(
      'AppState toggleWirelessRadio synchronously updates in-memory dashboardData and invalidates fetches',
      () async {
        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_radio_toggle',
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
          'uciWirelessConfig': <String, dynamic>{
            'radio0': <String, dynamic>{
              'disabled': '0',
              'type': 'mac80211',
              'channel': '36',
            },
            'wifinet0': <String, dynamic>{
              'device': 'radio0',
              'mode': 'ap',
              'ssid': 'Yala-5G',
              'disabled': '0',
            },
          },
          'wireless': <String, dynamic>{
            'radio0': <String, dynamic>{
              'up': true,
              'disabled': false,
              'interfaces': [
                {
                  'section': 'wifinet0',
                  'ifname': 'wlan0',
                  'config': {'ssid': 'Yala-5G', 'mode': 'ap'},
                },
              ],
            },
          },
        });

        expect(
          appState.dashboardData!['uciWirelessConfig']['radio0']['disabled'],
          equals('0'),
        );
        expect(
          appState.dashboardData!['wireless']['radio0']['up'],
          isTrue,
        );

        // Toggle radio OFF
        final offOk = await appState.toggleWirelessRadio('radio0', false);
        expect(offOk, isTrue);

        expect(
          appState.dashboardData!['uciWirelessConfig']['radio0']['disabled'],
          equals('1'),
        );
        expect(
          appState.dashboardData!['wireless']['radio0']['up'],
          isFalse,
        );
        expect(
          appState.dashboardData!['wireless']['radio0']['disabled'],
          isTrue,
        );

        // Toggle radio ON
        final onOk = await appState.toggleWirelessRadio('radio0', true);
        expect(onOk, isTrue);

        expect(
          appState.dashboardData!['uciWirelessConfig']['radio0']['disabled'],
          equals('0'),
        );
        expect(
          appState.dashboardData!['wireless']['radio0']['up'],
          isTrue,
        );
        expect(
          appState.dashboardData!['wireless']['radio0']['disabled'],
          isFalse,
        );
      },
    );

    test(
      'AppState setSsidEnabled synchronously updates in-memory dashboardData and invalidates fetches',
      () async {
        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_ssid_toggle',
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
          'uciWirelessConfig': <String, dynamic>{
            'wifinet0': <String, dynamic>{
              'device': 'radio0',
              'mode': 'ap',
              'ssid': 'Yala-Main',
              'disabled': '0',
            },
          },
          'wireless': <String, dynamic>{
            'radio0': <String, dynamic>{
              'up': true,
              'interfaces': [
                {
                  'section': 'wifinet0',
                  'ifname': 'wlan0',
                  'config': {'ssid': 'Yala-Main', 'disabled': '0'},
                },
              ],
            },
          },
        });

        final disableOk = await appState.setSsidEnabled('wifinet0', false);
        expect(disableOk, isTrue);
        expect(
          appState.dashboardData!['uciWirelessConfig']['wifinet0']['disabled'],
          equals('1'),
        );

        final enableOk = await appState.setSsidEnabled('wifinet0', true);
        expect(enableOk, isTrue);
        expect(
          appState.dashboardData!['uciWirelessConfig']['wifinet0']['disabled'],
          equals('0'),
        );
      },
    );

    testWidgets(
      'Virtual SSID card renders loading spinner strictly on the LEFT side of the switch during in-flight validation',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final appState = AppState.instance;
        const testRadio = WirelessRadio(
          name: 'radio0',
          isUp: true,
          channel: '36',
          country: 'US',
          interfaces: [],
        );
        const testInterface = WirelessInterface(
          sectionName: 'wifinet0',
          ifName: 'wlan0',
          ssid: 'Test-SSID',
          mode: 'ap',
          encryption: 'psk2',
          securityMode: WifiSecurityMode.wpa2Psk,
          pmfState: PmfState.disabled,
          channel: '36',
          isEnabled: true,
          stations: [],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith((ref) => appState),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: WirelessInterfaceCard(
                  radio: testRadio,
                  interface: testInterface,
                  isRadioEnabled: true,
                  isPending: true, // In-flight validation active
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final spinnerFinder = find.byType(CircularProgressIndicator);
        final switchFinder = find.byType(Switch);

        expect(spinnerFinder, findsOneWidget);
        expect(switchFinder, findsOneWidget);

        final spinnerTopLeft = tester.getTopLeft(spinnerFinder);
        final switchTopLeft = tester.getTopLeft(switchFinder);

        // Spinner must be strictly to the LEFT of the Switch (smaller dx)
        expect(
          spinnerTopLeft.dx,
          lessThan(switchTopLeft.dx),
          reason: 'Spinner must be strictly on the LEFT of the Switch in SSID card',
        );

        // Switch must be dimmed to 0.55 and disabled (onChanged == null)
        final switchWidget = tester.widget<Switch>(switchFinder);
        expect(switchWidget.onChanged, isNull);

        final animatedOpacityFinder = find.ancestor(
          of: switchFinder,
          matching: find.byType(AnimatedOpacity),
        );
        expect(animatedOpacityFinder, findsWidgets);
        final switchOpacityWidget = tester.widget<AnimatedOpacity>(
          animatedOpacityFinder.first,
        );
        expect(switchOpacityWidget.opacity, equals(0.55));
      },
    );

    testWidgets(
      'Disabling a WirelessRadio greys out child WirelessInterfaceCard (opacity: 0.45) and locks its switch',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final appState = AppState.instance;
        const testRadio = WirelessRadio(
          name: 'radio0',
          isUp: false,
          channel: '36',
          country: 'US',
          interfaces: [],
        );
        const testInterface = WirelessInterface(
          sectionName: 'wifinet0',
          ifName: 'wlan0',
          ssid: 'Test-SSID',
          mode: 'ap',
          encryption: 'psk2',
          securityMode: WifiSecurityMode.wpa2Psk,
          pmfState: PmfState.disabled,
          channel: '36',
          isEnabled: true, // Interface itself is enabled, but parent radio transceiver is off
          stations: [],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith((ref) => appState),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: WirelessInterfaceCard(
                  radio: testRadio,
                  interface: testInterface,
                  isRadioEnabled: false, // Parent radio is off!
                  isPending: false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final switchFinder = find.byType(Switch);
        expect(switchFinder, findsOneWidget);

        final switchWidget = tester.widget<Switch>(switchFinder);
        // Switch retains its true value (true) but is non-clickable
        expect(switchWidget.value, isTrue);
        expect(switchWidget.onChanged, isNull);

        // Outermost AnimatedOpacity must be greyed out to 0.45
        final cardOpacityFinder = find.byWidgetPredicate(
          (w) => w is AnimatedOpacity && (w.opacity - 0.45).abs() < 0.01,
        );
        expect(
          cardOpacityFinder,
          findsOneWidget,
          reason: 'Card must be greyed out to 0.45 when parent radio is disabled',
        );
      },
    );

    testWidgets(
      'Physical WirelessRadio header renders action buttons without master switch',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_radio_screen',
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
          'uciWirelessConfig': <String, dynamic>{
            'radio0': <String, dynamic>{
              'disabled': '0',
              'type': 'mac80211',
              'channel': '36',
            },
            'wifinet0': <String, dynamic>{
              'device': 'radio0',
              'mode': 'ap',
              'ssid': 'Yala-5G',
              'disabled': '0',
            },
          },
          'wireless': <String, dynamic>{
            'radio0': <String, dynamic>{
              'up': true,
              'disabled': false,
              'channel': 36,
              'country': 'US',
              'interfaces': [
                {
                  'section': 'wifinet0',
                  'ifname': 'wlan0',
                  'config': {'ssid': 'Yala-5G', 'mode': 'ap'},
                },
              ],
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
              home: Scaffold(
                body: WirelessManagementScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify Radio0 card is displayed
        expect(find.text('RADIO0'), findsOneWidget);

        // Verify action buttons are present in radio header
        expect(find.byIcon(Icons.add_circle_outline_rounded), findsWidgets);
        expect(find.byIcon(Icons.settings_outlined), findsWidgets);

        // Exactly one switch across the tree: virtual SSID switch (wifinet0), NO master radio switch
        final switchFinders = find.byType(Switch);
        expect(switchFinders, findsOneWidget);
        expect(tester.widget<Switch>(switchFinders.first).value, isTrue);
      },
    );

    testWidgets(
      'InterfacesScreen UnifiedNetworkCard renders spinner on the LEFT of the switch during isSaving',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: UnifiedNetworkCard(
                name: 'LAN',
                subtitle: 'br-lan • 192.168.1.1',
                isUp: true,
                icon: Icons.lan,
                details: SizedBox(),
                isSaving: true, // In-flight saving active!
                currentEnabled: true,
                onToggle: null, // Provided callback
              ),
            ),
          ),
        );
        await tester.pump();

        // Re-pump with onToggle provided
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: UnifiedNetworkCard(
                name: 'LAN',
                subtitle: 'br-lan • 192.168.1.1',
                isUp: true,
                icon: Icons.lan,
                details: const SizedBox(),
                isSaving: true, // In-flight saving active!
                currentEnabled: true,
                onToggle: (val) {},
              ),
            ),
          ),
        );
        await tester.pump();

        final spinnerFinder = find.byType(CircularProgressIndicator);
        final switchFinder = find.byType(Switch);

        expect(spinnerFinder, findsOneWidget);
        expect(switchFinder, findsOneWidget);

        final spinnerTopLeft = tester.getTopLeft(spinnerFinder);
        final switchTopLeft = tester.getTopLeft(switchFinder);

        // In Interfaces card, spinner must be strictly on the LEFT of the Switch (smaller dx)
        expect(
          spinnerTopLeft.dx,
          lessThan(switchTopLeft.dx),
          reason: 'Spinner must be strictly on the LEFT of the switch in UnifiedNetworkCard',
        );

        // Switch must be disabled while isSaving is true
        final switchWidget = tester.widget<Switch>(switchFinder);
        expect(switchWidget.onChanged, isNull);
      },
    );

    testWidgets(
      'Virtual SSID toggle retains initial state without bounce during validation and flips only upon completion',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_ssid_nobounce',
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
          'uciWirelessConfig': <String, dynamic>{
            'radio0': <String, dynamic>{
              'disabled': '0',
              'type': 'mac80211',
              'channel': '36',
            },
            'wifinet0': <String, dynamic>{
              'device': 'radio0',
              'mode': 'ap',
              'ssid': 'Yala-5G',
              'disabled': '0',
            },
            'wifinet1': <String, dynamic>{
              'device': 'radio0',
              'mode': 'ap',
              'ssid': 'Yala-Guest',
              'disabled': '0',
            },
          },
          'wireless': <String, dynamic>{
            'radio0': <String, dynamic>{
              'up': true,
              'disabled': false,
              'channel': 36,
              'country': 'US',
              'interfaces': [
                {
                  'section': 'wifinet0',
                  'ifname': 'wlan0',
                  'config': <String, dynamic>{
                    'ssid': 'Yala-5G',
                    'mode': 'ap',
                    'disabled': '0',
                  },
                },
                {
                  'section': 'wifinet1',
                  'ifname': 'wlan0-1',
                  'config': <String, dynamic>{
                    'ssid': 'Yala-Guest',
                    'mode': 'ap',
                    'disabled': '0',
                  },
                },
              ],
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
              home: Scaffold(
                body: WirelessManagementScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 2 switches: wifinet0 SSID switch and wifinet1 SSID switch (no radio master switch)
        final switchFinders = find.byType(Switch);
        expect(switchFinders, findsNWidgets(2));
        final ssidSwitchFinder = switchFinders.first;

        // Initial state is true
        expect(tester.widget<Switch>(ssidSwitchFinder).value, isTrue);

        // Tap SSID switch to disable
        await tester.tap(ssidSwitchFinder);
        await tester.pump();

        // Confirmation dialog appears
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Disable'));
        await tester.pump();

        // DURING IN-FLIGHT VALIDATION:
        // Switch MUST retain initial value (true) - NO OPTIMISTIC BOUNCE!
        final inFlightSwitch = tester.widget<Switch>(ssidSwitchFinder);
        expect(
          inFlightSwitch.value,
          isTrue,
          reason:
              'Switch must retain its initial value and NOT bounce optimistically during validation',
        );
        // Interaction locked during validation
        expect(inFlightSwitch.onChanged, isNull);

        // Spinner is shown to the LEFT of the SSID switch
        final spinnerFinder = find.byWidgetPredicate(
          (w) => w is CircularProgressIndicator && w.value == null,
        );
        expect(spinnerFinder, findsOneWidget);
        final spinnerTopLeft = tester.getTopLeft(spinnerFinder);
        final switchTopLeft = tester.getTopLeft(ssidSwitchFinder);
        expect(
          spinnerTopLeft.dx,
          lessThan(switchTopLeft.dx),
          reason: 'Spinner must be strictly on the LEFT of the SSID switch',
        );

        // Let async operation complete
        await tester.pumpAndSettle();

        // POST-COMPLETION:
        // Now switch value is smoothly flipped to false without any bounce
        final completedSwitch = tester.widget<Switch>(ssidSwitchFinder);
        expect(completedSwitch.value, isFalse);
        expect(completedSwitch.onChanged, isNotNull);
        expect(spinnerFinder, findsNothing);
      },
    );

    testWidgets(
      'Disabling the only SSID on a radio is allowed and not blocked by Cannot Disable Last SSID restriction',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_single_ssid',
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
          'uciWirelessConfig': <String, dynamic>{
            'radio0': <String, dynamic>{
              'disabled': '0',
              'type': 'mac80211',
              'channel': '36',
            },
            'wifinet0': <String, dynamic>{
              'device': 'radio0',
              'mode': 'ap',
              'ssid': 'SSID1-5G',
              'disabled': '0',
            },
          },
          'wireless': <String, dynamic>{
            'radio0': <String, dynamic>{
              'up': true,
              'disabled': false,
              'channel': 36,
              'country': 'US',
              'interfaces': [
                {
                  'section': 'wifinet0',
                  'ifname': 'wlan0',
                  'config': <String, dynamic>{
                    'ssid': 'SSID1-5G',
                    'mode': 'ap',
                    'disabled': '0',
                  },
                },
              ],
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
              home: Scaffold(
                body: WirelessManagementScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final switchFinder = find.byType(Switch);
        expect(switchFinder, findsOneWidget);

        // Tap the only SSID switch to disable it
        await tester.tap(switchFinder);
        await tester.pump();

        // Must NOT show "Cannot Disable Last SSID" restriction dialog!
        expect(find.text('Cannot Disable Last SSID'), findsNothing);

        // Standard confirmation dialog appears
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Disable'));
        await tester.pumpAndSettle();

        // Switch successfully toggles to false
        expect(tester.widget<Switch>(switchFinder).value, isFalse);
      },
    );
  });
}
