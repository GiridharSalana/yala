// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../services/interfaces/api_service_interface.dart';
import '../../../state/app_state.dart';
import '../models/dns_benchmark_models.dart';
import '../services/dns_benchmark_service.dart';
import '../services/dns_provider_registry.dart';
import '../services/dns_router_discovery.dart';

@immutable
class DnsBenchmarkState {
  final bool isRunning;
  final DnsVantagePoint vantagePoint;
  final DnsProtocol protocol;
  final RouterDnsConfig? routerDnsConfig;
  final DnsBenchmarkResult? routerResult;
  final List<DnsBenchmarkResult> publicResults;
  final DnsBenchmarkResult? fastestProvider;
  final DateTime? lastRunTimestamp;
  final String? activeProviderId;
  final String? errorMessage;
  final bool isCustomDnsEnabled;
  final String customDnsIp;

  const DnsBenchmarkState({
    this.isRunning = false,
    this.vantagePoint = DnsVantagePoint.clientDevice,
    this.protocol = DnsProtocol.udpPort53,
    this.routerDnsConfig,
    this.routerResult,
    required this.publicResults,
    this.fastestProvider,
    this.lastRunTimestamp,
    this.activeProviderId,
    this.errorMessage,
    this.isCustomDnsEnabled = false,
    this.customDnsIp = '',
  });

  /// Builds a [DnsProviderMetadata] if custom DNS is enabled and the IP is valid.
  DnsProviderMetadata? get customDnsProvider {
    if (!isCustomDnsEnabled) return null;
    final ip = customDnsIp.trim();
    if (ip.isEmpty || InternetAddress.tryParse(ip) == null) return null;
    return DnsProviderMetadata(
      id: 'custom_dns',
      name: 'Custom DNS ($ip)',
      primaryServer: ip,
      secondaryServer: ip,
      description: 'Custom DNS Resolver • $ip',
      features: const ['Custom'],
    );
  }

  /// Factory creating the initial pre-test state with public providers sorted alphabetically.
  factory DnsBenchmarkState.initial() {
    final initialList = DnsProviderRegistry.publicProviders.map((p) {
      return DnsBenchmarkResult(
        provider: p,
        status: DnsBenchmarkStatus.untested,
        testedEndpoint: '${p.primaryServer}:53',
        protocol: DnsProtocol.udpPort53,
        vantagePoint: DnsVantagePoint.clientDevice,
      );
    }).toList();

    // Enforce initial alphabetical sorting
    final sortedAlphabetical = DnsBenchmarkResult.sortAlphabetical(initialList);

    return DnsBenchmarkState(publicResults: sortedAlphabetical);
  }

  DnsBenchmarkState copyWith({
    bool? isRunning,
    DnsVantagePoint? vantagePoint,
    DnsProtocol? protocol,
    RouterDnsConfig? routerDnsConfig,
    DnsBenchmarkResult? routerResult,
    List<DnsBenchmarkResult>? publicResults,
    DnsBenchmarkResult? fastestProvider,
    DateTime? lastRunTimestamp,
    String? activeProviderId,
    String? errorMessage,
    bool? isCustomDnsEnabled,
    String? customDnsIp,
  }) {
    return DnsBenchmarkState(
      isRunning: isRunning ?? this.isRunning,
      vantagePoint: vantagePoint ?? this.vantagePoint,
      protocol: protocol ?? this.protocol,
      routerDnsConfig: routerDnsConfig ?? this.routerDnsConfig,
      routerResult: routerResult ?? this.routerResult,
      publicResults: publicResults ?? this.publicResults,
      fastestProvider: fastestProvider ?? this.fastestProvider,
      lastRunTimestamp: lastRunTimestamp ?? this.lastRunTimestamp,
      activeProviderId: activeProviderId,
      errorMessage: errorMessage,
      isCustomDnsEnabled: isCustomDnsEnabled ?? this.isCustomDnsEnabled,
      customDnsIp: customDnsIp ?? this.customDnsIp,
    );
  }
}

final dnsBenchmarkServiceProvider = Provider<IDnsBenchmarkService>((ref) {
  final appState = ref.watch(appStateProvider);
  return DnsBenchmarkService(api: appState.apiService);
});

final dnsBenchmarkControllerProvider =
    StateNotifierProvider<DnsBenchmarkController, DnsBenchmarkState>((ref) {
      final service = ref.watch(dnsBenchmarkServiceProvider);
      return DnsBenchmarkController(ref, service);
    });

class DnsBenchmarkController extends StateNotifier<DnsBenchmarkState> {
  final Ref _ref;
  final IDnsBenchmarkService _service;

  DnsBenchmarkController(this._ref, this._service)
    : super(DnsBenchmarkState.initial());

  AppState get _appState => _ref.read(appStateProvider);
  IApiService? get _api => _appState.apiService;

  String? get _routerIp =>
      _appState.selectedRouter?.ipAddress ??
      (_appState.reviewerModeEnabled ? '192.168.1.1' : null);

  String? get _sysauth =>
      _appState.sysauth ??
      (_appState.reviewerModeEnabled ? 'mock_auth_token' : null);

  bool get _useHttps => _appState.selectedRouter?.useHttps ?? false;

  void setVantagePoint(DnsVantagePoint vp) {
    if (state.isRunning) return;
    state = state.copyWith(
      vantagePoint: vp,
      protocol: vp == DnsVantagePoint.router
          ? DnsProtocol.routerNslookup
          : DnsProtocol.udpPort53,
    );
  }

  void toggleCustomDns(bool enabled) {
    if (state.isRunning) return;
    state = state.copyWith(isCustomDnsEnabled: enabled);
    _rebuildResolverList();
  }

  void updateCustomDns(String ip) {
    if (state.isRunning) return;
    state = state.copyWith(customDnsIp: ip);
    _rebuildResolverList();
  }

  void _rebuildResolverList() {
    final customProvider = state.customDnsProvider;
    final providers = <DnsProviderMetadata>[
      ...DnsProviderRegistry.publicProviders,
      ?customProvider,
    ];

    if (state.lastRunTimestamp == null) {
      // Untested: keep alphabetical A-Z
      final list = providers.map((p) {
        return DnsBenchmarkResult(
          provider: p,
          status: DnsBenchmarkStatus.untested,
          testedEndpoint: '${p.primaryServer}:53',
          protocol: state.protocol,
          vantagePoint: state.vantagePoint,
        );
      }).toList();
      state = state.copyWith(
        publicResults: DnsBenchmarkResult.sortAlphabetical(list),
      );
    } else {
      // Retain already-tested results, adding custom as untested if not present
      final currentMap = {
        for (final r in state.publicResults) r.provider.id: r,
      };
      final updated = <DnsBenchmarkResult>[];
      for (final p in providers) {
        if (currentMap.containsKey(p.id)) {
          updated.add(currentMap[p.id]!);
        } else {
          updated.add(
            DnsBenchmarkResult(
              provider: p,
              status: DnsBenchmarkStatus.untested,
              testedEndpoint: '${p.primaryServer}:53',
              protocol: state.protocol,
              vantagePoint: state.vantagePoint,
            ),
          );
        }
      }
      state = state.copyWith(
        publicResults: DnsBenchmarkResult.sortByAscendingLatency(updated),
      );
    }
  }

  Future<void> discoverRouterDns() async {
    final ip = _routerIp;
    final auth = _sysauth;
    final api = _api;

    if (ip == null) {
      state = state.copyWith(routerDnsConfig: RouterDnsConfig.unknown());
      return;
    }

    if (api == null || auth == null) {
      // Offline or minimal info
      final cfg = RouterDnsConfig(
        isLocalForwarder: true,
        localEndpoint: '$ip:53',
        upstreamServers: const ['ISP Assigned (WAN)'],
        isVerified: false,
        details: 'Local resolver on $ip:53 (unverified upstream)',
      );
      state = state.copyWith(
        routerDnsConfig: cfg,
        routerResult: DnsBenchmarkResult(
          provider: DnsProviderRegistry.createRouterDnsProvider(
            routerIp: ip,
            config: cfg,
          ),
          status: DnsBenchmarkStatus.untested,
          testedEndpoint: '$ip:53',
          protocol: state.protocol,
          vantagePoint: state.vantagePoint,
          routerDnsConfig: cfg,
        ),
      );
      return;
    }

    try {
      final discovery = DnsRouterDiscovery(api);
      final cfg = await discovery.discover(
        ipAddress: ip,
        sysauth: auth,
        useHttps: _useHttps,
        cachedDashboardData: _appState.dashboardData,
      );

      final routerProvider = DnsProviderRegistry.createRouterDnsProvider(
        routerIp: ip,
        config: cfg,
      );

      state = state.copyWith(
        routerDnsConfig: cfg,
        routerResult: DnsBenchmarkResult(
          provider: routerProvider,
          status: DnsBenchmarkStatus.untested,
          testedEndpoint: '$ip:53',
          protocol: state.protocol,
          vantagePoint: state.vantagePoint,
          routerDnsConfig: cfg,
        ),
      );
    } catch (e) {
      debugPrint('DnsBenchmarkController: discoverRouterDns error: $e');
    }
  }

  Future<void> startBenchmark({int sampleCount = 3}) async {
    // Single flight lock
    if (state.isRunning) return;

    final ip = _routerIp ?? '192.168.1.1';
    final auth = _sysauth;

    // Discover router config if not present
    if (state.routerDnsConfig == null) {
      await discoverRouterDns();
    }

    final effectiveRouterConfig =
        state.routerDnsConfig ?? RouterDnsConfig.unknown();
    final routerProvider = DnsProviderRegistry.createRouterDnsProvider(
      routerIp: ip,
      config: effectiveRouterConfig,
    );

    // Initial alphabetical reset of public & custom providers for the active run
    final customProvider = state.customDnsProvider;
    final allProviders = <DnsProviderMetadata>[
      ...DnsProviderRegistry.publicProviders,
      ?customProvider,
    ];

    final preTestList = DnsBenchmarkResult.sortAlphabetical(
      allProviders.map((p) {
        return DnsBenchmarkResult(
          provider: p,
          status: DnsBenchmarkStatus.untested,
          testedEndpoint: '${p.primaryServer}:53',
          protocol: state.protocol,
          vantagePoint: state.vantagePoint,
        );
      }).toList(),
    );

    state = state.copyWith(
      isRunning: true,
      errorMessage: null,
      routerResult: DnsBenchmarkResult(
        provider: routerProvider,
        status: DnsBenchmarkStatus.testing,
        testedEndpoint: '$ip:53',
        protocol: state.protocol,
        vantagePoint: state.vantagePoint,
        routerDnsConfig: effectiveRouterConfig,
      ),
      publicResults: preTestList,
      fastestProvider: null,
    );

    // 1. Benchmark Router DNS first
    DnsBenchmarkResult routerFinal;
    try {
      routerFinal = await _service.benchmarkProvider(
        provider: routerProvider,
        vantagePoint: state.vantagePoint,
        protocol: state.protocol,
        sampleCount: sampleCount,
        routerIp: ip,
        routerSysauth: auth,
        routerUseHttps: _useHttps,
      );
    } catch (e) {
      routerFinal = DnsBenchmarkResult(
        provider: routerProvider,
        status: DnsBenchmarkStatus.unreachable,
        testedEndpoint: '$ip:53',
        protocol: state.protocol,
        vantagePoint: state.vantagePoint,
        errorMessage: e.toString(),
      );
    }

    state = state.copyWith(routerResult: routerFinal);

    // 2. Benchmark Public & Custom Providers sequentially (stable pre-test ordering while running)
    final runningResults = List<DnsBenchmarkResult>.from(preTestList);

    for (int i = 0; i < runningResults.length; i++) {
      if (!state.isRunning) break; // cancelled

      final item = runningResults[i];
      state = state.copyWith(activeProviderId: item.provider.id);

      // Update current item to testing status
      runningResults[i] = item.copyWith(status: DnsBenchmarkStatus.testing);
      state = state.copyWith(publicResults: List.unmodifiable(runningResults));

      DnsBenchmarkResult measured;
      try {
        measured = await _service.benchmarkProvider(
          provider: item.provider,
          vantagePoint: state.vantagePoint,
          protocol: state.protocol,
          sampleCount: sampleCount,
          routerIp: ip,
          routerSysauth: auth,
          routerUseHttps: _useHttps,
        );
      } catch (e) {
        measured = item.copyWith(
          status: DnsBenchmarkStatus.unreachable,
          errorMessage: e.toString(),
        );
      }

      runningResults[i] = measured;
      state = state.copyWith(publicResults: List.unmodifiable(runningResults));
    }

    // 3. Post-Test Sorting: Rank by ascending median latency (lowest latency first)
    final sortedAscending = DnsBenchmarkResult.sortByAscendingLatency(
      runningResults,
    );

    // Identify fastest provider with valid latency
    DnsBenchmarkResult? fastest;
    for (final r in sortedAscending) {
      if (r.status.hasValidLatency && r.medianLatencyMs != null) {
        fastest = r;
        break;
      }
    }

    state = state.copyWith(
      isRunning: false,
      activeProviderId: null,
      publicResults: sortedAscending,
      fastestProvider: fastest,
      lastRunTimestamp: DateTime.now(),
    );
  }

  void cancelBenchmark() {
    if (!state.isRunning) return;
    _service.cancel();
    state = state.copyWith(isRunning: false, activeProviderId: null);
  }

  void reset() {
    _service.cancel();
    state = DnsBenchmarkState.initial();
    discoverRouterDns();
  }
}
