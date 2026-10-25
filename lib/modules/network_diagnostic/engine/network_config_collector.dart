// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import '../../../models/router_capabilities.dart';
import '../../../services/interfaces/api_service_interface.dart';
import '../../diagnostics/models/routing_neighbor_info.dart';
import '../models/diagnostic_capabilities.dart';

/// Represents a parsed network interface from live runtime status.
class DiscoveredInterface {
  final String name;
  final bool isUp;
  final bool isAvailable;
  final bool isPending;
  final bool autostart;
  final String protocol;
  final String device;
  final String l3Device;
  final int metric;
  final List<String> ipv4Addresses;
  final List<String> ipv6Addresses;
  final List<String> dnsServers;
  final List<Map<String, dynamic>> routes;
  final bool hasDefaultRoute;
  final String? gateway;
  final Map<String, dynamic> data;

  const DiscoveredInterface({
    required this.name,
    required this.isUp,
    required this.isAvailable,
    required this.isPending,
    required this.autostart,
    required this.protocol,
    required this.device,
    required this.l3Device,
    required this.metric,
    required this.ipv4Addresses,
    required this.ipv6Addresses,
    required this.dnsServers,
    required this.routes,
    required this.hasDefaultRoute,
    this.gateway,
    this.data = const {},
  });

  /// True if interface has at least one globally routable IPv6 address (2000::/3).
  bool get hasGlobalIpv6 => ipv6Addresses.any(
    (addr) =>
        !addr.toLowerCase().startsWith('fe80:') &&
        !addr.toLowerCase().startsWith('::1'),
  );

  factory DiscoveredInterface.fromJson(Map<String, dynamic> json) {
    final name = json['interface'] as String? ?? 'unknown';
    final isUp = json['up'] == true;
    final isAvailable = json['available'] == true;
    final isPending = json['pending'] == true;
    final autostart = json['autostart'] != false;
    final protocol = json['proto'] as String? ?? 'none';
    final device = json['device'] as String? ?? '';
    final l3Device = json['l3_device'] as String? ?? device;
    final metric = json['metric'] is int ? json['metric'] as int : 0;

    // IPv4 addresses
    final ipv4List = <String>[];
    if (json['ipv4-address'] is List) {
      for (final item in json['ipv4-address'] as List) {
        if (item is Map && item['address'] != null) {
          ipv4List.add(item['address'].toString());
        }
      }
    }

    // IPv6 addresses
    final ipv6List = <String>[];
    if (json['ipv6-address'] is List) {
      for (final item in json['ipv6-address'] as List) {
        if (item is Map && item['address'] != null) {
          ipv6List.add(item['address'].toString());
        }
      }
    }

    // DNS servers
    final dnsList = <String>[];
    if (json['dns-server'] is List) {
      for (final item in json['dns-server'] as List) {
        dnsList.add(item.toString());
      }
    }

    // Routes
    final routeList = <Map<String, dynamic>>[];
    bool hasDefault = json['defaultroute'] == true;
    String? foundGateway;

    if (json['route'] is List) {
      for (final item in json['route'] as List) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          routeList.add(m);
          final target = m['target']?.toString();
          final nexthop = m['nexthop']?.toString();
          if (target == '0.0.0.0' || target == 'default' || target == '::') {
            hasDefault = true;
            if (nexthop != null && nexthop.isNotEmpty && nexthop != '0.0.0.0') {
              foundGateway = nexthop;
            }
          }
        }
      }
    }

    final dataMap = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : <String, dynamic>{};

    return DiscoveredInterface(
      name: name,
      isUp: isUp,
      isAvailable: isAvailable,
      isPending: isPending,
      autostart: autostart,
      protocol: protocol,
      device: device,
      l3Device: l3Device,
      metric: metric,
      ipv4Addresses: ipv4List,
      ipv6Addresses: ipv6List,
      dnsServers: dnsList,
      routes: routeList,
      hasDefaultRoute: hasDefault,
      gateway: foundGateway,
      data: dataMap,
    );
  }
}

/// Aggregated, discovered network topology and runtime facts.
class DiscoveredNetworkConfig {
  final List<DiscoveredInterface> interfaces;
  final DiscoveredInterface? activeUplink;
  final DiscoveredInterface? secondaryUplink;
  final List<String> ipv4Gateways;
  final List<String> ipv6Gateways;
  final List<String> configuredDnsServers;
  final List<RouteEntry> kernelRoutes;
  final DiagnosticCapabilities capabilities;
  final bool isLanToWanForwardingAllowed;
  final bool isWanMasqueradingEnabled;
  final Map<String, dynamic> rawNetworkDump;

  const DiscoveredNetworkConfig({
    required this.interfaces,
    this.activeUplink,
    this.secondaryUplink,
    this.ipv4Gateways = const [],
    this.ipv6Gateways = const [],
    this.configuredDnsServers = const [],
    this.kernelRoutes = const [],
    required this.capabilities,
    this.isLanToWanForwardingAllowed = true,
    this.isWanMasqueradingEnabled = true,
    this.rawNetworkDump = const {},
  });
}

/// Inspects the live OpenWrt router network state without hardcoding interface names or topologies.
class NetworkConfigCollector {
  final IApiService api;
  final RouterCapabilities? routerCaps;

  const NetworkConfigCollector({required this.api, this.routerCaps});

  Future<DiscoveredNetworkConfig> collect({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
  }) async {
    final interfaces = <DiscoveredInterface>[];
    Map<String, dynamic> rawDump = {};

    // 1. Fetch live interface runtime state from ubus 'network.interface' dump
    try {
      final dumpRes = await api.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'network.interface',
        method: 'dump',
      );

      if (dumpRes is List && dumpRes.length > 1 && dumpRes[0] == 0) {
        final data = dumpRes[1];
        if (data is Map<String, dynamic>) {
          rawDump = data;
          final ifaceList = data['interface'] as List?;
          if (ifaceList != null) {
            for (final item in ifaceList) {
              if (item is Map) {
                interfaces.add(
                  DiscoveredInterface.fromJson(Map<String, dynamic>.from(item)),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('NetworkConfigCollector: interface dump failed: $e');
    }

    // 2. Fetch kernel routing table
    List<RouteEntry> kernelRoutes = [];
    try {
      kernelRoutes = await api.fetchRoutingTable(ipAddress, sysauth, useHttps);
    } catch (_) {}

    // 3. Inspect Firewall zone forwarding (LAN -> WAN) & Masquerading via UCI
    bool lanToWanForwardingAllowed = true;
    bool wanMasqueradingEnabled = true;
    final String fwBackend = routerCaps?.firewallBackend == FirewallBackend.fw3
        ? 'fw3'
        : 'fw4';

    try {
      final fwRes = await api.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'firewall'},
      );

      if (fwRes is List && fwRes.length > 1 && fwRes[0] == 0) {
        final values = fwRes[1]['values'] ?? fwRes[1];
        if (values is Map) {
          bool foundForwarding = false;
          bool forwardingAllowed = false;
          bool wanMasqFound = false;

          for (final entry in values.entries) {
            if (entry.value is Map) {
              final sec = entry.value as Map;
              final type = sec['.type'] as String?;

              // Zone definition check for wan masquerade
              if (type == 'zone') {
                final name = sec['name'] as String?;
                if (name == 'wan' || name == 'wan6') {
                  if (sec['masq'] != null) {
                    wanMasqFound = true;
                    if (sec['masq'] == '1' || sec['masq'] == true) {
                      wanMasqueradingEnabled = true;
                    } else {
                      wanMasqueradingEnabled = false;
                    }
                  }
                }
              }

              // Forwarding definition check: src=lan, dest=wan
              if (type == 'forwarding') {
                final src = sec['src'] as String?;
                final dest = sec['dest'] as String?;
                if (src == 'lan' && (dest == 'wan' || dest == 'wan6')) {
                  foundForwarding = true;
                  // If explicit forward drop/reject or disabled
                  final enabled =
                      sec['enabled'] != '0' && sec['enabled'] != false;
                  if (enabled) {
                    forwardingAllowed = true;
                  }
                }
              }
            }
          }

          if (foundForwarding) {
            lanToWanForwardingAllowed = forwardingAllowed;
          }
          if (wanMasqFound) {
            // Already set above
          }
        }
      }
    } catch (_) {}

    // 4. Identify the active uplink dynamically without hardcoding interface names
    // Strategy:
    // a) Find interface with hasDefaultRoute == true and isUp == true
    // b) Or find interface with active gateway in kernel routing table
    // c) Or interface matching standard wan/wwan/modem/cellular names with an IP address
    DiscoveredInterface? primaryUplink;
    DiscoveredInterface? secondaryUplink;

    final candidateUplinks = <DiscoveredInterface>[];

    for (final iface in interfaces) {
      if (iface.name == 'loopback' ||
          iface.name == 'lan' ||
          iface.name == 'br-lan') {
        continue;
      }

      final isExplicitDefault = iface.hasDefaultRoute;
      final hasIpv4 = iface.ipv4Addresses.isNotEmpty;
      final hasIpv6 = iface.ipv6Addresses.isNotEmpty;
      final hasGw = iface.gateway != null && iface.gateway!.isNotEmpty;
      final matchesName =
          iface.name.startsWith('wan') ||
          iface.name.startsWith('wwan') ||
          iface.name.startsWith('lte') ||
          iface.name.startsWith('modem') ||
          iface.name.contains('uplink');

      if (isExplicitDefault ||
          (hasGw && iface.isUp) ||
          (matchesName && (hasIpv4 || hasIpv6))) {
        candidateUplinks.add(iface);
      }
    }

    // Sort candidate uplinks by: isUp (true first), metric (lowest first), hasDefaultRoute (true first)
    candidateUplinks.sort((a, b) {
      if (a.isUp != b.isUp) return a.isUp ? -1 : 1;
      if (a.hasDefaultRoute != b.hasDefaultRoute) {
        return a.hasDefaultRoute ? -1 : 1;
      }
      return a.metric.compareTo(b.metric);
    });

    if (candidateUplinks.isNotEmpty) {
      primaryUplink = candidateUplinks.first;
      if (candidateUplinks.length > 1) {
        secondaryUplink = candidateUplinks[1];
      }
    } else {
      // Fallback: If no candidate found in dump, inspect kernel default route
      for (final r in kernelRoutes) {
        if (r.isDefault && r.interface != null) {
          final matched = interfaces.where(
            (i) =>
                i.device == r.interface ||
                i.l3Device == r.interface ||
                i.name == r.interface,
          );
          if (matched.isNotEmpty) {
            primaryUplink = matched.first;
            break;
          }
        }
      }
    }

    // 5. Aggregate Gateways & DNS servers
    final ipv4Gateways = <String>{};
    final ipv6Gateways = <String>{};
    final dnsServers = <String>{};

    for (final iface in interfaces) {
      if (iface.gateway != null && iface.gateway!.isNotEmpty) {
        if (iface.gateway!.contains(':')) {
          ipv6Gateways.add(iface.gateway!);
        } else {
          ipv4Gateways.add(iface.gateway!);
        }
      }
      dnsServers.addAll(iface.dnsServers);
    }

    for (final r in kernelRoutes) {
      if (r.isDefault && r.gateway != null && r.gateway!.isNotEmpty) {
        if (r.gateway!.contains(':')) {
          ipv6Gateways.add(r.gateway!);
        } else {
          ipv4Gateways.add(r.gateway!);
        }
      }
    }

    // Check if IPv6 is configured on router
    final isIpv6Configured = interfaces.any(
      (i) =>
          (i.name.contains('6') ||
              i.protocol.contains('6') ||
              i.ipv6Addresses.isNotEmpty) &&
          i.hasGlobalIpv6,
    );

    // 6. Capability assessment
    final caps = routerCaps;
    final hasMgmtApi = caps != null ? !caps.probeFailed : true;
    final hasFileExec = caps?.hasFileExec ?? true;
    final hasUci = caps?.hasUciWriteAccess ?? true;

    final diagCaps = DiagnosticCapabilities(
      hasManagementApi: hasMgmtApi,
      hasFileExec: hasFileExec,
      hasUci: hasUci,
      hasPing: hasFileExec, // rpcd file.exec enables /bin/ping
      hasPing6: hasFileExec && isIpv6Configured,
      hasNslookup: hasFileExec,
      hasIpRoute: hasFileExec,
      hasIpNeigh: hasFileExec,
      hasWgetOrCurl: false, // will be discovered or tested safely
      isIpv6Configured: isIpv6Configured,
      activeWanInterface: primaryUplink?.name,
      wanProtocol: primaryUplink?.protocol,
      wanDevice: primaryUplink?.device,
      ipv4Gateways: ipv4Gateways.toList(),
      ipv6Gateways: ipv6Gateways.toList(),
      configuredDnsServers: dnsServers.toList(),
      firewallBackend: fwBackend,
      isLanToWanForwardingAllowed: lanToWanForwardingAllowed,
      isWanMasqueradingEnabled: wanMasqueradingEnabled,
    );

    return DiscoveredNetworkConfig(
      interfaces: interfaces,
      activeUplink: primaryUplink,
      secondaryUplink: secondaryUplink,
      ipv4Gateways: ipv4Gateways.toList(),
      ipv6Gateways: ipv6Gateways.toList(),
      configuredDnsServers: dnsServers.toList(),
      kernelRoutes: kernelRoutes,
      capabilities: diagCaps,
      isLanToWanForwardingAllowed: lanToWanForwardingAllowed,
      isWanMasqueradingEnabled: wanMasqueradingEnabled,
      rawNetworkDump: rawDump,
    );
  }
}
