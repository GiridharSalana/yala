// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import '../models/internet_reachability.dart';
import '../models/ping_result.dart';
import '../models/traceroute_result.dart';
import '../models/dns_lookup_result.dart';
import '../models/routing_neighbor_info.dart';
import '../models/diagnostic_report.dart';
import '../models/flush_dns_result.dart';

class DiagnosticsState {
  final InternetReachability? internetReachability;
  final bool isTestingReachability;
  final PingResult? lastPingResult;
  final bool isPinging;
  final TracerouteResult? lastTracerouteResult;
  final bool isTracing;
  final DnsLookupResult? lastDnsResult;
  final bool isLookingUpDns;
  final List<RouteEntry> routes;
  final List<NeighborEntry> neighbors;
  final ConntrackInfo? conntrack;
  final bool isLoadingNetworkTables;
  final DiagnosticReport? lastReport;
  final bool isGeneratingReport;
  final FlushDnsResult? lastFlushResult;
  final bool isFlushingDns;
  final bool redactSensitiveData;
  final String? generalError;

  const DiagnosticsState({
    this.internetReachability,
    this.isTestingReachability = false,
    this.lastPingResult,
    this.isPinging = false,
    this.lastTracerouteResult,
    this.isTracing = false,
    this.lastDnsResult,
    this.isLookingUpDns = false,
    this.routes = const [],
    this.neighbors = const [],
    this.conntrack,
    this.isLoadingNetworkTables = false,
    this.lastReport,
    this.isGeneratingReport = false,
    this.lastFlushResult,
    this.isFlushingDns = false,
    this.redactSensitiveData = true,
    this.generalError,
  });

  DiagnosticsState copyWith({
    InternetReachability? internetReachability,
    bool? isTestingReachability,
    PingResult? lastPingResult,
    bool? isPinging,
    TracerouteResult? lastTracerouteResult,
    bool? isTracing,
    DnsLookupResult? lastDnsResult,
    bool? isLookingUpDns,
    List<RouteEntry>? routes,
    List<NeighborEntry>? neighbors,
    ConntrackInfo? conntrack,
    bool? isLoadingNetworkTables,
    DiagnosticReport? lastReport,
    bool? isGeneratingReport,
    FlushDnsResult? lastFlushResult,
    bool? isFlushingDns,
    bool? redactSensitiveData,
    String? generalError,
  }) {
    return DiagnosticsState(
      internetReachability: internetReachability ?? this.internetReachability,
      isTestingReachability:
          isTestingReachability ?? this.isTestingReachability,
      lastPingResult: lastPingResult ?? this.lastPingResult,
      isPinging: isPinging ?? this.isPinging,
      lastTracerouteResult: lastTracerouteResult ?? this.lastTracerouteResult,
      isTracing: isTracing ?? this.isTracing,
      lastDnsResult: lastDnsResult ?? this.lastDnsResult,
      isLookingUpDns: isLookingUpDns ?? this.isLookingUpDns,
      routes: routes ?? this.routes,
      neighbors: neighbors ?? this.neighbors,
      conntrack: conntrack ?? this.conntrack,
      isLoadingNetworkTables:
          isLoadingNetworkTables ?? this.isLoadingNetworkTables,
      lastReport: lastReport ?? this.lastReport,
      isGeneratingReport: isGeneratingReport ?? this.isGeneratingReport,
      lastFlushResult: lastFlushResult ?? this.lastFlushResult,
      isFlushingDns: isFlushingDns ?? this.isFlushingDns,
      redactSensitiveData: redactSensitiveData ?? this.redactSensitiveData,
      generalError: generalError,
    );
  }
}

class DiagnosticsController extends StateNotifier<DiagnosticsState> {
  final Ref _ref;

  DiagnosticsController(this._ref) : super(const DiagnosticsState());

  AppState get _appState => _ref.read(appStateProvider);
  IApiService? get _apiService => _appState.apiService;

  String? get _ip =>
      _appState.selectedRouter?.ipAddress ??
      (_appState.reviewerModeEnabled ? '192.168.1.1' : null);
  String? get _sysauth =>
      _appState.sysauth ??
      (_appState.reviewerModeEnabled ? 'mock_auth_token' : null);
  bool get _useHttps => _appState.selectedRouter?.useHttps ?? false;

  void toggleRedaction(bool value) {
    state = state.copyWith(redactSensitiveData: value);
  }

  Future<void> testReachability({BuildContext? context}) async {
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null || auth == null || api == null) return;

    state = state.copyWith(isTestingReachability: true, generalError: null);
    try {
      final res = await api.testInternetReachability(
        ip,
        auth,
        _useHttps,
        context: context,
      );
      state = state.copyWith(
        internetReachability: res,
        isTestingReachability: false,
      );
    } catch (e) {
      state = state.copyWith(
        isTestingReachability: false,
        generalError: e.toString(),
      );
    }
  }

  Future<void> ping(
    String target, {
    int count = 3,
    int timeout = 2,
    bool isIpv6 = false,
    BuildContext? context,
  }) async {
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null || auth == null || api == null || target.trim().isEmpty) {
      return;
    }

    state = state.copyWith(isPinging: true, generalError: null);
    try {
      final res = await api.executePing(
        ip,
        auth,
        _useHttps,
        target: target.trim(),
        count: count,
        timeoutSec: timeout,
        isIpv6: isIpv6,
        context: context,
      );
      state = state.copyWith(lastPingResult: res, isPinging: false);
    } catch (e) {
      state = state.copyWith(isPinging: false, generalError: 'Ping error: $e');
    }
  }

  Future<void> traceroute(
    String target, {
    int maxHops = 15,
    int timeout = 1,
    bool isIpv6 = false,
    BuildContext? context,
  }) async {
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null || auth == null || api == null || target.trim().isEmpty) {
      return;
    }

    state = state.copyWith(isTracing: true, generalError: null);
    try {
      final res = await api.executeTraceroute(
        ip,
        auth,
        _useHttps,
        target: target.trim(),
        maxHops: maxHops,
        timeoutSec: timeout,
        isIpv6: isIpv6,
        context: context,
      );
      state = state.copyWith(lastTracerouteResult: res, isTracing: false);
    } catch (e) {
      state = state.copyWith(
        isTracing: false,
        generalError: 'Traceroute error: $e',
      );
    }
  }

  Future<void> dnsLookup(
    String host, {
    String? server,
    BuildContext? context,
  }) async {
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null || auth == null || api == null || host.trim().isEmpty) {
      return;
    }

    state = state.copyWith(isLookingUpDns: true, generalError: null);
    try {
      final res = await api.executeDnsLookup(
        ip,
        auth,
        _useHttps,
        host: host.trim(),
        server: server?.trim().isNotEmpty == true ? server!.trim() : null,
        context: context,
      );
      state = state.copyWith(lastDnsResult: res, isLookingUpDns: false);
    } catch (e) {
      state = state.copyWith(
        isLookingUpDns: false,
        generalError: 'DNS error: $e',
      );
    }
  }

  Future<void> loadNetworkTables({BuildContext? context}) async {
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null || auth == null || api == null) return;

    state = state.copyWith(isLoadingNetworkTables: true, generalError: null);
    try {
      final results = await Future.wait([
        api.fetchRoutingTable(ip, auth, _useHttps, context: context),
        api.fetchNeighborTable(ip, auth, _useHttps, context: context),
        api.fetchConntrackInfo(ip, auth, _useHttps, context: context),
      ]);

      state = state.copyWith(
        routes: results[0] as List<RouteEntry>,
        neighbors: results[1] as List<NeighborEntry>,
        conntrack: results[2] as ConntrackInfo?,
        isLoadingNetworkTables: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingNetworkTables: false,
        generalError: 'Failed to load network tables: $e',
      );
    }
  }

  Future<DiagnosticReport?> generateReport({BuildContext? context}) async {
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null || auth == null || api == null) return null;

    state = state.copyWith(isGeneratingReport: true, generalError: null);
    try {
      final rep = await api.generateFullDiagnosticReport(
        ip,
        auth,
        _useHttps,
        context: context,
      );
      state = state.copyWith(lastReport: rep, isGeneratingReport: false);
      return rep;
    } catch (e) {
      state = state.copyWith(
        isGeneratingReport: false,
        generalError: 'Failed to generate diagnostic report: $e',
      );
      return null;
    }
  }

  Future<FlushDnsResult?> flushDns({BuildContext? context}) async {
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null || auth == null || api == null) return null;

    state = state.copyWith(isFlushingDns: true, generalError: null);
    try {
      final res = await api.flushDns(ip, auth, _useHttps, context: context);
      state = state.copyWith(lastFlushResult: res, isFlushingDns: false);
      return res;
    } catch (e) {
      final err = FlushDnsResult.failure('Failed to flush DNS cache: $e');
      state = state.copyWith(
        isFlushingDns: false,
        lastFlushResult: err,
        generalError: 'Flush DNS error: $e',
      );
      return err;
    }
  }
}

final diagnosticsControllerProvider =
    StateNotifierProvider<DiagnosticsController, DiagnosticsState>((ref) {
      return DiagnosticsController(ref);
    });
