// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

/// Network layer and architectural domain being evaluated.
enum DiagnosticScope {
  managementApi,
  routerUplink,
  addressing,
  routing,
  dns,
  ipv4,
  ipv6,
  pathMtu,
  clientForwarding;

  String get displayName {
    switch (this) {
      case DiagnosticScope.managementApi:
        return 'Router Management & API';
      case DiagnosticScope.routerUplink:
        return 'WAN Interface & Uplink';
      case DiagnosticScope.addressing:
        return 'IP Addressing & Gateway';
      case DiagnosticScope.routing:
        return 'Routing & Default Gateway';
      case DiagnosticScope.dns:
        return 'DNS Resolution';
      case DiagnosticScope.ipv4:
        return 'IPv4 Internet Reachability';
      case DiagnosticScope.ipv6:
        return 'IPv6 Internet Reachability';
      case DiagnosticScope.pathMtu:
        return 'MTU & Path Fragmentation';
      case DiagnosticScope.clientForwarding:
        return 'LAN Forwarding & NAT Policy';
    }
  }
}
