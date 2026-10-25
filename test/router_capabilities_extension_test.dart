// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/router_capabilities.dart';

void main() {
  group('RouterCapabilities Phase 0 Extension Tests', () {
    test('RouterCapabilities.mock() contains all Phase 0 capability flags', () {
      final mock = RouterCapabilities.mock();

      expect(mock.hasAdGuardHome, isTrue);
      expect(mock.hasOdhcpd, isTrue);
      expect(mock.hasCron, isTrue);
      expect(mock.hasDropbear, isTrue);
      expect(mock.supportsIpv6InternetFirewall, isTrue);
      expect(mock.hasUciApply, isTrue);
      expect(mock.hasUciConfirm, isTrue);
      expect(mock.probeFailed, isFalse);
    });

    test('RouterCapabilities.conservative() has safe conservative defaults', () {
      final conservative = RouterCapabilities.conservative('test-router');

      expect(conservative.routerId, equals('test-router'));
      expect(conservative.hasAdGuardHome, isFalse);
      expect(conservative.hasOdhcpd, isFalse);
      expect(conservative.hasCron, isFalse);
      expect(conservative.hasDropbear, isFalse);
      expect(conservative.supportsIpv6InternetFirewall, isFalse);
      expect(conservative.probeFailed, isTrue);
      // When probeFailed is true, hasMethod returns true as optimistic/conservative attempt
      expect(conservative.hasUciApply, isTrue);
      expect(conservative.hasUciConfirm, isTrue);
    });

    test(
      'hasUciApply and hasUciConfirm reflect ubus methods when probed successfully',
      () {
        final capsWithUci = RouterCapabilities(
          routerId: 'probed-router',
          ubusObjects: {'uci'},
          ubusMethods: {
            'uci': ['apply', 'confirm', 'get', 'set'],
          },
          probedAt: DateTime.now(),
          probeFailed: false,
        );

        expect(capsWithUci.hasUciApply, isTrue);
        expect(capsWithUci.hasUciConfirm, isTrue);

        final capsWithoutUciApply = RouterCapabilities(
          routerId: 'restricted-router',
          ubusObjects: {'uci'},
          ubusMethods: {
            'uci': ['get', 'set', 'commit'],
          },
          probedAt: DateTime.now(),
          probeFailed: false,
        );

        expect(capsWithoutUciApply.hasUciApply, isFalse);
        expect(capsWithoutUciApply.hasUciConfirm, isFalse);
      },
    );

    test('toJson and fromJson preserve Phase 0 capability flags', () {
      final original = RouterCapabilities(
        routerId: 'roundtrip-router',
        ubusObjects: {'uci', 'system', 'service'},
        ubusMethods: {
          'uci': ['apply', 'confirm'],
        },
        hasAdGuardHome: true,
        hasOdhcpd: false,
        hasCron: true,
        hasDropbear: true,
        supportsIpv6InternetFirewall: true,
        probedAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
        probeFailed: false,
      );

      final json = original.toJson();
      expect(json['hasAdGuardHome'], isTrue);
      expect(json['hasOdhcpd'], isFalse);
      expect(json['hasCron'], isTrue);
      expect(json['hasDropbear'], isTrue);
      expect(json['supportsIpv6InternetFirewall'], isTrue);

      final deserialized = RouterCapabilities.fromJson(json);
      expect(deserialized.routerId, equals('roundtrip-router'));
      expect(deserialized.hasAdGuardHome, isTrue);
      expect(deserialized.hasOdhcpd, isFalse);
      expect(deserialized.hasCron, isTrue);
      expect(deserialized.hasDropbear, isTrue);
      expect(deserialized.supportsIpv6InternetFirewall, isTrue);
      expect(deserialized.hasUciApply, isTrue);
      expect(deserialized.hasUciConfirm, isTrue);
    });

    test(
      'fromJson handles legacy or missing Phase 0 capability fields gracefully',
      () {
        final legacyJson = {
          'routerId': 'legacy-router',
          'ubusObjects': ['uci'],
          'ubusMethods': {
            'uci': ['get'],
          },
          'packageEngine': 'opkg',
          'firewallBackend': 'fw4',
          'networkModel': 'dsa',
          'releaseVersion': '23.05.0',
          'boardName': 'generic',
          'probedAt': '2026-01-01T00:00:00.000Z',
          'probeFailed': false,
        };

        final deserialized = RouterCapabilities.fromJson(legacyJson);
        expect(deserialized.hasAdGuardHome, isFalse);
        expect(deserialized.hasOdhcpd, isFalse);
        expect(deserialized.hasCron, isFalse);
        expect(deserialized.hasDropbear, isFalse);
        expect(deserialized.supportsIpv6InternetFirewall, isFalse);
      },
    );

    test('copyWith properly overrides Phase 0 capability flags', () {
      final base = RouterCapabilities.mock();
      expect(base.hasAdGuardHome, isTrue);
      expect(base.supportsIpv6InternetFirewall, isTrue);

      final modified = base.copyWith(
        hasAdGuardHome: false,
        hasDropbear: false,
        supportsIpv6InternetFirewall: false,
      );

      expect(modified.hasAdGuardHome, isFalse);
      expect(modified.hasDropbear, isFalse);
      expect(modified.supportsIpv6InternetFirewall, isFalse);
      expect(modified.hasOdhcpd, isTrue);
      expect(modified.hasCron, isTrue);
    });
  });
}
