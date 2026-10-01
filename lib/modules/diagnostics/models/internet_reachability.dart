// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

enum ReachabilityStatus { online, partial, offline, testing, unknown }

class InternetReachability {
  final ReachabilityStatus status;
  final bool isReachable;
  final String? wanInterface;
  final String? wanIp;
  final String? gatewayIp;
  final bool gatewayReachable;
  final double? gatewayLatencyMs;
  final bool publicDnsReachable;
  final double? publicDnsLatencyMs;
  final bool dnsResolving;
  final String statusMessage;
  final DateTime testedAt;

  const InternetReachability({
    required this.status,
    required this.isReachable,
    this.wanInterface,
    this.wanIp,
    this.gatewayIp,
    this.gatewayReachable = false,
    this.gatewayLatencyMs,
    this.publicDnsReachable = false,
    this.publicDnsLatencyMs,
    this.dnsResolving = false,
    required this.statusMessage,
    required this.testedAt,
  });

  factory InternetReachability.unknown() => InternetReachability(
    status: ReachabilityStatus.unknown,
    isReachable: false,
    statusMessage: 'Not tested yet',
    testedAt: DateTime.now(),
  );

  factory InternetReachability.testing() => InternetReachability(
    status: ReachabilityStatus.testing,
    isReachable: false,
    statusMessage: 'Testing connection...',
    testedAt: DateTime.now(),
  );

  factory InternetReachability.offline({
    String? reason,
    String? gatewayIp,
    String? wanInterface,
  }) => InternetReachability(
    status: ReachabilityStatus.offline,
    isReachable: false,
    wanInterface: wanInterface,
    gatewayIp: gatewayIp,
    statusMessage: reason ?? 'Internet unreachable',
    testedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'isReachable': isReachable,
    'wanInterface': wanInterface,
    'wanIp': wanIp,
    'gatewayIp': gatewayIp,
    'gatewayReachable': gatewayReachable,
    'gatewayLatencyMs': gatewayLatencyMs,
    'publicDnsReachable': publicDnsReachable,
    'publicDnsLatencyMs': publicDnsLatencyMs,
    'dnsResolving': dnsResolving,
    'statusMessage': statusMessage,
    'testedAt': testedAt.toIso8601String(),
  };

  factory InternetReachability.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'unknown';
    final status = ReachabilityStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => ReachabilityStatus.unknown,
    );

    return InternetReachability(
      status: status,
      isReachable: json['isReachable'] as bool? ?? false,
      wanInterface: json['wanInterface'] as String?,
      wanIp: json['wanIp'] as String?,
      gatewayIp: json['gatewayIp'] as String?,
      gatewayReachable: json['gatewayReachable'] as bool? ?? false,
      gatewayLatencyMs: (json['gatewayLatencyMs'] as num?)?.toDouble(),
      publicDnsReachable: json['publicDnsReachable'] as bool? ?? false,
      publicDnsLatencyMs: (json['publicDnsLatencyMs'] as num?)?.toDouble(),
      dnsResolving: json['dnsResolving'] as bool? ?? false,
      statusMessage: json['statusMessage'] as String? ?? '',
      testedAt:
          DateTime.tryParse(json['testedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
