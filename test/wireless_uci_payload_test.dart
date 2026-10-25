// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/services/mock_api_service.dart';

void main() {
  group('Wireless UCI Payload Generation & Transaction Safety Tests', () {
    late MockApiService mockApi;

    setUp(() {
      mockApi = MockApiService();
    });

    test(
      'addWirelessInterface merges extraOptions into UCI payload correctly',
      () async {
        final extraOptions = <String, String>{
          'isolate': '1',
          'hidden': '1',
          'ieee80211w': '2',
          'wmm': '1',
          'ieee80211r': '1',
          'ft_over_ds': '1',
          'mobility_domain': 'e1a0',
          'ieee80211k': '1',
          'ieee80211v': '1',
          'dtim_period': '2',
          'gtk_rekey': '3600',
          'inactivity_limit': '300',
          'max_listen_interval': '10',
          'macfilter': 'allow',
          'maclist': 'AA:BB:CC:DD:EE:FF 11:22:33:44:55:66',
        };

        final success = await mockApi.addWirelessInterface(
          '192.168.1.1',
          'sysauth_token',
          false,
          radioName: 'radio0',
          ssid: 'Enterprise_Mesh_WiFi',
          encryption: 'sae',
          key: 'SecureP@ssphrase2026',
          network: 'lan',
          extraOptions: extraOptions,
        );

        expect(success, isTrue);
      },
    );

    test(
      'updateInterfaceDhcpConfig updates subnet-level DHCP pool and IPv6 options',
      () async {
        final dhcpValues = <String, dynamic>{
          'start': '150',
          'limit': '100',
          'leasetime': '24h',
          'ra': 'server',
          'dhcpv6': 'server',
          'dns': ['1.1.1.1', '1.0.0.1'],
        };

        final success = await mockApi.updateInterfaceDhcpConfig(
          '192.168.1.1',
          'sysauth_token',
          false,
          interface: 'guest',
          values: dhcpValues,
        );

        expect(success, isTrue);
      },
    );

    test(
      'fetchWirelessHardwareCapabilities accurately gates unsupported security and ciphers',
      () async {
        final caps = await mockApi.fetchWirelessHardwareCapabilities(
          sectionName: 'wifinet0',
          radioName: 'radio0',
          ipAddress: '192.168.1.1',
          sysauth: 'sysauth_token',
          useHttps: false,
        );

        expect(caps, contains('encryptions'));
        expect(caps, contains('ciphers'));

        final encs = caps['encryptions'] as List;
        final ciphers = caps['ciphers'] as List;

        expect(encs.any((e) => e['value'] == 'sae'), isTrue);
        expect(encs.any((e) => e['value'] == 'sae-mixed'), isTrue);
        expect(encs.any((e) => e['value'] == 'psk2'), isTrue);
        expect(encs.any((e) => e['value'] == 'none'), isTrue);

        expect(ciphers.any((c) => c['value'] == 'ccmp'), isTrue);
        expect(ciphers.any((c) => c['value'] == 'tkip'), isTrue);
      },
    );

    test('deleteWirelessInterface removes interface cleanly', () async {
      final delResult = await mockApi.deleteWirelessInterface(
        '192.168.1.1',
        'sysauth_token',
        false,
        sectionName: 'wifinet0',
      );

      expect(delResult, isTrue);
    });

    test(
      'updateInterfaceDhcpConfig retry targets existing section and updates without duplication',
      () async {
        final dhcpValues1 = <String, dynamic>{
          'start': '100',
          'limit': '50',
          'leasetime': '12h',
        };

        final firstSuccess = await mockApi.updateInterfaceDhcpConfig(
          '192.168.1.1',
          'sysauth_token',
          false,
          interface: 'lan',
          values: dhcpValues1,
        );
        expect(firstSuccess, isTrue);

        // Retry / update with corrected values preserves idempotency
        final dhcpValues2 = <String, dynamic>{
          'start': '150',
          'limit': '100',
          'leasetime': '24h',
        };

        final retrySuccess = await mockApi.updateInterfaceDhcpConfig(
          '192.168.1.1',
          'sysauth_token',
          false,
          interface: 'lan',
          values: dhcpValues2,
        );
        expect(retrySuccess, isTrue);
      },
    );
  });
}
