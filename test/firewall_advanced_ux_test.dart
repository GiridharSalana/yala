// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/modules/firewall_security/models/firewall_info.dart';
import 'package:yala/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yala/models/network_access_policy.dart';
import 'package:yala/services/api_service.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/utils/self_device_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Acceptance 1: Bitwise CIDR Mathematics & Address Containment', () {
    test('IPv4 bitwise containment: identical subnets contain each other', () {
      expect(Ipv4CidrUtil.containsCidr('192.168.1.0/24', '192.168.1.0/24'), isTrue);
    });

    test('IPv4 bitwise containment: strictly nested smaller subnet', () {
      expect(Ipv4CidrUtil.containsCidr('10.0.0.0/8', '10.1.2.0/24'), isTrue);
      expect(Ipv4CidrUtil.containsCidr('192.168.0.0/16', '192.168.1.0/24'), isTrue);
      expect(Ipv4CidrUtil.containsCidr('192.168.1.0/24', '192.168.0.0/16'), isFalse);
    });

    test('IPv4 bitwise containment: adjacent sibling subnets are disjoint', () {
      expect(Ipv4CidrUtil.containsCidr('192.168.1.0/24', '192.168.2.0/24'), isFalse);
      expect(Ipv4CidrUtil.containsCidr('10.0.0.0/24', '10.0.1.0/24'), isFalse);
    });

    test('IPv4 bitwise IP containment: single host in subnet', () {
      expect(Ipv4CidrUtil.containsCidr('192.168.1.0/24', '192.168.1.15'), isTrue);
      expect(Ipv4CidrUtil.containsCidr('192.168.1.0/24', '192.168.2.1'), isFalse);
    });

    test('IPv6 bitwise containment: RFC 4291 scopes and prefix containment', () {
      final prefix32 = Ipv6AddressUtil.tryParse('2001:db8::')!;
      final host1 = Ipv6AddressUtil.tryParse('2001:db8:1::1')!;
      expect(Ipv6AddressUtil.containsIp(prefix32, host1, 32), isTrue);

      final prefix48 = Ipv6AddressUtil.tryParse('2001:db8:1::')!;
      final host2 = Ipv6AddressUtil.tryParse('2001:db8:2::1')!;
      expect(Ipv6AddressUtil.containsIp(prefix48, host2, 48), isFalse);

      final ula48 = Ipv6AddressUtil.tryParse('fd00:abcd::')!;
      final ulaHost1 = Ipv6AddressUtil.tryParse('fd00:abcd::1')!;
      final ulaHost2 = Ipv6AddressUtil.tryParse('fd00:beef::1')!;
      expect(Ipv6AddressUtil.containsIp(ula48, ulaHost1, 48), isTrue);
      expect(Ipv6AddressUtil.containsIp(ula48, ulaHost2, 48), isFalse);
    });

    test('IPv6 bitwise scopes: link-local vs ULA vs global unicast', () {
      final ll = Ipv6AddressUtil.tryParse('fe80::1ff:fe00:1')!;
      expect(Ipv6AddressUtil.isLinkLocal(ll), isTrue);
      expect(Ipv6AddressUtil.isGlobalUnicast(ll), isFalse);

      final ula = Ipv6AddressUtil.tryParse('fd12:3456:789a::1')!;
      expect(Ipv6AddressUtil.isUla(ula), isTrue);
      expect(Ipv6AddressUtil.isGlobalUnicast(ula), isFalse);

      final gua = Ipv6AddressUtil.tryParse('2400:cb00:2048:1::c629:d7a2')!;
      expect(Ipv6AddressUtil.isGlobalUnicast(gua), isTrue);
      expect(Ipv6AddressUtil.isLinkLocal(gua), isFalse);
    });
  });

  group('Acceptance 2: Port Forward Conflict Evaluation', () {
    final existingRules = [
      const FirewallPortForwarding(
        sectionKey: 'rule_web',
        name: 'Web Server',
        srcZone: 'wan',
        srcPort: '80,443',
        destZone: 'lan',
        destIp: '192.168.1.100',
        destPort: '80,443',
        proto: 'tcp',
        target: 'DNAT',
        enabled: true,
      ),
      const FirewallPortForwarding(
        sectionKey: 'rule_udp',
        name: 'WireGuard In',
        srcZone: 'wan',
        srcPort: '51820',
        destZone: 'lan',
        destIp: '192.168.1.1',
        destPort: '51820',
        proto: 'udp',
        target: 'DNAT',
        enabled: true,
      ),
      const FirewallPortForwarding(
        sectionKey: 'rule_disabled',
        name: 'Old Minecraft',
        srcZone: 'wan',
        srcPort: '25565',
        destZone: 'lan',
        destIp: '192.168.1.200',
        destPort: '25565',
        proto: 'tcp udp',
        target: 'DNAT',
        enabled: false,
      ),
    ];

    test('Conflict detected on overlapping TCP port 80', () {
      const candidate = FirewallPortForwarding(
        name: 'New Web',
        srcZone: 'wan',
        srcPort: '80',
        destZone: 'lan',
        destIp: '192.168.1.101',
        destPort: '80',
        proto: 'tcp',
        target: 'DNAT',
      );
      final res = FirewallValidator.checkPortForwardConflict(candidate, existingRules);
      expect(res.hasConflict, isTrue);
      expect(res.conflictingSectionKey, equals('rule_web'));
    });

    test('No conflict on disjoint port 8080', () {
      const candidate = FirewallPortForwarding(
        name: 'Alt Web',
        srcZone: 'wan',
        srcPort: '8080',
        destZone: 'lan',
        destIp: '192.168.1.101',
        destPort: '8080',
        proto: 'tcp',
        target: 'DNAT',
      );
      final res = FirewallValidator.checkPortForwardConflict(candidate, existingRules);
      expect(res.hasConflict, isFalse);
    });

    test('No conflict with disabled rule on port 25565', () {
      const candidate = FirewallPortForwarding(
        name: 'Minecraft Server',
        srcZone: 'wan',
        srcPort: '25565',
        destZone: 'lan',
        destIp: '192.168.1.50',
        destPort: '25565',
        proto: 'tcp',
        target: 'DNAT',
      );
      final res = FirewallValidator.checkPortForwardConflict(candidate, existingRules);
      expect(res.hasConflict, isFalse);
    });

    test('No conflict when updating self', () {
      const updatingCandidate = FirewallPortForwarding(
        sectionKey: 'rule_web',
        name: 'Web Server Renamed',
        srcZone: 'wan',
        srcPort: '80,443',
        destZone: 'lan',
        destIp: '192.168.1.100',
        destPort: '80,443',
        proto: 'tcp',
        target: 'DNAT',
      );
      final res = FirewallValidator.checkPortForwardConflict(updatingCandidate, existingRules);
      expect(res.hasConflict, isFalse);
    });

    test('No conflict on distinct protocols (UDP candidate on TCP port 80)', () {
      const candidate = FirewallPortForwarding(
        name: 'UDP 80',
        srcZone: 'wan',
        srcPort: '80',
        destZone: 'lan',
        destIp: '192.168.1.100',
        destPort: '80',
        proto: 'udp',
        target: 'DNAT',
      );
      final res = FirewallValidator.checkPortForwardConflict(candidate, existingRules);
      expect(res.hasConflict, isFalse);
    });

    test('Management port safety blocks exposure of router admin port 80 when targeting router LAN IP', () {
      const candidate = FirewallPortForwarding(
        name: 'Expose Router LuCI',
        srcZone: 'wan',
        srcPort: '80',
        destZone: 'lan',
        destIp: '192.168.1.1',
        destPort: '80',
        proto: 'tcp',
        target: 'DNAT',
      );
      final safety = FirewallValidator.checkManagementPortSafety(
        candidate,
        routerLanIp: '192.168.1.1',
      );
      expect(safety.isUnsafe, isTrue);
      expect(safety.port, equals(80));
    });

    test('Management port safety permits forwarding port 80 to internal server 192.168.1.100', () {
      const candidate = FirewallPortForwarding(
        name: 'Forward to Webserver',
        srcZone: 'wan',
        srcPort: '80',
        destZone: 'lan',
        destIp: '192.168.1.100',
        destPort: '80',
        proto: 'tcp',
        target: 'DNAT',
      );
      final safety = FirewallValidator.checkManagementPortSafety(
        candidate,
        routerLanIp: '192.168.1.1',
      );
      expect(safety.isUnsafe, isFalse);
    });
  });

  group('Acceptance 3: Topology Facts Resolution & Bridge Membership', () {
    test('Default route detection strictly requires target 0.0.0.0/0 or ::/0', () {
      final dump = {
        'interface': [
          {
            'interface': 'wan',
            'up': true,
            'device': 'eth1',
            'ipv4-address': [{'address': '203.0.113.10', 'mask': 24}],
            'route': [
              {'target': '0.0.0.0/0', 'nexthop': '203.0.113.1', 'metric': 10},
              {'target': '198.51.100.0/24', 'nexthop': '203.0.113.2', 'metric': 5},
            ],
          },
          {
            'interface': 'lan',
            'up': true,
            'device': 'br-lan',
            'ipv4-address': [{'address': '192.168.1.1', 'mask': 24}],
            'route': [
              {'target': '10.50.0.0/16', 'nexthop': '192.168.1.200', 'metric': 0},
            ],
          },
        ],
      };

      final facts = FirewallTopologyFacts.fromNetworkDump(dump);
      expect(facts.defaultIpv4RouteLogicalNetwork, equals('wan'));
      expect(facts.defaultIpv4Gateway, equals('203.0.113.1'));
      expect(facts.defaultIpv4RouteLogicalNetwork, isNot(equals('lan')));
    });

    test('Equal-metric default routes with conflicting gateways return null (unknown)', () {
      final dump = {
        'interface': [
          {
            'interface': 'wan',
            'up': true,
            'device': 'eth1',
            'ipv4-address': [{'address': '203.0.113.10', 'mask': 24}],
            'route': [
              {'target': '0.0.0.0/0', 'nexthop': '203.0.113.1', 'metric': 10},
              {'target': '0.0.0.0/0', 'nexthop': '203.0.113.2', 'metric': 10},
            ],
          },
        ],
      };

      final facts = FirewallTopologyFacts.fromNetworkDump(dump);
      expect(facts.defaultIpv4Gateway, isNull);
    });

    test('Deterministic unique lowest-metric default route selection', () {
      final dump = {
        'interface': [
          {
            'interface': 'wan',
            'up': true,
            'device': 'eth1',
            'ipv4-address': [{'address': '203.0.113.10', 'mask': 24}],
            'route': [
              {'target': '0.0.0.0/0', 'nexthop': '203.0.113.2', 'metric': 20},
              {'target': '0.0.0.0/0', 'nexthop': '203.0.113.1', 'metric': 10},
            ],
          },
        ],
      };

      final facts = FirewallTopologyFacts.fromNetworkDump(dump);
      expect(facts.defaultIpv4Gateway, equals('203.0.113.1'));
    });

    test('Positive host-facing bridge proof: AP/Ethernet member is host-facing, virtual-only is rejected', () {
      final devices = {
        'br-lan': {
          'type': 'Bridge',
          'bridge-members': ['lan1', 'wlan0'],
        },
        'br-tunnel': {
          'type': 'Bridge',
          'bridge-members': ['wg0', 'tun0'],
        },
        'lan1': {
          'type': 'Network device',
          'carrier': true,
        },
        'wlan0': {
          'type': 'Wireless adapter',
          'wireless': true,
        },
        'wg0': {
          'type': 'Virtual',
        },
        'tun0': {
          'type': 'Virtual',
        },
      };

      final dump = {
        'interface': [
          {
            'interface': 'lan',
            'up': true,
            'device': 'br-lan',
            'ipv4-address': [{'address': '192.168.1.1', 'mask': 24}],
          },
          {
            'interface': 'tunnel_net',
            'up': true,
            'device': 'br-tunnel',
            'ipv4-address': [{'address': '10.8.0.1', 'mask': 24}],
          },
        ],
      };

      final facts = FirewallTopologyFacts.fromNetworkDump(dump, networkDevices: devices);
      expect(facts.hostFacingLogicalNetworks.contains('lan'), isTrue);
      expect(facts.hostFacingLogicalNetworks.contains('tunnel_net'), isFalse);
    });
  });

  group('Acceptance 4: Authoritative NAT Reflection Capability Evaluator', () {
    const validOverview = FirewallOverview(
      backend: FirewallBackend.fw4,
      defaultPolicy: FirewallDefaultPolicy(
        input: 'DROP',
        output: 'ACCEPT',
        forward: 'DROP',
        synFlood: true,
      ),
      zones: [
        FirewallZone(
          name: 'lan',
          input: 'ACCEPT',
          output: 'ACCEPT',
          forward: 'ACCEPT',
          masquerade: false,
          networks: ['lan'],
        ),
        FirewallZone(
          name: 'wan',
          input: 'DROP',
          output: 'ACCEPT',
          forward: 'DROP',
          masquerade: true,
          masquerade6: true,
          networks: ['wan', 'wan6'],
        ),
      ],
      forwardings: [
        FirewallForwarding(srcZone: 'lan', destZone: 'wan'),
      ],
      portForwards: [],
      customRules: [],
      isAvailable: true,
      isNoCustomRules: false,
    );

    const wanIpv4Fact = Ipv4AddressFact(
      address: '203.0.113.10',
      prefixLength: 24,
      subnetCidr: '203.0.113.10/24',
      isPrivateRfc1918: false,
      isLinkLocal: false,
      isLoopback: false,
      isBroadcast: false,
      isCgnatRfc6598: false,
      isPublicRoutable: true,
    );

    final validFacts = FirewallTopologyFacts(
      defaultIpv4RouteLogicalNetwork: 'wan',
      defaultIpv4Gateway: '203.0.113.1',
      defaultIpv6RouteLogicalNetwork: 'wan6',
      defaultIpv6Gateway: '2001:db8::1',
      externalIpv4AddressFact: wanIpv4Fact,
      externalIpv6AddressFact: Ipv6AddressFact.tryParse(
        address: '2001:db8::10',
        prefixLength: 64,
        preferredLifetime: 86400,
        validLifetime: 86400,
      ),
      logicalNetworkIpv4Addresses: const {
        'lan': [
          Ipv4AddressFact(
            address: '192.168.1.1',
            prefixLength: 24,
            subnetCidr: '192.168.1.1/24',
            isPrivateRfc1918: true,
            isLinkLocal: false,
            isLoopback: false,
            isBroadcast: false,
            isCgnatRfc6598: false,
            isPublicRoutable: false,
          ),
        ],
        'wan': [wanIpv4Fact],
      },
      logicalNetworkIpv6Addresses: {
        'wan6': [
          Ipv6AddressFact.tryParse(
            address: '2001:db8::10',
            prefixLength: 64,
            preferredLifetime: 86400,
            validLifetime: 86400,
          )!,
        ],
      },
      logicalNetworkHasHostFacingDevice: const {'lan': true},
    );

    test('Full valid topology and redirect context returns NatReflectionStatus.supported', () {
      const context = NatReflectionRedirectContext(
        srcZone: 'wan',
        destZone: 'lan',
        destIp: '192.168.1.100',
        family: 'ipv4',
      );

      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.fullModernStack,
      );

      final result = FirewallValidator.evaluateNatReflectionCapability(
        overview: validOverview,
        capabilities: caps,
        redirectContext: context,
        topologyFacts: validFacts,
      );

      expect(result.status, equals(NatReflectionStatus.supported));
      expect(result.unsupportedReason, isNull);
    });

    test('Read-only capability returns NatReflectionStatus.unsupported with readOnly reason', () {
      const context = NatReflectionRedirectContext(
        srcZone: 'wan',
        destZone: 'lan',
        destIp: '192.168.1.100',
        family: 'ipv4',
      );

      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.readOnlyLuci,
      );

      final result = FirewallValidator.evaluateNatReflectionCapability(
        overview: validOverview,
        capabilities: caps,
        redirectContext: context,
        topologyFacts: validFacts,
      );

      expect(result.status, equals(NatReflectionStatus.unsupported));
      expect(result.unsupportedReason, equals(NatReflectionUnsupportedReason.readOnly));
    });

    test('Missing topology facts returns NatReflectionStatus.unknown', () {
      const context = NatReflectionRedirectContext(
        srcZone: 'wan',
        destZone: 'lan',
        destIp: '192.168.1.100',
        family: 'ipv4',
      );

      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.fullModernStack,
      );

      final result = FirewallValidator.evaluateNatReflectionCapability(
        overview: validOverview,
        capabilities: caps,
        redirectContext: context,
        topologyFacts: null,
      );

      expect(result.status, equals(NatReflectionStatus.unknown));
    });

    test('Unreachable destination IP returns NatReflectionStatus.unknown with reachability warning', () {
      const context = NatReflectionRedirectContext(
        srcZone: 'wan',
        destZone: 'lan',
        destIp: '172.16.5.99',
        family: 'ipv4',
      );

      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.fullModernStack,
      );

      final result = FirewallValidator.evaluateNatReflectionCapability(
        overview: validOverview,
        capabilities: caps,
        redirectContext: context,
        topologyFacts: validFacts,
      );

      expect(result.status, equals(NatReflectionStatus.unknown));
      expect(result.userFacingReason, contains('not reachable'));
    });

    test('Non-masquerading WAN zone returns NatReflectionStatus.unsupported', () {
      final noMasqWanOverview = FirewallOverview(
        backend: FirewallBackend.fw4,
        defaultPolicy: validOverview.defaultPolicy,
        zones: const [
          FirewallZone(
            name: 'lan',
            input: 'ACCEPT',
            output: 'ACCEPT',
            forward: 'ACCEPT',
            masquerade: false,
            networks: ['lan'],
          ),
          FirewallZone(
            name: 'wan',
            input: 'DROP',
            output: 'ACCEPT',
            forward: 'DROP',
            masquerade: false,
            masquerade6: false,
            networks: ['wan', 'wan6'],
          ),
        ],
        forwardings: validOverview.forwardings,
        portForwards: validOverview.portForwards,
        customRules: validOverview.customRules,
        isAvailable: true,
        isNoCustomRules: false,
      );

      const context = NatReflectionRedirectContext(
        srcZone: 'wan',
        destZone: 'lan',
        destIp: '192.168.1.100',
        family: 'ipv4',
      );

      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.fullModernStack,
      );

      final result = FirewallValidator.evaluateNatReflectionCapability(
        overview: noMasqWanOverview,
        capabilities: caps,
        redirectContext: context,
        topologyFacts: validFacts,
      );

      expect(result.status, equals(NatReflectionStatus.unsupported));
      expect(result.unsupportedReason, equals(NatReflectionUnsupportedReason.noMasqueradingWan));
    });

    test('reflection_src semantics: internal and external are accepted, sys/other returns unknown', () {
      final caps = MockApiService.getRouterCapabilitiesForProfile(
        MockCapabilityProfile.fullModernStack,
      );

      const validInternal = NatReflectionRedirectContext(
        srcZone: 'wan',
        destZone: 'lan',
        destIp: '192.168.1.100',
        family: 'ipv4',
        existingReflectionSrc: 'internal',
      );
      final resInternal = FirewallValidator.evaluateNatReflectionCapability(
        overview: validOverview,
        capabilities: caps,
        redirectContext: validInternal,
        topologyFacts: validFacts,
      );
      expect(resInternal.status, equals(NatReflectionStatus.supported));

      const invalidSys = NatReflectionRedirectContext(
        srcZone: 'wan',
        destZone: 'lan',
        destIp: '192.168.1.100',
        family: 'ipv4',
        existingReflectionSrc: 'sys',
      );
      final resSys = FirewallValidator.evaluateNatReflectionCapability(
        overview: validOverview,
        capabilities: caps,
        redirectContext: invalidSys,
        topologyFacts: validFacts,
      );
      expect(resSys.status, equals(NatReflectionStatus.unknown));
    });
  });

  group('Acceptance 5: Custom Rule Slot Identity Exchange & Safe Reordering', () {
    final mockService = MockApiService();
    const testIp = '192.168.1.1';
    const testAuth = 'mock_auth_token';

    setUp(() {
      MockApiService.resetMockFirewallState();
      MockApiService.activeProfile = MockCapabilityProfile.fullModernStack;
    });

    test('Safe reorder exchanges custom rule slot identities', () async {
      const ruleA = FirewallCustomRule(
        sectionKey: 'rule_a',
        name: 'Rule A',
        srcZone: 'lan',
        destZone: 'wan',
        target: 'ACCEPT',
        enabled: true,
      );
      const ruleB = FirewallCustomRule(
        sectionKey: 'rule_b',
        name: 'Rule B',
        srcZone: 'lan',
        destZone: 'wan',
        target: 'DROP',
        enabled: true,
      );
      await mockService.addFirewallCustomRule(testIp, testAuth, false, rule: ruleA);
      await mockService.addFirewallCustomRule(testIp, testAuth, false, rule: ruleB);

      final initialRules = MockApiService.mockCustomRules;
      expect(initialRules.length, equals(2));
      expect(initialRules[0].sectionKey, equals('rule_a'));
      expect(initialRules[1].sectionKey, equals('rule_b'));

      final expectedOrder = ['rule_a', 'rule_b'];
      final reorderOk = await mockService.reorderFirewallCustomRules(
        testIp,
        testAuth,
        false,
        targetSectionKey: 'rule_a',
        siblingSectionKey: 'rule_b',
        expectedRuleOrder: expectedOrder,
      );
      expect(reorderOk, isTrue);

      final mutatedRules = MockApiService.mockCustomRules;
      expect(mutatedRules[0].sectionKey, equals('rule_b'));
      expect(mutatedRules[1].sectionKey, equals('rule_a'));
    });

    test('Safe reorder aborts when snapshot order is stale', () async {
      const ruleA = FirewallCustomRule(
        sectionKey: 'rule_a',
        name: 'Rule A',
        srcZone: 'lan',
        destZone: 'wan',
        target: 'ACCEPT',
        enabled: true,
      );
      const ruleB = FirewallCustomRule(
        sectionKey: 'rule_b',
        name: 'Rule B',
        srcZone: 'lan',
        destZone: 'wan',
        target: 'DROP',
        enabled: true,
      );
      await mockService.addFirewallCustomRule(testIp, testAuth, false, rule: ruleA);
      await mockService.addFirewallCustomRule(testIp, testAuth, false, rule: ruleB);

      final reorderOk = await mockService.reorderFirewallCustomRules(
        testIp,
        testAuth,
        false,
        targetSectionKey: 'rule_a',
        siblingSectionKey: 'rule_b',
        expectedRuleOrder: ['stale_rule_1', 'stale_rule_2'],
      );
      expect(reorderOk, isFalse);
    });

    test('Safe reorder aborts when capability profile is readOnlyLuci', () async {
      MockApiService.activeProfile = MockCapabilityProfile.readOnlyLuci;
      const ruleA = FirewallCustomRule(
        sectionKey: 'rule_a',
        name: 'Rule A',
        srcZone: 'lan',
        destZone: 'wan',
        target: 'ACCEPT',
        enabled: true,
      );
      const ruleB = FirewallCustomRule(
        sectionKey: 'rule_b',
        name: 'Rule B',
        srcZone: 'lan',
        destZone: 'wan',
        target: 'DROP',
        enabled: true,
      );
      await mockService.addFirewallCustomRule(testIp, testAuth, false, rule: ruleA);
      await mockService.addFirewallCustomRule(testIp, testAuth, false, rule: ruleB);

      final reorderOk = await mockService.reorderFirewallCustomRules(
        testIp,
        testAuth,
        false,
        targetSectionKey: 'rule_a',
        siblingSectionKey: 'rule_b',
        expectedRuleOrder: ['rule_a', 'rule_b'],
      );
      expect(reorderOk, isFalse);
    });

    test('Safe reorder aborts when simulateRollbackFailure is true', () async {
      MockApiService.simulateRollbackFailure = true;
      const ruleA = FirewallCustomRule(
        sectionKey: 'rule_a',
        name: 'Rule A',
        srcZone: 'lan',
        destZone: 'wan',
        target: 'ACCEPT',
        enabled: true,
      );
      const ruleB = FirewallCustomRule(
        sectionKey: 'rule_b',
        name: 'Rule B',
        srcZone: 'lan',
        destZone: 'wan',
        target: 'DROP',
        enabled: true,
      );
      await mockService.addFirewallCustomRule(testIp, testAuth, false, rule: ruleA);
      await mockService.addFirewallCustomRule(testIp, testAuth, false, rule: ruleB);

      final reorderOk = await mockService.reorderFirewallCustomRules(
        testIp,
        testAuth,
        false,
        targetSectionKey: 'rule_a',
        siblingSectionKey: 'rule_b',
        expectedRuleOrder: ['rule_a', 'rule_b'],
      );
      expect(reorderOk, isFalse);
      MockApiService.simulateRollbackFailure = false;
    });

    test('Safe reorder aborts when target or sibling key is non-existent', () async {
      const ruleA = FirewallCustomRule(
        sectionKey: 'rule_a',
        name: 'Rule A',
        srcZone: 'lan',
        destZone: 'wan',
        target: 'ACCEPT',
        enabled: true,
      );
      await mockService.addFirewallCustomRule(testIp, testAuth, false, rule: ruleA);

      final reorderOk = await mockService.reorderFirewallCustomRules(
        testIp,
        testAuth,
        false,
        targetSectionKey: 'rule_a',
        siblingSectionKey: 'non_existent_b',
        expectedRuleOrder: ['rule_a'],
      );
      expect(reorderOk, isFalse);
    });
  });

  group('Acceptance 6: Management-Device Lockout Guardrail Evaluation', () {
    setUp(() {
      SelfDeviceGuard.setMockLocalAddresses({
        '192.168.1.50',
        '2001:db8::50',
        '00:11:22:33:44:55',
      });
    });

    tearDown(() {
      SelfDeviceGuard.setMockLocalAddresses(null);
    });

    test('SelfDeviceGuard blocks direct self MAC DROP rule', () async {
      final isRisk = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'DROP',
        srcZone: 'lan',
        srcMac: ['00:11:22:33:44:55'],
      );
      expect(isRisk, isTrue);
    });

    test('SelfDeviceGuard blocks direct self IP DROP rule', () async {
      final isRisk = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'DROP',
        srcZone: 'lan',
        srcIp: '192.168.1.50',
      );
      expect(isRisk, isTrue);
    });

    test('SelfDeviceGuard blocks self IP inside CIDR subnet DROP rule', () async {
      final isRisk = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'DROP',
        srcZone: 'lan',
        srcIp: '192.168.1.0/24',
      );
      expect(isRisk, isTrue);
    });

    test('SelfDeviceGuard blocks broad LAN DROP rule targeting router management port (80, 443, 22)', () async {
      final isRiskPort80 = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'DROP',
        srcZone: 'lan',
        destZone: '',
        destPort: '80',
        proto: 'tcp',
      );
      expect(isRiskPort80, isTrue);

      final isRiskPort443 = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'REJECT',
        srcZone: 'lan',
        destZone: '*',
        destPort: '443',
        proto: 'tcp',
      );
      expect(isRiskPort443, isTrue);
    });

    test('SelfDeviceGuard blocks broad LAN DROP rule with wildcard port', () async {
      final isRiskWildcard = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'DROP',
        srcZone: 'lan',
        destZone: '',
        destPort: '*',
        proto: 'tcp',
      );
      expect(isRiskWildcard, isTrue);
    });

    test('SelfDeviceGuard permits DROP rule for non-self device and non-management port', () async {
      final isRiskOtherDevice = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'DROP',
        srcZone: 'lan',
        srcIp: '192.168.1.99',
        destZone: 'wan',
      );
      expect(isRiskOtherDevice, isFalse);

      final isRiskOtherPort = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'DROP',
        srcZone: 'lan',
        destZone: '',
        destPort: '8080',
        proto: 'tcp',
        srcIp: '192.168.1.99',
      );
      expect(isRiskOtherPort, isFalse);
    });

    test('SelfDeviceGuard permits ACCEPT rule regardless of device or port', () async {
      final isRisk = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'ACCEPT',
        srcZone: 'lan',
        destZone: '',
        destPort: '80',
        proto: 'tcp',
        srcIp: '192.168.1.50',
      );
      expect(isRisk, isFalse);
    });

    test('SelfDeviceGuard blocks custom LuCI (8443) and custom SSH (2222) via dynamic discovery', () async {
      const testRouterId = 'router_custom_ports';
      SelfDeviceGuard.setDiscoveredManagementPorts(testRouterId, {8443, 2222});

      // DROP rule on custom LuCI port 8443
      final isLuciRisk = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'DROP',
        srcZone: 'lan',
        destZone: '',
        destPort: '8443',
        proto: 'tcp',
        routerId: testRouterId,
      );
      expect(isLuciRisk, isTrue);

      // DROP rule on custom SSH port 2222
      final isSshRisk = await SelfDeviceGuard.isManagementLockoutRisk(
        target: 'REJECT',
        srcZone: 'lan',
        destZone: 'lan',
        destPort: '2222',
        proto: 'tcp',
        routerId: testRouterId,
      );
      expect(isSshRisk, isTrue);

      // FirewallValidator.checkManagementPortSafety also detects custom management ports
      const forwardToCustomLuci = FirewallPortForwarding(
        sectionKey: 'fwd_luci',
        name: 'Expose Custom LuCI',
        srcZone: 'wan',
        srcPort: '8443',
        destZone: 'lan',
        destIp: '192.168.1.1',
        destPort: '8443',
        proto: 'tcp',
      );
      final safety = FirewallValidator.checkManagementPortSafety(
        forwardToCustomLuci,
        routerLanIp: '192.168.1.1',
        customManagementPorts: {8443, 2222},
      );
      expect(safety.isUnsafe, isTrue);
      expect(safety.port, 8443);

      SelfDeviceGuard.clearDiscoveredManagementPorts();
    });
  });

  group('Acceptance 12: Rollback, Post-Apply Verification, & Confirmation Safety', () {
    final mockApi = MockApiService();

    setUp(() {
      MockApiService.resetMockFirewallState();
    });

    tearDown(() {
      MockApiService.resetMockFirewallState();
    });

    test('Verification failure aborts port forward creation without confirming', () async {
      MockApiService.simulateVerificationFailure = true;

      final success = await mockApi.addFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        portForward: const FirewallPortForwarding(
          sectionKey: 'test_pf',
          name: 'Test PF',
          srcZone: 'wan',
          srcPort: '9000',
          destZone: 'lan',
          destIp: '192.168.1.100',
          destPort: '9000',
          proto: 'tcp',
        ),
      );

      expect(success, isFalse);
      expect(MockApiService.mockPortForwards.isEmpty, isTrue);
    });

    test('RPC loss after apply aborts custom rule creation without confirming', () async {
      MockApiService.simulateRpcLossAfterApply = true;

      final success = await mockApi.addFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        rule: const FirewallCustomRule(
          sectionKey: 'test_cr',
          name: 'Test Rule',
          srcZone: 'lan',
          destZone: 'wan',
          target: 'ACCEPT',
          enabled: true,
        ),
      );

      expect(success, isFalse);
      expect(MockApiService.mockCustomRules.isEmpty, isTrue);
    });

    test('Verification failure aborts custom rule reordering without confirming', () async {
      // First populate with 2 rules under normal conditions
      await mockApi.addFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        rule: const FirewallCustomRule(
          sectionKey: 'rule_1',
          name: 'Rule 1',
          srcZone: 'lan',
          destZone: 'wan',
          target: 'ACCEPT',
          enabled: true,
        ),
      );
      await mockApi.addFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        rule: const FirewallCustomRule(
          sectionKey: 'rule_2',
          name: 'Rule 2',
          srcZone: 'lan',
          destZone: 'wan',
          target: 'ACCEPT',
          enabled: true,
        ),
      );

      // Now trigger verification failure during reorder
      MockApiService.simulateVerificationFailure = true;

      final reorderSuccess = await mockApi.reorderFirewallCustomRules(
        '192.168.1.1',
        'auth_token',
        false,
        targetSectionKey: 'rule_1',
        siblingSectionKey: 'rule_2',
        expectedRuleOrder: ['rule_1', 'rule_2'],
      );

      expect(reorderSuccess, isFalse);
      // Order should remain unchanged
      expect(MockApiService.mockCustomRules[0].sectionKey, 'rule_1');
      expect(MockApiService.mockCustomRules[1].sectionKey, 'rule_2');
    });

    test('Lockout-inducing custom rule targeting custom management port is blocked at API layer', () async {
      MockApiService.mockDiscoveredManagementPorts = {22, 80, 443, 8443};

      final success = await mockApi.addFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        rule: const FirewallCustomRule(
          sectionKey: 'lockout_rule',
          name: 'Block LuCI 8443',
          srcZone: 'lan',
          destZone: '',
          destPort: '8443',
          proto: 'tcp',
          target: 'DROP',
          enabled: true,
        ),
      );

      expect(success, isFalse);
      expect(MockApiService.mockCustomRules.isEmpty, isTrue);
    });

    test('All remaining firewall mutation paths abort cleanly on verification failure', () async {
      MockApiService.simulateVerificationFailure = true;

      // updateFirewallPortForward
      final updatePfSuccess = await mockApi.updateFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        portForward: const FirewallPortForwarding(
          sectionKey: 'pf_dummy',
          name: 'PF Dummy',
          srcZone: 'wan',
          srcPort: '8080',
          destZone: 'lan',
          destIp: '192.168.1.50',
          destPort: '8080',
          proto: 'tcp',
        ),
      );
      expect(updatePfSuccess, isFalse);

      // deleteFirewallPortForward
      final deletePfSuccess = await mockApi.deleteFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        sectionKey: 'pf_dummy',
      );
      expect(deletePfSuccess, isFalse);

      // updateFirewallCustomRule
      final updateCrSuccess = await mockApi.updateFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        rule: const FirewallCustomRule(
          sectionKey: 'cr_dummy',
          name: 'CR Dummy',
          srcZone: 'lan',
          destZone: 'wan',
          target: 'ACCEPT',
          enabled: true,
        ),
      );
      expect(updateCrSuccess, isFalse);

      // deleteFirewallCustomRule
      final deleteCrSuccess = await mockApi.deleteFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        sectionKey: 'cr_dummy',
      );
      expect(deleteCrSuccess, isFalse);

      // applyPerDeviceNetworkAccessPolicy
      final policySuccess = await mockApi.applyPerDeviceNetworkAccessPolicy(
        '192.168.1.1',
        'auth_token',
        false,
        policy: NetworkAccessPolicy.blocked('00:aa:bb:cc:dd:ee'),
        capabilities: MockApiService.getRouterCapabilitiesForProfile(
          MockCapabilityProfile.fullModernStack,
        ),
      );
      expect(policySuccess, isFalse);
    });
  });

  group('Acceptance 13: Management Endpoint Discovery & Parsing Mathematics', () {
    test('extractPortsFromUciSpec correctly parses list-form uhttpd listeners', () {
      final ports = <int>{};
      RealApiService.extractPortsFromUciSpec(
        ['0.0.0.0:80', '[::]:80'],
        ports,
      );
      expect(ports, equals({80}));

      RealApiService.extractPortsFromUciSpec(
        ['0.0.0.0:443', '[::]:443', '[::]:8443'],
        ports,
      );
      expect(ports, equals({80, 443, 8443}));
    });

    test('extractPortsFromUciSpec correctly parses multiple Dropbear SSH ports', () {
      final ports = <int>{};
      RealApiService.extractPortsFromUciSpec(['22', '2222'], ports);
      expect(ports, equals({22, 2222}));

      RealApiService.extractPortsFromUciSpec('192.168.1.1:22222', ports);
      expect(ports, equals({22, 2222, 22222}));
    });

    test('extractPortsFromUciSpec rejects pure unbracketed IPv6 without ports', () {
      final ports = <int>{};
      RealApiService.extractPortsFromUciSpec('2001:db8::1', ports);
      RealApiService.extractPortsFromUciSpec('::1', ports);
      RealApiService.extractPortsFromUciSpec('fe80::1ff:fe00:1', ports);
      // None of the trailing hex/decimal parts of an unbracketed IPv6 address should be parsed as ports
      expect(ports, isEmpty);
    });

    test('extractPortsFromUciSpec handles missing, invalid, or out-of-range specs cleanly', () {
      final ports = <int>{};
      RealApiService.extractPortsFromUciSpec(null, ports);
      RealApiService.extractPortsFromUciSpec('', ports);
      RealApiService.extractPortsFromUciSpec('0', ports); // port 0 is invalid
      RealApiService.extractPortsFromUciSpec('70000', ports); // > 65535 is invalid
      RealApiService.extractPortsFromUciSpec('not_a_port', ports);
      RealApiService.extractPortsFromUciSpec([], ports);
      expect(ports, isEmpty);
    });

    test('SelfDeviceGuard stale cache eviction supports targeted and global clearing', () {
      const routerA = 'router_a';
      const routerB = 'router_b';

      SelfDeviceGuard.setDiscoveredManagementPorts(routerA, {8443});
      SelfDeviceGuard.setDiscoveredManagementPorts(routerB, {9443});

      expect(SelfDeviceGuard.getDiscoveredManagementPorts(routerA), contains(8443));
      expect(SelfDeviceGuard.getDiscoveredManagementPorts(routerB), contains(9443));

      // Clear only routerA
      SelfDeviceGuard.clearDiscoveredManagementPorts(routerA);
      // routerA now has standard ports, routerB still has its custom port
      expect(SelfDeviceGuard.getDiscoveredManagementPorts(routerA), isNot(contains(8443)));
      expect(SelfDeviceGuard.getDiscoveredManagementPorts(routerB), contains(9443));

      // Global clear
      SelfDeviceGuard.clearDiscoveredManagementPorts();
      expect(SelfDeviceGuard.getDiscoveredManagementPorts(routerB), isNot(contains(9443)));
    });
  });
}

