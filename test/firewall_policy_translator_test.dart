// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/network_access_policy.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/modules/firewall_security/models/firewall_info.dart';
import 'package:yala/modules/firewall_security/services/firewall_policy_translator.dart';

void main() {
  group('FirewallPolicyTranslator Legacy Recognition Tests', () {
    const mac = 'aa:bb:cc:dd:ee:ff';

    test(
      'Recognizes legacy nointernet_wireless_clients rule non-destructively',
      () {
        final legacyRules = [
          const FirewallCustomRule(
            sectionKey: 'rule_nointernet',
            name: 'nointernet_wireless_clients',
            srcZone: 'lan',
            destZone: 'wan',
            srcMac: ['aa:bb:cc:dd:ee:ff'],
            target: 'DROP',
            enabled: true,
          ),
        ];

        final recognized = FirewallPolicyTranslator.recognizePolicy(
          targetMac: mac,
          rules: legacyRules,
        );

        expect(recognized.targetMac, equals('AA:BB:CC:DD:EE:FF'));
        expect(recognized.hasActiveBlock, isTrue);
        expect(recognized.isLegacy, isTrue);
        expect(recognized.matchingSectionKeys, contains('rule_nointernet'));
        expect(recognized.policy.internetAccess, isFalse);
        expect(recognized.policy.effectiveIpv4Access, isFalse);
        expect(recognized.policy.effectiveIpv6Access, isFalse);
        expect(recognized.policy.isEffectivelyBlocked, isTrue);
      },
    );

    test('Recognizes Pause_Internet_<MAC> rule non-destructively', () {
      final legacyRules = [
        const FirewallCustomRule(
          sectionKey: 'rule_pause',
          name: 'Pause_Internet_aabbccddeeff',
          srcZone: 'lan',
          destZone: 'wan',
          srcMac: ['aa:bb:cc:dd:ee:ff'],
          target: 'REJECT',
          enabled: true,
        ),
      ];

      final recognized = FirewallPolicyTranslator.recognizePolicy(
        targetMac: mac,
        rules: legacyRules,
      );

      expect(recognized.hasActiveBlock, isTrue);
      expect(recognized.isLegacy, isTrue);
      expect(recognized.policy.internetAccess, isFalse);
      expect(recognized.policy.isEffectivelyBlocked, isTrue);
    });

    test('Recognizes Ban_Client_ and Kick_Client_ prefix legacy rules', () {
      final banRules = [
        const FirewallCustomRule(
          sectionKey: 'rule_ban',
          name: 'Ban_Client_aa:bb:cc:dd:ee:ff',
          srcZone: 'lan',
          destZone: 'wan',
          srcMac: ['aa:bb:cc:dd:ee:ff'],
          target: 'DROP',
          enabled: true,
        ),
      ];

      final recognized = FirewallPolicyTranslator.recognizePolicy(
        targetMac: mac,
        rules: banRules,
      );

      expect(recognized.hasActiveBlock, isTrue);
      expect(recognized.isLegacy, isTrue);
      expect(recognized.policy.internetAccess, isFalse);
    });

    test('Disabled legacy rules do not count as active blocks', () {
      final disabledRules = [
        const FirewallCustomRule(
          sectionKey: 'rule_pause',
          name: 'Pause_Internet_aabbccddeeff',
          srcZone: 'lan',
          destZone: 'wan',
          srcMac: ['aa:bb:cc:dd:ee:ff'],
          target: 'REJECT',
          enabled: false,
        ),
      ];

      final recognized = FirewallPolicyTranslator.recognizePolicy(
        targetMac: mac,
        rules: disabledRules,
      );

      expect(recognized.hasActiveBlock, isFalse);
      expect(recognized.policy.internetAccess, isTrue);
      expect(recognized.policy.isEffectivelyBlocked, isFalse);
    });
  });

  group('FirewallPolicyTranslator Policy-to-UCI Translation Tests', () {
    const mac = '11:22:33:44:55:66';
    final modernCapabilities = RouterCapabilities(
      routerId: 'router_modern',
      probedAt: DateTime.now(),
      firewallBackend: FirewallBackend.fw4,
      uciPermissions: const {
        '*': ['read', 'write'],
      },
      hasOdhcpd: true,
      supportsIpv6InternetFirewall: true,
    );

    test(
      'Translating unblocked policy generates delete mutation for existing rule',
      () {
        final existing = [
          const FirewallCustomRule(
            sectionKey: 'rule_old_block',
            name: 'Yala_Block_112233445566',
            srcZone: '*',
            destZone: 'wan',
            srcMac: ['11:22:33:44:55:66'],
            target: 'DROP',
            enabled: true,
          ),
        ];

        final policy = NetworkAccessPolicy.unrestricted(mac);
        final mutations = FirewallPolicyTranslator.translatePolicyToUci(
          policy: policy,
          capabilities: modernCapabilities,
          existingRules: existing,
        );

        expect(mutations.length, equals(1));
        expect(mutations.first.type, equals(UciMutationType.delete));
        expect(mutations.first.sectionKey, equals('rule_old_block'));
      },
    );

    test(
      'Translating global block updates existing rule preserving section key',
      () {
        final existing = [
          const FirewallCustomRule(
            sectionKey: 'rule_existing_key',
            name: 'Yala_Block_112233445566',
            srcZone: '*',
            destZone: 'wan',
            srcMac: ['11:22:33:44:55:66'],
            target: 'ACCEPT',
            enabled: true,
          ),
        ];

        final policy = NetworkAccessPolicy.blocked(mac);
        final mutations = FirewallPolicyTranslator.translatePolicyToUci(
          policy: policy,
          capabilities: modernCapabilities,
          existingRules: existing,
        );

        expect(mutations.length, equals(1));
        expect(mutations.first.type, equals(UciMutationType.set));
        expect(mutations.first.sectionKey, equals('rule_existing_key'));
        expect(mutations.first.values['target'], equals('DROP'));
        expect(mutations.first.values['enabled'], equals('1'));
      },
    );

    test('Translating IPv4-only block creates IPv4 family drop rule', () {
      const policy = NetworkAccessPolicy(
        targetMac: mac,
        internetAccess: true,
        ipv4Access: false,
        ipv6Access: true,
      );

      final mutations = FirewallPolicyTranslator.translatePolicyToUci(
        policy: policy,
        capabilities: modernCapabilities,
        existingRules: const [],
      );

      expect(mutations.length, equals(1));
      final mutation = mutations.first;
      expect(mutation.type, equals(UciMutationType.add));
      expect(mutation.values['family'], equals('ipv4'));
      expect(mutation.values['target'], equals('DROP'));
      expect(mutation.values['src_mac'], contains(mac));
    });

    test(
      'Case 1: odhcpd present + IPv6 Internet capability true -> IPv6 block generated',
      () {
        final case1Capabilities = RouterCapabilities(
          routerId: 'router_case1',
          probedAt: DateTime.now(),
          firewallBackend: FirewallBackend.fw4,
          uciPermissions: const {
            '*': ['read', 'write'],
          },
          hasOdhcpd: true,
          supportsIpv6InternetFirewall: true,
        );

        const policy = NetworkAccessPolicy(
          targetMac: mac,
          internetAccess: true,
          ipv4Access: true,
          ipv6Access: false,
        );

        final mutations = FirewallPolicyTranslator.translatePolicyToUci(
          policy: policy,
          capabilities: case1Capabilities,
          existingRules: const [],
        );

        expect(mutations.length, equals(1));
        final mutation = mutations.first;
        expect(mutation.type, equals(UciMutationType.add));
        expect(mutation.values['family'], equals('ipv6'));
        expect(mutation.values['target'], equals('DROP'));
        expect(mutation.values['src_mac'], contains(mac));
      },
    );

    test(
      'Case 2: odhcpd present + IPv6 Internet capability false -> IPv6 block NOT generated',
      () {
        final case2Capabilities = RouterCapabilities(
          routerId: 'router_case2',
          probedAt: DateTime.now(),
          firewallBackend: FirewallBackend.fw4,
          uciPermissions: const {
            '*': ['read', 'write'],
          },
          hasOdhcpd: true,
          supportsIpv6InternetFirewall: false,
        );

        const policy = NetworkAccessPolicy(
          targetMac: mac,
          internetAccess: true,
          ipv4Access: true,
          ipv6Access: false,
        );

        final mutations = FirewallPolicyTranslator.translatePolicyToUci(
          policy: policy,
          capabilities: case2Capabilities,
          existingRules: const [],
        );

        // Router lacks operational IPv6 Internet firewall support; rule creation skipped
        expect(mutations, isEmpty);
      },
    );

    test(
      'Case 3: odhcpd absent + IPv6 Internet capability false -> IPv6 block NOT generated',
      () {
        final case3Capabilities = RouterCapabilities(
          routerId: 'router_case3',
          probedAt: DateTime.now(),
          firewallBackend: FirewallBackend.fw3,
          uciPermissions: const {
            '*': ['read', 'write'],
          },
          hasOdhcpd: false,
          supportsIpv6InternetFirewall: false,
        );

        const policy = NetworkAccessPolicy(
          targetMac: mac,
          internetAccess: true,
          ipv4Access: true,
          ipv6Access: false,
        );

        final mutations = FirewallPolicyTranslator.translatePolicyToUci(
          policy: policy,
          capabilities: case3Capabilities,
          existingRules: const [],
        );

        // IPv4-only router; rule creation skipped
        expect(mutations, isEmpty);
      },
    );

    test(
      'Case 4: IPv4 functionality remains unaffected by IPv6 capability status',
      () {
        final ipv4OnlyCapabilities = RouterCapabilities(
          routerId: 'router_ipv4_only',
          probedAt: DateTime.now(),
          firewallBackend: FirewallBackend.fw3,
          uciPermissions: const {
            '*': ['read', 'write'],
          },
          hasOdhcpd: false,
          supportsIpv6InternetFirewall: false,
        );

        const policy = NetworkAccessPolicy(
          targetMac: mac,
          internetAccess: true,
          ipv4Access: false,
          ipv6Access: true,
        );

        final mutations = FirewallPolicyTranslator.translatePolicyToUci(
          policy: policy,
          capabilities: ipv4OnlyCapabilities,
          existingRules: const [],
        );

        expect(mutations.length, equals(1));
        final mutation = mutations.first;
        expect(mutation.type, equals(UciMutationType.add));
        expect(mutation.values['family'], equals('ipv4'));
        expect(mutation.values['target'], equals('DROP'));
        expect(mutation.values['src_mac'], contains(mac));
      },
    );
  });
}
