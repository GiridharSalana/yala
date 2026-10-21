// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

/// Detected capabilities and topological properties of the probed router.
///
/// Prevents false assumptions about tools, uplinks, or network protocols.
class DiagnosticCapabilities {
  final bool hasManagementApi;
  final bool hasFileExec;
  final bool hasUci;
  final bool hasPing;
  final bool hasPing6;
  final bool hasNslookup;
  final bool hasIpRoute;
  final bool hasIpNeigh;
  final bool hasWgetOrCurl;
  final bool isIpv6Configured;
  final String? activeWanInterface;
  final String? wanProtocol;
  final String? wanDevice;
  final List<String> ipv4Gateways;
  final List<String> ipv6Gateways;
  final List<String> configuredDnsServers;
  final String firewallBackend;
  final bool isLanToWanForwardingAllowed;
  final bool isWanMasqueradingEnabled;

  const DiagnosticCapabilities({
    this.hasManagementApi = false,
    this.hasFileExec = false,
    this.hasUci = false,
    this.hasPing = false,
    this.hasPing6 = false,
    this.hasNslookup = false,
    this.hasIpRoute = false,
    this.hasIpNeigh = false,
    this.hasWgetOrCurl = false,
    this.isIpv6Configured = false,
    this.activeWanInterface,
    this.wanProtocol,
    this.wanDevice,
    this.ipv4Gateways = const [],
    this.ipv6Gateways = const [],
    this.configuredDnsServers = const [],
    this.firewallBackend = 'fw4',
    this.isLanToWanForwardingAllowed = true,
    this.isWanMasqueradingEnabled = true,
  });

  DiagnosticCapabilities copyWith({
    bool? hasManagementApi,
    bool? hasFileExec,
    bool? hasUci,
    bool? hasPing,
    bool? hasPing6,
    bool? hasNslookup,
    bool? hasIpRoute,
    bool? hasIpNeigh,
    bool? hasWgetOrCurl,
    bool? isIpv6Configured,
    String? activeWanInterface,
    String? wanProtocol,
    String? wanDevice,
    List<String>? ipv4Gateways,
    List<String>? ipv6Gateways,
    List<String>? configuredDnsServers,
    String? firewallBackend,
    bool? isLanToWanForwardingAllowed,
    bool? isWanMasqueradingEnabled,
  }) {
    return DiagnosticCapabilities(
      hasManagementApi: hasManagementApi ?? this.hasManagementApi,
      hasFileExec: hasFileExec ?? this.hasFileExec,
      hasUci: hasUci ?? this.hasUci,
      hasPing: hasPing ?? this.hasPing,
      hasPing6: hasPing6 ?? this.hasPing6,
      hasNslookup: hasNslookup ?? this.hasNslookup,
      hasIpRoute: hasIpRoute ?? this.hasIpRoute,
      hasIpNeigh: hasIpNeigh ?? this.hasIpNeigh,
      hasWgetOrCurl: hasWgetOrCurl ?? this.hasWgetOrCurl,
      isIpv6Configured: isIpv6Configured ?? this.isIpv6Configured,
      activeWanInterface: activeWanInterface ?? this.activeWanInterface,
      wanProtocol: wanProtocol ?? this.wanProtocol,
      wanDevice: wanDevice ?? this.wanDevice,
      ipv4Gateways: ipv4Gateways ?? this.ipv4Gateways,
      ipv6Gateways: ipv6Gateways ?? this.ipv6Gateways,
      configuredDnsServers: configuredDnsServers ?? this.configuredDnsServers,
      firewallBackend: firewallBackend ?? this.firewallBackend,
      isLanToWanForwardingAllowed:
          isLanToWanForwardingAllowed ?? this.isLanToWanForwardingAllowed,
      isWanMasqueradingEnabled:
          isWanMasqueradingEnabled ?? this.isWanMasqueradingEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'hasManagementApi': hasManagementApi,
    'hasFileExec': hasFileExec,
    'hasUci': hasUci,
    'hasPing': hasPing,
    'hasPing6': hasPing6,
    'hasNslookup': hasNslookup,
    'hasIpRoute': hasIpRoute,
    'hasIpNeigh': hasIpNeigh,
    'hasWgetOrCurl': hasWgetOrCurl,
    'isIpv6Configured': isIpv6Configured,
    if (activeWanInterface != null) 'activeWanInterface': activeWanInterface,
    if (wanProtocol != null) 'wanProtocol': wanProtocol,
    if (wanDevice != null) 'wanDevice': wanDevice,
    'ipv4Gateways': ipv4Gateways,
    'ipv6Gateways': ipv6Gateways,
    'configuredDnsServers': configuredDnsServers,
    'firewallBackend': firewallBackend,
    'isLanToWanForwardingAllowed': isLanToWanForwardingAllowed,
    'isWanMasqueradingEnabled': isWanMasqueradingEnabled,
  };
}
