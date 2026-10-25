// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:yala/utils/client_naming_helper.dart';

/// Immutable model representing the internet access policy for a network device.
///
/// Follows the approved hierarchy:
/// ```text
/// Internet Access
/// ├── Allowed
/// │   ├── IPv4 state applies
/// │   └── IPv6 state applies
/// └── Blocked
///     ├── IPv4 = effectively blocked
///     └── IPv6 = effectively blocked
/// ```
///
/// If global [internetAccess] is false, both [effectiveIpv4Access] and
/// [effectiveIpv6Access] evaluate to false regardless of their raw values.
///
/// Scheduling in this milestone is strictly limited to:
/// - Indefinite ("Always") when [scheduleExpiry] is null.
/// - One-shot temporary ("Until date/time") when [scheduleExpiry] is non-null.
@immutable
class NetworkAccessPolicy {
  final String targetMac;
  final bool internetAccess;
  final bool ipv4Access;
  final bool ipv6Access;
  final DateTime? scheduleExpiry;

  const NetworkAccessPolicy({
    required this.targetMac,
    this.internetAccess = true,
    this.ipv4Access = true,
    this.ipv6Access = true,
    this.scheduleExpiry,
  });

  /// Factory creating an unrestricted policy (full internet access on IPv4 and IPv6).
  factory NetworkAccessPolicy.unrestricted(String targetMac) {
    return NetworkAccessPolicy(
      targetMac: ClientNamingHelper.normalizeMac(targetMac),
      internetAccess: true,
      ipv4Access: true,
      ipv6Access: true,
    );
  }

  /// Factory creating a fully blocked policy (all internet access suspended).
  factory NetworkAccessPolicy.blocked(
    String targetMac, {
    DateTime? scheduleExpiry,
  }) {
    return NetworkAccessPolicy(
      targetMac: ClientNamingHelper.normalizeMac(targetMac),
      internetAccess: false,
      ipv4Access: false,
      ipv6Access: false,
      scheduleExpiry: scheduleExpiry,
    );
  }

  /// Whether a temporary one-shot schedule has passed.
  bool get isExpired {
    if (scheduleExpiry == null) return false;
    return DateTime.now().isAfter(scheduleExpiry!);
  }

  /// Whether the policy applies indefinitely (no schedule expiry configured).
  bool get isIndefinite => scheduleExpiry == null;

  /// Effective global Internet access state.
  ///
  /// If [scheduleExpiry] is configured and has passed, effective access reverts to allowed.
  bool get effectiveInternetAccess {
    if (!internetAccess && isExpired) return true;
    return internetAccess;
  }

  /// Effective IPv4 Internet access state.
  ///
  /// Unconditionally returns false if [effectiveInternetAccess] is false (master override).
  bool get effectiveIpv4Access {
    if (!effectiveInternetAccess) return false;
    if (!ipv4Access && isExpired) return true;
    return ipv4Access;
  }

  /// Effective IPv6 Internet access state.
  ///
  /// Unconditionally returns false if [effectiveInternetAccess] is false (master override).
  bool get effectiveIpv6Access {
    if (!effectiveInternetAccess) return false;
    if (!ipv6Access && isExpired) return true;
    return ipv6Access;
  }

  /// Returns true if this device is effectively blocked either globally or across both IPv4 and IPv6.
  bool get isEffectivelyBlocked =>
      !effectiveInternetAccess ||
      (!effectiveIpv4Access && !effectiveIpv6Access);

  /// Returns true if IPv4 is specifically blocked while IPv6 remains allowed.
  bool get isIpv4OnlyBlocked =>
      effectiveInternetAccess && !effectiveIpv4Access && effectiveIpv6Access;

  /// Returns true if IPv6 is specifically blocked while IPv4 remains allowed.
  bool get isIpv6OnlyBlocked =>
      effectiveInternetAccess && effectiveIpv4Access && !effectiveIpv6Access;

  /// Returns true if any network access restriction is in effect (global, IPv4, or IPv6).
  bool get hasAnyRestriction =>
      !effectiveInternetAccess || !effectiveIpv4Access || !effectiveIpv6Access;

  /// Creates a copy of this policy with specified fields replaced.
  NetworkAccessPolicy copyWith({
    String? targetMac,
    bool? internetAccess,
    bool? ipv4Access,
    bool? ipv6Access,
    DateTime? scheduleExpiry,
    bool clearScheduleExpiry = false,
  }) {
    return NetworkAccessPolicy(
      targetMac: targetMac ?? this.targetMac,
      internetAccess: internetAccess ?? this.internetAccess,
      ipv4Access: ipv4Access ?? this.ipv4Access,
      ipv6Access: ipv6Access ?? this.ipv6Access,
      scheduleExpiry: clearScheduleExpiry
          ? null
          : (scheduleExpiry ?? this.scheduleExpiry),
    );
  }

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'targetMac': ClientNamingHelper.normalizeMac(targetMac),
      'internetAccess': internetAccess,
      'ipv4Access': ipv4Access,
      'ipv6Access': ipv6Access,
      if (scheduleExpiry != null)
        'scheduleExpiry': scheduleExpiry!.toIso8601String(),
    };
  }

  /// Deserializes from a JSON map.
  factory NetworkAccessPolicy.fromJson(Map<String, dynamic> json) {
    return NetworkAccessPolicy(
      targetMac: ClientNamingHelper.normalizeMac(
        json['targetMac']?.toString() ?? '',
      ),
      internetAccess: json['internetAccess'] as bool? ?? true,
      ipv4Access: json['ipv4Access'] as bool? ?? true,
      ipv6Access: json['ipv6Access'] as bool? ?? true,
      scheduleExpiry: json['scheduleExpiry'] != null
          ? DateTime.tryParse(json['scheduleExpiry'].toString())
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NetworkAccessPolicy &&
        ClientNamingHelper.normalizeMac(other.targetMac) ==
            ClientNamingHelper.normalizeMac(targetMac) &&
        other.internetAccess == internetAccess &&
        other.ipv4Access == ipv4Access &&
        other.ipv6Access == ipv6Access &&
        other.scheduleExpiry == scheduleExpiry;
  }

  @override
  int get hashCode => Object.hash(
    ClientNamingHelper.normalizeMac(targetMac),
    internetAccess,
    ipv4Access,
    ipv6Access,
    scheduleExpiry,
  );

  @override
  String toString() {
    return 'NetworkAccessPolicy(targetMac: $targetMac, internetAccess: $internetAccess, '
        'ipv4Access: $ipv4Access, ipv6Access: $ipv6Access, '
        'effectiveIpv4: $effectiveIpv4Access, effectiveIpv6: $effectiveIpv6Access, '
        'scheduleExpiry: $scheduleExpiry)';
  }
}
