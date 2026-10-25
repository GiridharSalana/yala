// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/network_access_policy.dart';

void main() {
  group('NetworkAccessPolicy Model Unit Tests', () {
    test('Default policy allows all access and initializes cleanly', () {
      final policy = NetworkAccessPolicy.unrestricted('aa:bb:cc:dd:ee:ff');
      expect(policy.targetMac, equals('AA:BB:CC:DD:EE:FF'));
      expect(policy.internetAccess, isTrue);
      expect(policy.ipv4Access, isTrue);
      expect(policy.ipv6Access, isTrue);
      expect(policy.scheduleExpiry, isNull);
      expect(policy.effectiveIpv4Access, isTrue);
      expect(policy.effectiveIpv6Access, isTrue);
      expect(policy.isEffectivelyBlocked, isFalse);
      expect(policy.isExpired, isFalse);
      expect(policy.isIndefinite, isTrue);
    });

    test(
      'Global Internet block overrides family-specific controls (Hierarchy rule)',
      () {
        // Global blocked, family controls set to true
        const blockedPolicy = NetworkAccessPolicy(
          targetMac: '11:22:33:44:55:66',
          internetAccess: false,
          ipv4Access: true,
          ipv6Access: true,
        );

        expect(blockedPolicy.internetAccess, isFalse);
        expect(blockedPolicy.ipv4Access, isTrue);
        expect(blockedPolicy.ipv6Access, isTrue);
        // Effective values MUST be false because internetAccess is false
        expect(blockedPolicy.effectiveIpv4Access, isFalse);
        expect(blockedPolicy.effectiveIpv6Access, isFalse);
        expect(blockedPolicy.isEffectivelyBlocked, isTrue);
      },
    );

    test(
      'IPv4-only blocking leaves IPv6 allowed if global internet is allowed',
      () {
        const ipv4Blocked = NetworkAccessPolicy(
          targetMac: '11:22:33:44:55:66',
          internetAccess: true,
          ipv4Access: false,
          ipv6Access: true,
        );

        expect(ipv4Blocked.internetAccess, isTrue);
        expect(ipv4Blocked.effectiveIpv4Access, isFalse);
        expect(ipv4Blocked.effectiveIpv6Access, isTrue);
        expect(ipv4Blocked.isIpv4OnlyBlocked, isTrue);
        expect(ipv4Blocked.isIpv6OnlyBlocked, isFalse);
      },
    );

    test(
      'IPv6-only blocking leaves IPv4 allowed if global internet is allowed',
      () {
        const ipv6Blocked = NetworkAccessPolicy(
          targetMac: '11:22:33:44:55:66',
          internetAccess: true,
          ipv4Access: true,
          ipv6Access: false,
        );

        expect(ipv6Blocked.internetAccess, isTrue);
        expect(ipv6Blocked.effectiveIpv4Access, isTrue);
        expect(ipv6Blocked.effectiveIpv6Access, isFalse);
        expect(ipv6Blocked.isIpv4OnlyBlocked, isFalse);
        expect(ipv6Blocked.isIpv6OnlyBlocked, isTrue);
      },
    );

    test(
      'One-shot scheduleExpiry checks correctly and reverts effective access on expiry',
      () {
        final pastDate = DateTime.now().subtract(const Duration(hours: 1));
        final futureDate = DateTime.now().add(const Duration(hours: 2));

        final expiredPolicy = NetworkAccessPolicy(
          targetMac: '11:22:33:44:55:66',
          internetAccess: false,
          scheduleExpiry: pastDate,
        );
        expect(expiredPolicy.isExpired, isTrue);
        expect(expiredPolicy.isIndefinite, isFalse);
        // On expiry, effective internet access reverts to allowed
        expect(expiredPolicy.effectiveInternetAccess, isTrue);
        expect(expiredPolicy.isEffectivelyBlocked, isFalse);

        final activePolicy = NetworkAccessPolicy(
          targetMac: '11:22:33:44:55:66',
          internetAccess: false,
          scheduleExpiry: futureDate,
        );
        expect(activePolicy.isExpired, isFalse);
        expect(activePolicy.effectiveInternetAccess, isFalse);
        expect(activePolicy.isEffectivelyBlocked, isTrue);
      },
    );

    test(
      'JSON serialization and deserialization roundtrip works seamlessly',
      () {
        final expiry = DateTime.parse('2026-12-31T23:59:59.000Z');
        final original = NetworkAccessPolicy(
          targetMac: 'AA:BB:CC:11:22:33',
          internetAccess: false,
          ipv4Access: false,
          ipv6Access: true,
          scheduleExpiry: expiry,
        );

        final json = original.toJson();
        expect(json['targetMac'], equals('AA:BB:CC:11:22:33'));
        expect(json['internetAccess'], isFalse);
        expect(json['ipv4Access'], isFalse);
        expect(json['ipv6Access'], isTrue);
        expect(json['scheduleExpiry'], equals(expiry.toIso8601String()));

        final recovered = NetworkAccessPolicy.fromJson(json);
        expect(recovered, equals(original));
        expect(recovered.hashCode, equals(original.hashCode));
        expect(recovered.targetMac, equals('AA:BB:CC:11:22:33'));
        expect(recovered.scheduleExpiry, equals(expiry));
      },
    );

    test('copyWith produces updated immutable copy with preserved fields', () {
      const policy = NetworkAccessPolicy(
        targetMac: '11:22:33:44:55:66',
        internetAccess: true,
        ipv4Access: true,
        ipv6Access: true,
      );

      final updated = policy.copyWith(internetAccess: false);
      expect(updated.targetMac, equals('11:22:33:44:55:66'));
      expect(updated.internetAccess, isFalse);
      expect(updated.ipv4Access, isTrue);
      expect(policy.internetAccess, isTrue); // original unmodified
    });
  });
}
