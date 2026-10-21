// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Network transport protocol used for DNS latency measurement.
enum DnsProtocol {
  /// Direct DNS query over UDP port 53 (RFC 1035).
  udpPort53,

  /// Direct DNS query over TCP port 53.
  tcpPort53,

  /// DNS-over-HTTPS (RFC 8484).
  doh,

  /// Router-originated DNS query via LuCI RPC (nslookup binary).
  routerNslookup,
}

extension DnsProtocolX on DnsProtocol {
  String get label {
    switch (this) {
      case DnsProtocol.udpPort53:
        return 'UDP Port 53';
      case DnsProtocol.tcpPort53:
        return 'TCP Port 53';
      case DnsProtocol.doh:
        return 'DNS-over-HTTPS (DoH)';
      case DnsProtocol.routerNslookup:
        return 'Router nslookup RPC';
    }
  }
}

/// Measurement origin / vantage point.
enum DnsVantagePoint {
  /// Measurement originated from the phone/client device running YALA.
  clientDevice,

  /// Measurement originated from the OpenWrt router itself.
  router,
}

extension DnsVantagePointX on DnsVantagePoint {
  String get label {
    switch (this) {
      case DnsVantagePoint.clientDevice:
        return 'Client Device';
      case DnsVantagePoint.router:
        return 'Router';
    }
  }
}

/// Status of an individual DNS provider measurement.
enum DnsBenchmarkStatus {
  /// Not yet tested in current session.
  untested,

  /// Currently collecting query samples.
  testing,

  /// Completed successfully with valid latency samples.
  success,

  /// Completed with some dropped or timed-out query samples.
  partial,

  /// Queries timed out waiting for server response.
  timeout,

  /// Socket connection refused or port unreachable.
  refused,

  /// Destination network or resolver unreachable.
  unreachable,

  /// DNS resolver returned Server Failure (RCODE 2).
  serverError,

  /// Protocol or address family not supported on current network.
  unsupported,

  /// Requires user account credentials or custom profile configuration.
  configRequired,
}

extension DnsBenchmarkStatusX on DnsBenchmarkStatus {
  bool get hasValidLatency =>
      this == DnsBenchmarkStatus.success || this == DnsBenchmarkStatus.partial;

  bool get isRunning => this == DnsBenchmarkStatus.testing;

  String get label {
    switch (this) {
      case DnsBenchmarkStatus.untested:
        return 'Untested';
      case DnsBenchmarkStatus.testing:
        return 'Testing...';
      case DnsBenchmarkStatus.success:
        return 'Success';
      case DnsBenchmarkStatus.partial:
        return 'Partial';
      case DnsBenchmarkStatus.timeout:
        return 'Timeout';
      case DnsBenchmarkStatus.refused:
        return 'Refused';
      case DnsBenchmarkStatus.unreachable:
        return 'Unreachable';
      case DnsBenchmarkStatus.serverError:
        return 'Server Error';
      case DnsBenchmarkStatus.unsupported:
        return 'Unsupported';
      case DnsBenchmarkStatus.configRequired:
        return 'Config Required';
    }
  }
}

/// Discovered DNS configuration of the router.
@immutable
class RouterDnsConfig {
  /// True if the router runs a local forwarding resolver (e.g. dnsmasq, unbound).
  final bool isLocalForwarder;

  /// Local resolver listening endpoint on LAN (e.g. 192.168.1.1:53).
  final String localEndpoint;

  /// Active upstream DNS servers configured for the router / WAN.
  final List<String> upstreamServers;

  /// Discovered active WAN interface name.
  final String? wanInterface;

  /// Whether active upstream servers were verified from runtime interfaces vs UCI.
  final bool isVerified;

  /// Human-readable description of discovered configuration.
  final String details;

  const RouterDnsConfig({
    required this.isLocalForwarder,
    required this.localEndpoint,
    required this.upstreamServers,
    this.wanInterface,
    this.isVerified = false,
    required this.details,
  });

  factory RouterDnsConfig.unknown() {
    return const RouterDnsConfig(
      isLocalForwarder: false,
      localEndpoint: 'Unknown',
      upstreamServers: [],
      isVerified: false,
      details: 'Current router DNS resolver configuration is unknown.',
    );
  }
}

/// Metadata describing a supported DNS provider in the registry.
@immutable
class DnsProviderMetadata {
  /// Stable unique provider identifier (e.g. 'cloudflare', 'quad9').
  final String id;

  /// Official human-readable display name.
  final String name;

  /// Primary IPv4 resolver address.
  final String primaryServer;

  /// Secondary / fallback IPv4 resolver address.
  final String? secondaryServer;

  /// Primary IPv6 resolver address, if available.
  final String? ipv6Server;

  /// Official DoH endpoint template, if available.
  final String? dohUrl;

  /// True if this entry represents the currently connected router's DNS.
  final bool isRouterDns;

  /// True if a user profile or account is required for personalized filtering.
  final bool isCustomConfigRequired;

  /// Description of default test endpoint and capabilities.
  final String description;

  /// Key provider features (e.g. 'Malware blocking', 'Ad blocking', 'Anycast').
  final List<String> features;

  const DnsProviderMetadata({
    required this.id,
    required this.name,
    required this.primaryServer,
    this.secondaryServer,
    this.ipv6Server,
    this.dohUrl,
    this.isRouterDns = false,
    this.isCustomConfigRequired = false,
    required this.description,
    this.features = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'primaryServer': primaryServer,
    'secondaryServer': secondaryServer,
    'ipv6Server': ipv6Server,
    'dohUrl': dohUrl,
    'isRouterDns': isRouterDns,
    'isCustomConfigRequired': isCustomConfigRequired,
    'description': description,
    'features': features,
  };
}

/// Measured benchmark result for a single DNS provider.
@immutable
class DnsBenchmarkResult {
  final DnsProviderMetadata provider;
  final DnsBenchmarkStatus status;
  final double? medianLatencyMs;
  final double? minLatencyMs;
  final double? maxLatencyMs;
  final double? avgLatencyMs;
  final List<double> samples;
  final int totalQueries;
  final int successfulQueries;
  final int failedQueries;
  final String testedEndpoint;
  final DnsProtocol protocol;
  final DnsVantagePoint vantagePoint;
  final String? errorMessage;
  final DateTime? timestamp;
  final RouterDnsConfig? routerDnsConfig;

  const DnsBenchmarkResult({
    required this.provider,
    this.status = DnsBenchmarkStatus.untested,
    this.medianLatencyMs,
    this.minLatencyMs,
    this.maxLatencyMs,
    this.avgLatencyMs,
    this.samples = const [],
    this.totalQueries = 0,
    this.successfulQueries = 0,
    this.failedQueries = 0,
    required this.testedEndpoint,
    this.protocol = DnsProtocol.udpPort53,
    this.vantagePoint = DnsVantagePoint.clientDevice,
    this.errorMessage,
    this.timestamp,
    this.routerDnsConfig,
  });

  DnsBenchmarkResult copyWith({
    DnsBenchmarkStatus? status,
    double? medianLatencyMs,
    double? minLatencyMs,
    double? maxLatencyMs,
    double? avgLatencyMs,
    List<double>? samples,
    int? totalQueries,
    int? successfulQueries,
    int? failedQueries,
    String? testedEndpoint,
    DnsProtocol? protocol,
    DnsVantagePoint? vantagePoint,
    String? errorMessage,
    DateTime? timestamp,
    RouterDnsConfig? routerDnsConfig,
  }) {
    return DnsBenchmarkResult(
      provider: provider,
      status: status ?? this.status,
      medianLatencyMs: medianLatencyMs ?? this.medianLatencyMs,
      minLatencyMs: minLatencyMs ?? this.minLatencyMs,
      maxLatencyMs: maxLatencyMs ?? this.maxLatencyMs,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      samples: samples ?? this.samples,
      totalQueries: totalQueries ?? this.totalQueries,
      successfulQueries: successfulQueries ?? this.successfulQueries,
      failedQueries: failedQueries ?? this.failedQueries,
      testedEndpoint: testedEndpoint ?? this.testedEndpoint,
      protocol: protocol ?? this.protocol,
      vantagePoint: vantagePoint ?? this.vantagePoint,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: timestamp ?? this.timestamp,
      routerDnsConfig: routerDnsConfig ?? this.routerDnsConfig,
    );
  }

  /// Initial sorting: alphabetical by display name (case-insensitive).
  static List<DnsBenchmarkResult> sortAlphabetical(
    List<DnsBenchmarkResult> list,
  ) {
    final copy = List<DnsBenchmarkResult>.from(list);
    copy.sort(
      (a, b) => a.provider.name.toLowerCase().compareTo(
        b.provider.name.toLowerCase(),
      ),
    );
    return copy;
  }

  /// Post-test sorting: ascending by median latency (fastest first).
  ///
  /// - Providers with valid measured latency are sorted lowest to highest.
  /// - Equal latency values use deterministic tie-breaker: provider display name (case-insensitive).
  /// - Providers without valid latency (failed, timeout, untested) are placed after all measured providers,
  ///   sorted deterministically by status index then provider name.
  static List<DnsBenchmarkResult> sortByAscendingLatency(
    List<DnsBenchmarkResult> list,
  ) {
    final copy = List<DnsBenchmarkResult>.from(list);
    copy.sort((a, b) {
      final aHasValid = a.status.hasValidLatency && a.medianLatencyMs != null;
      final bHasValid = b.status.hasValidLatency && b.medianLatencyMs != null;

      if (aHasValid && bHasValid) {
        final diff = a.medianLatencyMs!.compareTo(b.medianLatencyMs!);
        if (diff != 0) return diff;
        return a.provider.name.toLowerCase().compareTo(
          b.provider.name.toLowerCase(),
        );
      }

      if (aHasValid && !bHasValid) return -1;
      if (!aHasValid && bHasValid) return 1;

      // Both unmeasured / failed: deterministic sort by status index, then name
      final statusDiff = a.status.index.compareTo(b.status.index);
      if (statusDiff != 0) return statusDiff;
      return a.provider.name.toLowerCase().compareTo(
        b.provider.name.toLowerCase(),
      );
    });
    return copy;
  }
}
