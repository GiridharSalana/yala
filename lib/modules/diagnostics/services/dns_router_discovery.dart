// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import '../../../services/interfaces/api_service_interface.dart';
import '../models/dns_benchmark_models.dart';

/// Discovers the active DNS resolver configuration of an OpenWrt router
/// using ubus and UCI, distinguishing local forwarding from upstream resolvers.
class DnsRouterDiscovery {
  final IApiService api;

  const DnsRouterDiscovery(this.api);

  Future<RouterDnsConfig> discover({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    Map<String, dynamic>? cachedDashboardData,
  }) async {
    final upstreamServers = <String>{};
    String? wanInterfaceName;
    bool isLocalForwarder = true; // dnsmasq is standard on OpenWrt
    bool isVerified = false;

    // 1. Inspect live WAN / uplink interface DNS via ubus 'network.interface dump'
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
        if (data is Map && data['interface'] is List) {
          final ifaces = data['interface'] as List;
          Map? activeWan;

          // Find active default route interface
          for (final item in ifaces) {
            if (item is Map) {
              final isUp = item['up'] == true;
              final hasDefault = item['defaultroute'] == true;
              final name = item['interface']?.toString() ?? '';
              if (isUp &&
                  (hasDefault ||
                      name.startsWith('wan') ||
                      name.startsWith('wwan'))) {
                activeWan ??= item;
                if (hasDefault) {
                  activeWan = item;
                  break;
                }
              }
            }
          }

          if (activeWan != null) {
            wanInterfaceName = activeWan['interface']?.toString();
            if (activeWan['dns-server'] is List) {
              for (final dns in activeWan['dns-server'] as List) {
                final d = dns?.toString().trim();
                if (d != null && d.isNotEmpty) {
                  upstreamServers.add(d);
                  isVerified = true;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('DnsRouterDiscovery: ubus network.interface dump error: $e');
    }

    // 2. Inspect UCI DHCP & dnsmasq configuration
    final customForwarders = <String>[];
    bool noResolv = false;
    try {
      final dhcpRes = await api.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'dhcp'},
      );

      if (dhcpRes is List && dhcpRes.length > 1 && dhcpRes[0] == 0) {
        final values = dhcpRes[1]['values'] ?? dhcpRes[1];
        if (values is Map) {
          for (final entry in values.entries) {
            if (entry.value is Map) {
              final sec = entry.value as Map;
              if (sec['.type'] == 'dnsmasq') {
                if (sec['port'] == '0' || sec['port'] == 0) {
                  isLocalForwarder = false;
                }
                if (sec['noresolv'] == '1' || sec['noresolv'] == true) {
                  noResolv = true;
                }
                final srv = sec['server'];
                if (srv is List) {
                  for (final s in srv) {
                    final str = s.toString().trim();
                    if (str.isNotEmpty && !str.startsWith('/')) {
                      customForwarders.add(str);
                    }
                  }
                } else if (srv is String &&
                    srv.trim().isNotEmpty &&
                    !srv.trim().startsWith('/')) {
                  customForwarders.add(srv.trim());
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('DnsRouterDiscovery: ubus uci get dhcp error: $e');
    }

    // 3. Fallback to cached dashboard data if available
    if (upstreamServers.isEmpty &&
        customForwarders.isEmpty &&
        cachedDashboardData != null) {
      final rawUciDhcp = cachedDashboardData['uciDhcp'];
      if (rawUciDhcp is Map) {
        final values = rawUciDhcp['values'] ?? rawUciDhcp;
        if (values is Map) {
          for (final entry in values.entries) {
            if (entry.value is Map) {
              final sec = entry.value as Map;
              if (sec['.type'] == 'dnsmasq' && sec['server'] != null) {
                final srv = sec['server'];
                if (srv is List) {
                  for (final s in srv) {
                    final str = s.toString().trim();
                    if (str.isNotEmpty && !str.startsWith('/')) {
                      customForwarders.add(str);
                    }
                  }
                } else if (srv is String &&
                    srv.trim().isNotEmpty &&
                    !srv.trim().startsWith('/')) {
                  customForwarders.add(srv.trim());
                }
              }
            }
          }
        }
      }
    }

    // Determine effective upstreams
    final finalUpstreams = <String>[];
    if (noResolv && customForwarders.isNotEmpty) {
      finalUpstreams.addAll(customForwarders);
    } else {
      finalUpstreams.addAll(customForwarders);
      for (final u in upstreamServers) {
        if (!finalUpstreams.contains(u)) {
          finalUpstreams.add(u);
        }
      }
    }

    final localEndpoint = '$ipAddress:53';
    String details;
    if (isLocalForwarder) {
      if (finalUpstreams.isNotEmpty) {
        details =
            'Local dnsmasq forwarder on $localEndpoint querying: ${finalUpstreams.join(', ')}';
      } else {
        details =
            'Local dnsmasq forwarder on $localEndpoint (ISP assigned upstream on ${wanInterfaceName ?? 'WAN'})';
      }
    } else {
      if (finalUpstreams.isNotEmpty) {
        details = 'Direct upstream DNS: ${finalUpstreams.join(', ')}';
      } else {
        details =
            'Direct upstream DNS (ISP assigned on ${wanInterfaceName ?? 'WAN'})';
      }
    }

    return RouterDnsConfig(
      isLocalForwarder: isLocalForwarder,
      localEndpoint: localEndpoint,
      upstreamServers: finalUpstreams.isNotEmpty
          ? finalUpstreams
          : (wanInterfaceName != null
                ? ['ISP Assigned ($wanInterfaceName)']
                : ['ISP Default']),
      wanInterface: wanInterfaceName,
      isVerified: isVerified || customForwarders.isNotEmpty,
      details: details,
    );
  }
}
