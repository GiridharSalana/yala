// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart' hide Router;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yala/main.dart';
import 'package:yala/models/router.dart';
import 'package:yala/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yala/modules/adguard_home/services/mock_adguard_api_service.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/interfaces/auth_service_interface.dart';
import 'package:yala/services/operation_queue.dart';
import 'package:yala/services/secure_storage_service.dart';
import 'package:yala/utils/logger.dart';

/// Polling frequency intervals for AdGuard Home telemetry.
enum AdGuardPollingInterval {
  off(0),
  s5(5),
  s10(10),
  s30(30),
  manual(0);

  final int seconds;
  const AdGuardPollingInterval(this.seconds);
}

/// Immutable state container for AdGuard Home module.
@immutable
class AdGuardState {
  final String routerId;
  final AdGuardConnectionStatus connectionStatus;
  final bool isLoading;
  final bool isRefreshing;
  final bool isMutatingProtection;
  final bool isManagingService;
  final bool isMutatingDns;
  final bool isMutatingFilterLists;

  // Active instance configuration
  final AdGuardInstanceProfile? activeProfile;
  final List<AdGuardInstanceProfile> profiles;

  // Domain telemetry models
  final AdGuardStatus? status;
  final AdGuardStats? stats;
  final AdGuardFilteringStatus? filtering;
  final AdGuardProcessTelemetry? processTelemetry;
  final AdGuardCapabilities capabilities;
  final AdGuardDnsTopology topology;

  // Polling lifecycle configuration
  final AdGuardPollingInterval pollingInterval;
  final bool isPollingActive;
  final DateTime? lastSuccessfulRefresh;

  // Statistics scope configuration
  final AdGuardStatsPeriod statsPeriod;

  // Granular partial error reporting
  final String? generalError;
  final String? statusError;
  final String? statsError;
  final String? filteringError;
  final String? processTelemetryError;
  final String? serviceActionError;
  final String? protectionActionError;
  final String? dnsActionError;
  final String? filterListActionError;

  const AdGuardState({
    required this.routerId,
    this.connectionStatus = AdGuardConnectionStatus.initial,
    this.isLoading = false,
    this.isRefreshing = false,
    this.isMutatingProtection = false,
    this.isManagingService = false,
    this.isMutatingDns = false,
    this.isMutatingFilterLists = false,
    this.activeProfile,
    this.profiles = const [],
    this.status,
    this.stats,
    this.filtering,
    this.processTelemetry,
    this.capabilities = const AdGuardCapabilities(
      isInstalled: false,
      isServiceManageable: false,
      isApiReachable: false,
      isApiAuthenticated: false,
      isDnsOperational: false,
      topology: AdGuardDnsTopology(
        mode: AdGuardTopologyMode.unknown,
        adguardDnsPort: 53,
        dnsmasqPort: 53,
        forwarders: [],
        hasFirewallRedirect: false,
        isIpv6Supported: false,
        description: 'Topology not yet probed',
      ),
    ),
    this.topology = const AdGuardDnsTopology(
      mode: AdGuardTopologyMode.unknown,
      adguardDnsPort: 53,
      dnsmasqPort: 53,
      forwarders: [],
      hasFirewallRedirect: false,
      isIpv6Supported: false,
      description: 'Topology not yet probed',
    ),
    this.pollingInterval = AdGuardPollingInterval.s10,
    this.isPollingActive = false,
    this.lastSuccessfulRefresh,
    this.statsPeriod = AdGuardStatsPeriod.all,
    this.generalError,
    this.statusError,
    this.statsError,
    this.filteringError,
    this.processTelemetryError,
    this.serviceActionError,
    this.protectionActionError,
    this.dnsActionError,
    this.filterListActionError,
  });

  /// Whether initial discovery or status probe is actively running without any cached data.
  bool get isInitialLoading =>
      status == null &&
      lastSuccessfulRefresh == null &&
      (isLoading ||
          connectionStatus == AdGuardConnectionStatus.initial ||
          connectionStatus == AdGuardConnectionStatus.discovering);

  /// Whether initial discovery failed completely without valid cached data.
  bool get isDiscoveryFailed =>
      status == null &&
      lastSuccessfulRefresh == null &&
      (connectionStatus == AdGuardConnectionStatus.apiUnreachable ||
          connectionStatus == AdGuardConnectionStatus.invalidEndpoint ||
          connectionStatus == AdGuardConnectionStatus.error);

  /// Whether the active profile is an external host (non-router local).
  bool get isExternal =>
      activeProfile?.type == AdGuardInstanceType.externalHost;

  /// Effective instance ID for storage and session caching.
  String get effectiveInstanceId => activeProfile?.id ?? 'local_$routerId';

  factory AdGuardState.initial(
    String routerId, {
    AdGuardInstanceProfile? activeProfile,
    List<AdGuardInstanceProfile> profiles = const [],
  }) =>
      AdGuardState(
        routerId: routerId,
        activeProfile: activeProfile,
        profiles: profiles,
      );

  AdGuardState copyWith({
    AdGuardConnectionStatus? connectionStatus,
    bool? isLoading,
    bool? isRefreshing,
    bool? isMutatingProtection,
    bool? isManagingService,
    bool? isMutatingDns,
    bool? isMutatingFilterLists,
    AdGuardInstanceProfile? activeProfile,
    bool clearActiveProfile = false,
    List<AdGuardInstanceProfile>? profiles,
    AdGuardStatus? status,
    bool clearStatus = false,
    AdGuardStats? stats,
    bool clearStats = false,
    AdGuardFilteringStatus? filtering,
    bool clearFiltering = false,
    AdGuardProcessTelemetry? processTelemetry,
    bool clearProcessTelemetry = false,
    AdGuardCapabilities? capabilities,
    AdGuardDnsTopology? topology,
    AdGuardPollingInterval? pollingInterval,
    bool? isPollingActive,
    DateTime? lastSuccessfulRefresh,
    AdGuardStatsPeriod? statsPeriod,
    String? generalError,
    bool clearGeneralError = false,
    String? statusError,
    bool clearStatusError = false,
    String? statsError,
    bool clearStatsError = false,
    String? filteringError,
    bool clearFilteringError = false,
    String? processTelemetryError,
    bool clearProcessTelemetryError = false,
    String? serviceActionError,
    bool clearServiceActionError = false,
    String? protectionActionError,
    bool clearProtectionActionError = false,
    String? dnsActionError,
    bool clearDnsActionError = false,
    String? filterListActionError,
    bool clearFilterListActionError = false,
  }) {
    return AdGuardState(
      routerId: routerId,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isMutatingProtection: isMutatingProtection ?? this.isMutatingProtection,
      isManagingService: isManagingService ?? this.isManagingService,
      isMutatingDns: isMutatingDns ?? this.isMutatingDns,
      isMutatingFilterLists:
          isMutatingFilterLists ?? this.isMutatingFilterLists,
      activeProfile:
          clearActiveProfile ? null : (activeProfile ?? this.activeProfile),
      profiles: profiles ?? this.profiles,
      status: clearStatus ? null : (status ?? this.status),
      stats: clearStats ? null : (stats ?? this.stats),
      filtering: clearFiltering ? null : (filtering ?? this.filtering),
      processTelemetry: clearProcessTelemetry
          ? null
          : (processTelemetry ?? this.processTelemetry),
      capabilities: capabilities ?? this.capabilities,
      topology: topology ?? this.topology,
      pollingInterval: pollingInterval ?? this.pollingInterval,
      isPollingActive: isPollingActive ?? this.isPollingActive,
      lastSuccessfulRefresh:
          lastSuccessfulRefresh ?? this.lastSuccessfulRefresh,
      statsPeriod: statsPeriod ?? this.statsPeriod,
      generalError:
          clearGeneralError ? null : (generalError ?? this.generalError),
      statusError:
          clearStatusError ? null : (statusError ?? this.statusError),
      statsError: clearStatsError ? null : (statsError ?? this.statsError),
      filteringError:
          clearFilteringError ? null : (filteringError ?? this.filteringError),
      processTelemetryError: clearProcessTelemetryError
          ? null
          : (processTelemetryError ?? this.processTelemetryError),
      serviceActionError: clearServiceActionError
          ? null
          : (serviceActionError ?? this.serviceActionError),
      protectionActionError: clearProtectionActionError
          ? null
          : (protectionActionError ?? this.protectionActionError),
      dnsActionError: clearDnsActionError
          ? null
          : (dnsActionError ?? this.dnsActionError),
      filterListActionError: clearFilterListActionError
          ? null
          : (filterListActionError ?? this.filterListActionError),
    );
  }
}

/// Internal immutable container for cached UCI DNS topology configuration.
@immutable
class _CachedUciTopologyConfig {
  final int dnsmasqPort;
  final List<String> dnsmasqServers;
  final bool hasDnatRedirect;
  final List<String> odhcpdIpv6Dns;
  final bool? raDnsEnabled;
  final bool isIndeterminateIpv6;
  final List<String> routerInterfaceIpv6Addresses;
  final DateTime probedAt;

  const _CachedUciTopologyConfig({
    required this.dnsmasqPort,
    required this.dnsmasqServers,
    required this.hasDnatRedirect,
    this.odhcpdIpv6Dns = const [],
    this.raDnsEnabled,
    this.isIndeterminateIpv6 = false,
    this.routerInterfaceIpv6Addresses = const [],
    required this.probedAt,
  });

  bool isExpired(Duration ttl, {DateTime? now}) {
    final currentTime = now ?? DateTime.now().toUtc();
    return currentTime.difference(probedAt) >= ttl;
  }
}

/// Contract for checking network interface connectivity.
abstract class IConnectivityChecker {
  Future<bool> checkConnectivity();
}

/// Default network connectivity checker based on native NetworkInterface query.
class DefaultConnectivityChecker implements IConnectivityChecker {
  const DefaultConnectivityChecker();

  @override
  Future<bool> checkConnectivity() async {
    // In Flutter test runner environment, avoid OS network interface queries that block FakeAsync
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false)
          .timeout(const Duration(seconds: 1), onTimeout: () => []);
      if (interfaces.isNotEmpty) return true;
      final loopbacks = await NetworkInterface.list(includeLoopback: true)
          .timeout(const Duration(seconds: 1), onTimeout: () => []);
      return loopbacks.isNotEmpty;
    } catch (_) {
      return true;
    }
  }
}

/// StateNotifier coordinator for AdGuard Home module scoped by [routerId].
///
/// Features:
/// - Request epoch and router ID validation on all asynchronous state mutations.
/// - Single-flight lock preventing overlapping refresh cycles.
/// - Polling active only during screen visibility; immediate cancellation on dispose.
/// - Operation queue domain isolation: `'service'` for procd mutations, `'agh_protection'` for protection.
/// - AdGuard HTTP 401 stops polling, transitions to `authRequired`, and never touches router auth.
/// - Reviewer / Demo mode operates 100% in-memory with zero external network or ubus side-effects.
class AdGuardController extends StateNotifier<AdGuardState>
    with WidgetsBindingObserver {
  final Ref ref;
  final String routerId;

  // Injected service overrides for deterministic unit testing
  final IAdGuardApiService? _apiServiceOverride;
  final RouterScopedOperationQueue? _operationQueueOverride;
  final IApiService? _luciApiServiceOverride;
  final IAuthService? _authServiceOverride;
  final SecureStorageService? _secureStorageOverride;
  final IConnectivityChecker? _connectivityCheckerOverride;

  IConnectivityChecker get _connectivityChecker =>
      _connectivityCheckerOverride ?? const DefaultConnectivityChecker();

  Timer? _pollingTimer;
  int _fetchEpoch = 0;
  int _activeFetchEpoch = 0;
  bool _isRefreshing = false;
  bool _disposed = false;

  bool _isPausedForLifecycle = false;
  bool _isWaitingForConnectivity = false;
  DateTime? _lastConnectivityRestoreTime;
  int _consecutiveFailures = 0;

  @visibleForTesting
  bool get isPausedForLifecycle => _isPausedForLifecycle;

  @visibleForTesting
  bool get isWaitingForConnectivity => _isWaitingForConnectivity;

  @visibleForTesting
  int get consecutiveFailures => _consecutiveFailures;

  @visibleForTesting
  void setConsecutiveFailuresForTesting(int count) {
    _consecutiveFailures = count;
  }

  /// In-memory cache duration for UCI DNS topology probing (5 minutes).
  static const Duration topologyCacheTtl = Duration(minutes: 5);

  _CachedUciTopologyConfig? _cachedUciTopology;
  IAdGuardApiService? _cachedApiService;
  String? _cachedApiServiceKey;

  /// Public getters for diagnostics and unit testing of topology cache.
  @visibleForTesting
  DateTime? get topologyCacheProbedAt => _cachedUciTopology?.probedAt;

  @visibleForTesting
  int? get cachedDnsmasqPort => _cachedUciTopology?.dnsmasqPort;

  @visibleForTesting
  List<String>? get cachedDnsmasqServers => _cachedUciTopology?.dnsmasqServers;

  @visibleForTesting
  bool? get cachedHasDnatRedirect => _cachedUciTopology?.hasDnatRedirect;

  @visibleForTesting
  bool get hasValidTopologyCache =>
      _cachedUciTopology != null &&
      !_cachedUciTopology!.isExpired(topologyCacheTtl);

  @visibleForTesting
  void setCachedTopologyForTesting({
    required int dnsmasqPort,
    required List<String> dnsmasqServers,
    required bool hasDnatRedirect,
    required DateTime probedAt,
    List<String> odhcpdIpv6Dns = const [],
    bool? raDnsEnabled,
    bool isIndeterminateIpv6 = false,
    List<String> routerInterfaceIpv6Addresses = const [],
  }) {
    _cachedUciTopology = _CachedUciTopologyConfig(
      dnsmasqPort: dnsmasqPort,
      dnsmasqServers: List.unmodifiable(dnsmasqServers),
      hasDnatRedirect: hasDnatRedirect,
      odhcpdIpv6Dns: List.unmodifiable(odhcpdIpv6Dns),
      raDnsEnabled: raDnsEnabled,
      isIndeterminateIpv6: isIndeterminateIpv6,
      routerInterfaceIpv6Addresses: List.unmodifiable(routerInterfaceIpv6Addresses),
      probedAt: probedAt,
    );
  }

  static final Map<String, AdGuardState> _sessionCache = {};

  /// In-memory session cache invalidation.
  static void invalidateSessionCache([String? targetId]) {
    if (targetId != null) {
      _sessionCache.remove(targetId);
      _sessionCache.remove('local_$targetId');
    } else {
      _sessionCache.clear();
    }
  }

  @visibleForTesting
  static Map<String, AdGuardState> get sessionCache => _sessionCache;

  AdGuardController(
    this.ref,
    this.routerId, {
    AdGuardInstanceProfile? initialProfile,
    IAdGuardApiService? apiServiceOverride,
    RouterScopedOperationQueue? operationQueueOverride,
    IApiService? luciApiServiceOverride,
    IAuthService? authServiceOverride,
    SecureStorageService? secureStorageOverride,
    IConnectivityChecker? connectivityCheckerOverride,
  })  : _apiServiceOverride = apiServiceOverride,
        _operationQueueOverride = operationQueueOverride,
        _luciApiServiceOverride = luciApiServiceOverride,
        _authServiceOverride = authServiceOverride,
        _secureStorageOverride = secureStorageOverride,
        _connectivityCheckerOverride = connectivityCheckerOverride,
        super(
          _sessionCache[initialProfile?.id ?? 'local_$routerId'] ??
              _sessionCache[routerId] ??
              AdGuardState.initial(
                routerId,
                activeProfile: initialProfile,
              ),
        ) {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  // ── Dependency Accessors ──────────────────────────────────────────────────

  bool get _isReviewerMode {
    if (routerId == 'reviewer-mock-router' ||
        routerId.startsWith('reviewer://')) {
      return true;
    }
    try {
      return ref.read(appStateProvider).reviewerModeEnabled;
    } catch (_) {
      return false;
    }
  }

  Router? get _currentRouter {
    try {
      final appState = ref.read(appStateProvider);
      if (appState.selectedRouter?.id == routerId) {
        return appState.selectedRouter;
      }
      return appState.routers.firstWhere(
        (r) => r.id == routerId,
        orElse: () => Router(
          id: routerId,
          ipAddress: '192.168.1.1',
          username: 'root',
          password: '',
          useHttps: false,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Read-only snapshot of current controller state.
  AdGuardState get currentState => state;

  RouterScopedOperationQueue get _operationQueue =>
      _operationQueueOverride ?? RouterScopedOperationQueue.instance;

  SecureStorageService? get _secureStorage =>
      _secureStorageOverride ?? SecureStorageService();

  IApiService? get _luciApiService =>
      _luciApiServiceOverride ??
      (() {
        try {
          return ref.read(appStateProvider).apiService;
        } catch (_) {
          return null;
        }
      })();

  String? get _sysauth {
    try {
      return ref.read(appStateProvider).sysauth;
    } catch (_) {
      return null;
    }
  }

  IAdGuardApiService get _apiService {
    if (_apiServiceOverride != null) return _apiServiceOverride;
    if (_isReviewerMode) {
      return MockAdGuardApiService(
        routerId: routerId,
        customInstanceId: state.effectiveInstanceId,
      );
    }
    final active = state.activeProfile;
    final router = _currentRouter;
    final host = active?.host ?? (router?.ipAddress ?? '192.168.1.1');
    final port = active?.port ?? 3000;
    final useHttps = active?.useHttps ?? (router?.useHttps ?? false);
    final instanceId = active?.id ?? 'local_$routerId';

    final key = '$routerId|$instanceId|$host|$port|$useHttps';
    if (_cachedApiService != null && _cachedApiServiceKey == key) {
      return _cachedApiService!;
    }

    _cachedApiServiceKey = key;
    _cachedApiService = AdGuardApiService(
      routerId: routerId,
      instanceId: instanceId,
      host: host,
      port: port,
      useHttps: useHttps,
      secureStorageService: _secureStorage,
    );
    return _cachedApiService!;
  }

  // ── Profile Management ────────────────────────────────────────────────────

  /// Loads available profiles from SecureStorage, restores persisted active profile,
  /// and ensures default local profile exists.
  Future<void> loadProfiles() async {
    if (_disposed || !mounted) return;
    try {
      final storedProfiles = await _secureStorage?.getAdGuardProfiles() ?? [];
      final router = _currentRouter;
      final defaultLocal = AdGuardInstanceProfile.local(
        routerId: routerId,
        host: router?.ipAddress ?? '192.168.1.1',
        port: 3000,
        useHttps: router?.useHttps ?? false,
      );

      final hasLocal = storedProfiles.any(
        (p) => p.id == defaultLocal.id || p.routerId == routerId,
      );
      final allProfiles = [
        if (!hasLocal) defaultLocal,
        ...storedProfiles,
      ];

      // Restore persisted active profile ID with strict router-context isolation
      final savedActiveId =
          await _secureStorage?.getActiveAdGuardProfileId(routerId);
      AdGuardInstanceProfile? targetActive;

      if (savedActiveId != null) {
        try {
          final found = allProfiles.firstWhere((p) => p.id == savedActiveId);
          // Strict router context isolation:
          // A local router profile is only valid if its routerId matches this controller's routerId!
          if (found.type != AdGuardInstanceType.localRouter ||
              found.routerId == routerId) {
            targetActive = found;
          }
        } catch (_) {
          // Saved profile not found in available list
        }
      }

      final currentActive =
          targetActive ?? state.activeProfile ?? defaultLocal;
      final cached = _sessionCache[currentActive.id];
      if (cached != null) {
        state = cached.copyWith(
          profiles: allProfiles,
          activeProfile: currentActive,
        );
      } else {
        state = state.copyWith(
          profiles: allProfiles,
          activeProfile: currentActive,
        );
      }
    } catch (e) {
      Logger.error('Failed to load AdGuard profiles for router $routerId', e);
    }
  }

  /// Switches active profile, restoring cached state if available or initiating fresh discovery.
  Future<void> selectProfile(AdGuardInstanceProfile profile) async {
    if (_disposed || !mounted) return;
    if (state.activeProfile?.id == profile.id &&
        state.lastSuccessfulRefresh != null) {
      return;
    }

    // Persist active profile ID
    await _secureStorage?.saveActiveAdGuardProfileId(routerId, profile.id);

    stopPolling();
    _cachedApiService = null;
    _cachedApiServiceKey = null;
    // Invalidate in-flight refresh cycles from any previous profile
    final newEpoch = ++_fetchEpoch;
    _isRefreshing = false;
    _consecutiveFailures = 0;

    final cached = _sessionCache[profile.id];
    if (cached != null) {
      state = cached.copyWith(
        activeProfile: profile,
        profiles: state.profiles,
        isLoading: false,
        isRefreshing: true,
      );
    } else {
      state = AdGuardState.initial(
        routerId,
        activeProfile: profile,
        profiles: state.profiles,
      ).copyWith(
        isLoading: true,
        connectionStatus: AdGuardConnectionStatus.discovering,
      );
    }

    await refresh();
    if (_fetchEpoch == newEpoch &&
        state.pollingInterval != AdGuardPollingInterval.manual &&
        state.pollingInterval != AdGuardPollingInterval.off) {
      startPolling();
    }
  }

  /// Adds and selects a new external instance profile.
  Future<void> addExternalProfile(
    AdGuardInstanceProfile profile, {
    String? username,
    String? password,
  }) async {
    if (_disposed || !mounted) return;
    await _secureStorage?.saveAdGuardProfile(profile);
    if (username != null &&
        password != null &&
        username.trim().isNotEmpty) {
      await _secureStorage?.saveAdGuardCredentialsForInstance(
        profile.id,
        username.trim(),
        password,
      );
    }
    await loadProfiles();
    await selectProfile(profile);
  }

  /// Updates an existing external instance profile, preserving its ID and credentials if unchanged.
  Future<void> updateProfile(
    AdGuardInstanceProfile profile, {
    String? username,
    String? password,
  }) async {
    if (_disposed || !mounted) return;
    await _secureStorage?.saveAdGuardProfile(profile);
    if (username != null &&
        username.trim().isNotEmpty &&
        password != null) {
      await _secureStorage?.saveAdGuardCredentialsForInstance(
        profile.id,
        username.trim(),
        password,
      );
    }
    invalidateSessionCache(profile.id);
    await loadProfiles();

    if (state.activeProfile?.id == profile.id) {
      stopPolling();
      final newEpoch = ++_fetchEpoch;
      _isRefreshing = false;
      state = state.copyWith(
        activeProfile: profile,
        isLoading: true,
        connectionStatus: AdGuardConnectionStatus.discovering,
      );
      await refresh(forceProbe: true);
      if (_fetchEpoch == newEpoch &&
          state.pollingInterval != AdGuardPollingInterval.manual &&
          state.pollingInterval != AdGuardPollingInterval.off) {
        startPolling();
      }
    }
  }

  /// Probes an AdGuard Home endpoint to verify reachability and authentication
  /// before saving an instance profile. Uses an isolated probe instance ID
  /// and does not touch stored SecureStorage credentials.
  Future<AdGuardConnectionStatus> testProfileConnection({
    required String host,
    required int port,
    required bool useHttps,
    String? username,
    String? password,
  }) async {
    if (_isReviewerMode) {
      return AdGuardConnectionStatus.authenticated;
    }
    final probeId = 'temp_probe_${DateTime.now().millisecondsSinceEpoch}';
    final tempService = _apiServiceOverride ??
        AdGuardApiService(
          routerId: routerId,
          instanceId: probeId,
          host: host,
          port: port,
          useHttps: useHttps,
        );
    AdGuardCredentials? creds;
    if (username != null && username.trim().isNotEmpty) {
      creds = AdGuardCredentials(
        username: username.trim(),
        password: password ?? '',
      );
    }
    return await tempService.testConnection(credentials: creds);
  }

  /// Deletes an external instance profile.
  Future<void> deleteExternalProfile(String profileId) async {
    if (_disposed || !mounted) return;
    await _secureStorage?.deleteAdGuardProfile(profileId);
    invalidateSessionCache(profileId);
    _cachedApiService = null;
    _cachedApiServiceKey = null;

    final savedActiveId =
        await _secureStorage?.getActiveAdGuardProfileId(routerId);
    if (savedActiveId == profileId) {
      await _secureStorage?.clearActiveAdGuardProfileId(routerId);
    }

    await loadProfiles();
    if (state.activeProfile?.id == profileId) {
      final defaultLocal = state.profiles.firstWhere(
        (p) => p.type == AdGuardInstanceType.localRouter,
        orElse: () => AdGuardInstanceProfile.local(
          routerId: routerId,
          host: _currentRouter?.ipAddress ?? '192.168.1.1',
        ),
      );
      await selectProfile(defaultLocal);
    }
  }

  // ── Polling Lifecycle & Resilience ────────────────────────────────────────

  /// Activates polling and triggers an immediate initial refresh.
  void startPolling() {
    if (_disposed || !mounted) return;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    state = state.copyWith(isPollingActive: true);
    _consecutiveFailures = 0;
    refresh();
  }

  /// Halts background polling without discarding active telemetry state.
  void stopPolling({bool updateState = true}) {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isWaitingForConnectivity = false;
    if (updateState && !_disposed && mounted) {
      state = state.copyWith(isPollingActive: false);
    }
  }

  /// Updates polling interval and reschedules timer if currently active.
  void setPollingInterval(AdGuardPollingInterval interval) {
    if (_disposed || !mounted) return;
    state = state.copyWith(pollingInterval: interval);
    if (state.isPollingActive) {
      if (interval == AdGuardPollingInterval.manual ||
          interval == AdGuardPollingInterval.off) {
        _pollingTimer?.cancel();
        _pollingTimer = null;
      } else {
        _scheduleNextPoll(calculateNextPollDelay());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || !mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _isPausedForLifecycle = true;
      _pollingTimer?.cancel();
      _pollingTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_isPausedForLifecycle) {
        _isPausedForLifecycle = false;
        if (this.state.isPollingActive) {
          _consecutiveFailures = 0;
          refresh();
        }
      }
    }
  }

  Future<bool> _checkConnectivity() async {
    return await _connectivityChecker.checkConnectivity();
  }

  /// Handles connectivity restoration with burst-suppression and immediate guarded refresh.
  Future<void> onConnectivityRestored() async {
    if (_disposed || !mounted) return;
    final now = DateTime.now();
    if (_lastConnectivityRestoreTime != null &&
        now.difference(_lastConnectivityRestoreTime!) <
            const Duration(milliseconds: 500)) {
      return;
    }
    _lastConnectivityRestoreTime = now;
    _isWaitingForConnectivity = false;
    if (state.isPollingActive && !_isPausedForLifecycle) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      await refresh();
    }
  }

  /// Handles external connectivity change events.
  Future<void> onConnectivityChanged(bool isOnline) async {
    if (isOnline) {
      await onConnectivityRestored();
    } else {
      _isWaitingForConnectivity = true;
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  /// Calculates dynamic next polling interval applying exponential backoff:
  /// Base (e.g. 5s) -> 15s -> 30s -> 60s (capped), respecting [retryAfter] from HTTP 429/503.
  @visibleForTesting
  Duration calculateNextPollDelay({Duration? retryAfter}) {
    final baseSeconds = state.pollingInterval.seconds > 0
        ? state.pollingInterval.seconds
        : 5;
    Duration delay;
    switch (_consecutiveFailures) {
      case 0:
      case 1:
        delay = Duration(seconds: baseSeconds);
        break;
      case 2:
        delay = const Duration(seconds: 15);
        break;
      case 3:
        delay = const Duration(seconds: 30);
        break;
      default:
        delay = const Duration(seconds: 60);
        break;
    }
    if (retryAfter != null && retryAfter > delay) {
      delay = retryAfter;
    }
    return delay;
  }

  void _scheduleNextPoll(Duration delay) {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    if (_disposed || !mounted) return;
    if (!state.isPollingActive || _isPausedForLifecycle) return;
    if (state.pollingInterval == AdGuardPollingInterval.manual ||
        state.pollingInterval == AdGuardPollingInterval.off ||
        state.pollingInterval.seconds == 0) {
      return;
    }
    _pollingTimer = Timer(delay, () {
      if (!_disposed &&
          mounted &&
          state.isPollingActive &&
          !_isPausedForLifecycle) {
        refresh();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _cachedUciTopology = null;
    _cachedApiService = null;
    _cachedApiServiceKey = null;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    super.dispose();
  }

  // ── Telemetry Refresh & Multi-Source Coordination ─────────────────────────

  /// Refreshes AdGuard status, statistics, filter status, and process telemetry.
  ///
  /// Guarantees:
  /// 1. Single-flight lock: Overlapping refresh requests are skipped.
  /// 2. Epoch validation: Asynchronous results from stale cycles are dropped immediately.
  /// 3. Router-scoping: Results are never applied if routerId has changed.
  /// 4. Partial-failure resilience: Successful sources are preserved when one source fails.
  /// 5. 401 handling: Stops polling, transitions to `authRequired`, zero router re-auth calls.
  /// 6. UCI topology caching: Evaluates read-only UCI DNS settings with 5-minute TTL.
  Future<void> refresh({
    bool forceProbe = false,
    bool forceTopologyProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  }) async {
    if (_disposed || !mounted) return;
    if (_isRefreshing) {
      Logger.debug(
        'AdGuardController[$routerId]: Refresh skipped, cycle already in-flight',
      );
      return;
    }

    _isRefreshing = true;
    final cycleEpoch = ++_fetchEpoch;
    _activeFetchEpoch = cycleEpoch;
    final capturedRouterId = routerId;
    final capturedInstanceId = state.effectiveInstanceId;

    state = state.copyWith(
      isRefreshing: true,
      clearGeneralError: true,
      connectionStatus: state.status == null
          ? AdGuardConnectionStatus.discovering
          : state.connectionStatus,
    );

    // Connectivity guard: prevent socket exhaustion when offline
    final isOnline = await _checkConnectivity();
    if (_disposed ||
        !mounted ||
        cycleEpoch != _fetchEpoch ||
        routerId != capturedRouterId ||
        state.effectiveInstanceId != capturedInstanceId) {
      if (_activeFetchEpoch == cycleEpoch) {
        _isRefreshing = false;
      }
      return;
    }

    if (!isOnline) {
      _isWaitingForConnectivity = true;
      _consecutiveFailures++;
      _isRefreshing = false;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        connectionStatus: state.status == null
            ? AdGuardConnectionStatus.apiUnreachable
            : state.connectionStatus,
        statusError: 'No network connectivity',
      );
      _scheduleNextPoll(calculateNextPollDelay());
      return;
    } else {
      _isWaitingForConnectivity = false;
    }

    try {
      final api = _apiService;

      // 1. Fetch AdGuard status first or in parallel
      final statusResult = await api.getStatus(
        forceProbe: forceProbe,
        allowFallbackToRouterCredentials: allowFallbackToRouterCredentials,
        routerCredentials: routerCredentials,
      );

      // Race & stale checks
      if (_disposed ||
          !mounted ||
          cycleEpoch != _fetchEpoch ||
          routerId != capturedRouterId ||
          state.effectiveInstanceId != capturedInstanceId) {
        return;
      }

      AdGuardDnsTopology buildUnreachableTopology() {
        final profType = state.activeProfile?.type ??
            (state.isExternal
                ? AdGuardInstanceType.externalHost
                : AdGuardInstanceType.localRouter);
        final profHost =
            state.activeProfile?.host ?? (state.isExternal ? '' : '127.0.0.1');

        return AdGuardDnsTopology.infer(
          adguardDnsPort: state.status?.dnsPort ?? state.topology.adguardDnsPort,
          dnsmasqPort:
              _cachedUciTopology?.dnsmasqPort ?? state.topology.dnsmasqPort,
          dnsmasqServers:
              _cachedUciTopology?.dnsmasqServers ?? state.topology.forwarders,
          hasDnatRedirect: _cachedUciTopology?.hasDnatRedirect ??
              state.topology.hasFirewallRedirect,
          adguardDnsAddresses: state.status?.dnsAddresses ?? const [],
          isDnsRunning: false,
          isApiReachable: false,
          instanceType: profType,
          targetHost: profHost,
          topClients: const [],
          totalQueries: 0,
          odhcpdIpv6Dns: _cachedUciTopology?.odhcpdIpv6Dns ?? const [],
          raDnsEnabled: _cachedUciTopology?.raDnsEnabled,
          isIndeterminateIpv6:
              _cachedUciTopology?.isIndeterminateIpv6 ?? true,
          routerIp: _currentRouter?.ipAddress,
        );
      }

      // Handle Authentication Required
      if (statusResult.isAuthRequired) {
        stopPolling();
        final unreachTop = buildUnreachableTopology();
        state = state.copyWith(
          isLoading: false,
          isRefreshing: false,
          connectionStatus: AdGuardConnectionStatus.authRequired,
          statusError: statusResult.error?.message ?? 'Authentication required',
          topology: unreachTop,
          capabilities: state.capabilities.copyWith(
            isApiReachable: true,
            isApiAuthenticated: false,
            topology: unreachTop,
          ),
        );
        return;
      }

      // Handle Non-AdGuard Payload (HTTP 200 invalid)
      if (statusResult.error?.type == AdGuardApiErrorType.invalidPayload) {
        _consecutiveFailures++;
        final unreachTop = buildUnreachableTopology();
        state = state.copyWith(
          isLoading: false,
          isRefreshing: false,
          connectionStatus: AdGuardConnectionStatus.invalidEndpoint,
          statusError: statusResult.error?.message ??
              'Response is not genuine AdGuard Home',
          topology: unreachTop,
          capabilities: state.capabilities.copyWith(
            isApiReachable: false,
            topology: unreachTop,
          ),
        );
        _scheduleNextPoll(calculateNextPollDelay());
        return;
      }

      // Handle Network / Unreachable / Timeout / RateLimited / ServiceUnavailable
      if (!statusResult.isSuccess || statusResult.data == null) {
        _consecutiveFailures++;
        final retryAfter = statusResult.error?.retryAfter;
        final errType = statusResult.error?.type;
        final connStatus = (errType == AdGuardApiErrorType.networkFailure ||
                errType == AdGuardApiErrorType.timeout ||
                errType == AdGuardApiErrorType.rateLimited ||
                errType == AdGuardApiErrorType.serviceUnavailable)
            ? AdGuardConnectionStatus.apiUnreachable
            : AdGuardConnectionStatus.error;

        final unreachTop = buildUnreachableTopology();
        state = state.copyWith(
          isLoading: false,
          isRefreshing: false,
          connectionStatus: connStatus,
          statusError: statusResult.error?.message ?? 'Failed to reach API',
          topology: unreachTop,
          capabilities: state.capabilities.copyWith(
            isApiReachable: false,
            topology: unreachTop,
          ),
        );
        _scheduleNextPoll(calculateNextPollDelay(retryAfter: retryAfter));
        return;
      }

      final validStatus = statusResult.data!;

      // Evaluate whether UCI topology probing is required
      final bool isCacheValid = _cachedUciTopology != null &&
          !_cachedUciTopology!.isExpired(topologyCacheTtl);
      final bool shouldProbeTopology =
          !_isReviewerMode && (forceTopologyProbe || !isCacheValid);

      // 2. Fetch parallel telemetry sources: stats, filtering, process telemetry, and UCI topology
      AdGuardStats? fetchedStats;
      String? statsErrorMsg;
      AdGuardFilteringStatus? fetchedFiltering;
      String? filteringErrorMsg;
      AdGuardProcessTelemetry? fetchedProcess;
      String? processErrorMsg;
      bool? fetchedServiceEnabled;
      _CachedUciTopologyConfig? freshlyProbedTopology;

      await Future.wait([
        // Stats fetch with active period duration
        () async {
          final statsRes =
              await api.getStats(recent: state.statsPeriod.duration);
          if (statsRes.isSuccess && statsRes.data != null) {
            fetchedStats = statsRes.data;
          } else {
            statsErrorMsg = statsRes.error?.message ?? 'Failed to fetch stats';
          }
        }(),

        // Filtering fetch
        () async {
          final filterRes = await api.getFilteringStatus();
          if (filterRes.isSuccess && filterRes.data != null) {
            fetchedFiltering = filterRes.data;
          } else {
            filteringErrorMsg =
                filterRes.error?.message ?? 'Failed to fetch filter status';
          }
        }(),

        // Host process telemetry fetch
        () async {
          if (state.isExternal) return;
          try {
            fetchedProcess = await _fetchProcessTelemetry();
          } catch (e) {
            processErrorMsg = 'Process telemetry unavailable: $e';
          }
        }(),

        // Service autostart probe (local router only)
        () async {
          if (state.isExternal) return;
          if (_isReviewerMode) {
            fetchedServiceEnabled = state.capabilities.isServiceEnabled ?? true;
            return;
          }
          fetchedServiceEnabled = await _fetchServiceAutostart();
        }(),

        // UCI DNS topology probe (if needed)
        if (shouldProbeTopology && (!state.isExternal || _currentRouter != null))
          () async {
            try {
              freshlyProbedTopology =
                  await _fetchDnsUciConfig(cycleEpoch, capturedRouterId);
            } catch (e) {
              Logger.warning(
                'AdGuardController[$capturedRouterId]: UCI topology probe exception: $e',
              );
            }
          }(),
      ]);

      // Guard after parallel futures
      if (_disposed ||
          !mounted ||
          cycleEpoch != _fetchEpoch ||
          routerId != capturedRouterId ||
          state.effectiveInstanceId != capturedInstanceId) {
        return;
      }

      // If probe succeeded, update cache
      if (freshlyProbedTopology != null) {
        _cachedUciTopology = freshlyProbedTopology;
      }

      // Reconcile effective topology values with graceful fallback:
      // cached if available, else safe defaults (53, [], false)
      final effectiveDnsmasqPort = _cachedUciTopology?.dnsmasqPort ?? 53;
      final effectiveDnsmasqServers =
          _cachedUciTopology?.dnsmasqServers ?? const <String>[];
      final effectiveHasDnatRedirect =
          _cachedUciTopology?.hasDnatRedirect ?? false;
      final effectiveOdhcpdIpv6 =
          _cachedUciTopology?.odhcpdIpv6Dns ?? const <String>[];
      final effectiveRaDns = _cachedUciTopology?.raDnsEnabled;
      final effectiveIndeterminateIpv6 =
          _cachedUciTopology?.isIndeterminateIpv6 ?? (_cachedUciTopology == null);

      // Evaluate port conflict (Mode collision)
      bool portConflict = false;
      String? portConflictReason;
      if (!state.isExternal &&
          validStatus.dnsPort == 53 &&
          effectiveDnsmasqPort == 53 &&
          !effectiveHasDnatRedirect) {
        portConflict = true;
        portConflictReason =
            'Port conflict: Both AdGuard Home and router dnsmasq are configured on port 53 without port relocation.';
      }

      final activeProf = state.activeProfile;
      final profType = activeProf?.type ??
          (state.isExternal
              ? AdGuardInstanceType.externalHost
              : AdGuardInstanceType.localRouter);
      final profHost = activeProf?.host ?? (state.isExternal ? '' : '127.0.0.1');

      // Infer DNS topology mode and 8 routing states
      final inferredTopology = AdGuardDnsTopology.infer(
        adguardDnsPort: validStatus.dnsPort,
        dnsmasqPort: effectiveDnsmasqPort,
        dnsmasqServers: effectiveDnsmasqServers,
        hasDnatRedirect: effectiveHasDnatRedirect,
        adguardDnsAddresses: validStatus.dnsAddresses,
        isDnsRunning: validStatus.running,
        isApiReachable: true,
        instanceType: profType,
        targetHost: profHost,
        topClients: fetchedStats?.topClients ?? const [],
        totalQueries: fetchedStats?.numDnsQueries ?? 0,
        odhcpdIpv6Dns: effectiveOdhcpdIpv6,
        raDnsEnabled: effectiveRaDns,
        isIndeterminateIpv6: effectiveIndeterminateIpv6,
        routerIp: _currentRouter?.ipAddress,
        portConflict: portConflict,
        portConflictReason: portConflictReason,
      );

      final effectiveTopology = inferredTopology;

      // Evaluate capabilities
      final evaluatedCapabilities = state.isExternal
          ? AdGuardCapabilities(
              isInstalled: true,
              isServiceManageable: false,
              isApiReachable: true,
              isApiAuthenticated: true,
              isDnsOperational: validStatus.running,
              topology: effectiveTopology,
              discoveredHttpPort: validStatus.httpPort,
              version: validStatus.version,
            )
          : AdGuardCapabilities.evaluate(
              hasServiceInRcList: true,
              hasInitScript: true,
              resolvedServiceName: 'adguardhome',
              hasRunningProcess: (fetchedProcess?.pid ?? '').isNotEmpty,
              isApiReachable: true,
              isApiAuthenticated: true,
              status: validStatus,
              topology: inferredTopology,
              configuredHttpPort: validStatus.httpPort,
              isServiceEnabled: fetchedServiceEnabled,
            );

      // Check whether partial telemetry degradation occurred
      final bool isDegraded = statsErrorMsg != null ||
          filteringErrorMsg != null ||
          (!state.isExternal && processErrorMsg != null);

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        clearGeneralError: true,
        connectionStatus: isDegraded
            ? AdGuardConnectionStatus.degraded
            : AdGuardConnectionStatus.authenticated,
        status: validStatus,
        clearStatusError: true,
        stats: fetchedStats ?? state.stats, // retain previous on failure
        statsError: statsErrorMsg,
        clearStatsError: statsErrorMsg == null,
        filtering: fetchedFiltering ?? state.filtering, // retain previous
        filteringError: filteringErrorMsg,
        clearFilteringError: filteringErrorMsg == null,
        processTelemetry: state.isExternal
            ? null
            : (fetchedProcess ?? state.processTelemetry), // retain previous
        processTelemetryError: state.isExternal ? null : processErrorMsg,
        clearProcessTelemetryError: state.isExternal || processErrorMsg == null,
        capabilities: evaluatedCapabilities,
        topology: effectiveTopology,
        lastSuccessfulRefresh: DateTime.now().toUtc(),
      );

      _consecutiveFailures = 0;
      // Commit state to session cache
      _sessionCache[capturedInstanceId] = state;
      _scheduleNextPoll(calculateNextPollDelay());
    } catch (e, stack) {
      _consecutiveFailures++;
      Duration? errRetryAfter;
      if (e is AdGuardApiException) {
        errRetryAfter = e.retryAfter;
      }
      Logger.error(
        'AdGuardController[$routerId]: Unexpected refresh failure',
        e,
        stack,
      );
      if (!_disposed &&
          mounted &&
          cycleEpoch == _fetchEpoch &&
          routerId == capturedRouterId &&
          state.effectiveInstanceId == capturedInstanceId) {
        state = state.copyWith(
          isLoading: false,
          isRefreshing: false,
          connectionStatus: AdGuardConnectionStatus.error,
          generalError: 'Unexpected refresh failure: $e',
        );
        _scheduleNextPoll(calculateNextPollDelay(retryAfter: errRetryAfter));
      }
    } finally {
      if (_activeFetchEpoch == cycleEpoch) {
        _isRefreshing = false;
      }
    }
  }

  /// Non-blocking dashboard card hydration.
  ///
  /// Guarantees:
  /// - Restores session cache immediately if present.
  /// - Loads profiles without blocking UI.
  /// - Skips network calls completely if router lacks AdGuard capability AND no external profiles exist.
  /// - Never starts continuous polling or duplicate refresh cycles.
  /// - Never silently changes active profile selection.
  Future<void> hydrateDashboardIfNeeded({
    bool hasRouterCapability = false,
  }) async {
    if (_disposed || !mounted) return;

    // 1. If already refreshed or has data, no need to re-hydrate
    if (state.status != null || state.lastSuccessfulRefresh != null) {
      return;
    }

    // 2. Check session cache for effective instance ID or router ID
    final cached = _sessionCache[state.effectiveInstanceId] ??
        _sessionCache[routerId] ??
        _sessionCache['local_$routerId'];
    if (cached != null && cached.status != null) {
      state = cached.copyWith(
        profiles: state.profiles.isNotEmpty ? state.profiles : cached.profiles,
        activeProfile: state.activeProfile ?? cached.activeProfile,
      );
      return;
    }

    // 3. Load saved profiles & active profile
    await loadProfiles();
    if (_disposed || !mounted) return;

    // 4. Check if we should attempt discovery:
    // If router has local capability OR active/stored profile is external
    final hasExternal = state.isExternal ||
        state.profiles.any((p) => p.type == AdGuardInstanceType.externalHost);
    if (!hasRouterCapability && !hasExternal) {
      // No local router capability and no external profiles configured:
      // Skip network discovery entirely to avoid spurious traffic.
      return;
    }

    // 5. Initiate a single non-blocking refresh if not already refreshing
    if (!_isRefreshing) {
      await refresh(forceProbe: false);
    }
  }

  // ── Credential Delegation ─────────────────────────────────────────────────

  /// Sets authoritative AdGuard Home credentials on the underlying API service,
  /// persists them to secure storage for the active profile/router,
  /// triggers an immediate refresh cycle, and returns whether authentication succeeded.
  Future<bool> setCredentials(AdGuardCredentials credentials) async {
    final instanceId = state.activeProfile?.id ?? 'local_$routerId';
    if (credentials.username.isNotEmpty) {
      await _secureStorage?.saveAdGuardCredentialsForInstance(
        instanceId,
        credentials.username,
        credentials.password,
      );
    }
    _apiService.setCredentials(credentials);
    await refresh();
    return state.connectionStatus == AdGuardConnectionStatus.authenticated;
  }

  // ── Protection Mutation (Serialized via `agh_protection`) ─────────────────

  /// Modifies AdGuard Home protection state (enable, pause, or disable).
  ///
  /// Serialized in domain `'agh_protection'`. Authoritative status is re-fetched
  /// upon success to eliminate optimistic state drift.
  Future<bool> setProtection({
    required bool enabled,
    Duration? duration,
  }) async {
    if (_disposed || !mounted) return false;

    state = state.copyWith(
      isMutatingProtection: true,
      clearProtectionActionError: true,
    );

    final capturedRouterId = routerId;
    final currentEpoch = ++_fetchEpoch;

    try {
      final success = await _operationQueue.runLocked(
        routerId: routerId,
        domain: 'agh_protection',
        action: () async {
          final res = await _apiService.setProtection(
            enabled: enabled,
            duration: duration,
          );
          return res.isSuccess;
        },
      );

      if (_disposed ||
          !mounted ||
          routerId != capturedRouterId ||
          currentEpoch != _fetchEpoch) {
        return success;
      }

      if (success) {
        // Authoritative verification: Re-fetch status from server
        final verifyRes = await _apiService.getStatus();
        if (!_disposed &&
            mounted &&
            routerId == capturedRouterId &&
            currentEpoch == _fetchEpoch) {
          state = state.copyWith(
            isMutatingProtection: false,
            clearProtectionActionError: true,
            status: verifyRes.isSuccess && verifyRes.data != null
                ? verifyRes.data
                : state.status,
          );
        }
        return true;
      } else {
        state = state.copyWith(
          isMutatingProtection: false,
          protectionActionError: 'Failed to update protection status',
        );
        return false;
      }
    } catch (e) {
      if (!_disposed &&
          mounted &&
          routerId == capturedRouterId &&
          currentEpoch == _fetchEpoch) {
        state = state.copyWith(
          isMutatingProtection: false,
          protectionActionError: 'Protection mutation error: $e',
        );
      }
      return false;
    }
  }

  /// Helper dispatching [AdGuardProtectionState] tri-state transitions.
  Future<bool> setProtectionState(
    AdGuardProtectionState targetState, {
    Duration? pauseDuration,
  }) {
    switch (targetState) {
      case AdGuardProtectionState.enabled:
        return setProtection(enabled: true);
      case AdGuardProtectionState.paused:
        return setProtection(
          enabled: false,
          duration: pauseDuration ?? const Duration(minutes: 15),
        );
      case AdGuardProtectionState.disabled:
        return setProtection(enabled: false, duration: Duration.zero);
    }
  }

  // ── OpenWrt Service Lifecycle (Serialized via `service`) ──────────────────

  Future<bool> startService() => _manageService('start');
  Future<bool> stopService() => _manageService('stop');
  Future<bool> restartService() => _manageService('restart');
  Future<bool> enableService() => _manageService('enable');
  Future<bool> disableService() => _manageService('disable');

  /// Toggles service autostart on router boot.
  Future<bool> setServiceAutostart(bool enable) async {
    final success = await (enable ? enableService() : disableService());
    if (success && _isReviewerMode) {
      state = state.copyWith(
        capabilities: state.capabilities.copyWith(isServiceEnabled: enable),
      );
    }
    return success;
  }

  // ── Statistics Period Selection ──────────────────────────────────────────

  /// Updates the active statistics query time-window period and re-fetches stats.
  Future<void> setStatsPeriod(AdGuardStatsPeriod period) async {
    if (_disposed || !mounted) return;
    if (state.statsPeriod == period) return;
    state = state.copyWith(statsPeriod: period);
    await refresh();
  }

  // ── Custom User Rules Management ─────────────────────────────────────────

  /// Updates custom filtering rules via `/control/filtering/set_rules`.
  Future<bool> updateUserRules(List<String> rules) async {
    if (_disposed || !mounted) return false;

    final capturedRouterId = routerId;
    final currentEpoch = ++_fetchEpoch;

    try {
      final api = _apiService;
      final result = await api.setUserRules(rules);

      if (_disposed ||
          !mounted ||
          routerId != capturedRouterId ||
          currentEpoch != _fetchEpoch) {
        return result.isSuccess;
      }

      if (result.isSuccess) {
        // Authoritatively re-probe filtering status after rule updates
        final filterRes = await api.getFilteringStatus();
        if (!_disposed &&
            mounted &&
            routerId == capturedRouterId &&
            currentEpoch == _fetchEpoch) {
          if (filterRes.isSuccess && filterRes.data != null) {
            state = state.copyWith(
              filtering: filterRes.data,
              clearFilteringError: true,
            );
          } else if (state.filtering != null) {
            state = state.copyWith(
              filtering: state.filtering!.copyWith(userRules: rules),
              clearFilteringError: true,
            );
          }
        }
        return true;
      } else {
        final errorMsg =
            result.error?.message ?? 'Failed to update custom rules';
        state = state.copyWith(filteringError: errorMsg);
        return false;
      }
    } catch (e) {
      if (!_disposed &&
          mounted &&
          routerId == capturedRouterId &&
          currentEpoch == _fetchEpoch) {
        state = state.copyWith(filteringError: 'Update rules error: $e');
      }
      return false;
    }
  }

  // ── Filter Lists Management ───────────────────────────────────────────────

  /// Clears any active filter list action error banner.
  void clearFilterListActionError() {
    if (_disposed || !mounted) return;
    state = state.copyWith(clearFilterListActionError: true);
  }

  /// Adds a new filter list subscription or allowlist.
  Future<bool> addFilterList({
    required String name,
    required String url,
    required bool whitelist,
  }) async {
    if (_disposed || !mounted) return false;

    final trimmedName = name.trim();
    final trimmedUrl = url.trim();

    if (trimmedName.isEmpty || trimmedUrl.isEmpty) {
      state = state.copyWith(
        filterListActionError: 'Filter list name and URL cannot be empty.',
      );
      return false;
    }

    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      state = state.copyWith(
        filterListActionError:
            'Invalid URL. Please enter a valid HTTP or HTTPS URL.',
      );
      return false;
    }

    // Check duplicate URL against existing lists in current category
    final currentLists = whitelist
        ? (state.filtering?.whitelistFilters ?? const <AdGuardFilterList>[])
        : (state.filtering?.filterLists ?? const <AdGuardFilterList>[]);
    if (currentLists.any((l) => l.url.trim() == trimmedUrl)) {
      state = state.copyWith(
        filterListActionError: 'A filter list with this URL already exists.',
      );
      return false;
    }

    final capturedRouterId = routerId;
    final currentEpoch = ++_fetchEpoch;

    state = state.copyWith(
      isMutatingFilterLists: true,
      clearFilterListActionError: true,
    );

    try {
      final api = _apiService;
      final result = await api.addFilterList(
        name: trimmedName,
        url: trimmedUrl,
        whitelist: whitelist,
      );

      if (_disposed ||
          !mounted ||
          routerId != capturedRouterId ||
          currentEpoch != _fetchEpoch) {
        return result.isSuccess;
      }

      if (result.isSuccess) {
        final filterRes = await api.getFilteringStatus();
        if (!_disposed &&
            mounted &&
            routerId == capturedRouterId &&
            currentEpoch == _fetchEpoch) {
          state = state.copyWith(
            isMutatingFilterLists: false,
            filtering: filterRes.isSuccess && filterRes.data != null
                ? filterRes.data
                : state.filtering,
            clearFilterListActionError: true,
          );
        }
        return true;
      } else {
        final errorMsg = result.error?.message ?? 'Failed to add filter list';
        state = state.copyWith(
          isMutatingFilterLists: false,
          filterListActionError: errorMsg,
        );
        return false;
      }
    } catch (e) {
      if (!_disposed &&
          mounted &&
          routerId == capturedRouterId &&
          currentEpoch == _fetchEpoch) {
        state = state.copyWith(
          isMutatingFilterLists: false,
          filterListActionError: 'Failed to add filter list: $e',
        );
      }
      return false;
    }
  }

  /// Toggles enabled state of an existing filter list.
  Future<bool> toggleFilterList({
    required AdGuardFilterList list,
    required bool enabled,
  }) async {
    final listUrl = list.url.isNotEmpty ? list.url : list.name;
    return editFilterList(
      url: listUrl,
      name: list.name,
      newUrl: listUrl,
      enabled: enabled,
      whitelist: list.whitelist,
    );
  }

  /// Edits an existing filter list properties.
  Future<bool> editFilterList({
    required String url,
    required String name,
    required String newUrl,
    required bool enabled,
    required bool whitelist,
  }) async {
    if (_disposed || !mounted) return false;

    final trimmedName = name.trim();
    final trimmedNewUrl = newUrl.trim();

    if (trimmedName.isEmpty || trimmedNewUrl.isEmpty) {
      state = state.copyWith(
        filterListActionError: 'Filter list name and URL cannot be empty.',
      );
      return false;
    }

    final uri = Uri.tryParse(trimmedNewUrl);
    if (uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      state = state.copyWith(
        filterListActionError:
            'Invalid URL. Please enter a valid HTTP or HTTPS URL.',
      );
      return false;
    }

    final capturedRouterId = routerId;
    final currentEpoch = ++_fetchEpoch;

    state = state.copyWith(
      isMutatingFilterLists: true,
      clearFilterListActionError: true,
    );

    try {
      final api = _apiService;
      final result = await api.setFilterList(
        url: url.trim(),
        name: trimmedName,
        newUrl: trimmedNewUrl,
        enabled: enabled,
        whitelist: whitelist,
      );

      if (_disposed ||
          !mounted ||
          routerId != capturedRouterId ||
          currentEpoch != _fetchEpoch) {
        return result.isSuccess;
      }

      if (result.isSuccess) {
        final filterRes = await api.getFilteringStatus();
        if (!_disposed &&
            mounted &&
            routerId == capturedRouterId &&
            currentEpoch == _fetchEpoch) {
          state = state.copyWith(
            isMutatingFilterLists: false,
            filtering: filterRes.isSuccess && filterRes.data != null
                ? filterRes.data
                : state.filtering,
            clearFilterListActionError: true,
          );
        }
        return true;
      } else {
        final errorMsg =
            result.error?.message ?? 'Failed to update filter list';
        state = state.copyWith(
          isMutatingFilterLists: false,
          filterListActionError: errorMsg,
        );
        return false;
      }
    } catch (e) {
      if (!_disposed &&
          mounted &&
          routerId == capturedRouterId &&
          currentEpoch == _fetchEpoch) {
        state = state.copyWith(
          isMutatingFilterLists: false,
          filterListActionError: 'Failed to update filter list: $e',
        );
      }
      return false;
    }
  }

  /// Removes an existing filter list subscription or allowlist.
  Future<bool> removeFilterList({
    required String url,
    required bool whitelist,
  }) async {
    if (_disposed || !mounted) return false;

    final capturedRouterId = routerId;
    final currentEpoch = ++_fetchEpoch;

    state = state.copyWith(
      isMutatingFilterLists: true,
      clearFilterListActionError: true,
    );

    try {
      final api = _apiService;
      final result = await api.removeFilterList(
        url: url.trim(),
        whitelist: whitelist,
      );

      if (_disposed ||
          !mounted ||
          routerId != capturedRouterId ||
          currentEpoch != _fetchEpoch) {
        return result.isSuccess;
      }

      if (result.isSuccess) {
        final filterRes = await api.getFilteringStatus();
        if (!_disposed &&
            mounted &&
            routerId == capturedRouterId &&
            currentEpoch == _fetchEpoch) {
          state = state.copyWith(
            isMutatingFilterLists: false,
            filtering: filterRes.isSuccess && filterRes.data != null
                ? filterRes.data
                : state.filtering,
            clearFilterListActionError: true,
          );
        }
        return true;
      } else {
        final errorMsg =
            result.error?.message ?? 'Failed to remove filter list';
        state = state.copyWith(
          isMutatingFilterLists: false,
          filterListActionError: errorMsg,
        );
        return false;
      }
    } catch (e) {
      if (!_disposed &&
          mounted &&
          routerId == capturedRouterId &&
          currentEpoch == _fetchEpoch) {
        state = state.copyWith(
          isMutatingFilterLists: false,
          filterListActionError: 'Failed to remove filter list: $e',
        );
      }
      return false;
    }
  }

  /// Triggers a manual update/refresh of filtering list subscriptions.
  Future<bool> refreshFilterLists({bool? whitelist}) async {
    if (_disposed || !mounted) return false;

    final capturedRouterId = routerId;
    final currentEpoch = ++_fetchEpoch;

    state = state.copyWith(
      isMutatingFilterLists: true,
      clearFilterListActionError: true,
    );

    try {
      final api = _apiService;
      final result = await api.refreshFilterLists(whitelist: whitelist);

      if (_disposed ||
          !mounted ||
          routerId != capturedRouterId ||
          currentEpoch != _fetchEpoch) {
        return result.isSuccess;
      }

      if (result.isSuccess) {
        final filterRes = await api.getFilteringStatus();
        if (!_disposed &&
            mounted &&
            routerId == capturedRouterId &&
            currentEpoch == _fetchEpoch) {
          state = state.copyWith(
            isMutatingFilterLists: false,
            filtering: filterRes.isSuccess && filterRes.data != null
                ? filterRes.data
                : state.filtering,
            clearFilterListActionError: true,
          );
        }
        return true;
      } else {
        final errorMsg =
            result.error?.message ?? 'Failed to refresh filter lists';
        state = state.copyWith(
          isMutatingFilterLists: false,
          filterListActionError: errorMsg,
        );
        return false;
      }
    } catch (e) {
      if (!_disposed &&
          mounted &&
          routerId == capturedRouterId &&
          currentEpoch == _fetchEpoch) {
        state = state.copyWith(
          isMutatingFilterLists: false,
          filterListActionError: 'Failed to refresh filter lists: $e',
        );
      }
      return false;
    }
  }

  Future<bool> _manageService(String action) async {
    if (_disposed || !mounted) return false;

    if (state.isExternal) {
      state = state.copyWith(
        serviceActionError:
            'Service management is not available for external AdGuard Home instances.',
      );
      return false;
    }

    // Check manageability
    if (!state.capabilities.isServiceManageable && !_isReviewerMode) {
      state = state.copyWith(
        serviceActionError:
            'Service is not manageable (no OpenWrt init script registered)',
      );
      return false;
    }

    state = state.copyWith(
      isManagingService: true,
      clearServiceActionError: true,
    );

    final capturedRouterId = routerId;
    final currentEpoch = ++_fetchEpoch;

    try {
      final success = await _operationQueue.runLocked(
        routerId: routerId,
        domain: 'service',
        action: () async {
          if (_isReviewerMode) {
            return true;
          }

          final serviceName = state.capabilities.serviceName ?? 'adguardhome';
          final api = _luciApiService;
          final router = _currentRouter;
          final sysauth = _authServiceOverride?.sysauth ?? _sysauth ?? '';

          if (api == null || router == null) return false;

          return await api.manageServiceAction(
            router.ipAddress,
            sysauth,
            router.useHttps,
            serviceName: serviceName,
            action: action,
          );
        },
      );

      if (_disposed ||
          !mounted ||
          routerId != capturedRouterId ||
          currentEpoch != _fetchEpoch) {
        return success;
      }

      if (success) {
        state = state.copyWith(
          isManagingService: false,
          clearServiceActionError: true,
        );
        // Authoritatively re-probe service status after mutation
        await refresh();
        return true;
      } else {
        state = state.copyWith(
          isManagingService: false,
          serviceActionError: 'Failed to execute $action on AdGuard Home service',
        );
        return false;
      }
    } catch (e) {
      if (!_disposed &&
          mounted &&
          routerId == capturedRouterId &&
          currentEpoch == _fetchEpoch) {
        state = state.copyWith(
          isManagingService: false,
          serviceActionError: 'Service action $action error: $e',
        );
      }
      return false;
    }
  }

  // ── Process Telemetry Helper ──────────────────────────────────────────────

  Future<AdGuardProcessTelemetry?> _fetchProcessTelemetry() async {
    if (_isReviewerMode) {
      return const AdGuardProcessTelemetry(
        pid: '1660',
        cpuPercent: 0.5,
        vszKb: 24580,
        vszMb: 24.0,
        memPercent: 2.1,
        estimatedRamMb: 5.4,
      );
    }

    final api = _luciApiService;
    final router = _currentRouter;
    final sysauth = _authServiceOverride?.sysauth ?? _sysauth ?? '';
    if (api == null || router == null) return null;
    final res = await api.call(
      router.ipAddress,
      sysauth,
      router.useHttps,
      object: 'luci',
      method: 'getProcessList',
    );

    if (res is Map && res['result'] is List) {
      final list = res['result'] as List;
      for (final proc in list) {
        if (proc is Map) {
          final cmd = (proc['COMMAND'] ?? '').toString();
          if (cmd.contains('AdGuardHome') || cmd.contains('adguardhome')) {
            return AdGuardProcessTelemetry.fromLuciProcess(
              proc.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
        }
      }
      return null;
    }
    return null;
  }

  Future<bool?> _fetchServiceAutostart() async {
    final api = _luciApiService;
    final router = _currentRouter;
    final sysauth = _authServiceOverride?.sysauth ?? _sysauth ?? '';
    if (api == null || router == null) return null;

    try {
      final rcRes = await api.call(
        router.ipAddress,
        sysauth,
        router.useHttps,
        object: 'rc',
        method: 'list',
      );

      Map<String, dynamic>? servicesMap;
      if (rcRes is List && rcRes.length > 1 && rcRes[0] == 0) {
        servicesMap = rcRes[1] as Map<String, dynamic>?;
      } else if (rcRes is Map<String, dynamic>) {
        servicesMap = rcRes;
      }

      if (servicesMap != null) {
        final serviceName = state.capabilities.serviceName ?? 'adguardhome';
        final meta = servicesMap[serviceName] ??
            servicesMap['adguardhome'] ??
            servicesMap['AdGuardHome'];
        if (meta is Map) {
          return meta['enabled'] == true ||
              meta['enabled'] == 1 ||
              meta['enabled'] == '1';
        }
      }
    } catch (e) {
      Logger.debug('AdGuardController: rc.list autostart probe failed: $e');
    }
    return null;
  }

  // ── UCI DNS Topology Probing & Cache Helpers ──────────────────────────────

  Future<_CachedUciTopologyConfig?> _fetchDnsUciConfig(
    int cycleEpoch,
    String capturedRouterId,
  ) async {
    final api = _luciApiService;
    final router = _currentRouter;
    final sysauth = _authServiceOverride?.sysauth ?? _sysauth ?? '';
    if (api == null || router == null) return null;

    dynamic dhcpRaw;
    dynamic firewallRaw;
    dynamic netDumpRaw;

    await Future.wait([
      () async {
        try {
          dhcpRaw = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'dhcp'},
          );
        } catch (e) {
          Logger.warning(
            'AdGuardController[$capturedRouterId]: uci get dhcp failed: $e',
          );
        }
      }(),
      () async {
        try {
          firewallRaw = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
          );
        } catch (e) {
          Logger.warning(
            'AdGuardController[$capturedRouterId]: uci get firewall failed: $e',
          );
        }
      }(),
      () async {
        try {
          netDumpRaw = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'network.interface',
            method: 'dump',
          );
        } catch (e) {
          Logger.warning(
            'AdGuardController[$capturedRouterId]: network.interface dump failed: $e',
          );
        }
      }(),
    ]);

    if (_disposed ||
        !mounted ||
        cycleEpoch != _fetchEpoch ||
        routerId != capturedRouterId) {
      return null;
    }

    if (dhcpRaw == null && firewallRaw == null && netDumpRaw == null) {
      return null;
    }

    final dhcpValues = extractUciValues(dhcpRaw);
    final firewallValues = extractUciValues(firewallRaw);

    int port = _cachedUciTopology?.dnsmasqPort ?? 53;
    List<String> servers = _cachedUciTopology?.dnsmasqServers ?? const [];
    bool hasDnat = _cachedUciTopology?.hasDnatRedirect ?? false;
    List<String> ipv6Dns = _cachedUciTopology?.odhcpdIpv6Dns ?? const [];
    bool? raDns = _cachedUciTopology?.raDnsEnabled;
    bool isIndeterminate = _cachedUciTopology?.isIndeterminateIpv6 ?? false;
    List<String> routerIpv6Addrs =
        _cachedUciTopology?.routerInterfaceIpv6Addresses ?? const [];

    if (dhcpValues != null) {
      final parsedDhcp = parseDhcpUci(dhcpValues);
      port = parsedDhcp.dnsmasqPort;
      servers = parsedDhcp.dnsmasqServers;
      ipv6Dns = parsedDhcp.odhcpdIpv6Dns;
      raDns = parsedDhcp.raDnsEnabled;
      isIndeterminate = parsedDhcp.isIndeterminateIpv6;
    } else {
      isIndeterminate = true;
    }

    if (firewallValues != null) {
      hasDnat = parseFirewallUci(firewallValues);
    }

    if (netDumpRaw != null) {
      routerIpv6Addrs = extractInterfaceDumpIpv6Addresses(netDumpRaw);
    }

    return _CachedUciTopologyConfig(
      dnsmasqPort: port,
      dnsmasqServers: List.unmodifiable(servers),
      hasDnatRedirect: hasDnat,
      odhcpdIpv6Dns: List.unmodifiable(ipv6Dns),
      raDnsEnabled: raDns,
      isIndeterminateIpv6: isIndeterminate,
      routerInterfaceIpv6Addresses: List.unmodifiable(routerIpv6Addrs),
      probedAt: DateTime.now().toUtc(),
    );
  }

  /// Extracts authoritative router interface IPv6 addresses from `network.interface dump`.
  @visibleForTesting
  static List<String> extractInterfaceDumpIpv6Addresses(dynamic res) {
    if (res == null) return const [];
    dynamic payload = res;
    if (payload is Map && payload.containsKey('result')) {
      payload = payload['result'];
    }
    if (payload is List && payload.isNotEmpty) {
      if (payload.length > 1 && payload[0] == 0) {
        payload = payload[1];
      } else if (payload.length == 1 && payload[0] is Map) {
        payload = payload[0];
      } else if (payload.last is Map) {
        payload = payload.last;
      } else {
        return const [];
      }
    }
    if (payload is! Map) return const [];

    final interfaces = payload['interface'];
    if (interfaces is! List) return const [];

    final addresses = <String>{};
    for (final iface in interfaces) {
      if (iface is! Map) continue;
      final ipv6List = iface['ipv6-address'];
      if (ipv6List is List) {
        for (final entry in ipv6List) {
          if (entry is Map && entry['address'] != null) {
            final addr = entry['address'].toString().trim().toLowerCase();
            if (addr.isNotEmpty) {
              addresses.add(addr);
            }
          }
        }
      }
    }
    return List.unmodifiable(addresses.toList());
  }

  @visibleForTesting
  static Map<String, dynamic>? extractUciValues(dynamic res) {
    if (res == null) return null;
    dynamic payload = res;
    if (payload is Map && payload.containsKey('result')) {
      payload = payload['result'];
    }
    if (payload is List && payload.isNotEmpty) {
      if (payload.length > 1 && payload[0] == 0) {
        payload = payload[1];
      } else if (payload.length == 1 && payload[0] is Map) {
        payload = payload[0];
      } else if (payload.last is Map) {
        payload = payload.last;
      } else {
        return null;
      }
    }
    if (payload is Map) {
      if (payload['values'] is Map) {
        return (payload['values'] as Map)
            .map((k, v) => MapEntry(k.toString(), v));
      }
      return payload.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  @visibleForTesting
  static ({
    int dnsmasqPort,
    List<String> dnsmasqServers,
    List<String> odhcpdIpv6Dns,
    bool? raDnsEnabled,
    bool isIndeterminateIpv6,
  }) parseDhcpUci(
    Map<String, dynamic> values,
  ) {
    int port = 53;
    final List<String> servers = [];
    final List<String> ipv6Dns = [];
    bool? raDns;
    bool hasDhcpSection = false;

    for (final section in values.values) {
      if (section is Map && section['.type'] == 'dnsmasq') {
        final rawPort = section['port'];
        if (rawPort != null) {
          if (rawPort is num) {
            port = rawPort.toInt();
          } else {
            final parsed = int.tryParse(rawPort.toString().trim());
            if (parsed != null) {
              port = parsed;
            }
          }
        }

        final rawServer = section['server'];
        if (rawServer is List) {
          for (final s in rawServer) {
            if (s != null) {
              final str = s.toString().trim();
              if (str.isNotEmpty) servers.add(str);
            }
          }
        } else if (rawServer is String) {
          final str = rawServer.trim();
          if (str.isNotEmpty) servers.add(str);
        }
      }

      if (section is Map && section['.type'] == 'dhcp') {
        hasDhcpSection = true;
        final rawDns = section['dns'];
        if (rawDns is List) {
          for (final d in rawDns) {
            if (d != null) {
              final str = d.toString().trim();
              if (str.contains(':')) ipv6Dns.add(str);
            }
          }
        } else if (rawDns is String) {
          final str = rawDns.trim();
          if (str.contains(':')) ipv6Dns.add(str);
        }

        final rawRaDns = section['ra_dns'];
        if (rawRaDns != null) {
          if (rawRaDns == '0' || rawRaDns == 0 || rawRaDns == false) {
            raDns = false;
          } else if (rawRaDns == '1' || rawRaDns == 1 || rawRaDns == true) {
            raDns = true;
          }
        }
      }
    }

    return (
      dnsmasqPort: port,
      dnsmasqServers: servers,
      odhcpdIpv6Dns: ipv6Dns,
      raDnsEnabled: raDns,
      isIndeterminateIpv6: !hasDhcpSection,
    );
  }

  @visibleForTesting
  static bool parseFirewallUci(Map<String, dynamic> values) {
    for (final section in values.values) {
      if (section is Map && section['.type'] == 'redirect') {
        final target = section['target']?.toString().toUpperCase();
        final isDnat = target == null || target.isEmpty || target == 'DNAT';
        if (!isDnat) continue;

        final srcDportRaw = section['src_dport'];
        bool matchesPort53 = false;
        if (srcDportRaw is num && srcDportRaw == 53) {
          matchesPort53 = true;
        } else if (srcDportRaw is String) {
          final parts = srcDportRaw.split(RegExp(r'[\s,]+'));
          matchesPort53 = parts.any((p) => p.trim() == '53');
        } else if (srcDportRaw is List) {
          matchesPort53 = srcDportRaw.any((p) => p.toString().trim() == '53');
        }

        if (matchesPort53) {
          return true;
        }
      }
    }
    return false;
  }

  // ── Milestone E: DNS Routing Orchestration, Loop Guard & Rollback ─────────

  /// Parses a dnsmasq UCI/dnsmasq.conf `server` entry into structured components.
  @visibleForTesting
  static ({
    bool isConditional,
    String? domains,
    String? targetHost,
    int targetPort,
    bool isLocalOnly,
    bool isMalformed,
  }) parseDnsmasqServerRule(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (
        isConditional: false,
        domains: null,
        targetHost: null,
        targetPort: 53,
        isLocalOnly: false,
        isMalformed: true,
      );
    }

    if (!trimmed.startsWith('/')) {
      // Standard upstream server (e.g. 1.1.1.1, 127.0.0.1#5353, [::1]#5353)
      String host;
      int port = 53;
      if (trimmed.contains('#')) {
        final hashIdx = trimmed.indexOf('#');
        host = trimmed.substring(0, hashIdx).trim();
        final p = int.tryParse(trimmed.substring(hashIdx + 1).trim());
        if (p != null) port = p;
      } else {
        host = trimmed;
      }
      if (host.startsWith('[') && host.endsWith(']')) {
        host = host.substring(1, host.length - 1);
      }
      return (
        isConditional: false,
        domains: null,
        targetHost: host,
        targetPort: port,
        isLocalOnly: false,
        isMalformed: false,
      );
    }

    // Conditional rule starting with '/'
    final lastSlash = trimmed.lastIndexOf('/');
    if (lastSlash == 0) {
      // Only one slash, e.g. "/broken"
      return (
        isConditional: true,
        domains: null,
        targetHost: null,
        targetPort: 53,
        isLocalOnly: false,
        isMalformed: true,
      );
    }

    final domains = trimmed.substring(1, lastSlash).trim();
    final target = trimmed.substring(lastSlash + 1).trim();

    if (target.isEmpty) {
      // Local-only rule: queries never forwarded (e.g. "/local/")
      return (
        isConditional: true,
        domains: domains,
        targetHost: null,
        targetPort: 53,
        isLocalOnly: true,
        isMalformed: false,
      );
    }

    if (target == '#') {
      // Use standard upstream servers
      return (
        isConditional: true,
        domains: domains,
        targetHost: null,
        targetPort: 53,
        isLocalOnly: false,
        isMalformed: false,
      );
    }

    String host;
    int port = 53;
    if (target.contains('#')) {
      final hashIdx = target.indexOf('#');
      host = target.substring(0, hashIdx).trim();
      final p = int.tryParse(target.substring(hashIdx + 1).trim());
      if (p != null) port = p;
    } else {
      host = target;
    }
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }

    return (
      isConditional: true,
      domains: domains,
      targetHost: host,
      targetPort: port,
      isLocalOnly: false,
      isMalformed: false,
    );
  }

  /// Normalizes an IPv4, IPv6, or hostname literal into a canonical representation for reliable comparison.
  /// Uncompressed, compressed, and bracketed IPv6 literals (e.g. `2001:db8::1`, `2001:db8:0:0:0:0:0:1`, `[::1]`)
  /// are parsed to their 16-byte representation and formatted uniformly as 8 hex parts without leading zeros.
  @visibleForTesting
  static String normalizeHost(String host) {
    final trimmed = host.trim().toLowerCase();
    final unbracketed = (trimmed.startsWith('[') && trimmed.endsWith(']'))
        ? trimmed.substring(1, trimmed.length - 1).trim()
        : trimmed;
    try {
      final bytes = Uri.parseIPv6Address(unbracketed);
      final parts = <String>[];
      for (int i = 0; i < 16; i += 2) {
        final val = (bytes[i] << 8) | bytes[i + 1];
        parts.add(val.toRadixString(16));
      }
      return parts.join(':');
    } catch (_) {
      return unbracketed;
    }
  }

  /// Parses an AdGuard Home conditional upstream rule into structured components.
  @visibleForTesting
  static ({
    bool isConditional,
    String? domains,
    String? targetHost,
    int targetPort,
    bool isBlockOnly,
    bool isMalformed,
  }) parseAdguardConditionalUpstream(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (
        isConditional: false,
        domains: null,
        targetHost: null,
        targetPort: 53,
        isBlockOnly: false,
        isMalformed: true,
      );
    }

    String? domains;
    String target;

    if (trimmed.startsWith('[/')) {
      final closeIdx = trimmed.indexOf('/]');
      if (closeIdx == -1) {
        return (
          isConditional: true,
          domains: null,
          targetHost: null,
          targetPort: 53,
          isBlockOnly: false,
          isMalformed: true,
        );
      }
      if (closeIdx > 2) {
        final d = trimmed.substring(2, closeIdx).trim();
        domains = d.isEmpty ? null : d;
      } else {
        // Handle empty-domain / catch-all syntax: "[/]"
        domains = null;
      }
      target = trimmed.substring(closeIdx + 2).trim();
    } else if (trimmed.startsWith('/')) {
      final lastSlash = trimmed.lastIndexOf('/');
      if (lastSlash == 0) {
        return (
          isConditional: true,
          domains: null,
          targetHost: null,
          targetPort: 53,
          isBlockOnly: false,
          isMalformed: true,
        );
      }
      if (lastSlash > 1) {
        final d = trimmed.substring(1, lastSlash).trim();
        domains = d.isEmpty ? null : d;
      } else {
        // Handle empty-domain / catch-all syntax: "//"
        domains = null;
      }
      target = trimmed.substring(lastSlash + 1).trim();
    } else {
      return (
        isConditional: false,
        domains: null,
        targetHost: null,
        targetPort: 53,
        isBlockOnly: false,
        isMalformed: false,
      );
    }

    if (target.isEmpty || target == '#' || target == "''") {
      return (
        isConditional: true,
        domains: domains,
        targetHost: null,
        targetPort: 53,
        isBlockOnly: true,
        isMalformed: false,
      );
    }

    // Strip transport protocol prefixes (udp://, tcp://, tls://, etc.)
    String addr = target;
    final protoIdx = addr.indexOf('://');
    if (protoIdx != -1) {
      addr = addr.substring(protoIdx + 3);
    }
    // Strip URL paths
    final slashIdx = addr.indexOf('/');
    if (slashIdx != -1) {
      addr = addr.substring(0, slashIdx);
    }

    String host;
    int port = 53;

    if (addr.startsWith('[') && addr.contains(']')) {
      final endBracket = addr.indexOf(']');
      host = addr.substring(1, endBracket).trim();
      final remainder = addr.substring(endBracket + 1).trim();
      if (remainder.startsWith(':') || remainder.startsWith('#')) {
        final parsedPort = int.tryParse(remainder.substring(1).trim());
        if (parsedPort != null) port = parsedPort;
      }
    } else if (addr.contains('#')) {
      final hashIdx = addr.indexOf('#');
      host = addr.substring(0, hashIdx).trim();
      final parsedPort = int.tryParse(addr.substring(hashIdx + 1).trim());
      if (parsedPort != null) port = parsedPort;
    } else {
      // Check if addr is an unbracketed IPv6 literal (compressed or uncompressed)
      bool isIpv6 = false;
      try {
        Uri.parseIPv6Address(addr.trim());
        isIpv6 = true;
      } catch (_) {}

      if (isIpv6) {
        host = addr.trim();
      } else if (addr.contains(':')) {
        final colonIdx = addr.lastIndexOf(':');
        final candidateHost = addr.substring(0, colonIdx).trim();
        final candidatePort = int.tryParse(addr.substring(colonIdx + 1).trim());
        if (candidatePort != null) {
          host = candidateHost;
          port = candidatePort;
        } else {
          host = addr.trim();
        }
      } else {
        host = addr.trim();
      }
    }

    if (host.trim().isEmpty) {
      return (
        isConditional: true,
        domains: domains,
        targetHost: null,
        targetPort: port,
        isBlockOnly: false,
        isMalformed: true,
      );
    }

    return (
      isConditional: true,
      domains: domains,
      targetHost: host.trim(),
      targetPort: port,
      isBlockOnly: false,
      isMalformed: false,
    );
  }

  /// Normalizes addresses and detects potential infinite DNS forwarding loops.
  @visibleForTesting
  static ({
    bool loopDetected,
    bool isWarningOnly,
    String? loopReason,
  }) detectForwardingLoop({
    required List<String> adguardUpstreams,
    required String? routerIp,
    List<String> routerIpv6Addresses = const [],
    required int dnsmasqPort,
    required bool isExternal,
  }) {
    if (adguardUpstreams.isEmpty) {
      return (loopDetected: false, isWarningOnly: false, loopReason: null);
    }

    final normalizedRouterIps = <String>{
      '127.0.0.1',
      'localhost',
      '::1',
      '0.0.0.0',
      normalizeHost('127.0.0.1'),
      normalizeHost('localhost'),
      normalizeHost('::1'),
      normalizeHost('0.0.0.0'),
      if (routerIp != null && routerIp.trim().isNotEmpty) ...[
        routerIp.trim().toLowerCase(),
        normalizeHost(routerIp),
      ],
      for (final ip in routerIpv6Addresses)
        if (ip.trim().isNotEmpty) ...[
          ip.trim().toLowerCase(),
          normalizeHost(ip),
        ],
    };

    ({bool loopDetected, bool isWarningOnly, String? loopReason})? advisoryWarning;

    for (final raw in adguardUpstreams) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('!')) continue;

      // Handle domain-specific conditional forwarders (e.g. [/lan/]192.168.1.1:53 or /lan/127.0.0.1#53)
      if (trimmed.startsWith('[/') || trimmed.startsWith('/')) {
        final parsed = parseAdguardConditionalUpstream(trimmed);
        if (parsed.isMalformed) {
          advisoryWarning ??= (
            loopDetected: false,
            isWarningOnly: true,
            loopReason:
                'AdGuard conditional upstream rule "$trimmed" is malformed. Verify syntax before applying.',
          );
          continue;
        }

        if (parsed.isBlockOnly || parsed.targetHost == null) {
          continue;
        }

        final normHost = normalizeHost(parsed.targetHost!);
        if (normalizedRouterIps.contains(normHost) ||
            normalizedRouterIps.contains(parsed.targetHost!.toLowerCase())) {
          if (parsed.targetPort == dnsmasqPort) {
            final domainsLabel = parsed.domains != null ? ' "${parsed.domains}"' : '';
            final reason =
                'AdGuard conditional upstream "$trimmed" forwards$domainsLabel queries back to router resolver on port $dnsmasqPort. '
                'Configuring router DNS to forward to AdGuard creates a circular forwarding loop for these domains.';
            return (loopDetected: true, isWarningOnly: false, loopReason: reason);
          } else {
            advisoryWarning ??= (
              loopDetected: false,
              isWarningOnly: true,
              loopReason:
                  'AdGuard conditional upstream "$trimmed" targets a local service on port ${parsed.targetPort}. '
                  'Verify that this resolver does not route queries back to router dnsmasq (port $dnsmasqPort) or AdGuard.',
            );
          }
        }
        continue;
      }

      // Strip transport prefixes (udp://, tcp://, tls://, https://, quic://, sdns://, etc.)
      String addressPart = trimmed;
      final protoIdx = addressPart.indexOf('://');
      if (protoIdx != -1) {
        addressPart = addressPart.substring(protoIdx + 3);
      }

      // Strip URL paths (e.g. https://dns.adguard.com/dns-query)
      final slashIdx = addressPart.indexOf('/');
      if (slashIdx != -1) {
        addressPart = addressPart.substring(0, slashIdx);
      }

      // Extract host and optional port
      String host;
      int port = 53; // default DNS port if not specified

      if (addressPart.startsWith('[') && addressPart.contains(']')) {
        final endBracket = addressPart.indexOf(']');
        host = addressPart.substring(1, endBracket).trim();
        final remainder = addressPart.substring(endBracket + 1).trim();
        if (remainder.startsWith(':') || remainder.startsWith('#')) {
          final parsedPort = int.tryParse(remainder.substring(1).trim());
          if (parsedPort != null) port = parsedPort;
        }
      } else if (addressPart.contains('#')) {
        final hashIdx = addressPart.indexOf('#');
        host = addressPart.substring(0, hashIdx).trim();
        final parsedPort = int.tryParse(addressPart.substring(hashIdx + 1).trim());
        if (parsedPort != null) port = parsedPort;
      } else {
        // Check if addressPart is an unbracketed IPv6 literal (e.g. 2001:db8::1 or 2001:db8:0:0:0:0:0:1)
        bool isIpv6 = false;
        try {
          Uri.parseIPv6Address(addressPart.trim());
          isIpv6 = true;
        } catch (_) {}

        if (isIpv6) {
          host = addressPart.trim();
        } else if (addressPart.contains(':')) {
          // host:port (IPv4 or hostname with port)
          final colonIdx = addressPart.lastIndexOf(':');
          final candidateHost = addressPart.substring(0, colonIdx).trim();
          final candidatePort = int.tryParse(addressPart.substring(colonIdx + 1).trim());
          if (candidatePort != null) {
            host = candidateHost;
            port = candidatePort;
          } else {
            host = addressPart.trim();
          }
        } else {
          // bare IPv4, bare hostname
          host = addressPart.trim();
        }
      }

      final normHost = normalizeHost(host);

      // Check if upstream points back to the router
      if (normalizedRouterIps.contains(normHost) ||
          normalizedRouterIps.contains(host.trim().toLowerCase())) {
        if (port == dnsmasqPort) {
          final reason =
              'AdGuard upstream "$trimmed" forwards queries back to router resolver on port $dnsmasqPort. '
              'Configuring router DNS to forward to AdGuard creates an infinite resolution loop.';
          return (loopDetected: true, isWarningOnly: false, loopReason: reason);
        } else {
          advisoryWarning ??= (
            loopDetected: false,
            isWarningOnly: true,
            loopReason:
                'AdGuard upstream "$trimmed" targets a local service on port $port. '
                'Verify that this resolver does not route queries back to router dnsmasq (port $dnsmasqPort) or AdGuard.',
          );
        }
      }
    }

    if (advisoryWarning != null) {
      return advisoryWarning;
    }

    return (loopDetected: false, isWarningOnly: false, loopReason: null);
  }

  /// Performs preflight safety validation before presenting or executing router DNS changes.
  Future<AdGuardDnsPreflightResult> preflightRouterDnsConfiguration() async {
    final router = _currentRouter;
    final status = state.status;
    final profile = state.activeProfile;

    if (router == null) {
      return const AdGuardDnsPreflightResult(
        canProceed: false,
        targetHost: '',
        targetPort: 0,
        targetForwarder: '',
        currentServers: [],
        warnings: ['No router session active.'],
      );
    }

    // STRICT INVARIANT: Always use status.dnsPort (not profile.port)
    final dnsPort = (status?.dnsPort != null && status!.dnsPort > 0)
        ? status.dnsPort
        : 53;
    final isExt = profile?.type.isExternal ?? state.isExternal;
    final host = isExt ? (profile?.host.trim() ?? '') : '127.0.0.1';

    // Format target forwarder: <ip>#<port> (or plain <ip> if port 53)
    final targetForwarder = (dnsPort == 53) ? host : '$host#$dnsPort';

    final warnings = <String>[];
    bool isHostname = false;

    // Check if host is raw IP or hostname
    final isIpv4 = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
    final isIpv6 = host.contains(':');
    if (!isIpv4 && !isIpv6) {
      isHostname = true;
      warnings.add(
        'The AdGuard destination "$host" is a hostname. If dnsmasq forwards queries to a hostname, '
        'it may fail to resolve that hostname when DNS is interrupted. Using an IP address is strongly recommended.',
      );
    }

    // Read current dnsmasq servers
    final currentServers = List<String>.from(
      _cachedUciTopology?.dnsmasqServers ?? const [],
    );
    final isAlreadyConfigured = currentServers.any((s) {
      final trimmed = s.trim();
      return trimmed == targetForwarder ||
          trimmed == '$host#$dnsPort' ||
          (dnsPort == 53 && trimmed == host);
    });

    // Check forwarding loop against AdGuard upstreams
    bool loopDetected = false;
    String? loopReason;
    try {
      final upstreamsRes = await _apiService.getUpstreamDns();
      if (upstreamsRes.isSuccess && upstreamsRes.data != null) {
        final routerIpv6List =
            _cachedUciTopology?.routerInterfaceIpv6Addresses ?? const [];
        final loopCheck = detectForwardingLoop(
          adguardUpstreams: upstreamsRes.data!,
          routerIp: router.ipAddress,
          routerIpv6Addresses: routerIpv6List,
          dnsmasqPort: _cachedUciTopology?.dnsmasqPort ?? 53,
          isExternal: isExt,
        );
        loopDetected = loopCheck.loopDetected;
        loopReason = loopCheck.loopReason;
        if (loopReason != null) {
          warnings.add(loopReason);
        }
        if (routerIpv6List.isEmpty &&
            upstreamsRes.data!.any((u) {
              final trimmed = u.trim();
              if (trimmed.startsWith('#') || trimmed.startsWith('!')) return false;
              if (trimmed.contains('[') && trimmed.contains(']')) return true;
              final withoutProto = trimmed.contains('://')
                  ? trimmed.substring(trimmed.indexOf('://') + 3)
                  : trimmed;
              final hostPart = withoutProto.split('/')[0].split('#')[0];
              try {
                Uri.parseIPv6Address(hostPart);
                return true;
              } catch (_) {
                return false;
              }
            })) {
          warnings.add(
            'Router interface IPv6 addresses were unavailable. IPv6 forwarding loop detection could not verify all interface addresses.',
          );
        }
      }
    } catch (e) {
      warnings.add(
        'Could not complete DNS loop detection verification ($e). Please verify AdGuard upstreams manually before applying.',
      );
    }

    // Check port conflict
    bool portConflict = false;
    String? portConflictReason;
    if (!isExt &&
        dnsPort == 53 &&
        (_cachedUciTopology?.dnsmasqPort ?? 53) == 53 &&
        !(_cachedUciTopology?.hasDnatRedirect ?? false)) {
      portConflict = true;
      portConflictReason =
          'Port conflict: AdGuard Home is configured on port 53, but dnsmasq is also listening on port 53. '
          'Dnsmasq must be relocated or disabled first.';
      warnings.add(portConflictReason);
    }

    final canProceed = !loopDetected && !portConflict && host.isNotEmpty;

    return AdGuardDnsPreflightResult(
      canProceed: canProceed,
      targetHost: host,
      targetPort: dnsPort,
      targetForwarder: targetForwarder,
      currentServers: currentServers,
      isAlreadyConfigured: isAlreadyConfigured,
      isExternal: isExt,
      isHostname: isHostname,
      loopDetected: loopDetected,
      loopReason: loopReason,
      portConflict: portConflict,
      portConflictReason: portConflictReason,
      warnings: warnings,
    );
  }

  /// Configures router dnsmasq forwarding to AdGuard with atomic 30-second rollback watchdog.
  Future<AdGuardDnsConfigResult> configureRouterDns({
    required bool preserveExistingAsFallback,
    required String targetForwarder,
  }) async {
    final router = _currentRouter;
    final sysauth = _authServiceOverride?.sysauth ?? _sysauth;

    if (router == null || sysauth == null) {
      return const AdGuardDnsConfigResult(
        status: AdGuardDnsConfigStatus.failed,
        message: 'No authenticated router session available.',
      );
    }

    // Reviewer Mode Guard: Zero real writes, ubus, or network calls
    if (_isReviewerMode) {
      state = state.copyWith(isMutatingDns: false, clearDnsActionError: true);
      return AdGuardDnsConfigResult(
        status: AdGuardDnsConfigStatus.success,
        message: 'Reviewer Mode: router DNS forwarding simulated successfully.',
        appliedServers: preserveExistingAsFallback
            ? [targetForwarder, '1.1.1.1']
            : [targetForwarder],
      );
    }

    state = state.copyWith(isMutatingDns: true, clearDnsActionError: true);

    try {
      final result = await _operationQueue.runLocked(
        routerId: router.id,
        domain: 'dns',
        action: () async {
          final actualApi = _luciApiService;
          if (actualApi == null) {
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'LuCI API service unavailable.',
            );
          }

          // 1. Snapshot and locate dnsmasq section
          dynamic getRes;
          try {
            getRes = await actualApi.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'uci',
              method: 'get',
              params: {'config': 'dhcp'},
            );
          } catch (e) {
            return AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'Failed to read current DHCP/dnsmasq configuration: $e',
            );
          }

          final uciValues = extractUciValues(getRes);
          if (uciValues == null) {
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'Failed to parse DHCP configuration from router.',
            );
          }

          String dnsmasqSection = '@dnsmasq[0]';
          final originalServers = <String>[];
          for (final entry in uciValues.entries) {
            if (entry.value is Map && entry.value['.type'] == 'dnsmasq') {
              dnsmasqSection = entry.key;
              final rawServer = entry.value['server'];
              if (rawServer is List) {
                for (final s in rawServer) {
                  if (s != null) {
                    final str = s.toString().trim();
                    if (str.isNotEmpty) originalServers.add(str);
                  }
                }
              } else if (rawServer is String) {
                final s = rawServer.trim();
                if (s.isNotEmpty) originalServers.add(s);
              }
              break;
            }
          }

          // 2. Compute new server list
          // Parse target forwarder to identify AdGuard host and port
          final targetParsed = parseDnsmasqServerRule(targetForwarder);
          final targetHostNorm = (targetParsed.targetHost ?? '').toLowerCase();
          final targetPortNorm = targetParsed.targetPort;

          bool targetsAdGuard(String rule) {
            final trimmed = rule.trim();
            if (trimmed == targetForwarder) return true;
            final p = parseDnsmasqServerRule(trimmed);
            if (p.isLocalOnly || p.targetHost == null) return false;
            final h = p.targetHost!.toLowerCase();
            final isSameHost = h == targetHostNorm ||
                (targetHostNorm == '127.0.0.1' && (h == 'localhost' || h == '127.0.0.1' || h == '::1')) ||
                (targetHostNorm == 'localhost' && (h == '127.0.0.1' || h == '::1')) ||
                (normalizeHost(h) == normalizeHost(targetHostNorm));
            return isSameHost && p.targetPort == targetPortNorm;
          }

          // Preserve valid independent domain and reverse-DNS forwarders while stripping rules targeting AdGuard
          final List<String> conditionalRules = originalServers
              .where((s) => s.startsWith('/') && !targetsAdGuard(s))
              .toList();

          final List<String> newServers = preserveExistingAsFallback
              ? [targetForwarder, ...originalServers.where((s) => !targetsAdGuard(s))]
              : [targetForwarder, ...conditionalRules];

          // 3. Stage changes with uci.set (passes staged uncommitted delta to uciApply)
          try {
            final setRes = await actualApi.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'uci',
              method: 'set',
              params: {
                'config': 'dhcp',
                'section': dnsmasqSection,
                'values': {'server': newServers},
              },
            );

            if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
              return const AdGuardDnsConfigResult(
                status: AdGuardDnsConfigStatus.failed,
                message: 'Failed to stage dnsmasq forwarder configuration in UCI.',
              );
            }
          } catch (e) {
            return AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'Exception while staging UCI configuration: $e',
            );
          }

          // 4. Arm server-side rollback watchdog via uciApply(rollback: true, timeout: 30)
          bool applied = false;
          try {
            applied = await actualApi.uciApply(
              router.ipAddress,
              sysauth,
              router.useHttps,
              rollback: true,
              timeout: 30,
            );
          } catch (e) {
            Logger.warning('uciApply exception: $e');
          }

          if (!applied) {
            try {
              await actualApi.uciRevert(
                router.ipAddress,
                sysauth,
                router.useHttps,
                config: 'dhcp',
              );
            } catch (_) {}
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'Router rejected configuration apply. Staged changes reverted.',
              wasRolledBack: true,
            );
          }

          // 5. Post-apply verification: authenticated router reachability & readback
          bool reachabilityOk = false;
          try {
            final pingRes = await actualApi.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'system',
              method: 'board',
            );
            if (pingRes is List && pingRes.isNotEmpty && (pingRes[0] == 0 || pingRes[0] == 5)) {
              reachabilityOk = true;
            } else if (pingRes is Map) {
              reachabilityOk = true;
            }
          } catch (e) {
            Logger.warning('Post-apply reachability check failed: $e');
          }

          if (!reachabilityOk) {
            try {
              await actualApi.uciRevert(
                router.ipAddress,
                sysauth,
                router.useHttps,
                config: 'dhcp',
              );
            } catch (_) {}
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.rolledBack,
              message: 'Router reachability check failed after apply. 30-second rollback watchdog triggered.',
              wasRolledBack: true,
            );
          }

          // Read back config to verify target forwarder is present
          bool configVerified = false;
          try {
            final readRes = await actualApi.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'uci',
              method: 'get',
              params: {'config': 'dhcp', 'section': dnsmasqSection},
            );
            final readValues = extractUciValues(readRes);
            if (readValues != null) {
              final rawServer = readValues['values'] is Map
                  ? (readValues['values'] as Map)['server']
                  : readValues['server'];
              if (rawServer is List && rawServer.map((e) => e.toString().trim()).contains(targetForwarder)) {
                configVerified = true;
              } else if (rawServer is String && rawServer.trim() == targetForwarder) {
                configVerified = true;
              }
            }
          } catch (e) {
            Logger.warning('Post-apply configuration readback failed: $e');
          }

          if (!configVerified) {
            try {
              await actualApi.uciRevert(
                router.ipAddress,
                sysauth,
                router.useHttps,
                config: 'dhcp',
              );
            } catch (_) {}
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'Configuration verification readback failed. Changes reverted.',
              wasRolledBack: true,
            );
          }

          // 6. Confirm transaction
          bool confirmed = false;
          try {
            confirmed = await actualApi.uciConfirm(
              router.ipAddress,
              sysauth,
              router.useHttps,
            );
          } catch (e) {
            Logger.warning('uciConfirm exception: $e');
          }

          if (!confirmed) {
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.ambiguous,
              message: 'Configuration was applied and verified, but confirmation returned an ambiguous response. Please verify router status.',
            );
          }

          // 7. Success: clear cache and refresh topology
          _cachedUciTopology = null;
          unawaited(refresh(forceTopologyProbe: true));

          return AdGuardDnsConfigResult(
            status: AdGuardDnsConfigStatus.success,
            message: 'Router DNS forwarding configured successfully.',
            appliedServers: newServers,
          );
        },
      );

      state = state.copyWith(
        isMutatingDns: false,
        dnsActionError: result.isSuccess ? null : result.message,
        clearDnsActionError: result.isSuccess,
      );
      return result;
    } catch (e) {
      state = state.copyWith(
        isMutatingDns: false,
        dnsActionError: 'Exception during DNS configuration: $e',
      );
      return AdGuardDnsConfigResult(
        status: AdGuardDnsConfigStatus.failed,
        message: 'Exception during DNS configuration: $e',
      );
    }
  }

  /// Preflights removal of router dnsmasq forwarding to AdGuard.
  ///
  /// Inspects current dnsmasq `server` configuration, resolves the exact forwarder
  /// rule targeting this AdGuard instance, and detects missing or ambiguous targets.
  Future<AdGuardDnsRevertPreflightResult> preflightRevertRouterDns() async {
    final router = _currentRouter;
    final sysauth = _authServiceOverride?.sysauth ?? _sysauth;

    if (router == null || sysauth == null) {
      return const AdGuardDnsRevertPreflightResult(
        canProceed: false,
        failureReason: 'No authenticated router session available.',
      );
    }

    final profile = state.activeProfile;
    final dnsPort = (state.status?.dnsPort != null && state.status!.dnsPort > 0)
        ? state.status!.dnsPort
        : 53;
    final isExt = profile?.type.isExternal ?? state.isExternal;
    final host = isExt ? (profile?.host.trim() ?? '') : '127.0.0.1';
    final targetForwarder = (dnsPort == 53) ? host : '$host#$dnsPort';

    if (_isReviewerMode) {
      return AdGuardDnsRevertPreflightResult(
        canProceed: true,
        targetRule: targetForwarder,
        currentServers: [targetForwarder, '1.1.1.1'],
        remainingServers: ['1.1.1.1'],
      );
    }

    // Read current dnsmasq servers directly from LuCI or cache
    List<String> currentServers = [];
    final actualApi = _luciApiService;
    if (actualApi != null) {
      try {
        final getRes = await actualApi.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'uci',
          method: 'get',
          params: {'config': 'dhcp'},
        );
        final uciValues = extractUciValues(getRes);
        if (uciValues != null) {
          for (final entry in uciValues.entries) {
            if (entry.value is Map && entry.value['.type'] == 'dnsmasq') {
              final rawServer = entry.value['server'];
              if (rawServer is List) {
                for (final s in rawServer) {
                  if (s != null) {
                    final str = s.toString().trim();
                    if (str.isNotEmpty) currentServers.add(str);
                  }
                }
              } else if (rawServer is String) {
                final s = rawServer.trim();
                if (s.isNotEmpty) currentServers.add(s);
              }
              break;
            }
          }
        }
      } catch (e) {
        Logger.warning('preflightRevertRouterDns failed to fetch live UCI: $e');
      }
    }

    if (currentServers.isEmpty && _cachedUciTopology?.dnsmasqServers != null) {
      currentServers = List<String>.from(_cachedUciTopology!.dnsmasqServers);
    }

    // Match helper for AdGuard rules
    final targetParsed = parseDnsmasqServerRule(targetForwarder);
    final targetHostNorm = (targetParsed.targetHost ?? '').toLowerCase();
    final targetPortNorm = targetParsed.targetPort;

    bool targetsAdGuard(String rule) {
      final trimmed = rule.trim();
      if (trimmed == targetForwarder) return true;
      final p = parseDnsmasqServerRule(trimmed);
      if (p.isLocalOnly || p.targetHost == null) return false;
      final h = p.targetHost!.toLowerCase();
      final isSameHost = h == targetHostNorm ||
          (targetHostNorm == '127.0.0.1' &&
              (h == 'localhost' || h == '127.0.0.1' || h == '::1')) ||
          (targetHostNorm == 'localhost' &&
              (h == '127.0.0.1' || h == '::1')) ||
          (normalizeHost(h) == normalizeHost(targetHostNorm));
      return isSameHost && p.targetPort == targetPortNorm;
    }

    final matchingRules = currentServers.where(targetsAdGuard).toList();

    if (matchingRules.isEmpty) {
      return AdGuardDnsRevertPreflightResult(
        canProceed: false,
        currentServers: currentServers,
        isMissing: true,
        failureReason:
            'No active dnsmasq forwarder rule targeting this AdGuard Home instance was found.',
      );
    }

    if (matchingRules.length > 1) {
      return AdGuardDnsRevertPreflightResult(
        canProceed: false,
        currentServers: currentServers,
        isAmbiguous: true,
        failureReason:
            'Multiple ambiguous forwarding rules targeting AdGuard Home were found (${matchingRules.join(', ')}). Manual review in LuCI is required.',
      );
    }

    final matchedRule = matchingRules.first;
    final remainingServers =
        currentServers.where((s) => s != matchedRule).toList();
    final warnings = <String>[];
    if (remainingServers.isEmpty) {
      warnings.add(
        'Removing this rule will leave no upstream DNS servers configured in dnsmasq. '
        'The router will rely on ISP-provided DNS servers from the WAN interface.',
      );
    }

    return AdGuardDnsRevertPreflightResult(
      canProceed: true,
      targetRule: matchedRule,
      currentServers: currentServers,
      remainingServers: remainingServers,
      warnings: warnings,
    );
  }

  /// Removes router dnsmasq forwarding to AdGuard with atomic 30-second rollback watchdog.
  ///
  /// Revalidates that [targetForwarder] is present and unambiguous immediately before mutation.
  /// Preserves all unrelated DNS forwarders, conditional rules, DHCP, and firewall configurations.
  Future<AdGuardDnsConfigResult> revertRouterDns({
    required String targetForwarder,
  }) async {
    final router = _currentRouter;
    final sysauth = _authServiceOverride?.sysauth ?? _sysauth;

    if (router == null || sysauth == null) {
      state = state.copyWith(
        dnsActionError: 'No authenticated router session available.',
      );
      return const AdGuardDnsConfigResult(
        status: AdGuardDnsConfigStatus.failed,
        message: 'No authenticated router session available.',
      );
    }

    // Reviewer Mode Guard: Zero real writes, ubus, or network calls
    if (_isReviewerMode) {
      state = state.copyWith(isMutatingDns: false, clearDnsActionError: true);
      return const AdGuardDnsConfigResult(
        status: AdGuardDnsConfigStatus.success,
        message: 'Reviewer Mode: router DNS forwarding reverted successfully.',
        appliedServers: ['1.1.1.1'],
      );
    }

    state = state.copyWith(isMutatingDns: true, clearDnsActionError: true);

    try {
      final result = await _operationQueue.runLocked(
        routerId: router.id,
        domain: 'dns',
        action: () async {
          final actualApi = _luciApiService;
          if (actualApi == null) {
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'LuCI API service unavailable.',
            );
          }

          // 1. Snapshot and locate dnsmasq section
          dynamic getRes;
          try {
            getRes = await actualApi.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'uci',
              method: 'get',
              params: {'config': 'dhcp'},
            );
          } catch (e) {
            return AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'Failed to read current DHCP/dnsmasq configuration: $e',
            );
          }

          final uciValues = extractUciValues(getRes);
          if (uciValues == null) {
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'Failed to parse DHCP configuration from router.',
            );
          }

          String dnsmasqSection = '@dnsmasq[0]';
          final originalServers = <String>[];
          for (final entry in uciValues.entries) {
            if (entry.value is Map && entry.value['.type'] == 'dnsmasq') {
              dnsmasqSection = entry.key;
              final rawServer = entry.value['server'];
              if (rawServer is List) {
                for (final s in rawServer) {
                  if (s != null) {
                    final str = s.toString().trim();
                    if (str.isNotEmpty) originalServers.add(str);
                  }
                }
              } else if (rawServer is String) {
                final s = rawServer.trim();
                if (s.isNotEmpty) originalServers.add(s);
              }
              break;
            }
          }

          // 2. Pre-mutation Revalidation: Check target exists and is unambiguous
          final targetParsed = parseDnsmasqServerRule(targetForwarder);
          final targetHostNorm = (targetParsed.targetHost ?? '').toLowerCase();
          final targetPortNorm = targetParsed.targetPort;

          bool targetsAdGuard(String rule) {
            final trimmed = rule.trim();
            if (trimmed == targetForwarder) return true;
            final p = parseDnsmasqServerRule(trimmed);
            if (p.isLocalOnly || p.targetHost == null) return false;
            final h = p.targetHost!.toLowerCase();
            final isSameHost = h == targetHostNorm ||
                (targetHostNorm == '127.0.0.1' &&
                    (h == 'localhost' || h == '127.0.0.1' || h == '::1')) ||
                (targetHostNorm == 'localhost' &&
                    (h == '127.0.0.1' || h == '::1')) ||
                (normalizeHost(h) == normalizeHost(targetHostNorm));
            return isSameHost && p.targetPort == targetPortNorm;
          }

          final matchingRules = originalServers
              .where((s) => s.trim() == targetForwarder.trim() || targetsAdGuard(s))
              .toList();

          if (matchingRules.isEmpty) {
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message:
                  'Target forwarder rule is no longer present in router configuration. Revert aborted.',
            );
          }

          if (matchingRules.length > 1) {
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message:
                  'Configuration changed: multiple matching forwarder rules detected. Revert aborted.',
            );
          }

          final matchedRule = matchingRules.first;

          // 3. Compute remaining servers (preserve all other rules verbatim in order)
          final newServers =
              originalServers.where((s) => s != matchedRule).toList();

          // 4. Stage changes with uci.set
          try {
            final setRes = await actualApi.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'uci',
              method: 'set',
              params: {
                'config': 'dhcp',
                'section': dnsmasqSection,
                'values': {'server': newServers},
              },
            );

            if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
              return const AdGuardDnsConfigResult(
                status: AdGuardDnsConfigStatus.failed,
                message:
                    'Failed to stage updated forwarder configuration in UCI.',
              );
            }
          } catch (e) {
            return AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message: 'Exception while staging UCI configuration: $e',
            );
          }

          // 5. Arm server-side rollback watchdog via uciApply(rollback: true, timeout: 30)
          bool applied = false;
          try {
            applied = await actualApi.uciApply(
              router.ipAddress,
              sysauth,
              router.useHttps,
              rollback: true,
              timeout: 30,
            );
          } catch (e) {
            Logger.warning('uciApply exception during revert: $e');
          }

          if (!applied) {
            try {
              await actualApi.uciRevert(
                router.ipAddress,
                sysauth,
                router.useHttps,
                config: 'dhcp',
              );
            } catch (_) {}
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message:
                  'Router rejected configuration apply. Staged changes reverted.',
              wasRolledBack: true,
            );
          }

          // 6. Post-apply verification: authenticated router reachability & readback
          bool reachabilityOk = false;
          try {
            final pingRes = await actualApi.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'system',
              method: 'board',
            );
            if (pingRes is List &&
                pingRes.isNotEmpty &&
                (pingRes[0] == 0 || pingRes[0] == 5)) {
              reachabilityOk = true;
            } else if (pingRes is Map) {
              reachabilityOk = true;
            }
          } catch (e) {
            Logger.warning('Post-revert reachability check failed: $e');
          }

          if (!reachabilityOk) {
            try {
              await actualApi.uciRevert(
                router.ipAddress,
                sysauth,
                router.useHttps,
                config: 'dhcp',
              );
            } catch (_) {}
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.rolledBack,
              message:
                  'Router reachability check failed after apply. 30-second rollback watchdog triggered.',
              wasRolledBack: true,
            );
          }

          // Read back config to verify target forwarder is absent and remaining servers match
          bool configVerified = false;
          try {
            final readRes = await actualApi.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'uci',
              method: 'get',
              params: {'config': 'dhcp', 'section': dnsmasqSection},
            );
            final readValues = extractUciValues(readRes);
            if (readValues != null) {
              final rawServer = readValues['values'] is Map
                  ? (readValues['values'] as Map)['server']
                  : readValues['server'];
              final List<String> verifiedServers = [];
              if (rawServer is List) {
                for (final s in rawServer) {
                  if (s != null) {
                    final str = s.toString().trim();
                    if (str.isNotEmpty) verifiedServers.add(str);
                  }
                }
              } else if (rawServer is String) {
                final s = rawServer.trim();
                if (s.isNotEmpty) verifiedServers.add(s);
              }

              // Verify target forwarder is absent
              final targetStillPresent = verifiedServers
                  .any((s) => s == matchedRule || targetsAdGuard(s));
              // Verify all newServers are present in verifiedServers and length matches
              final allRemainingPresent = newServers
                      .every((s) => verifiedServers.contains(s)) &&
                  verifiedServers.length == newServers.length;

              if (!targetStillPresent &&
                  (newServers.isEmpty || allRemainingPresent)) {
                configVerified = true;
              }
            }
          } catch (e) {
            Logger.warning('Post-revert configuration readback failed: $e');
          }

          if (!configVerified) {
            try {
              await actualApi.uciRevert(
                router.ipAddress,
                sysauth,
                router.useHttps,
                config: 'dhcp',
              );
            } catch (_) {}
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.failed,
              message:
                  'Configuration verification readback failed. Removal reverted.',
              wasRolledBack: true,
            );
          }

          // 7. Confirm transaction
          bool confirmed = false;
          try {
            confirmed = await actualApi.uciConfirm(
              router.ipAddress,
              sysauth,
              router.useHttps,
            );
          } catch (e) {
            Logger.warning('uciConfirm exception during revert: $e');
          }

          if (!confirmed) {
            return const AdGuardDnsConfigResult(
              status: AdGuardDnsConfigStatus.ambiguous,
              message:
                  'Configuration was applied and verified, but confirmation returned an ambiguous response. Please verify router status.',
            );
          }

          // 8. Success: clear cache and refresh topology
          _cachedUciTopology = null;
          unawaited(refresh(forceTopologyProbe: true));

          return AdGuardDnsConfigResult(
            status: AdGuardDnsConfigStatus.success,
            message: 'Router DNS forwarding removed successfully.',
            appliedServers: newServers,
          );
        },
      );

      state = state.copyWith(
        isMutatingDns: false,
        dnsActionError: result.isSuccess ? null : result.message,
        clearDnsActionError: result.isSuccess,
      );
      return result;
    } catch (e) {
      state = state.copyWith(
        isMutatingDns: false,
        dnsActionError: 'Exception during DNS revert: $e',
      );
      return AdGuardDnsConfigResult(
        status: AdGuardDnsConfigStatus.failed,
        message: 'Exception during DNS revert: $e',
      );
    }
  }
}

/// Router-scoped autoDispose family provider for [AdGuardController].
final adguardControllerProvider = StateNotifierProvider.autoDispose.family<
    AdGuardController, AdGuardState, String>((ref, routerId) {
  return AdGuardController(ref, routerId);
});
