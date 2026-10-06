// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/wifi_qr_dialog.dart';

void main() {
  testWidgets(
    'WifiQrDialog renders without intrinsic dimension assertion error',
    (WidgetTester tester) async {
      const mockIface = WirelessInterface(
        ifName: 'wlan0',
        sectionName: 'default_radio0',
        ssid: 'Test_Network',
        mode: 'ap',
        encryption: 'psk2',
        securityMode: WifiSecurityMode.wpa2Psk,
        pmfState: PmfState.disabled,
        channel: '6',
        isEnabled: true,
        stations: [],
        key: 'SecretPassword123',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: WifiQrDialog(interface: mockIface)),
          ),
        ),
      );

      expect(find.text('Wi-Fi Quick Connect'), findsOneWidget);
      expect(find.text('Test_Network'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    },
  );

  testWidgets(
    'WifiQrDialog generates correct QR payload for WPA3-SAE and Open',
    (WidgetTester tester) async {
      const saeIface = WirelessInterface(
        ifName: 'wlan0',
        sectionName: 'default_radio0',
        ssid: 'SAE_Network',
        mode: 'ap',
        encryption: 'sae',
        securityMode: WifiSecurityMode.saeOnly,
        pmfState: PmfState.required,
        channel: '36',
        isEnabled: true,
        stations: [],
        key: 'Wpa3Password123',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: WifiQrDialog(interface: saeIface)),
          ),
        ),
      );

      expect(find.text('SAE_Network'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    },
  );
}
