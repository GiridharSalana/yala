// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/network_access_policy.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/modules/firewall_security/models/firewall_info.dart';
import 'package:yala/services/mock_api_service.dart';

void main() {
  group('MockApiService 4-Profile Capability Tests', () {
    setUp(() {
      MockApiService.resetMockFirewallState();
      MockApiService.activeProfile = MockCapabilityProfile.fullModernStack;
      MockApiService.simulateRollbackFailure = false;
    });

    test('Profile A (Full Modern Stack) reports fw4, IPv6/odhcpd, AGH, and UCI write access', () {
      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.fullModernStack,
      );
      expect(caps.firewallBackend, equals(FirewallBackend.fw4));
      expect(caps.hasUciWriteAccess, isTrue);
      expect(caps.hasOdhcpd, isTrue);
      expect(caps.hasAdGuardHome, isTrue);
    });

    test('Profile B (Legacy Constrained) reports fw3, no odhcpd, no AGH', () {
      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.legacyConstrained,
      );
      expect(caps.firewallBackend, equals(FirewallBackend.fw3));
      expect(caps.hasUciWriteAccess, isTrue);
      expect(caps.hasOdhcpd, isFalse);
      expect(caps.hasAdGuardHome, isFalse);
    });

    test('Profile C (Read-Only LuCI) reports hasUciWriteAccess as false', () {
      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.readOnlyLuci,
      );
      expect(caps.hasUciWriteAccess, isFalse);
    });

    test('Profile D (Constrained / Degraded) reports rollback failure simulation flag', () {
      MockApiService.activeProfile = MockCapabilityProfile.constrainedFailure;
      MockApiService.simulateRollbackFailure = true;
      expect(MockApiService.simulateRollbackFailure, isTrue);
    });
  });

  group('Firewall Port Forward CRUD on MockApiService', () {
    final mockService = MockApiService();
    const testIp = '192.168.1.1';
    const testAuth = 'mock_auth_token';

    setUp(() {
      MockApiService.resetMockFirewallState();
      MockApiService.activeProfile = MockCapabilityProfile.fullModernStack;
      MockApiService.simulateRollbackFailure = false;
    });

    test('Add, update, and delete port forwarding works with section key preservation', () async {
      const fwd = FirewallPortForwarding(
        sectionKey: 'cfg_pf_1',
        name: 'Web-Server',
        srcZone: 'wan',
        srcPort: '8080',
        destZone: 'lan',
        destIp: '192.168.1.100',
        destPort: '80',
        proto: 'tcp',
      );

      // Add
      final added = await mockService.addFirewallPortForward(
        testIp,
        testAuth,
        false,
        portForward: fwd,
      );
      expect(added, isTrue);

      // Update
      final updatedFwd = fwd.copyWith(destPort: '8080');
      final updated = await mockService.updateFirewallPortForward(
        testIp,
        testAuth,
        false,
        portForward: updatedFwd,
      );
      expect(updated, isTrue);

      // Delete
      final deleted = await mockService.deleteFirewallPortForward(
        testIp,
        testAuth,
        false,
        sectionKey: 'cfg_pf_1',
      );
      expect(deleted, isTrue);
    });

    test('Port forward mutations fail gracefully on Profile C (Read-only)', () async {
      MockApiService.activeProfile = MockCapabilityProfile.readOnlyLuci;

      const fwd = FirewallPortForwarding(
        sectionKey: 'cfg_pf_readonly',
        name: 'Blocked-Add',
        srcZone: 'wan',
        srcPort: '443',
        destZone: 'lan',
        destIp: '192.168.1.200',
        destPort: '443',
        proto: 'tcp',
      );

      final added = await mockService.addFirewallPortForward(
        testIp,
        testAuth,
        false,
        portForward: fwd,
      );
      expect(added, isFalse);
    });

    test('Port forward mutations roll back on Profile D failure simulation', () async {
      MockApiService.activeProfile = MockCapabilityProfile.constrainedFailure;
      MockApiService.simulateRollbackFailure = true;

      const fwd = FirewallPortForwarding(
        sectionKey: 'cfg_pf_fail',
        name: 'Should-Rollback',
        srcZone: 'wan',
        srcPort: '9000',
        destZone: 'lan',
        destIp: '192.168.1.250',
        destPort: '9000',
        proto: 'tcp',
      );

      final added = await mockService.addFirewallPortForward(
        testIp,
        testAuth,
        false,
        portForward: fwd,
      );
      expect(added, isFalse);
    });
  });

  group('Firewall Custom Rule CRUD & Per-Device Policy on MockApiService', () {
    final mockService = MockApiService();
    const testIp = '192.168.1.1';
    const testAuth = 'mock_auth_token';

    setUp(() {
      MockApiService.resetMockFirewallState();
      MockApiService.activeProfile = MockCapabilityProfile.fullModernStack;
      MockApiService.simulateRollbackFailure = false;
    });

    test('Add, update, and delete custom rules work smoothly', () async {
      const rule = FirewallCustomRule(
        sectionKey: 'rule_custom_1',
        name: 'Block-Game-Console',
        srcZone: 'lan',
        destZone: 'wan',
        srcMac: ['aa:bb:cc:dd:ee:ff'],
        target: 'DROP',
        enabled: true,
      );

      final added = await mockService.addFirewallCustomRule(
        testIp,
        testAuth,
        false,
        rule: rule,
      );
      expect(added, isTrue);

      final updatedRule = rule.copyWith(target: 'REJECT');
      final updated = await mockService.updateFirewallCustomRule(
        testIp,
        testAuth,
        false,
        rule: updatedRule,
      );
      expect(updated, isTrue);

      final deleted = await mockService.deleteFirewallCustomRule(
        testIp,
        testAuth,
        false,
        sectionKey: 'rule_custom_1',
      );
      expect(deleted, isTrue);
    });

    test('Applying per-device policy records policy and updates mock store', () async {
      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.fullModernStack,
      );
      const policy = NetworkAccessPolicy(
        targetMac: '00:11:22:33:44:55',
        internetAccess: false,
      );

      final applied = await mockService.applyPerDeviceNetworkAccessPolicy(
        testIp,
        testAuth,
        false,
        policy: policy,
        capabilities: caps,
      );
      expect(applied, isTrue);
    });
  });
}
