// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/network_topology.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/models/rpc_result.dart';

void main() {
  group('Network Topology & Interfaces Unit Tests', () {
    test('DsaTopologyParser correctly parses bridge-vlan sections', () {
      final mockUciNetwork = {
        'values': {
          'br0': {'.type': 'device', 'name': 'br-lan', 'type': 'bridge'},
          'vlan10': {
            '.type': 'bridge-vlan',
            'device': 'br-lan',
            'vlan': '10',
            'ports': ['lan1:u', 'lan2:u', 'lan3:t'],
          },
        },
      };

      final topology = DsaTopologyParser.parse(mockUciNetwork, null);
      expect(topology.isAvailable, isTrue);
      expect(topology.isZeroVlans, isFalse);
      expect(topology.modelType, equals(NetworkModel.dsa));
      expect(topology.vlans.length, equals(1));
      expect(topology.vlans.first.vid, equals(10));
      expect(topology.vlans.first.ports.length, equals(3));
      expect(topology.vlans.first.ports.first.name, equals('lan1'));
      expect(topology.vlans.first.ports.first.isTagged, isFalse);
      expect(topology.vlans.first.ports.last.name, equals('lan3'));
      expect(topology.vlans.first.ports.last.isTagged, isTrue);
    });

    test('SwconfigTopologyParser correctly parses switch_vlan sections', () {
      final mockUciNetwork = {
        'values': {
          'sw0': {'.type': 'switch', 'name': 'switch0'},
          'vlan1': {
            '.type': 'switch_vlan',
            'device': 'switch0',
            'vlan': '1',
            'ports': '1 2 3 5t',
          },
        },
      };

      final topology = SwconfigTopologyParser.parse(mockUciNetwork, null);
      expect(topology.isAvailable, isTrue);
      expect(topology.isZeroVlans, isFalse);
      expect(topology.modelType, equals(NetworkModel.swconfig));
      expect(topology.vlans.length, equals(1));
      expect(topology.vlans.first.vid, equals(1));
      expect(topology.vlans.first.ports.length, equals(4));
      expect(topology.vlans.first.ports.last.isTagged, isTrue);
    });

    test(
      'DsaTopologyParser parses unsegmented flat bridge and resolves port carrier/speed',
      () {
        final mockUciNetwork = {
          'values': {
            'br_lan': {
              '.type': 'device',
              'name': 'br-lan',
              'type': 'bridge',
              'ports': ['lan1', 'lan2', 'lan3', 'lan4'],
            },
            'wan_dev': {'.type': 'device', 'name': 'wan'},
          },
        };

        final mockNetworkDevices = {
          'lan1': {'up': true, 'carrier': true, 'speed': '1000F'},
          'lan2': {'up': true, 'carrier': true, 'speed': '100F'},
          'lan3': {'up': true, 'carrier': false, 'speed': null},
          'lan4': {'up': true, 'carrier': false, 'speed': null},
          'wan': {'up': true, 'carrier': true, 'speed': '1000F'},
        };

        final topology = DsaTopologyParser.parse(
          mockUciNetwork,
          mockNetworkDevices,
        );
        expect(topology.isAvailable, isTrue);
        expect(topology.isZeroVlans, isFalse);
        expect(topology.modelType, equals(NetworkModel.dsa));

        // Should have synthesized Default Bridge and WAN interface
        expect(topology.vlans.length, equals(2));
        final defaultBridge = topology.vlans.first;
        expect(defaultBridge.name, equals('Default Bridge (br-lan)'));
        expect(defaultBridge.ports.length, equals(4));

        // Check port carrier states
        final p1 = defaultBridge.ports.firstWhere((p) => p.name == 'lan1');
        expect(p1.isUp, isTrue);
        expect(p1.linkSpeed, equals('1000F'));

        final p2 = defaultBridge.ports.firstWhere((p) => p.name == 'lan2');
        expect(p2.isUp, isTrue);
        expect(p2.linkSpeed, equals('100F'));

        final p3 = defaultBridge.ports.firstWhere((p) => p.name == 'lan3');
        expect(p3.isUp, isFalse);
        expect(p3.linkSpeed, isNull);

        final p4 = defaultBridge.ports.firstWhere((p) => p.name == 'lan4');
        expect(p4.isUp, isFalse);
        expect(p4.linkSpeed, isNull);

        // Check WAN port
        final wanVlan = topology.vlans.last;
        expect(wanVlan.ports.first.name, equals('wan'));
        expect(wanVlan.ports.first.isUp, isTrue);
        expect(wanVlan.ports.first.linkSpeed, equals('1000F'));
      },
    );

    test(
      'SwconfigTopologyParser resolves port link state and speeds from swconfigPortState',
      () {
        final mockUciNetwork = {
          'values': {
            'sw0': {'.type': 'switch', 'name': 'switch0'},
            'vlan1': {
              '.type': 'switch_vlan',
              'device': 'switch0',
              'vlan': '1',
              'ports': '1 2 3 4 0t',
            },
          },
        };

        final mockNetworkDevices = {
          'swconfigPortState': {
            'result': [
              {'port': 0, 'link': false, 'speed': 0},
              {'port': 0, 'link': true, 'speed': 1000},
              {'port': 1, 'link': false, 'speed': 0},
              {'port': 2, 'link': false, 'speed': 0},
              {'port': 3, 'link': false, 'speed': 0},
              {'port': 4, 'link': false, 'speed': 0},
            ],
          },
        };

        final topology = SwconfigTopologyParser.parse(
          mockUciNetwork,
          mockNetworkDevices,
        );
        expect(topology.isAvailable, isTrue);
        expect(topology.isZeroVlans, isFalse);
        expect(topology.vlans.length, equals(1));

        final vlan1 = topology.vlans.first;
        final wanPort = vlan1.ports.firstWhere((p) => p.portIndex == 0);
        expect(wanPort.isUp, isTrue);
        expect(wanPort.linkSpeed, equals('1000M'));

        final lan1Port = vlan1.ports.firstWhere((p) => p.portIndex == 1);
        expect(lan1Port.isUp, isFalse);
        expect(lan1Port.linkSpeed, isNull);
      },
    );

    test('Parser produces distinct empty states: zeroVlans vs unavailable', () {
      final validFlatNetworkUci = {
        'values': {
          'lan': {'.type': 'interface', 'device': 'br-lan'},
        },
      };
      final emptyPayloadUci = {'values': {}};

      // 1. Genuine Zero VLANs (Flat Network) state on valid config
      final zeroDsa = DsaTopologyParser.parse(validFlatNetworkUci, null);
      expect(zeroDsa.isAvailable, isTrue);
      expect(zeroDsa.isZeroVlans, isTrue);
      expect(zeroDsa.vlans, isEmpty);

      // 2. Empty payload is treated as unavailable, NOT zeroVlans
      final emptyParse = DsaTopologyParser.parse(emptyPayloadUci, null);
      expect(emptyParse.isAvailable, isFalse);
      expect(emptyParse.isZeroVlans, isFalse);

      // 3. Capability unavailable state (e.g. unknown network model / conservative fallback)
      final unavailable = NetworkTopology.unavailable(
        NetworkModel.unknown,
        'Conservative mode',
      );
      expect(unavailable.isAvailable, isFalse);
      expect(unavailable.isZeroVlans, isFalse);
      expect(unavailable.errorMessage, contains('Conservative mode'));
    });

    test(
      'WanProtocol correctly parses standard and unrecognized protocols',
      () {
        expect(WanProtocol.parse('dhcp'), equals(WanProtocol.dhcp));
        expect(WanProtocol.parse('static'), equals(WanProtocol.static));
        expect(WanProtocol.parse('pppoe'), equals(WanProtocol.pppoe));
        expect(WanProtocol.parse('map'), equals(WanProtocol.map));
        expect(WanProtocol.parse('dslite'), equals(WanProtocol.dslite));
        expect(WanProtocol.parse('6in4'), equals(WanProtocol.sixInFour));
        expect(WanProtocol.parse('wireguard'), equals(WanProtocol.wireguard));
        expect(WanProtocol.parse('openvpn'), equals(WanProtocol.openvpn));
        expect(WanProtocol.parse('ovpn'), equals(WanProtocol.openvpn));
        expect(WanProtocol.openvpn.displayName, equals('OpenVPN Tunnel'));

        // Unrecognized proto fallback test
        final unknown = WanProtocol.parse('custom_proto_xyz');
        expect(unknown, equals(WanProtocol.unknown));
        expect(unknown.displayName, equals('Unrecognized Protocol'));
      },
    );

    test(
      'RpcResult classification handles transport and ubus status branches',
      () {
        final successRpc = [
          0,
          {'code': 0, 'stdout': 'lan1 lan2'},
        ];
        final resSuccess = RpcResult.classifyExecResult(successRpc, (d) => d);
        expect(resSuccess.isSuccess, isTrue);

        final notFoundRpc = [3, 'Object not found'];
        final resNotFound = RpcResult.fromUbusResponse(notFoundRpc, (d) => d);
        expect(resNotFound.isMethodNotFound, isTrue);

        final permDeniedRpc = [6, 'Permission denied'];
        final resPermDenied = RpcResult.fromUbusResponse(
          permDeniedRpc,
          (d) => d,
        );
        expect(resPermDenied.isPermissionDenied, isTrue);
      },
    );

    test(
      'SwconfigTopologyParser maps hardware switch ports to chassis port indexes using board.json',
      () {
        final mockUciNetwork = {
          'values': {
            'sw0': {'.type': 'switch', 'name': 'switch0'},
            'vlan1': {
              '.type': 'switch_vlan',
              'device': 'switch0',
              'vlan': '1',
              'ports': '1 2 3 4 0t',
            },
          },
        };

        // TP-Link Archer C60 v3 board.json switch layout where hardware num 4 is physical LAN 1
        final mockBoardJson = {
          'switch': {
            'switch0': {
              'enable': true,
              'reset': true,
              'ports': [
                {'num': 0, 'device': 'eth0'},
                {'num': 1, 'role': 'lan', 'index': 4},
                {'num': 2, 'role': 'lan', 'index': 3},
                {'num': 3, 'role': 'lan', 'index': 2},
                {'num': 4, 'role': 'lan', 'index': 1},
              ],
            },
          },
        };

        final mockNetworkDevices = {
          'swconfigPortState': {
            'result': [
              {'port': 0, 'link': true, 'speed': 1000},
              {'port': 1, 'link': false, 'speed': 0},
              {'port': 2, 'link': false, 'speed': 0},
              {'port': 3, 'link': false, 'speed': 0},
              {'port': 4, 'link': true, 'speed': 100},
            ],
          },
        };

        final topology = SwconfigTopologyParser.parse(
          mockUciNetwork,
          mockNetworkDevices,
          boardJson: mockBoardJson,
        );

        expect(topology.isAvailable, isTrue);
        final vlan1 = topology.vlans.first;
        expect(vlan1.ports.length, equals(5));

        // Ports should be sorted by physical chassis index order
        expect(vlan1.ports[0].name, equals('LAN Port 1'));
        expect(vlan1.ports[0].portIndex, equals(4)); // Hardware switch port 4
        expect(vlan1.ports[0].isUp, isTrue);
        expect(vlan1.ports[0].linkSpeed, equals('100M'));

        expect(vlan1.ports[1].name, equals('LAN Port 2'));
        expect(vlan1.ports[1].portIndex, equals(3));
        expect(vlan1.ports[1].isUp, isFalse);

        expect(vlan1.ports[2].name, equals('LAN Port 3'));
        expect(vlan1.ports[2].portIndex, equals(2));
        expect(vlan1.ports[2].isUp, isFalse);

        expect(vlan1.ports[3].name, equals('LAN Port 4'));
        expect(vlan1.ports[3].portIndex, equals(1));
        expect(vlan1.ports[3].isUp, isFalse);

        // CPU port at the end
        expect(vlan1.ports[4].name, equals('CPU (eth0)'));
        expect(vlan1.ports[4].portIndex, equals(0));
        expect(vlan1.ports[4].isTagged, isTrue);
        expect(vlan1.ports[4].isWan, isFalse); // eth0 is CPU, not WAN!
        expect(vlan1.ports[4].isCpu, isTrue);
      },
    );

    test(
      'SwconfigTopologyParser detects and synthesizes standalone WAN interface (eth1) alongside switch0',
      () {
        // Exact Archer C60 v3 layout where LAN is switch0 (eth0.1) and WAN is eth1
        final mockUciNetwork = {
          'values': {
            'sw0': {'.type': 'switch', 'name': 'switch0'},
            'vlan1': {
              '.type': 'switch_vlan',
              'device': 'switch0',
              'vlan': '1',
              'ports': '1 2 3 4 0t',
            },
            'wan': {'.type': 'interface', 'device': 'eth1', 'proto': 'dhcp'},
            'wan6': {'.type': 'interface', 'device': 'eth1', 'proto': 'dhcpv6'},
          },
        };

        final mockBoardJson = {
          'network': {
            'lan': {'device': 'eth0.1', 'protocol': 'static'},
            'wan': {'device': 'eth1', 'protocol': 'dhcp'},
          },
          'switch': {
            'switch0': {
              'enable': true,
              'reset': true,
              'ports': [
                {'num': 0, 'device': 'eth0'},
                {'num': 1, 'role': 'lan', 'index': 4},
                {'num': 2, 'role': 'lan', 'index': 3},
                {'num': 3, 'role': 'lan', 'index': 2},
                {'num': 4, 'role': 'lan', 'index': 1},
              ],
            },
          },
        };

        final mockNetworkDevices = {
          'swconfigPortState': {
            'result': [
              {'port': 0, 'link': true, 'speed': 1000},
              {'port': 1, 'link': false, 'speed': 0},
              {'port': 2, 'link': false, 'speed': 0},
              {'port': 3, 'link': false, 'speed': 0},
              {'port': 4, 'link': true, 'speed': 100},
            ],
          },
          'eth1': {'up': true, 'carrier': true, 'speed': '100F'},
          'eth0': {'up': true, 'carrier': true, 'speed': '1000F'},
        };

        final topology = SwconfigTopologyParser.parse(
          mockUciNetwork,
          mockNetworkDevices,
          boardJson: mockBoardJson,
        );

        expect(topology.isAvailable, isTrue);
        // Expect both VLAN 1 (switch0) and WAN Interface (eth1)
        expect(topology.vlans.length, equals(2));

        final switchVlan = topology.vlans.first;
        expect(switchVlan.name, equals('VLAN 1 (switch0)'));
        expect(switchVlan.ports.length, equals(5));

        // CPU port on switch0
        final cpuPort = switchVlan.ports.firstWhere((p) => p.name == 'CPU (eth0)');
        expect(cpuPort.isCpu, isTrue);
        expect(cpuPort.isWan, isFalse);
        expect(cpuPort.isTagged, isTrue);
        expect(cpuPort.isUp, isTrue);
        expect(cpuPort.linkSpeed, equals('1000M'));

        // Standalone WAN interface
        final wanVlan = topology.vlans.last;
        expect(wanVlan.name, equals('WAN Interface (eth1)'));
        expect(wanVlan.ports.length, equals(1));
        final wanPort = wanVlan.ports.first;
        expect(wanPort.name, equals('WAN (eth1)'));
        expect(wanPort.isWan, isTrue);
        expect(wanPort.isCpu, isFalse);
        expect(wanPort.isUp, isTrue);
        expect(wanPort.linkSpeed, equals('100F'));
      },
    );

    test(
      'SwconfigTopologyParser does NOT duplicate WAN when WAN is already a switch0 VLAN port',
      () {
        // Router where WAN is port 1 on switch0 (e.g. Archer C7 v5)
        final mockUciNetwork = {
          'values': {
            'sw0': {'.type': 'switch', 'name': 'switch0'},
            'vlan1': {
              '.type': 'switch_vlan',
              'device': 'switch0',
              'vlan': '1',
              'ports': '2 3 4 5 0t',
            },
            'vlan2': {
              '.type': 'switch_vlan',
              'device': 'switch0',
              'vlan': '2',
              'ports': '1 0t',
            },
            'wan': {'.type': 'interface', 'device': 'eth0.2', 'proto': 'dhcp'},
          },
        };

        final mockBoardJson = {
          'network': {
            'lan': {'device': 'eth0.1'},
            'wan': {'device': 'eth0.2'},
          },
          'switch': {
            'switch0': {
              'ports': [
                {'num': 0, 'device': 'eth0', 'role': 'cpu'},
                {'num': 1, 'role': 'wan', 'index': 1},
                {'num': 2, 'role': 'lan', 'index': 1},
                {'num': 3, 'role': 'lan', 'index': 2},
                {'num': 4, 'role': 'lan', 'index': 3},
                {'num': 5, 'role': 'lan', 'index': 4},
              ],
            },
          },
        };

        final mockNetworkDevices = {
          'swconfigPortState': {
            'result': [
              {'port': 0, 'link': true, 'speed': 1000},
              {'port': 1, 'link': true, 'speed': 1000},
              {'port': 2, 'link': true, 'speed': 100},
            ],
          },
        };

        final topology = SwconfigTopologyParser.parse(
          mockUciNetwork,
          mockNetworkDevices,
          boardJson: mockBoardJson,
        );

        expect(topology.isAvailable, isTrue);
        // Only 2 switch_vlan sections, NO duplicate 3rd standalone WAN row
        expect(topology.vlans.length, equals(2));
        expect(topology.vlans[0].name, equals('VLAN 1 (switch0)'));
        expect(topology.vlans[1].name, equals('VLAN 2 (switch0)'));

        final wanPort = topology.vlans[1].ports.firstWhere((p) => p.isWan);
        expect(wanPort.name, equals('WAN'));
        expect(wanPort.isUp, isTrue);
        expect(wanPort.isCpu, isFalse);
      },
    );

    test(
      'SwconfigTopologyParser handles standalone WAN with ISP VLAN tagging (eth1.835) and filters tunnels',
      () {
        final mockUciNetwork = {
          'values': {
            'sw0': {'.type': 'switch', 'name': 'switch0'},
            'vlan1': {
              '.type': 'switch_vlan',
              'device': 'switch0',
              'vlan': '1',
              'ports': '1 2 3 4 0t',
            },
            'wan': {'.type': 'interface', 'device': 'eth1.835', 'proto': 'pppoe'},
            'vpn_wan': {'.type': 'interface', 'device': 'wg0', 'proto': 'wireguard'},
          },
        };

        final mockBoardJson = {
          'network': {
            'wan': {'device': 'eth1.835'},
          },
          'switch': {
            'switch0': {
              'ports': [
                {'num': 0, 'device': 'eth0'},
                {'num': 1, 'role': 'lan', 'index': 1},
              ],
            },
          },
        };

        final mockNetworkDevices = {
          'eth1': {'up': true, 'carrier': true, 'speed': '1000F'},
          'wg0': {'up': true, 'carrier': true},
        };

        final topology = SwconfigTopologyParser.parse(
          mockUciNetwork,
          mockNetworkDevices,
          boardJson: mockBoardJson,
        );

        expect(topology.isAvailable, isTrue);
        // Should have VLAN 1 and WAN Interface (eth1), but NOT wg0
        expect(topology.vlans.length, equals(2));
        final wanVlan = topology.vlans.last;
        expect(wanVlan.name, equals('WAN Interface (eth1)'));
        expect(wanVlan.ports.first.name, equals('WAN (eth1)'));
        expect(wanVlan.ports.first.linkSpeed, equals('1000F'));
      },
    );
  });
}
