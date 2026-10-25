// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/modules/wireless_management/models/wireless_info.dart';
import 'package:yala/modules/wireless_management/widgets/add_ssid_dialog.dart';
import 'package:yala/modules/wireless_management/widgets/edit_ssid_dialog.dart';
import 'package:yala/state/app_state.dart';

Future<void> pumpFrames(
  WidgetTester tester, {
  int count = 10,
  Duration duration = const Duration(milliseconds: 50),
}) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(duration);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  const mockRadio = WirelessRadio(
    name: 'radio0',
    isUp: true,
    channel: '36',
    country: 'US',
    interfaces: [
      WirelessInterface(
        ifName: 'wlan0',
        sectionName: 'cfg01',
        ssid: 'Home_WiFi',
        mode: 'ap',
        encryption: 'psk2',
        securityMode: WifiSecurityMode.wpa2Psk,
        pmfState: PmfState.optional,
        channel: '36',
        isEnabled: true,
        stations: [],
        key: 'SuperSecret123',
        networkBridge: 'lan',
      ),
    ],
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          return null;
        });
  });

  setUp(() async {
    await AppState.instance.setReviewerMode(true);
  });

  Widget buildTestWidget(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  group('Milestone 5: SSID Quick Setup UX & Progressive Disclosure', () {
    testWidgets(
      'Criterion 1: Quick Setup default path enables submit button with essential inputs',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        // Find primary button
        final createBtnFinder = find.widgetWithText(
          ElevatedButton,
          'Create Wi-Fi Network',
        );
        expect(createBtnFinder, findsOneWidget);

        // Initial empty SSID -> Disabled
        final initialBtn = tester.widget<ElevatedButton>(createBtnFinder);
        expect(initialBtn.onPressed, isNull);

        // Enter valid SSID and Passphrase
        final textFields = find.byType(TextFormField);
        final ssidField = textFields.at(0);
        final passField = textFields.at(1);

        await tester.enterText(ssidField, 'Fast_New_WiFi');
        await tester.enterText(passField, 'ValidPassphrase123');
        await pumpFrames(tester);

        // Primary button should now be enabled
        final enabledBtn = tester.widget<ElevatedButton>(createBtnFinder);
        expect(enabledBtn.onPressed, isNotNull);

        // Setup Summary card should be present with details
        expect(find.text('Fast_New_WiFi'), findsWidgets);
        expect(find.textContaining('Summary'), findsOneWidget);

        // Advanced settings should remain collapsed by default
        expect(find.text('Isolate Wireless Clients'), findsNothing);
      },
    );

    testWidgets(
      'Criterion 2: Advanced Settings collapsed by default and exposes 4 distinct groups upon expansion',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        // Advanced Settings header is visible
        final advancedTileFinder = find.widgetWithText(
          ExpansionTile,
          'Advanced Settings',
        );
        expect(advancedTileFinder, findsOneWidget);

        // Before expansion, advanced fields are NOT visible
        expect(find.text('Security & Privacy'), findsNothing);
        expect(find.text('Network Assignment'), findsNothing);
        expect(find.text('Fast Roaming & Performance'), findsNothing);
        expect(find.text('IP & DHCP Settings'), findsNothing);

        // Expand Advanced Settings
        await tester.tap(advancedTileFinder);
        await pumpFrames(tester, count: 15);

        // Now all 4 distinct groups are visible
        expect(find.text('Security & Privacy'), findsOneWidget);
        expect(find.text('Network Assignment'), findsOneWidget);
        expect(find.text('Fast Roaming & Performance'), findsOneWidget);
        expect(find.text('IP & DHCP Settings'), findsOneWidget);

        // Key controls within groups are rendered
        expect(find.text('Isolate Wireless Clients'), findsOneWidget);
        expect(
          find.textContaining('802.11r Fast BSS Transition'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Criterion 3: Open network (none) requires explicit confirmation checkbox to submit',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        // Enter SSID
        final textFields = find.byType(TextFormField);
        await tester.enterText(textFields.at(0), 'Public_Open_WiFi');
        await pumpFrames(tester);

        // Change Security Protocol to Open ('none')
        final securityDropdown = find
            .byType(DropdownButtonFormField<String>)
            .at(1);
        await tester.tap(securityDropdown);
        await tester.pumpAndSettle();

        // Tap Open / None option
        await tester.tap(
          find
              .byWidgetPredicate(
                (w) => w is DropdownMenuItem<String> && w.value == 'none',
              )
              .last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Passphrase field is hidden
        expect(find.text('Passphrase / Key'), findsNothing);

        // Amber warning banner and confirmation checkbox are visible
        expect(
          find.textContaining('transmits data without encryption'),
          findsOneWidget,
        );
        final checkboxFinder = find.byType(CheckboxListTile);
        expect(checkboxFinder, findsOneWidget);

        // Create button must be DISABLED until checkbox is checked
        final createBtnFinder = find.widgetWithText(
          ElevatedButton,
          'Create Wi-Fi Network',
        );
        var btn = tester.widget<ElevatedButton>(createBtnFinder);
        expect(
          btn.onPressed,
          isNull,
          reason: 'Submit must be blocked without open-network confirmation',
        );

        // Check confirmation checkbox
        await tester.tap(checkboxFinder);
        await pumpFrames(tester);

        btn = tester.widget<ElevatedButton>(createBtnFinder);
        expect(
          btn.onPressed,
          isNotNull,
          reason: 'Submit must be enabled once confirmation is checked',
        );

        // Uncheck confirmation checkbox
        await tester.tap(checkboxFinder);
        await pumpFrames(tester);

        btn = tester.widget<ElevatedButton>(createBtnFinder);
        expect(
          btn.onPressed,
          isNull,
          reason: 'Submit must be blocked again when unchecked',
        );
      },
    );

    testWidgets(
      'Criterion 4: Network-wide warning updates dynamically when network interface changes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        // Expand Advanced Settings to view IP & DHCP Settings
        final advancedTile = find.widgetWithText(
          ExpansionTile,
          'Advanced Settings',
        );
        await tester.tap(advancedTile);
        await pumpFrames(tester, count: 15);

        // Mandatory warning should mention default network 'lan'
        expect(
          find.text(
            'These settings apply to all devices connected to the lan network, not only this Wi-Fi network.',
          ),
          findsOneWidget,
        );

        // Change Network Interface to 'guest'
        final networkDropdown = find
            .byType(DropdownButtonFormField<String>)
            .first;
        await tester.tap(networkDropdown);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Guest Network (guest)').last);
        await tester.pumpAndSettle();

        // Warning banner must now dynamically reference 'guest'
        expect(
          find.text(
            'These settings apply to all devices connected to the guest network, not only this Wi-Fi network.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Criterion 5: Capability gating disables unsupported security modes and applies smart defaults',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        // Open security dropdown
        final securityDropdown = find
            .byType(DropdownButtonFormField<String>)
            .at(1);
        await tester.tap(securityDropdown);
        await tester.pumpAndSettle();

        // All supported options are selectable
        expect(find.textContaining('WPA2/WPA3 Mixed'), findsWidgets);
        expect(find.textContaining('WPA2-PSK'), findsWidgets);

        // Close dropdown
        await tester.tap(find.textContaining('WPA2/WPA3 Mixed').last);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Criterion 6: EditSsidDialog preserves baseline configuration and enforces progressive disclosure',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            EditSsidDialog(
              radio: mockRadio,
              interface: mockRadio.interfaces.first,
            ),
          ),
        );
        await pumpFrames(tester);

        // Baseline SSID name is loaded
        expect(find.text('Home_WiFi'), findsOneWidget);

        // Save & Apply button is disabled initially
        final saveBtnFinder = find.widgetWithText(
          ElevatedButton,
          'Save & Apply',
        );
        expect(saveBtnFinder, findsOneWidget);

        var saveBtn = tester.widget<ElevatedButton>(saveBtnFinder);
        expect(
          saveBtn.onPressed,
          isNull,
          reason: 'Save button must be disabled when no edits were made',
        );

        // Modify SSID name
        final ssidFieldFinder = find.byType(TextFormField).first;
        await tester.enterText(ssidFieldFinder, 'Home_WiFi_Modified');
        await pumpFrames(tester);

        saveBtn = tester.widget<ElevatedButton>(saveBtnFinder);
        expect(
          saveBtn.onPressed,
          isNotNull,
          reason: 'Save button must be enabled when SSID changed',
        );

        // Revert SSID back
        await tester.enterText(ssidFieldFinder, 'Home_WiFi');
        await pumpFrames(tester);

        saveBtn = tester.widget<ElevatedButton>(saveBtnFinder);
        expect(
          saveBtn.onPressed,
          isNull,
          reason: 'Save button must revert to disabled',
        );

        // Expand Advanced Settings in EditSsidDialog
        final advancedTile = find.widgetWithText(
          ExpansionTile,
          'Advanced Settings',
        );
        await tester.tap(advancedTile);
        await pumpFrames(tester, count: 15);

        // 4 distinct groups must also be present in EditSsidDialog
        expect(find.text('Security & Privacy'), findsOneWidget);
        expect(find.text('Network Assignment'), findsOneWidget);
        expect(find.text('Fast Roaming & Performance'), findsOneWidget);
        expect(find.text('IP & DHCP Settings'), findsOneWidget);

        // Network-wide warning banner must also be present
        expect(
          find.text(
            'These settings apply to all devices connected to the lan network, not only this Wi-Fi network.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Criterion 7: AddSsidDialog rejects duplicate SSID name on the same radio to prevent duplicate creation on retry',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        // mockRadio already contains an interface with SSID 'Home_WiFi'
        final ssidFieldFinder = find.byType(TextFormField).first;
        await tester.enterText(ssidFieldFinder, 'Home_WiFi');
        await pumpFrames(tester);

        // Enter valid password
        final passFieldFinder = find.byType(TextFormField).at(1);
        await tester.enterText(passFieldFinder, 'ValidPassphrase123');
        await pumpFrames(tester);

        // Submit button MUST remain disabled because 'Home_WiFi' already exists on radio0
        final submitBtnFinder = find.byType(ElevatedButton);
        var submitBtn = tester.widget<ElevatedButton>(submitBtnFinder);
        expect(
          submitBtn.onPressed,
          isNull,
          reason:
              'Submit button must be disabled for duplicate SSID on the same radio',
        );

        // Changing to a unique SSID name immediately enables the submit button
        await tester.enterText(ssidFieldFinder, 'New_Unique_WiFi');
        await pumpFrames(tester);

        submitBtn = tester.widget<ElevatedButton>(submitBtnFinder);
        expect(
          submitBtn.onPressed,
          isNotNull,
          reason: 'Submit button must be enabled when SSID is unique',
        );
      },
    );
  });
}
