// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'router_capabilities.dart';

/// Explicitly supported WAN protocols on OpenWrt interfaces
enum WanProtocol {
  dhcp,
  static,
  pppoe,
  dhcpv6,
  dslite,
  map,
  sixInFour, // 6in4
  sixToFour, // 6to4
  qmi,
  ncm,
  wireguard,
  openvpn,
  unknown;

  static WanProtocol parse(String? rawProto) {
    if (rawProto == null || rawProto.trim().isEmpty) return WanProtocol.unknown;
    final normalized = rawProto.trim().toLowerCase();
    switch (normalized) {
      case 'dhcp':
        return WanProtocol.dhcp;
      case 'static':
        return WanProtocol.static;
      case 'pppoe':
        return WanProtocol.pppoe;
      case 'dhcpv6':
        return WanProtocol.dhcpv6;
      case 'dslite':
        return WanProtocol.dslite;
      case 'map':
        return WanProtocol.map;
      case '6in4':
        return WanProtocol.sixInFour;
      case '6to4':
        return WanProtocol.sixToFour;
      case 'qmi':
        return WanProtocol.qmi;
      case 'ncm':
        return WanProtocol.ncm;
      case 'wireguard':
        return WanProtocol.wireguard;
      case 'openvpn':
      case 'ovpn':
        return WanProtocol.openvpn;
      default:
        return WanProtocol.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case WanProtocol.dhcp:
        return 'DHCP';
      case WanProtocol.static:
        return 'Static IP';
      case WanProtocol.pppoe:
        return 'PPPoE';
      case WanProtocol.dhcpv6:
        return 'DHCPv6';
      case WanProtocol.dslite:
        return 'DS-Lite';
      case WanProtocol.map:
        return 'MAP-E/MAP-T';
      case WanProtocol.sixInFour:
        return '6in4 Tunnel';
      case WanProtocol.sixToFour:
        return '6to4 Tunnel';
      case WanProtocol.qmi:
        return 'QMI Cellular';
      case WanProtocol.ncm:
        return 'NCM Cellular';
      case WanProtocol.wireguard:
        return 'WireGuard';
      case WanProtocol.openvpn:
        return 'OpenVPN Tunnel';
      case WanProtocol.unknown:
        return 'Unrecognized Protocol';
    }
  }
}

/// Individual port representation within network switch / bridge topology
class TopologyPort {
  final String name;
  final bool isTagged;
  final bool isWan;
  final int? portIndex;
  final bool isUp;
  final String? linkSpeed;

  const TopologyPort({
    required this.name,
    this.isTagged = false,
    this.isWan = false,
    this.portIndex,
    this.isUp = true,
    this.linkSpeed,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'isTagged': isTagged,
    'isWan': isWan,
    'portIndex': portIndex,
    'isUp': isUp,
    'linkSpeed': linkSpeed,
  };
}

/// Configured VLAN entry
class VlanConfig {
  final int vid;
  final String name;
  final List<TopologyPort> ports;
  final String? device;

  const VlanConfig({
    required this.vid,
    required this.name,
    required this.ports,
    this.device,
  });

  Map<String, dynamic> toJson() => {
    'vid': vid,
    'name': name,
    'ports': ports.map((p) => p.toJson()).toList(),
    'device': device,
  };
}

/// Unified output schema for Network Topology (DSA or swconfig)
class NetworkTopology {
  final NetworkModel modelType;
  final List<TopologyPort> ports;
  final List<VlanConfig> vlans;
  final List<String> bridges;
  final bool isAvailable;
  final bool isZeroVlans;
  final String? errorMessage;

  const NetworkTopology({
    required this.modelType,
    required this.ports,
    required this.vlans,
    required this.bridges,
    required this.isAvailable,
    required this.isZeroVlans,
    this.errorMessage,
  });

  factory NetworkTopology.unavailable(NetworkModel model, [String? reason]) {
    return NetworkTopology(
      modelType: model,
      ports: const [],
      vlans: const [],
      bridges: const [],
      isAvailable: false,
      isZeroVlans: false,
      errorMessage:
          reason ?? 'Topology unavailable for current capabilities profile',
    );
  }

  factory NetworkTopology.zeroVlans(
    NetworkModel model, {
    List<TopologyPort>? ports,
    List<String>? bridges,
  }) {
    return NetworkTopology(
      modelType: model,
      ports: ports ?? const [],
      vlans: const [],
      bridges: bridges ?? const [],
      isAvailable: true,
      isZeroVlans: true,
    );
  }
}

/// Dedicated DSA (Distributed Switch Architecture) topology parser
class DsaTopologyParser {
  static NetworkTopology parse(
    Map<String, dynamic> uciNetworkConfig,
    Map<String, dynamic>? networkDevices,
  ) {
    try {
      final rawValues = uciNetworkConfig['values'];
      final Map<String, dynamic> uciValues = (rawValues is Map)
          ? Map<String, dynamic>.from(rawValues)
          : Map<String, dynamic>.from(uciNetworkConfig);

      if (uciValues.isEmpty) {
        return NetworkTopology.unavailable(
          NetworkModel.dsa,
          'UCI network configuration payload is empty or unpopulated',
        );
      }

      final vlans = <VlanConfig>[];
      final allPorts = <TopologyPort>[];
      final bridges = <String>[];
      final bridgeMemberPorts = <String, List<String>>{};
      final wanPortNames = <String>{};
      bool hasValidNetworkSections = false;

      TopologyPort buildDsaPort(
        String rawName, {
        bool isTagged = false,
        bool? isWanOverride,
        int? portIndex,
      }) {
        final cleanName = rawName.split(':').first.trim();
        final isWan = isWanOverride ?? cleanName.toLowerCase().contains('wan');

        bool isUp = false;
        String? linkSpeed;
        if (networkDevices != null && networkDevices.containsKey(cleanName)) {
          final devInfo = networkDevices[cleanName];
          if (devInfo is Map) {
            final carrier = devInfo['carrier'];
            final up = devInfo['up'];
            if (carrier != null) {
              isUp = carrier == true || carrier == 1 || carrier == '1';
            } else if (up != null) {
              isUp = up == true || up == 1 || up == '1';
            }
            if (devInfo['speed'] != null) {
              linkSpeed = devInfo['speed'].toString();
            }
          }
        } else if (networkDevices == null) {
          // Default to true when device status is omitted (e.g. mock / tests)
          isUp = true;
        }

        return TopologyPort(
          name: cleanName,
          isTagged: isTagged,
          isWan: isWan,
          portIndex: portIndex,
          isUp: isUp,
          linkSpeed: linkSpeed,
        );
      }

      uciValues.forEach((key, val) {
        if (val is Map) {
          final type = val['.type']?.toString();
          if (type == 'interface' ||
              type == 'device' ||
              type == 'bridge-vlan') {
            hasValidNetworkSections = true;
          }

          if (type == 'device' && val['type'] == 'bridge') {
            final name = val['name']?.toString() ?? 'br-lan';
            if (!bridges.contains(name)) bridges.add(name);

            final rawPorts = val['ports'];
            final mPorts = <String>[];
            if (rawPorts is List) {
              for (final p in rawPorts) {
                if (p != null && p.toString().trim().isNotEmpty) {
                  mPorts.add(p.toString().trim());
                }
              }
            } else if (rawPorts is String && rawPorts.trim().isNotEmpty) {
              for (final p in rawPorts.split(' ')) {
                if (p.trim().isNotEmpty) {
                  mPorts.add(p.trim());
                }
              }
            }
            if (mPorts.isNotEmpty) {
              bridgeMemberPorts[name] = mPorts;
            }
          } else if (type == 'device') {
            final devName = val['name']?.toString() ?? '';
            if (devName.toLowerCase().contains('wan')) {
              wanPortNames.add(devName);
            }
          } else if (type == 'interface') {
            final ifName = key.toLowerCase();
            final devName = val['device']?.toString() ?? '';
            if (ifName.contains('wan') && devName.isNotEmpty) {
              wanPortNames.add(devName);
            }
          } else if (type == 'bridge-vlan') {
            final device = val['device']?.toString() ?? 'br-lan';
            final vlanIdStr = val['vlan']?.toString() ?? '1';
            final vid = int.tryParse(vlanIdStr) ?? 1;
            final rawPorts = val['ports'];

            final portsList = <TopologyPort>[];
            if (rawPorts is List) {
              for (final p in rawPorts) {
                final pStr = p.toString().trim();
                final portSuffix = pStr.contains(':')
                    ? pStr.substring(pStr.indexOf(':'))
                    : '';
                final isTagged = portSuffix.startsWith(':t');
                final port = buildDsaPort(pStr, isTagged: isTagged);
                portsList.add(port);
                if (!allPorts.any((ap) => ap.name == port.name)) {
                  allPorts.add(port);
                }
              }
            } else if (rawPorts is String && rawPorts.isNotEmpty) {
              for (final pStr in rawPorts.split(' ')) {
                if (pStr.trim().isEmpty) continue;
                final portSuffix = pStr.contains(':')
                    ? pStr.substring(pStr.indexOf(':'))
                    : '';
                final isTagged = portSuffix.startsWith(':t');
                final port = buildDsaPort(pStr, isTagged: isTagged);
                portsList.add(port);
                if (!allPorts.any((ap) => ap.name == port.name)) {
                  allPorts.add(port);
                }
              }
            }

            vlans.add(
              VlanConfig(
                vid: vid,
                name: 'VLAN $vid',
                ports: portsList,
                device: device,
              ),
            );
          }
        }
      });

      if (!hasValidNetworkSections) {
        return NetworkTopology.unavailable(
          NetworkModel.dsa,
          'No valid network sections found in UCI payload',
        );
      }

      // If no bridge-vlan sections were configured, synthesize from unsegmented bridge device
      if (vlans.isEmpty && bridgeMemberPorts.isNotEmpty) {
        bridgeMemberPorts.forEach((bridgeName, memberPorts) {
          final portsList = <TopologyPort>[];
          for (final pStr in memberPorts) {
            final port = buildDsaPort(pStr);
            portsList.add(port);
            if (!allPorts.any((ap) => ap.name == port.name)) {
              allPorts.add(port);
            }
          }
          vlans.add(
            VlanConfig(
              vid: 1,
              name: 'Default Bridge ($bridgeName)',
              ports: portsList,
              device: bridgeName,
            ),
          );
        });

        // Also detect standalone WAN device if present and not already listed
        if (wanPortNames.isEmpty &&
            networkDevices != null &&
            networkDevices.containsKey('wan')) {
          wanPortNames.add('wan');
        }
        for (final wanName in wanPortNames) {
          if (!allPorts.any((ap) => ap.name == wanName)) {
            final wanPort = buildDsaPort(wanName, isWanOverride: true);
            allPorts.add(wanPort);
            vlans.add(
              VlanConfig(
                vid: 0,
                name: 'WAN Interface ($wanName)',
                ports: [wanPort],
                device: wanName,
              ),
            );
          }
        }
      }

      if (vlans.isEmpty) {
        return NetworkTopology.zeroVlans(
          NetworkModel.dsa,
          ports: allPorts,
          bridges: bridges,
        );
      }

      return NetworkTopology(
        modelType: NetworkModel.dsa,
        ports: allPorts,
        vlans: vlans,
        bridges: bridges,
        isAvailable: true,
        isZeroVlans: false,
      );
    } catch (e) {
      return NetworkTopology.unavailable(
        NetworkModel.dsa,
        'Failed to parse DSA topology: $e',
      );
    }
  }
}

/// Dedicated swconfig (legacy switch_vlan) topology parser
class SwconfigTopologyParser {
  static NetworkTopology parse(
    Map<String, dynamic> uciNetworkConfig,
    Map<String, dynamic>? networkDevices,
  ) {
    try {
      final rawValues = uciNetworkConfig['values'];
      final Map<String, dynamic> uciValues = (rawValues is Map)
          ? Map<String, dynamic>.from(rawValues)
          : Map<String, dynamic>.from(uciNetworkConfig);

      if (uciValues.isEmpty) {
        return NetworkTopology.unavailable(
          NetworkModel.swconfig,
          'UCI network configuration payload is empty or unpopulated',
        );
      }

      final vlans = <VlanConfig>[];
      final allPorts = <TopologyPort>[];
      final switches = <String>[];
      bool hasValidNetworkSections = false;

      // Extract swconfig port state list if provided
      List<dynamic>? swconfigPortList;
      if (networkDevices != null) {
        final rawSw = networkDevices['swconfigPortState'];
        if (rawSw is Map && rawSw['result'] is List) {
          swconfigPortList = rawSw['result'] as List;
        } else if (rawSw is List) {
          swconfigPortList = rawSw;
        }
      }

      uciValues.forEach((key, val) {
        if (val is Map) {
          final type = val['.type']?.toString();
          if (type == 'interface' ||
              type == 'switch' ||
              type == 'switch_vlan') {
            hasValidNetworkSections = true;
          }

          if (type == 'switch') {
            final name =
                val['name']?.toString() ??
                val['.name']?.toString() ??
                'switch0';
            switches.add(name);
          } else if (type == 'switch_vlan') {
            final switchDev = val['device']?.toString() ?? 'switch0';
            final vlanIdStr =
                val['vlan']?.toString() ?? val['vlan_id']?.toString() ?? '1';
            final vid = int.tryParse(vlanIdStr) ?? 1;
            final rawPorts = val['ports']?.toString() ?? '';

            final portsList = <TopologyPort>[];
            for (final portToken in rawPorts.split(' ')) {
              if (portToken.trim().isEmpty) continue;
              final isTagged = portToken.endsWith('t');
              final rawNum = portToken.replaceAll(RegExp(r'[^\d]'), '');
              final pIndex = int.tryParse(rawNum);
              final portName = pIndex == 0
                  ? 'WAN (Port 0)'
                  : 'LAN Port $rawNum';
              final isWan =
                  pIndex == 0 || portName.toLowerCase().contains('wan');

              bool isUp = false;
              String? linkSpeed;

              if (swconfigPortList != null && pIndex != null) {
                for (final item in swconfigPortList) {
                  if (item is Map) {
                    final portVal = item['port'];
                    if (portVal == pIndex || portVal.toString() == rawNum) {
                      if (item['link'] == true) {
                        isUp = true;
                        final spd = item['speed'];
                        if (spd != null && spd != 0 && spd != '0') {
                          linkSpeed = '${spd}M';
                        }
                        break;
                      }
                    }
                  }
                }
              } else if (networkDevices != null &&
                  networkDevices.containsKey(portName)) {
                final devInfo = networkDevices[portName];
                if (devInfo is Map) {
                  final carrier = devInfo['carrier'];
                  final up = devInfo['up'];
                  if (carrier != null) {
                    isUp = carrier == true || carrier == 1 || carrier == '1';
                  } else if (up != null) {
                    isUp = up == true || up == 1 || up == '1';
                  }
                  if (devInfo['speed'] != null) {
                    linkSpeed = devInfo['speed'].toString();
                  }
                }
              } else if (networkDevices == null) {
                // Fallback default for unit tests
                isUp = true;
              }

              final port = TopologyPort(
                name: portName,
                isTagged: isTagged,
                isWan: isWan,
                portIndex: pIndex,
                isUp: isUp,
                linkSpeed: linkSpeed,
              );
              portsList.add(port);
              if (!allPorts.any((ap) => ap.name == portName)) {
                allPorts.add(port);
              }
            }

            vlans.add(
              VlanConfig(
                vid: vid,
                name: 'VLAN $vid ($switchDev)',
                ports: portsList,
                device: switchDev,
              ),
            );
          }
        }
      });

      if (!hasValidNetworkSections) {
        return NetworkTopology.unavailable(
          NetworkModel.swconfig,
          'No valid network sections found in UCI payload',
        );
      }

      if (vlans.isEmpty) {
        return NetworkTopology.zeroVlans(
          NetworkModel.swconfig,
          ports: allPorts,
          bridges: switches,
        );
      }

      return NetworkTopology(
        modelType: NetworkModel.swconfig,
        ports: allPorts,
        vlans: vlans,
        bridges: switches,
        isAvailable: true,
        isZeroVlans: false,
      );
    } catch (e) {
      return NetworkTopology.unavailable(
        NetworkModel.swconfig,
        'Failed to parse swconfig topology: $e',
      );
    }
  }
}
