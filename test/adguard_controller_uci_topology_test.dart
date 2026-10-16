// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/adguard_home/controllers/adguard_controller.dart';
import 'package:yala/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/operation_queue.dart';

/// Test mock of [IAdGuardApiService] for topology controller tests.
class TopologyTestMockAdGuardApiService implements IAdGuardApiService {
  @override
  final String routerId;

  @override
  String get instanceId => 'local_$routerId';

  @override
  Future<AdGuardConnectionStatus> testConnection({
    AdGuardCredentials? credentials,
  }) async =>
      AdGuardConnectionStatus.authenticated;

  AdGuardStatus status;
  AdGuardStats stats;
  AdGuardFilteringStatus filtering;

  TopologyTestMockAdGuardApiService({
    required this.routerId,
    this.status = const AdGuardStatus(
      version: 'v0.107.52',
      running: true,
      protectionState: AdGuardProtectionState.enabled,
      dnsAddresses: ['192.168.1.1'],
      dnsPort: 53,
      httpPort: 3000,
    ),
    this.stats = const AdGuardStats(
      numDnsQueries: 100,
      numBlockedFiltering: 20,
      numReplacedSafebrowsing: 0,
      numReplacedSafesearch: 0,
      numReplacedParental: 0,
      avgProcessingTime: 0.01,
      topQueriedDomains: [],
      topBlockedDomains: [],
      topClients: [],
      dnsQueriesTrend: [],
      blockedFilteringTrend: [],
      blockRatePercentage: 20.0,
    ),
    this.filtering = const AdGuardFilteringStatus(
      enabled: true,
      filterLists: [],
      userRules: [],
      totalRulesCount: 100,
    ),
  });

  @override
  AdGuardCredentials? get activeCredentials => null;

  @override
  bool get isAuthenticated => true;

  @override
  bool get isAuthRequired => false;

  @override
  void setCredentials(AdGuardCredentials? credentials) {}

  @override
  Future<AdGuardApiResult<AdGuardStatus>> getStatus({
    bool forceProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  }) async {
    return AdGuardApiResult.success(status);
  }

  @override
  Future<AdGuardApiResult<AdGuardStats>> getStats({Duration? recent}) async {
    return AdGuardApiResult.success(stats);
  }

  @override
  Future<AdGuardApiResult<AdGuardFilteringStatus>> getFilteringStatus() async {
    return AdGuardApiResult.success(filtering);
  }

  @override
  Future<AdGuardApiResult<bool>> setProtection({
    required bool enabled,
    Duration? duration,
  }) async {
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> setProtectionState(
    AdGuardProtectionState state, {
    Duration? pauseDuration,
  }) async {
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> setUserRules(List<String> rules) async {
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<List<AdGuardClient>>> getClients() async {
    return AdGuardApiResult.success(const []);
  }

  @override
  Future<AdGuardApiResult<bool>> addClient(AdGuardClient client) async {
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> updateClient(String oldName, AdGuardClient client) async {
    return AdGuardApiResult.success(true);
  }

  List<String> upstreamDns = const ['1.1.1.1', '8.8.8.8'];

  @override
  Future<AdGuardApiResult<List<String>>> getUpstreamDns() async {
    return AdGuardApiResult.success(upstreamDns);
  }

  @override
  Future<AdGuardApiResult<bool>> addFilterList({
    required String name,
    required String url,
    required bool whitelist,
  }) async =>
      AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> setFilterList({
    required String url,
    required String name,
    required String newUrl,
    required bool enabled,
    required bool whitelist,
  }) async =>
      AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> removeFilterList({
    required String url,
    required bool whitelist,
  }) async =>
      AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> refreshFilterLists({bool? whitelist}) async =>
      AdGuardApiResult.success(true);
}

/// Call record tracking LuCI / ubus RPC calls.
class LuciCallRecord {
  final String object;
  final String method;
  final Map<String, dynamic>? params;
  final DateTime timestamp;

  LuciCallRecord({
    required this.object,
    required this.method,
    this.params,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Fake [IApiService] tracking all calls and providing mock UCI get responses.
class TrackingFakeLuciApiService implements IApiService {
  final List<LuciCallRecord> callLog = [];

  dynamic dhcpResponse;
  dynamic firewallResponse;
  bool throwOnDhcp = false;
  bool throwOnFirewall = false;

  Completer<void>? uciCallCompleter;

  int get dhcpQueryCount => callLog.where(
        (c) =>
            c.object == 'uci' &&
            c.method == 'get' &&
            c.params?['config'] == 'dhcp',
      ).length;

  int get firewallQueryCount => callLog.where(
        (c) =>
            c.object == 'uci' &&
            c.method == 'get' &&
            c.params?['config'] == 'firewall',
      ).length;

  int get totalUciCallCount =>
      callLog.where((c) => c.object == 'uci').length;

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    callLog.add(LuciCallRecord(
      object: object,
      method: method,
      params: params != null ? Map<String, dynamic>.from(params) : null,
    ));

    if (uciCallCompleter != null) {
      await uciCallCompleter!.future;
    }

    if (object == 'uci' && method == 'get') {
      final config = params?['config'];
      if (config == 'dhcp') {
        if (throwOnDhcp) {
          throw Exception('Simulated UCI dhcp get error');
        }
        return dhcpResponse ?? {'result': []};
      }
      if (config == 'firewall') {
        if (throwOnFirewall) {
          throw Exception('Simulated UCI firewall get error');
        }
        return firewallResponse ?? {'result': []};
      }
    }

    if (object == 'luci' && method == 'getProcessList') {
      return {
        'result': [
          {
            'PID': '1660',
            'COMMAND': '/usr/bin/AdGuardHome -c /etc/adguardhome.yaml',
            '%CPU': '0.5%',
            '%MEM': '2.0%',
            'VSZ': '24000',
          }
        ]
      };
    }

    return {'result': []};
  }

  @override
  Future<bool> manageServiceAction(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String serviceName,
    required String action,
    BuildContext? context,
  }) async {
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });
  });

  group('AdGuardController — UCI Parser Unit Tests', () {
    test('extractUciValues handles standard rpcd array-wrapped result format', () {
      final input = [
        0,
        {
          'values': {
            'cfg01': {'.type': 'dnsmasq', 'port': '53'}
          }
        }
      ];
      final extracted = AdGuardController.extractUciValues(input);
      expect(extracted, isNotNull);
      expect(extracted!['cfg01']['port'], equals('53'));
    });

    test('extractUciValues handles nested JSON-RPC result map', () {
      final input = {
        'result': [
          0,
          {
            'values': {
              'cfg02': {'.type': 'redirect', 'target': 'DNAT'}
            }
          }
        ]
      };
      final extracted = AdGuardController.extractUciValues(input);
      expect(extracted, isNotNull);
      expect(extracted!['cfg02']['target'], equals('DNAT'));
    });

    test('extractUciValues handles direct values map and raw sections', () {
      final inputValues = {
        'values': {
          'cfg03': {'.type': 'dnsmasq', 'port': 5353}
        }
      };
      final extracted1 = AdGuardController.extractUciValues(inputValues);
      expect(extracted1?['cfg03']['port'], equals(5353));

      final inputRaw = {
        'cfg04': {'.type': 'dnsmasq', 'port': 53}
      };
      final extracted2 = AdGuardController.extractUciValues(inputRaw);
      expect(extracted2?['cfg04']['port'], equals(53));
    });

    test('extractUciValues safely returns null on malformed or empty responses', () {
      expect(AdGuardController.extractUciValues(null), isNull);
      expect(AdGuardController.extractUciValues([]), isNull);
      expect(AdGuardController.extractUciValues({'result': []}), isNull);
      expect(AdGuardController.extractUciValues('malformed string'), isNull);
    });

    test('parseDhcpUci parses numeric and string dnsmasq port correctly', () {
      final valuesNumeric = {
        'cfg01': {'.type': 'dnsmasq', 'port': 5353, 'server': ['127.0.0.1#53']}
      };
      final parsedNum = AdGuardController.parseDhcpUci(valuesNumeric);
      expect(parsedNum.dnsmasqPort, equals(5353));
      expect(parsedNum.dnsmasqServers, equals(['127.0.0.1#53']));

      final valuesString = {
        'cfg02': {'.type': 'dnsmasq', 'port': '5353'}
      };
      final parsedStr = AdGuardController.parseDhcpUci(valuesString);
      expect(parsedStr.dnsmasqPort, equals(5353));
    });

    test('parseDhcpUci falls back to default port 53 when port is omitted', () {
      final values = {
        'cfg01': {'.type': 'dnsmasq'}
      };
      final parsed = AdGuardController.parseDhcpUci(values);
      expect(parsed.dnsmasqPort, equals(53));
      expect(parsed.dnsmasqServers, isEmpty);
    });

    test('parseDhcpUci handles single string server option and trims values', () {
      final values = {
        'cfg01': {
          '.type': 'dnsmasq',
          'server': ' 127.0.0.1#3000 ',
        }
      };
      final parsed = AdGuardController.parseDhcpUci(values);
      expect(parsed.dnsmasqServers, equals(['127.0.0.1#3000']));
    });

    test('parseFirewallUci detects DNAT redirect on port 53', () {
      final values = {
        'cfg01': {
          '.type': 'redirect',
          'target': 'DNAT',
          'src_dport': '53',
        }
      };
      expect(AdGuardController.parseFirewallUci(values), isTrue);
    });

    test('parseFirewallUci handles omitted target defaulting to DNAT in OpenWrt', () {
      final values = {
        'cfg01': {
          '.type': 'redirect',
          'src_dport': 53,
        }
      };
      expect(AdGuardController.parseFirewallUci(values), isTrue);
    });

    test('parseFirewallUci handles comma-separated, space-separated, and list ports', () {
      final valuesComma = {
        'cfg01': {
          '.type': 'redirect',
          'target': 'DNAT',
          'src_dport': '53, 5353',
        }
      };
      expect(AdGuardController.parseFirewallUci(valuesComma), isTrue);

      final valuesList = {
        'cfg02': {
          '.type': 'redirect',
          'target': 'DNAT',
          'src_dport': ['53', '5353'],
        }
      };
      expect(AdGuardController.parseFirewallUci(valuesList), isTrue);
    });

    test('parseFirewallUci ignores non-port-53 or non-DNAT rules', () {
      final valuesOtherPort = {
        'cfg01': {
          '.type': 'redirect',
          'target': 'DNAT',
          'src_dport': '80 443',
        }
      };
      expect(AdGuardController.parseFirewallUci(valuesOtherPort), isFalse);

      final valuesAccept = {
        'cfg02': {
          '.type': 'redirect',
          'target': 'ACCEPT',
          'src_dport': '53',
        }
      };
      expect(AdGuardController.parseFirewallUci(valuesAccept), isFalse);
    });
  });

  group('AdGuardController — Mode A/B/C Topology Inference', () {
    test('Mode A (AdGuard Primary): dnsmasq relocated to 5353, AGH on 53', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..dhcpResponse = [
          0,
          {
            'values': {
              'cfg01': {'.type': 'dnsmasq', 'port': '5353'}
            }
          }
        ]
        ..firewallResponse = [0, {'values': {}}];

      final mockApi = TopologyTestMockAdGuardApiService(
        routerId: 'router-1',
        status: const AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        ),
      );

      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
        operationQueueOverride: RouterScopedOperationQueue.instance,
      );

      await controller.refresh();

      expect(controller.state.topology.mode,
          equals(AdGuardTopologyMode.adguardPrimary));
      expect(controller.state.topology.adguardDnsPort, equals(53));
      expect(controller.state.topology.dnsmasqPort, equals(5353));
      expect(controller.cachedDnsmasqPort, equals(5353));
      expect(controller.cachedHasDnatRedirect, isFalse);
      controller.dispose();
    });

    test('Mode B (dnsmasq Forwarder): dnsmasq on 53 forwarding to AGH on 3000', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..dhcpResponse = [
          0,
          {
            'values': {
              'cfg01': {
                '.type': 'dnsmasq',
                'port': '53',
                'server': ['127.0.0.1#3000']
              }
            }
          }
        ]
        ..firewallResponse = [0, {'values': {}}];

      final mockApi = TopologyTestMockAdGuardApiService(
        routerId: 'router-1',
        status: const AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 3000,
          httpPort: 8080,
        ),
      );

      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
        operationQueueOverride: RouterScopedOperationQueue.instance,
      );

      await controller.refresh();

      expect(controller.state.topology.mode,
          equals(AdGuardTopologyMode.dnsmasqForwarder));
      expect(controller.state.topology.adguardDnsPort, equals(3000));
      expect(controller.state.topology.dnsmasqPort, equals(53));
      expect(controller.cachedDnsmasqServers, equals(['127.0.0.1#3000']));
      controller.dispose();
    });

    test('Mode C (Firewall Redirect): Port 53 DNAT rule redirects to AGH on 3000', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..dhcpResponse = [
          0,
          {
            'values': {
              'cfg01': {'.type': 'dnsmasq', 'port': '53'}
            }
          }
        ]
        ..firewallResponse = [
          0,
          {
            'values': {
              'cfg02': {
                '.type': 'redirect',
                'target': 'DNAT',
                'src_dport': '53',
              }
            }
          }
        ];

      final mockApi = TopologyTestMockAdGuardApiService(
        routerId: 'router-1',
        status: const AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 3000,
          httpPort: 8080,
        ),
      );

      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
        operationQueueOverride: RouterScopedOperationQueue.instance,
      );

      await controller.refresh();

      expect(controller.state.topology.mode,
          equals(AdGuardTopologyMode.firewallRedirect));
      expect(controller.state.topology.hasFirewallRedirect, isTrue);
      expect(controller.cachedHasDnatRedirect, isTrue);
      controller.dispose();
    });
  });

  group('AdGuardController — 5-Minute Cache & Lifecycle Tests', () {
    test('Cache Hit: Initial refresh queries UCI; second refresh within TTL skips UCI', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..dhcpResponse = [
          0,
          {
            'values': {
              'cfg01': {'.type': 'dnsmasq', 'port': '5353'}
            }
          }
        ]
        ..firewallResponse = [0, {'values': {}}];

      final mockApi = TopologyTestMockAdGuardApiService(routerId: 'router-1');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
        operationQueueOverride: RouterScopedOperationQueue.instance,
      );

      // 1. Initial refresh: cache miss -> probes UCI
      await controller.refresh();
      expect(fakeLuci.dhcpQueryCount, equals(1));
      expect(fakeLuci.firewallQueryCount, equals(1));
      expect(controller.hasValidTopologyCache, isTrue);
      final initialProbeTime = controller.topologyCacheProbedAt;
      expect(initialProbeTime, isNotNull);

      // 2. Immediate second refresh (e.g. background poll): cache hit -> 0 additional UCI calls
      await controller.refresh();
      expect(fakeLuci.dhcpQueryCount, equals(1)); // Still 1!
      expect(fakeLuci.firewallQueryCount, equals(1)); // Still 1!
      expect(controller.topologyCacheProbedAt, equals(initialProbeTime));

      controller.dispose();
    });

    test('Cache Miss / TTL Expiry: Expired cache (>5m) re-probes UCI', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..dhcpResponse = [
          0,
          {
            'values': {
              'cfg01': {'.type': 'dnsmasq', 'port': '5353'}
            }
          }
        ]
        ..firewallResponse = [0, {'values': {}}];

      final mockApi = TopologyTestMockAdGuardApiService(routerId: 'router-1');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
        operationQueueOverride: RouterScopedOperationQueue.instance,
      );

      // Seed an expired cache from 6 minutes ago
      final expiredTime = DateTime.now().toUtc().subtract(const Duration(minutes: 6));
      controller.setCachedTopologyForTesting(
        dnsmasqPort: 5353,
        dnsmasqServers: [],
        hasDnatRedirect: false,
        probedAt: expiredTime,
      );

      expect(controller.hasValidTopologyCache, isFalse);

      // Refresh triggers fresh UCI probe due to TTL expiry
      await controller.refresh();
      expect(fakeLuci.dhcpQueryCount, equals(1));
      expect(fakeLuci.firewallQueryCount, equals(1));
      expect(controller.hasValidTopologyCache, isTrue);
      expect(controller.topologyCacheProbedAt!.isAfter(expiredTime), isTrue);

      controller.dispose();
    });

    test('forceTopologyProbe: true forces UCI probe even on fresh cache (<5m)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..dhcpResponse = [
          0,
          {
            'values': {
              'cfg01': {'.type': 'dnsmasq', 'port': '5353'}
            }
          }
        ]
        ..firewallResponse = [0, {'values': {}}];

      final mockApi = TopologyTestMockAdGuardApiService(routerId: 'router-1');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
        operationQueueOverride: RouterScopedOperationQueue.instance,
      );

      // Seed a fresh cache from 1 minute ago
      final freshTime = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      controller.setCachedTopologyForTesting(
        dnsmasqPort: 5353,
        dnsmasqServers: [],
        hasDnatRedirect: false,
        probedAt: freshTime,
      );

      expect(controller.hasValidTopologyCache, isTrue);

      // Manual refresh with forceTopologyProbe: true must bypass valid cache
      await controller.refresh(forceTopologyProbe: true);
      expect(fakeLuci.dhcpQueryCount, equals(1));
      expect(fakeLuci.firewallQueryCount, equals(1));
      expect(controller.topologyCacheProbedAt!.isAfter(freshTime), isTrue);

      controller.dispose();
    });

    test('dispose() clears the in-memory topology cache', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..dhcpResponse = [
          0,
          {
            'values': {
              'cfg01': {'.type': 'dnsmasq', 'port': '5353'}
            }
          }
        ]
        ..firewallResponse = [0, {'values': {}}];

      final mockApi = TopologyTestMockAdGuardApiService(routerId: 'router-1');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
        operationQueueOverride: RouterScopedOperationQueue.instance,
      );

      await controller.refresh();
      expect(controller.hasValidTopologyCache, isTrue);

      controller.dispose();
      expect(controller.hasValidTopologyCache, isFalse);
      expect(controller.topologyCacheProbedAt, isNull);
      expect(controller.cachedDnsmasqPort, isNull);
    });

    test('Router isolation: separate controllers maintain independent caches', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuciA = TrackingFakeLuciApiService()
        ..dhcpResponse = [
          0,
          {
            'values': {
              'cfg01': {'.type': 'dnsmasq', 'port': '5353'}
            }
          }
        ];
      final fakeLuciB = TrackingFakeLuciApiService()
        ..dhcpResponse = [
          0,
          {
            'values': {
              'cfg01': {'.type': 'dnsmasq', 'port': '53'}
            }
          }
        ];

      final mockApiA = TopologyTestMockAdGuardApiService(routerId: 'router-A');
      final mockApiB = TopologyTestMockAdGuardApiService(routerId: 'router-B');

      final controllerA = AdGuardController(
        container.read(adguardControllerProvider('router-A').notifier).ref,
        'router-A',
        apiServiceOverride: mockApiA,
        luciApiServiceOverride: fakeLuciA,
      );
      final controllerB = AdGuardController(
        container.read(adguardControllerProvider('router-B').notifier).ref,
        'router-B',
        apiServiceOverride: mockApiB,
        luciApiServiceOverride: fakeLuciB,
      );

      await controllerA.refresh();
      await controllerB.refresh();

      expect(controllerA.cachedDnsmasqPort, equals(5353));
      expect(controllerB.cachedDnsmasqPort, equals(53));

      controllerA.dispose();
      controllerB.dispose();
    });
  });

  group('AdGuardController — Failure Resilience & Safety Invariants', () {
    test('UCI RPC failure falls back to safe defaults without failing refresh', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..throwOnDhcp = true
        ..throwOnFirewall = true;

      final mockApi = TopologyTestMockAdGuardApiService(routerId: 'router-1');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
        operationQueueOverride: RouterScopedOperationQueue.instance,
      );

      // Refresh must succeed despite UCI probe failure
      await controller.refresh();

      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.authenticated));
      expect(controller.state.status, isNotNull);
      // Safe defaults applied
      expect(controller.state.topology.dnsmasqPort, equals(53));
      expect(controller.state.topology.forwarders, isEmpty);
      expect(controller.state.topology.hasFirewallRedirect, isFalse);

      controller.dispose();
    });

    test('UCI RPC failure preserves previously cached topology if available', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..throwOnDhcp = true
        ..throwOnFirewall = true;

      final mockApi = TopologyTestMockAdGuardApiService(routerId: 'router-1');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
        operationQueueOverride: RouterScopedOperationQueue.instance,
      );

      // Seed valid cache
      controller.setCachedTopologyForTesting(
        dnsmasqPort: 5353,
        dnsmasqServers: ['127.0.0.1#53'],
        hasDnatRedirect: true,
        probedAt: DateTime.now().toUtc(),
      );

      // Refresh with forced probe that fails
      await controller.refresh(forceTopologyProbe: true);

      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.authenticated));
      expect(controller.state.topology.dnsmasqPort, equals(5353));
      expect(controller.state.topology.forwarders, equals(['127.0.0.1#53']));
      expect(controller.state.topology.hasFirewallRedirect, isTrue);

      controller.dispose();
    });

    test('Reviewer Mode Isolation: Zero UCI calls made even with forceTopologyProbe: true', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService();
      final mockApi = TopologyTestMockAdGuardApiService(
        routerId: 'reviewer-mock-router',
      );

      final controller = AdGuardController(
        container.read(adguardControllerProvider('reviewer-mock-router').notifier).ref,
        'reviewer-mock-router',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
      );

      await controller.refresh(forceTopologyProbe: true);

      // ZERO UCI calls under any circumstance
      expect(fakeLuci.totalUciCallCount, equals(0));
      expect(fakeLuci.dhcpQueryCount, equals(0));
      expect(fakeLuci.firewallQueryCount, equals(0));

      controller.dispose();
    });

    test('Read-only guarantee: Controller NEVER calls mutating uci operations', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final fakeLuci = TrackingFakeLuciApiService()
        ..dhcpResponse = [0, {'values': {}}]
        ..firewallResponse = [0, {'values': {}}];

      final mockApi = TopologyTestMockAdGuardApiService(routerId: 'router-1');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-1').notifier).ref,
        'router-1',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
      );

      await controller.refresh(forceTopologyProbe: true);

      final mutatingMethods = ['set', 'add', 'delete', 'commit', 'apply', 'revert'];
      for (final call in fakeLuci.callLog) {
        if (call.object == 'uci') {
          expect(mutatingMethods.contains(call.method), isFalse,
              reason: 'Forbidden UCI mutation method called: ${call.method}');
          expect(call.method, equals('get'));
        }
      }

      controller.dispose();
    });
  });
}
