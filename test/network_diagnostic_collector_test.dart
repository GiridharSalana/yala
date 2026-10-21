// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/routing_neighbor_info.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/engine/network_config_collector.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

class StubCollectorApiService extends MockApiService {
  final Map<String, dynamic>? customDump;
  final Map<String, dynamic>? customFw;
  final List<RouteEntry>? customRoutes;

  StubCollectorApiService({this.customDump, this.customFw, this.customRoutes});

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async {
    if (object == 'network.interface' && method == 'dump') {
      if (customDump != null) {
        return [0, customDump!];
      }
    }
    if (object == 'uci' && method == 'get' && params?['config'] == 'firewall') {
      if (customFw != null) {
        return [
          0,
          {'values': customFw!},
        ];
      }
    }
    return super.call(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }

  @override
  Future<List<RouteEntry>> fetchRoutingTable(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    dynamic context,
  }) async {
    if (customRoutes != null) return customRoutes!;
    return super.fetchRoutingTable(
      ipAddress,
      sysauth,
      useHttps,
      context: context,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkConfigCollector Uplink Detection', () {
    test(
      'Dynamically discovers PPPoE uplink without hardcoded wan name',
      () async {
        final mockDump = {
          'interface': [
            {
              'interface': 'custom_fiber_pppoe',
              'up': true,
              'proto': 'pppoe',
              'device': 'eth1.100', // VLAN tagged DSA port
              'defaultroute': true,
              'ipv4-address': [
                {'address': '182.74.12.34', 'mask': 32},
              ],
              'route': [
                {'target': '0.0.0.0', 'mask': 0, 'nexthop': '182.74.12.1'},
              ],
              'dns-server': ['1.1.1.1', '8.8.8.8'],
            },
            {
              'interface': 'lan',
              'up': true,
              'proto': 'static',
              'device': 'br-lan',
              'defaultroute': false,
              'ipv4-address': [
                {'address': '192.168.1.1', 'mask': 24},
              ],
            },
          ],
        };

        final api = StubCollectorApiService(customDump: mockDump);
        final collector = NetworkConfigCollector(api: api);

        final config = await collector.collect(
          ipAddress: '192.168.1.1',
          sysauth: 'token',
          useHttps: false,
        );

        expect(config.activeUplink, isNotNull);
        expect(config.activeUplink!.name, equals('custom_fiber_pppoe'));
        expect(config.activeUplink!.protocol, equals('pppoe'));
        expect(config.activeUplink!.device, equals('eth1.100'));
        expect(config.ipv4Gateways, contains('182.74.12.1'));
        expect(config.configuredDnsServers, contains('1.1.1.1'));
      },
    );

    test(
      'Discovers cellular / LTE modem uplink when no interface is named wan',
      () async {
        final mockDump = {
          'interface': [
            {
              'interface': 'wwan_lte',
              'up': true,
              'proto': 'qmi',
              'device': 'cdc-wdm0',
              'defaultroute': true,
              'ipv4-address': [
                {'address': '10.150.20.5', 'mask': 24},
              ],
              'route': [
                {'target': '0.0.0.0', 'mask': 0, 'nexthop': '10.150.20.1'},
              ],
            },
          ],
        };

        final api = StubCollectorApiService(customDump: mockDump);
        final collector = NetworkConfigCollector(api: api);

        final config = await collector.collect(
          ipAddress: '192.168.1.1',
          sysauth: 'token',
          useHttps: false,
        );

        expect(config.activeUplink, isNotNull);
        expect(config.activeUplink!.name, equals('wwan_lte'));
        expect(config.activeUplink!.protocol, equals('qmi'));
      },
    );

    test(
      'Gracefully handles empty or malformed interface dump without crashing',
      () async {
        final api = StubCollectorApiService(
          customDump: {'interface': 'invalid_list'},
        );
        final collector = NetworkConfigCollector(api: api);

        final config = await collector.collect(
          ipAddress: '192.168.1.1',
          sysauth: 'token',
          useHttps: false,
        );

        expect(config.interfaces, isEmpty);
        expect(config.activeUplink, isNull);
        expect(config.capabilities.hasManagementApi, isTrue);
      },
    );

    test(
      'Detects firewall forwarding (lan -> wan) and masquerade status',
      () async {
        final mockFw = {
          'cfg1': {'.type': 'zone', 'name': 'wan', 'masq': '1'},
          'cfg2': {
            '.type': 'forwarding',
            'src': 'lan',
            'dest': 'wan',
            'enabled': '1',
          },
        };

        final api = StubCollectorApiService(customFw: mockFw);
        final collector = NetworkConfigCollector(api: api);

        final config = await collector.collect(
          ipAddress: '192.168.1.1',
          sysauth: 'token',
          useHttps: false,
        );

        expect(config.isLanToWanForwardingAllowed, isTrue);
        expect(config.isWanMasqueradingEnabled, isTrue);
      },
    );
  });
}
