// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/services/api_service.dart';
import 'package:yala/services/mock_api_service.dart';

void main() {
  group('Client Access Control & Live Router Query Tests', () {
    late MockApiService mockApiService;

    setUp(() {
      mockApiService = MockApiService();
    });

    test('pauseClientInternet succeeds in mock service', () async {
      final success = await mockApiService.pauseClientInternet(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'AA:BB:CC:11:22:33',
        pause: true,
      );
      expect(success, isTrue);
    });

    test('resumeClientInternet succeeds in mock service', () async {
      final success = await mockApiService.pauseClientInternet(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'AA:BB:CC:11:22:33',
        pause: false,
      );
      expect(success, isTrue);
    });

    test('banWirelessClient succeeds in mock service', () async {
      final success = await mockApiService.banWirelessClient(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'DD:EE:FF:44:55:66',
        iface: 'wlan0',
      );
      expect(success, isTrue);
    });

    test('unbanWirelessClient succeeds in mock service', () async {
      final success = await mockApiService.unbanWirelessClient(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'DD:EE:FF:44:55:66',
      );
      expect(success, isTrue);
    });

    test(
      'fetchRestrictedAndBannedClientsLive returns direct router status',
      () async {
        final data = await mockApiService.fetchRestrictedAndBannedClientsLive(
          '192.168.1.1',
          'mock-sysauth',
          false,
        );

        expect(data, contains('restricted'));
        expect(data, contains('banned'));
        expect(data['restricted'], isNotEmpty);
        expect(data['banned'], isNotEmpty);
        expect(data['restricted']!.first['mac'], equals('11:22:33:44:55:66'));
        expect(data['banned']!.first['mac'], equals('99:88:77:66:55:44'));
      },
    );
  });

  group('RealApiService Client Ban & Fast Unban Pipeline Tests', () {
    test(
      'unbanWirelessClient fast-path completes immediately without service reload when no rules exist',
      () async {
        final executedCalls = <String>[];
        final testApi = _TestableRealApiService(
          onCall: (object, method, params) async {
            executedCalls.add('$object.$method');
            if (object == 'uci' && method == 'get') {
              // Return clean configs with no rules matching the target MAC
              return [
                0,
                {
                  'values': {
                    'rule1': {
                      '.type': 'rule',
                      'name': 'Allow-DNS',
                      'target': 'ACCEPT',
                    },
                    'wifinet1': {
                      '.type': 'wifi-iface',
                      'macfilter': 'allow',
                      'maclist': ['AA:BB:CC:DD:EE:FF'],
                    },
                  },
                },
              ];
            }
            if (object.startsWith('hostapd.') && method == 'del_client') {
              return [0];
            }
            if (object == 'file' && method == 'exec') {
              return [
                0,
                {'code': 0, 'stdout': ''},
              ];
            }
            return [0];
          },
          mockObjects: ['hostapd.phy0-ap0', 'hostapd.phy1-ap0'],
        );

        final result = await testApi.unbanWirelessClient(
          '10.0.0.1',
          'token',
          false,
          macAddress: '11:22:33:44:55:66',
        );

        expect(result, isTrue);
        // Verify hostapd del_client was called with ban_time: 0
        expect(executedCalls, contains('hostapd.phy0-ap0.del_client'));
        expect(executedCalls, contains('hostapd.phy1-ap0.del_client'));
        // Verify uci get was queried for clean check
        expect(executedCalls, contains('uci.get'));
        // Verify that neither uci commit nor rc.init reload was called because no rule existed!
        expect(executedCalls, isNot(contains('uci.commit')));
        expect(executedCalls, isNot(contains('rc.init')));
        expect(executedCalls, isNot(contains('network.wireless.up')));
      },
    );

    test(
      'disconnectWirelessClient discovers hostapd.* and calls del_client natively',
      () async {
        final delClientCalls = <String>[];
        final testApi = _TestableRealApiService(
          onCall: (object, method, params) async {
            if (object.startsWith('hostapd.') && method == 'del_client') {
              delClientCalls.add(object);
              return [0];
            }
            if (object == 'file' && method == 'exec') {
              return [
                0,
                {'code': 0, 'stdout': ''},
              ];
            }
            return [0];
          },
          mockObjects: [
            'hostapd.phy0-ap0',
            'hostapd.phy1-ap0',
            'hostapd.phy2-ap0',
          ],
        );

        final result = await testApi.disconnectWirelessClient(
          '10.0.0.1',
          'token',
          false,
          macAddress: 'C0:06:C3:47:D6:83',
          banTimeSeconds: 600,
        );

        expect(result, isTrue);
        expect(delClientCalls, contains('hostapd.phy0-ap0'));
        expect(delClientCalls, contains('hostapd.phy1-ap0'));
        expect(delClientCalls, contains('hostapd.phy2-ap0'));
      },
    );

    test(
      'fetchRestrictedAndBannedClientsLive ignores allowlist maclist in ubus fallback',
      () async {
        final testApi = _TestableRealApiService(
          onCall: (object, method, params) async {
            if (object == 'file' && method == 'exec') {
              // Simulate strict rpcd ACL failure (code 6)
              return [6];
            }
            if (object == 'uci' &&
                method == 'get' &&
                params?['config'] == 'wireless') {
              return [
                0,
                {
                  'values': {
                    'wifinet1': {
                      '.type': 'wifi-iface',
                      'macfilter': 'allow',
                      'maclist': [
                        '48:EF:1C:23:B8:7C',
                        '2C:BE:EB:62:28:DC',
                      ],
                    },
                    'wifinet2': {
                      '.type': 'wifi-iface',
                      'macfilter': 'deny',
                      'maclist': ['99:88:77:66:55:44'],
                    },
                  },
                },
              ];
            }
            if (object == 'uci' &&
                method == 'get' &&
                params?['config'] == 'firewall') {
              return [
                0,
                {
                  'values': {
                    'rule_pause': {
                      '.type': 'rule',
                      'name': 'Pause_Internet_112233445566',
                      'target': 'DROP',
                      'src_mac': '11:22:33:44:55:66',
                    },
                  },
                },
              ];
            }
            return [0];
          },
          mockObjects: [],
        );

        final data = await testApi.fetchRestrictedAndBannedClientsLive(
          '10.0.0.1',
          'token',
          false,
        );

        // Allowlist devices must NOT be classified as banned!
        expect(
          data['banned']!.map((e) => e['mac']),
          contains('99:88:77:66:55:44'),
        );
        expect(
          data['banned']!.map((e) => e['mac']),
          isNot(contains('48:EF:1C:23:B8:7C')),
        );
        expect(
          data['banned']!.map((e) => e['mac']),
          isNot(contains('2C:BE:EB:62:28:DC')),
        );

        // Restricted devices must be classified accurately
        expect(
          data['restricted']!.map((e) => e['mac']),
          contains('11:22:33:44:55:66'),
        );
      },
    );

    test(
      'banWirelessClient on multiple wired clients updates the same Ban_Client_List firewall rule',
      () async {
        final Map<String, dynamic> firewallValues = {};
        final testApi = _TestableRealApiService(
          onCall: (object, method, params) async {
            if (object == 'uci' && method == 'get') {
              return [0, {'values': firewallValues}];
            }
            if (object == 'uci' && method == 'add') {
              final secKey = 'rule_ban_${firewallValues.length + 1}';
              firewallValues[secKey] = {
                '.type': 'rule',
                ...params?['values'] as Map<String, dynamic>,
              };
              return [0, {'section': secKey}];
            }
            if (object == 'uci' && method == 'set') {
              final sec = params?['section'] as String;
              if (firewallValues.containsKey(sec)) {
                final values = params?['values'] as Map<String, dynamic>;
                firewallValues[sec].addAll(values);
              }
              return [0];
            }
            if (object == 'uci' && method == 'delete') {
              final sec = params?['section'] as String;
              firewallValues.remove(sec);
              return [0];
            }
            if (object == 'uci' && method == 'commit') return [0];
            if (object == 'rc' && method == 'init') return [0];
            if (object == 'file' && method == 'exec') {
              return [0, {'code': 0, 'stdout': ''}];
            }
            return [0];
          },
          mockObjects: [], // No hostapd wireless objects (pure wired clients)
        );

        // 1. Ban first wired client
        final res1 = await testApi.banWirelessClient(
          '192.168.1.1',
          'token',
          false,
          macAddress: '02:AA:BB:CC:DD:01',
        );
        expect(res1, isTrue);
        expect(firewallValues.length, equals(1));
        final secKey1 = firewallValues.keys.first;
        expect(firewallValues[secKey1]['name'], equals('Ban_Client_List'));
        expect(firewallValues[secKey1]['src_mac'], equals(['02:AA:BB:CC:DD:01']));

        // 2. Ban second wired client -> must update the SAME rule
        final res2 = await testApi.banWirelessClient(
          '192.168.1.1',
          'token',
          false,
          macAddress: '02:AA:BB:CC:DD:02',
        );
        expect(res2, isTrue);
        expect(firewallValues.length, equals(1)); // Still only 1 rule!
        expect(
          firewallValues[secKey1]['src_mac'],
          equals(['02:AA:BB:CC:DD:01', '02:AA:BB:CC:DD:02']),
        );

        // 3. Unban first wired client -> must retain second client in the SAME rule
        final unban1 = await testApi.unbanWirelessClient(
          '192.168.1.1',
          'token',
          false,
          macAddress: '02:AA:BB:CC:DD:01',
        );
        expect(unban1, isTrue);
        expect(firewallValues.length, equals(1)); // Still exists
        expect(firewallValues[secKey1]['src_mac'], equals(['02:AA:BB:CC:DD:02']));

        // 4. Unban second wired client -> rule is removed
        final unban2 = await testApi.unbanWirelessClient(
          '192.168.1.1',
          'token',
          false,
          macAddress: '02:AA:BB:CC:DD:02',
        );
        expect(unban2, isTrue);
        expect(firewallValues.isEmpty, isTrue); // Cleaned up!
      },
    );
  });
}

class _TestableRealApiService extends RealApiService {
  final Future<dynamic> Function(
    String object,
    String method,
    Map<String, dynamic>? params,
  ) onCall;
  final List<String> mockObjects;

  _TestableRealApiService({
    required this.onCall,
    required this.mockObjects,
  });

  @override
  Future<List<String>> listUbusObjects(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String? pattern,
    BuildContext? context,
  }) async {
    return mockObjects;
  }

  @override
  Future<dynamic> callWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
    bool isRetry = false,
  }) async {
    return onCall(object, method, params);
  }
}
