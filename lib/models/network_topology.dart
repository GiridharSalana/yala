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
  final bool isCpu;
  final int? portIndex;
  final bool isUp;
  final String? linkSpeed;

  const TopologyPort({
    required this.name,
    this.isTagged = false,
    this.isWan = false,
    this.isCpu = false,
    this.portIndex,
    this.isUp = true,
    this.linkSpeed,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'isTagged': isTagged,
    'isWan': isWan,
    'isCpu': isCpu,
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
        final isCpu = cleanName.toLowerCase().contains('cpu');

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
          isCpu: isCpu,
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
      }

      // Also detect standalone WAN device if present and not already listed
      if (wanPortNames.isEmpty &&
          networkDevices != null &&
          networkDevices.containsKey('wan')) {
        wanPortNames.add('wan');
      }
      for (final wanName in wanPortNames) {
        if (!allPorts.any((ap) => ap.name == wanName || (ap.isWan && !ap.isCpu))) {
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
    Map<String, dynamic>? networkDevices, {
    Map<String, dynamic>? boardJson,
  }) {
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

      // Build hardware-to-chassis port label mapping from board.json if available
      final boardPortLabels = <String, Map<int, String>>{};
      final boardWanPorts = <String, Set<int>>{};
      final boardCpuPorts = <String, Set<int>>{};
      final boardPortOrder = <String, Map<int, int>>{};
      final cpuDeviceNames = <String>{};

      if (boardJson != null && boardJson['switch'] is Map) {
        final switchSection = boardJson['switch'] as Map;
        switchSection.forEach((swName, swLayout) {
          if (swLayout is Map && swLayout['ports'] is List) {
            final portsList = swLayout['ports'] as List;
            final specs =
                <({int num, String role, int index, String? device})>[];
            for (final p in portsList) {
              if (p is Map) {
                final numVal = p['num'] is int
                    ? p['num'] as int
                    : int.tryParse(p['num']?.toString() ?? '');
                if (numVal == null) continue;
                final roleVal = p['role']?.toString();
                final devVal = p['device']?.toString();
                final role = roleVal ?? (devVal != null ? 'cpu' : 'lan');
                final idxVal = p['index'] is int
                    ? p['index'] as int
                    : int.tryParse(p['index']?.toString() ?? '') ?? numVal;
                specs.add(
                  (num: numVal, role: role, index: idxVal, device: devVal),
                );
              }
            }

            final roleCounts = <String, int>{};
            for (final s in specs) {
              roleCounts[s.role] = (roleCounts[s.role] ?? 0) + 1;
            }

            // Sort by role then chassis index ascending (exact LuCI algorithm)
            specs.sort((a, b) {
              final rc = a.role.compareTo(b.role);
              if (rc != 0) return rc;
              return a.index.compareTo(b.index);
            });

            final labels = <int, String>{};
            final wanSet = <int>{};
            final cpuSet = <int>{};
            final orderMap = <int, int>{};
            int pnum = 1;
            String? currentRole;

            for (final s in specs) {
              if (s.role != currentRole) {
                currentRole = s.role;
                pnum = 1;
              }

              if (s.role == 'cpu') {
                cpuSet.add(s.num);
                orderMap[s.num] = 900 + s.index; // CPU ports at the end
                final devStr =
                    s.device != null && s.device!.isNotEmpty ? s.device! : 'eth0';
                cpuDeviceNames.add(devStr);
                labels[s.num] = 'CPU ($devStr)';
              } else if (s.role == 'wan') {
                wanSet.add(s.num);
                orderMap[s.num] = s.index;
                labels[s.num] =
                    (roleCounts['wan'] ?? 0) > 1 ? 'WAN $pnum' : 'WAN';
                pnum++;
              } else {
                // LAN or other
                final upper = s.role.toUpperCase();
                orderMap[s.num] = s.index;
                labels[s.num] = (roleCounts[s.role] ?? 0) > 1
                    ? '$upper Port ${s.index}'
                    : upper;
                pnum++;
              }
            }

            final swKey = swName.toString();
            boardPortLabels[swKey] = labels;
            boardWanPorts[swKey] = wanSet;
            boardCpuPorts[swKey] = cpuSet;
            boardPortOrder[swKey] = orderMap;
          }
        });
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

            final swLabels = boardPortLabels[switchDev] ??
                (boardPortLabels.isNotEmpty
                    ? boardPortLabels.values.first
                    : null);
            final swWan = boardWanPorts[switchDev] ??
                (boardWanPorts.isNotEmpty ? boardWanPorts.values.first : null);
            final swCpu = boardCpuPorts[switchDev] ??
                (boardCpuPorts.isNotEmpty ? boardCpuPorts.values.first : null);
            final swOrder = boardPortOrder[switchDev] ??
                (boardPortOrder.isNotEmpty ? boardPortOrder.values.first : null);

            final portsList = <TopologyPort>[];
            for (final portToken in rawPorts.split(' ')) {
              if (portToken.trim().isEmpty) continue;
              final isTagged = portToken.endsWith('t');
              final rawNum = portToken.replaceAll(RegExp(r'[^\d]'), '');
              final pIndex = int.tryParse(rawNum);

              final String portName;
              final bool isWan;
              final bool isCpu;
              if (pIndex != null &&
                  swLabels != null &&
                  swLabels.containsKey(pIndex)) {
                portName = swLabels[pIndex]!;
                isWan = swWan?.contains(pIndex) ?? false;
                isCpu = swCpu?.contains(pIndex) ??
                    portName.toLowerCase().contains('cpu');
              } else {
                isCpu = (pIndex != null && swCpu != null && swCpu.contains(pIndex)) ||
                    (pIndex == 0 && isTagged);
                isWan = !isCpu && (pIndex == 0);
                portName = isCpu
                    ? (pIndex == 0 ? 'CPU (eth0)' : 'CPU (Port $rawNum)')
                    : (isWan ? 'WAN (Port $rawNum)' : 'LAN Port $rawNum');
              }

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
                          final spdStr = spd.toString().trim();
                          linkSpeed = RegExp(r'^\d+$').hasMatch(spdStr)
                              ? '${spdStr}M'
                              : spdStr;
                        }
                        break;
                      }
                    }
                  }
                }
              } else if (networkDevices != null) {
                String? devKey;
                if (networkDevices.containsKey(portName)) {
                  devKey = portName;
                } else if (isCpu) {
                  final m = RegExp(r'\(([^)]+)\)').firstMatch(portName);
                  if (m != null && networkDevices.containsKey(m.group(1))) {
                    devKey = m.group(1);
                  }
                }
                if (devKey != null) {
                  final devInfo = networkDevices[devKey];
                  if (devInfo is Map) {
                    final carrier = devInfo['carrier'];
                    final up = devInfo['up'];
                    if (carrier != null) {
                      isUp = carrier == true || carrier == 1 || carrier == '1';
                    } else if (up != null) {
                      isUp = up == true || up == 1 || up == '1';
                    }
                    if (devInfo['speed'] != null) {
                      final spd = devInfo['speed'].toString().trim();
                      if (RegExp(r'^\d+$').hasMatch(spd)) {
                        linkSpeed = '${spd}M';
                      } else {
                        linkSpeed = spd;
                      }
                    }
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
                isCpu: isCpu,
                portIndex: pIndex,
                isUp: isUp,
                linkSpeed: linkSpeed,
              );
              portsList.add(port);
              if (!allPorts.any((ap) => ap.name == portName)) {
                allPorts.add(port);
              }
            }

            if (swOrder != null) {
              portsList.sort((a, b) {
                final orderA = a.portIndex != null
                    ? (swOrder[a.portIndex!] ?? 999)
                    : 999;
                final orderB = b.portIndex != null
                    ? (swOrder[b.portIndex!] ?? 999)
                    : 999;
                return orderA.compareTo(orderB);
              });
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

      // Standalone WAN interface detection (e.g. eth1 on routers where WAN is not part of switch0)
      final wanCandidates = <String>{};

      if (boardJson != null && boardJson['network'] is Map) {
        final netSection = boardJson['network'] as Map;
        for (final wanKey in ['wan', 'wan6']) {
          final wanNet = netSection[wanKey];
          if (wanNet is Map) {
            final dev =
                wanNet['device']?.toString() ?? wanNet['ifname']?.toString();
            if (dev != null && dev.isNotEmpty) {
              for (final d in dev.split(' ')) {
                if (d.trim().isNotEmpty) wanCandidates.add(d.trim());
              }
            }
            final ports = wanNet['ports'];
            if (ports is List) {
              for (final p in ports) {
                if (p != null && p.toString().trim().isNotEmpty) {
                  wanCandidates.add(p.toString().trim());
                }
              }
            }
          }
        }
      }

      uciValues.forEach((key, val) {
        if (val is Map) {
          final type = val['.type']?.toString();
          if (type == 'interface') {
            final ifName = key.toLowerCase();
            if (ifName == 'wan' ||
                ifName == 'wan6' ||
                ifName.startsWith('wan')) {
              final dev =
                  val['device']?.toString() ?? val['ifname']?.toString();
              if (dev != null && dev.isNotEmpty) {
                for (final d in dev.split(' ')) {
                  if (d.trim().isNotEmpty) wanCandidates.add(d.trim());
                }
              }
            }
          }
        }
      });

      if (wanCandidates.isEmpty && networkDevices != null) {
        if (networkDevices.containsKey('wan')) {
          wanCandidates.add('wan');
        } else if (networkDevices.containsKey('eth1')) {
          wanCandidates.add('eth1');
        }
      }

      bool isPhysicalNetdev(String name) {
        final lower = name.toLowerCase();
        if (lower.startsWith('lo') ||
            lower.startsWith('wg') ||
            lower.startsWith('tun') ||
            lower.startsWith('tap') ||
            lower.startsWith('br-') ||
            lower.startsWith('wlan') ||
            lower.startsWith('phy') ||
            lower.startsWith('/dev/')) {
          return false;
        }
        return true;
      }

      for (final rawWanDev in wanCandidates) {
        if (!isPhysicalNetdev(rawWanDev)) continue;

        final baseDev =
            rawWanDev.contains('.') ? rawWanDev.split('.').first : rawWanDev;

        // If baseDev is the CPU interconnect of the switch (e.g. eth0 in eth0.2), WAN is switch-integrated
        if (cpuDeviceNames.contains(baseDev)) continue;

        // Avoid adding standalone WAN if a physical WAN port is already present
        if (allPorts.any(
          (ap) =>
              ap.name == baseDev ||
              ap.name == 'WAN ($baseDev)' ||
              (ap.isWan && !ap.isCpu),
        )) {
          continue;
        }

        bool isUp = false;
        String? linkSpeed;
        if (networkDevices != null) {
          Map? devInfo;
          if (networkDevices.containsKey(baseDev) &&
              networkDevices[baseDev] is Map) {
            devInfo = networkDevices[baseDev] as Map;
          } else if (networkDevices.containsKey(rawWanDev) &&
              networkDevices[rawWanDev] is Map) {
            devInfo = networkDevices[rawWanDev] as Map;
          } else if (networkDevices.containsKey('wan') &&
              networkDevices['wan'] is Map) {
            devInfo = networkDevices['wan'] as Map;
          }

          if (devInfo != null) {
            final carrier = devInfo['carrier'];
            final up = devInfo['up'];
            if (carrier != null) {
              isUp = carrier == true || carrier == 1 || carrier == '1';
            } else if (up != null) {
              isUp = up == true || up == 1 || up == '1';
            }
            if (devInfo['speed'] != null) {
              final spd = devInfo['speed'].toString().trim();
              if (RegExp(r'^\d+$').hasMatch(spd)) {
                linkSpeed = '${spd}M';
              } else {
                linkSpeed = spd;
              }
            }
          }
        } else {
          isUp = true;
        }

        final portDisplayName =
            baseDev.toLowerCase() == 'wan' ? 'WAN' : 'WAN ($baseDev)';
        final wanPort = TopologyPort(
          name: portDisplayName,
          isTagged: false,
          isWan: true,
          isCpu: false,
          portIndex: 0,
          isUp: isUp,
          linkSpeed: linkSpeed,
        );

        allPorts.add(wanPort);
        vlans.add(
          VlanConfig(
            vid: 0,
            name: 'WAN Interface ($baseDev)',
            ports: [wanPort],
            device: baseDev,
          ),
        );
      }

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
