// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/services/mock_adguard_api_service.dart';
import 'package:yala/modules/domain_blocking/models/domain_block_rule.dart';
import 'package:yala/modules/domain_blocking/services/domain_blocking_service.dart';
import 'package:yala/services/mock_api_service.dart';

void main() {
  group('DomainBlockingService - Engine Selection', () {
    late MockApiService mockApi;
    late MockAdGuardApiService mockAdGuard;

    setUp(() {
      MockApiService.resetMockState();
      mockApi = MockApiService();
      mockAdGuard = MockAdGuardApiService(requiresAuth: false);
    });

    test('selects AdGuard Home when installed, authed, and in adguardPrimary mode', () {
      final capabilities = RouterCapabilities.mock(); // hasAdGuardHome: true, hasUciWriteAccess: true
      const topology = AdGuardDnsTopology(
        mode: AdGuardTopologyMode.adguardPrimary,
        adguardDnsPort: 53,
        dnsmasqPort: 5353,
        forwarders: ['127.0.0.1#5353'],
        hasFirewallRedirect: false,
        isIpv6Supported: true,
        description: 'Primary',
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        topology: topology,
        routerId: 'router-1',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      expect(service.resolveEngine(), DnsBlockingEngine.adguardHome);
    });

    test('selects AdGuard Home in firewallRedirect mode', () {
      final capabilities = RouterCapabilities.mock();
      const topology = AdGuardDnsTopology(
        mode: AdGuardTopologyMode.firewallRedirect,
        adguardDnsPort: 5353,
        dnsmasqPort: 53,
        forwarders: [],
        hasFirewallRedirect: true,
        isIpv6Supported: true,
        description: 'Firewall Redirect',
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        topology: topology,
        routerId: 'router-1',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      expect(service.resolveEngine(), DnsBlockingEngine.adguardHome);
    });

    test('selects AdGuard Home in dnsmasqForwarder mode', () {
      final capabilities = RouterCapabilities.mock();
      const topology = AdGuardDnsTopology(
        mode: AdGuardTopologyMode.dnsmasqForwarder,
        adguardDnsPort: 5353,
        dnsmasqPort: 53,
        forwarders: ['127.0.0.1#5353'],
        hasFirewallRedirect: false,
        isIpv6Supported: true,
        description: 'Forwarder',
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        topology: topology,
        routerId: 'router-1',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      expect(service.resolveEngine(), DnsBlockingEngine.adguardHome);
    });

    test('falls back to native dnsmasq when AdGuard is in standalone mode and UCI write is available', () {
      final capabilities = RouterCapabilities.mock();
      const topology = AdGuardDnsTopology(
        mode: AdGuardTopologyMode.standalone,
        adguardDnsPort: 5353,
        dnsmasqPort: 53,
        forwarders: [],
        hasFirewallRedirect: false,
        isIpv6Supported: false,
        description: 'Standalone',
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        topology: topology,
        routerId: 'router-1',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      expect(service.resolveEngine(), DnsBlockingEngine.dnsmasqNative);
    });

    test('falls back to native dnsmasq when AdGuard Home requires authentication but is unauthenticated', () {
      final unauthedAdGuard = MockAdGuardApiService(requiresAuth: true);
      final capabilities = RouterCapabilities.mock();
      const topology = AdGuardDnsTopology(
        mode: AdGuardTopologyMode.adguardPrimary,
        adguardDnsPort: 53,
        dnsmasqPort: 5353,
        forwarders: [],
        hasFirewallRedirect: false,
        isIpv6Supported: true,
        description: 'Primary',
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: unauthedAdGuard,
        capabilities: capabilities,
        topology: topology,
        routerId: 'router-1',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      expect(service.resolveEngine(), DnsBlockingEngine.dnsmasqNative);
    });

    test('selects native dnsmasq when AdGuard Home is not installed on router', () {
      final capabilities = RouterCapabilities(
        routerId: 'router-legacy',
        probedAt: DateTime.now(),
        hasAdGuardHome: false,
        ubusObjects: const {'uci'},
        ubusMethods: const {
          'uci': ['set', 'apply', 'commit', 'get'],
        },
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        routerId: 'router-legacy',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      expect(service.resolveEngine(), DnsBlockingEngine.dnsmasqNative);
    });

    test('selects none when router has neither AdGuard nor UCI write access', () {
      final capabilities = RouterCapabilities(
        routerId: 'router-ro',
        probedAt: DateTime.now(),
        hasAdGuardHome: false,
        ubusObjects: const {'system'},
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        routerId: 'router-ro',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      expect(service.resolveEngine(), DnsBlockingEngine.none);
    });
  });

  group('DomainBlockingService - Policy Retrieval & Mutation', () {
    late MockApiService mockApi;
    late MockAdGuardApiService mockAdGuard;

    setUp(() {
      MockApiService.resetMockState();
      mockApi = MockApiService();
      mockAdGuard = MockAdGuardApiService(requiresAuth: false);
    });

    test('getPolicyState retrieves AdGuard Home rules and reports supported scopes', () async {
      final capabilities = RouterCapabilities.mock();
      const topology = AdGuardDnsTopology(
        mode: AdGuardTopologyMode.adguardPrimary,
        adguardDnsPort: 53,
        dnsmasqPort: 5353,
        forwarders: [],
        hasFirewallRedirect: false,
        isIpv6Supported: true,
        description: 'Primary',
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        topology: topology,
        routerId: 'router-1',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      final state = await service.getPolicyState();
      expect(state.activeEngine, DnsBlockingEngine.adguardHome);
      expect(state.isFilteringActive, isTrue);
      expect(state.supportedScopes, contains(DomainBlockScope.global));
      expect(state.supportedScopes, contains(DomainBlockScope.perDevice));
      expect(state.globalRules.map((r) => r.domain), contains('tracker.example.com'));
      expect(state.globalRules.map((r) => r.domain), contains('telemetry.sample.net'));
      // @@ allowlist rule should NOT be included in blocked rules
      expect(state.globalRules.map((r) => r.domain), isNot(contains('allowed.workplace.com')));
    });

    test('getPolicyState in dnsmasqForwarder warns of per-device limitation', () async {
      final capabilities = RouterCapabilities.mock();
      const topology = AdGuardDnsTopology(
        mode: AdGuardTopologyMode.dnsmasqForwarder,
        adguardDnsPort: 5353,
        dnsmasqPort: 53,
        forwarders: ['127.0.0.1#5353'],
        hasFirewallRedirect: false,
        isIpv6Supported: true,
        description: 'Forwarder',
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        topology: topology,
        routerId: 'router-1',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      final state = await service.getPolicyState();
      expect(state.activeEngine, DnsBlockingEngine.adguardHome);
      expect(state.supportedScopes, equals({DomainBlockScope.global}));
      expect(state.warning, contains('All LAN DNS queries pass through dnsmasq'));
    });

    test('addGlobalDomain and removeGlobalDomain operate on AdGuard Home', () async {
      final capabilities = RouterCapabilities.mock();
      const topology = AdGuardDnsTopology(
        mode: AdGuardTopologyMode.adguardPrimary,
        adguardDnsPort: 53,
        dnsmasqPort: 5353,
        forwarders: [],
        hasFirewallRedirect: false,
        isIpv6Supported: true,
        description: 'Primary',
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        topology: topology,
        routerId: 'router-1',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      // Add
      final addResult = await service.addGlobalDomain('HTTPS://TIKTOK.COM/browse');
      expect(addResult.success, isTrue);
      expect(addResult.engine, DnsBlockingEngine.adguardHome);

      final stateAfterAdd = await service.getPolicyState();
      expect(stateAfterAdd.globalRules.map((r) => r.domain), contains('tiktok.com'));

      // Remove
      final removeResult = await service.removeGlobalDomain('tiktok.com');
      expect(removeResult.success, isTrue);
      expect(removeResult.engine, DnsBlockingEngine.adguardHome);

      final stateAfterRemove = await service.getPolicyState();
      expect(stateAfterRemove.globalRules.map((r) => r.domain), isNot(contains('tiktok.com')));
    });

    test('addGlobalDomain and removeGlobalDomain operate on native dnsmasq', () async {
      final capabilities = RouterCapabilities(
        routerId: 'router-native',
        probedAt: DateTime.now(),
        hasAdGuardHome: false,
        ubusObjects: const {'uci'},
        ubusMethods: const {
          'uci': ['set', 'apply', 'commit', 'get'],
        },
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        routerId: 'router-native',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      // Read initial
      final initialState = await service.getPolicyState();
      expect(initialState.activeEngine, DnsBlockingEngine.dnsmasqNative);
      expect(initialState.globalRules.map((r) => r.domain), contains('ads.example.com'));

      // Add
      final addResult = await service.addGlobalDomain('facebook.com');
      expect(addResult.success, isTrue);
      expect(addResult.engine, DnsBlockingEngine.dnsmasqNative);

      final stateAfterAdd = await service.getPolicyState();
      expect(stateAfterAdd.globalRules.map((r) => r.domain), contains('facebook.com'));

      // Remove
      final removeResult = await service.removeGlobalDomain('facebook.com');
      expect(removeResult.success, isTrue);

      final stateAfterRemove = await service.getPolicyState();
      expect(stateAfterRemove.globalRules.map((r) => r.domain), isNot(contains('facebook.com')));
    });

    test('validates domain input before attempting mutation', () async {
      final capabilities = RouterCapabilities.mock();
      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        routerId: 'router-1',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      final badResult = await service.addGlobalDomain('invalid..domain');
      expect(badResult.success, isFalse);
      expect(badResult.message, contains('consecutive dots'));
    });

    test('serializes concurrent mutations on operation queue', () async {
      final capabilities = RouterCapabilities.mock();
      const topology = AdGuardDnsTopology(
        mode: AdGuardTopologyMode.adguardPrimary,
        adguardDnsPort: 53,
        dnsmasqPort: 5353,
        forwarders: [],
        hasFirewallRedirect: false,
        isIpv6Supported: true,
        description: 'Primary',
      );

      final service = DomainBlockingService(
        apiService: mockApi,
        adguardApiService: mockAdGuard,
        capabilities: capabilities,
        topology: topology,
        routerId: 'router-concurrent',
        ipAddress: '192.168.1.1',
        sysauth: 'token',
        useHttps: false,
      );

      final futures = [
        service.addGlobalDomain('site1.com'),
        service.addGlobalDomain('site2.com'),
        service.addGlobalDomain('site3.com'),
      ];

      final results = await Future.wait(futures);
      for (final res in results) {
        expect(res.success, isTrue);
      }

      final finalState = await service.getPolicyState();
      final domains = finalState.globalRules.map((r) => r.domain).toSet();
      expect(domains, contains('site1.com'));
      expect(domains, contains('site2.com'));
      expect(domains, contains('site3.com'));
    });
  });
}
