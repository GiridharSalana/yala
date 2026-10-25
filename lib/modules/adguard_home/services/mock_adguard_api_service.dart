// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:yala/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yala/services/secure_storage_service.dart';
import 'package:yala/utils/http_client_manager.dart';

/// In-memory mock implementation of [IAdGuardApiService] and [AdGuardApiService].
///
/// Invariants:
/// - Executes ZERO network calls (no Dio, no HTTP, no socket).
/// - Executes ZERO ubus calls.
/// - Executes ZERO SecureStorage writes or reads.
/// - Operates 100% in-memory with deterministic telemetry data.
/// - Reviewer / Demo mode safe.
class MockAdGuardApiService implements IAdGuardApiService, AdGuardApiService {
  @override
  final String routerId;

  // In-memory configuration flags
  bool requiresAuth;
  String expectedUsername;
  String expectedPassword;
  AdGuardProtectionState currentProtectionState;
  int currentPauseDurationMs;

  // Failure simulation flags for unit testing
  bool simulateNetworkFailure;
  bool simulateTimeout;
  bool simulateInvalidPayload;
  bool simulateMalformedJson;
  bool simulateHttpError;
  int simulatedHttpErrorCode;
  bool simulateRecentRejection;

  // Metric tracking to assert test isolation and verify zero external calls
  int statusCallCount = 0;
  int statsCallCount = 0;
  int filteringCallCount = 0;
  int protectionCallCount = 0;
  int recentRejectedRetryCount = 0;
  int setUserRulesCallCount = 0;
  int getClientsCallCount = 0;
  int addClientCallCount = 0;
  int updateClientCallCount = 0;
  int addFilterListCallCount = 0;
  int setFilterListCallCount = 0;
  int removeFilterListCallCount = 0;
  int refreshFilterListsCallCount = 0;

  List<String> mockUserRules = [
    '||tracker.example.com^',
    '||telemetry.sample.net^',
    '@@||allowed.workplace.com^',
  ];
  List<AdGuardClient> mockClients = [];

  List<AdGuardFilterList> mockFilterLists = [
    const AdGuardFilterList(
      id: 1,
      name: 'AdGuard DNS filter',
      url:
          'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt',
      rulesCount: 65000,
      enabled: true,
      lastUpdated: '2026-10-07T12:00:00Z',
      whitelist: false,
    ),
    const AdGuardFilterList(
      id: 2,
      name: 'AdAway Default Blocklist',
      url: 'https://adaway.org/hosts.txt',
      rulesCount: 12500,
      enabled: true,
      lastUpdated: '2026-10-06T08:00:00Z',
      whitelist: false,
    ),
  ];

  List<AdGuardFilterList> mockWhitelistFilters = [];

  AdGuardCredentials? _activeCredentials;
  bool _isAuthenticated = false;
  bool _isAuthRequired = false;

  MockAdGuardApiService({
    this.routerId = 'reviewer-mock-router',
    this.requiresAuth = false,
    this.expectedUsername = 'admin',
    this.expectedPassword = 'password',
    this.currentProtectionState = AdGuardProtectionState.enabled,
    this.currentPauseDurationMs = 0,
    this.simulateNetworkFailure = false,
    this.simulateTimeout = false,
    this.simulateInvalidPayload = false,
    this.simulateMalformedJson = false,
    this.simulateHttpError = false,
    this.simulatedHttpErrorCode = 500,
    this.simulateRecentRejection = false,
    this.customInstanceId,
  }) {
    if (!requiresAuth) {
      _isAuthenticated = true;
      _isAuthRequired = false;
    } else {
      _isAuthenticated = false;
      _isAuthRequired = true;
    }
  }

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  bool get isAuthRequired => _isAuthRequired;

  @override
  AdGuardCredentials? get activeCredentials => _activeCredentials;

  @override
  void setCredentials(AdGuardCredentials? credentials) {
    _activeCredentials = credentials;
    if (credentials != null) {
      if (credentials.username == expectedUsername &&
          credentials.password == expectedPassword) {
        _isAuthenticated = true;
        _isAuthRequired = false;
      } else {
        _isAuthenticated = false;
        _isAuthRequired = true;
      }
    }
  }

  // Properties required to conform to AdGuardApiService interface without external side-effects
  @override
  String get host => '127.0.0.1';

  @override
  int get port => 3000;

  @override
  bool get useHttps => false;

  @override
  String get hostWithPort => '127.0.0.1:3000';

  @override
  String get baseUrl => 'http://127.0.0.1:3000';

  @override
  HttpClientManager get httpClientManager => throw UnsupportedError(
    'MockAdGuardApiService never invokes HttpClientManager',
  );

  @override
  SecureStorageService? get secureStorageService => null;

  @override
  Dio? get dioOverride => null;

  @override
  String get storageCredsKey => 'agh_creds_$instanceId';

  final String? customInstanceId;

  @override
  String get instanceId => customInstanceId ?? routerId;

  @override
  bool get isCanonicalLocal =>
      instanceId == 'local_$routerId' || instanceId == routerId;

  @override
  Future<AdGuardConnectionStatus> testConnection({
    AdGuardCredentials? credentials,
  }) async {
    if (simulateNetworkFailure) return AdGuardConnectionStatus.apiUnreachable;
    if (simulateTimeout) return AdGuardConnectionStatus.apiUnreachable;
    if (simulateHttpError) {
      if (simulatedHttpErrorCode == 401) {
        return AdGuardConnectionStatus.authRequired;
      }
      return AdGuardConnectionStatus.invalidEndpoint;
    }
    if (simulateInvalidPayload || simulateMalformedJson) {
      return AdGuardConnectionStatus.invalidEndpoint;
    }
    if (requiresAuth) {
      final creds = credentials ?? _activeCredentials;
      if (creds == null ||
          creds.username != expectedUsername ||
          creds.password != expectedPassword) {
        return AdGuardConnectionStatus.authRequired;
      }
    }
    return AdGuardConnectionStatus.authenticated;
  }

  @override
  Future<AdGuardCredentials?> getStoredCredentials() async {
    // Pure in-memory: zero SecureStorage access
    return _activeCredentials;
  }

  @override
  Future<void> saveStoredCredentials(AdGuardCredentials creds) async {
    // Pure in-memory: zero SecureStorage writes
    _activeCredentials = creds;
  }

  @override
  Future<void> clearStoredCredentials() async {
    // Pure in-memory: zero SecureStorage writes
    _activeCredentials = null;
  }

  @override
  Future<AdGuardApiResult<AdGuardStatus>> getStatus({
    bool forceProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  }) async {
    statusCallCount++;

    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (simulateMalformedJson) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.malformedJson,
          message: 'Simulated malformed JSON response',
        ),
      );
    }
    if (simulateInvalidPayload) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.invalidPayload,
          statusCode: 200,
          message: 'Simulated non-AdGuard HTTP 200 payload',
        ),
      );
    }

    if (requiresAuth) {
      if (forceProbe) {
        // Unauthenticated probe encounters 401
        _isAuthenticated = false;
        _isAuthRequired = true;
      }

      if (!_isAuthenticated) {
        if (allowFallbackToRouterCredentials && routerCredentials != null) {
          if (routerCredentials.username == expectedUsername &&
              routerCredentials.password == expectedPassword) {
            _activeCredentials = routerCredentials;
            _isAuthenticated = true;
            _isAuthRequired = false;
          } else {
            return AdGuardApiResult.authRequired(
              'Router credentials rejected by AdGuard Home',
            );
          }
        } else if (_activeCredentials != null) {
          if (_activeCredentials!.username == expectedUsername &&
              _activeCredentials!.password == expectedPassword) {
            _isAuthenticated = true;
            _isAuthRequired = false;
          } else {
            _activeCredentials = null;
            return AdGuardApiResult.authRequired(
              'Stored credentials rejected by AdGuard Home',
            );
          }
        } else {
          return AdGuardApiResult.authRequired(
            'AdGuard Home authentication required',
          );
        }
      }
    }

    return AdGuardApiResult.success(
      AdGuardStatus(
        version: 'v0.107.52',
        running: true,
        protectionState: currentProtectionState,
        pauseDurationMs: currentPauseDurationMs,
        dnsAddresses: const ['192.168.1.1', '127.0.0.1'],
        dnsPort: 53,
        httpPort: 3000,
        startTimeMs: 1700000000000,
      ),
    );
  }

  @override
  Future<AdGuardApiResult<AdGuardStats>> getStats({Duration? recent}) async {
    statsCallCount++;

    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for stats',
      );
    }

    if (simulateRecentRejection && recent != null) {
      // Simulates older server returning 400 on `recent`, followed by retry without parameter
      recentRejectedRetryCount++;
    }

    const int totalQueries = 34812;
    const int blockedQueries = 5219;
    final double blockRate = AdGuardStats.calculateBlockRate(
      totalQueries,
      blockedQueries,
    );

    return AdGuardApiResult.success(
      AdGuardStats(
        numDnsQueries: totalQueries,
        numBlockedFiltering: blockedQueries,
        numReplacedSafebrowsing: 12,
        numReplacedSafesearch: 0,
        numReplacedParental: 0,
        avgProcessingTime: 0.015,
        topQueriedDomains: const [
          AdGuardTopItem(identifier: 'gateway.icloud.com', count: 4892),
          AdGuardTopItem(identifier: 'google.com', count: 3210),
          AdGuardTopItem(
            identifier: 'connectivitycheck.android.com',
            count: 2154,
          ),
        ],
        topBlockedDomains: const [
          AdGuardTopItem(identifier: 'ads.google.com', count: 1840),
          AdGuardTopItem(identifier: 'analytics.facebook.com', count: 1210),
          AdGuardTopItem(identifier: 'telemetry.microsoft.com', count: 852),
        ],
        topClients: const [
          AdGuardTopItem(identifier: '192.168.1.100', count: 12450),
          AdGuardTopItem(identifier: '192.168.1.105', count: 9820),
          AdGuardTopItem(identifier: '192.168.1.142', count: 4210),
        ],
        dnsQueriesTrend: List.generate(24, (i) => 1000 + (i * 50)),
        blockedFilteringTrend: List.generate(24, (i) => 150 + (i * 10)),
        timeUnits: 'hours',
        blockRatePercentage: blockRate,
      ),
    );
  }

  @override
  Future<AdGuardApiResult<AdGuardFilteringStatus>> getFilteringStatus() async {
    filteringCallCount++;

    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for filtering',
      );
    }

    final totalRules =
        mockFilterLists
            .where((f) => f.enabled)
            .fold<int>(0, (sum, f) => sum + f.rulesCount) +
        mockWhitelistFilters
            .where((f) => f.enabled)
            .fold<int>(0, (sum, f) => sum + f.rulesCount) +
        mockUserRules.length;

    return AdGuardApiResult.success(
      AdGuardFilteringStatus(
        enabled: true,
        filterLists: List.unmodifiable(mockFilterLists),
        whitelistFilters: List.unmodifiable(mockWhitelistFilters),
        userRules: List.unmodifiable(mockUserRules),
        totalRulesCount: totalRules,
      ),
    );
  }

  @override
  Future<AdGuardApiResult<bool>> setProtection({
    required bool enabled,
    Duration? duration,
  }) async {
    protectionCallCount++;

    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for protection mutation',
      );
    }

    if (enabled) {
      currentProtectionState = AdGuardProtectionState.enabled;
      currentPauseDurationMs = 0;
    } else {
      final int ms = duration?.inMilliseconds ?? 0;
      if (ms > 0) {
        currentProtectionState = AdGuardProtectionState.paused;
        currentPauseDurationMs = ms;
      } else {
        currentProtectionState = AdGuardProtectionState.disabled;
        currentPauseDurationMs = 0;
      }
    }

    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> setProtectionState(
    AdGuardProtectionState state, {
    Duration? pauseDuration,
  }) {
    switch (state) {
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

  @override
  Future<AdGuardApiResult<bool>> setUserRules(List<String> rules) async {
    setUserRulesCallCount++;
    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for setUserRules',
      );
    }
    mockUserRules = List.from(rules);
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<List<AdGuardClient>>> getClients() async {
    getClientsCallCount++;
    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for getClients',
      );
    }
    return AdGuardApiResult.success(List.unmodifiable(mockClients));
  }

  @override
  Future<AdGuardApiResult<bool>> addClient(AdGuardClient client) async {
    addClientCallCount++;
    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for addClient',
      );
    }
    mockClients.removeWhere((c) => c.name == client.name);
    mockClients.add(client);
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> updateClient(
    String oldName,
    AdGuardClient client,
  ) async {
    updateClientCallCount++;
    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for updateClient',
      );
    }
    mockClients.removeWhere((c) => c.name == oldName);
    mockClients.add(client);
    return AdGuardApiResult.success(true);
  }

  List<String> mockUpstreamDns = const ['1.1.1.1', '8.8.8.8'];

  @override
  Future<AdGuardApiResult<List<String>>> getUpstreamDns() async {
    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for getUpstreamDns',
      );
    }
    return AdGuardApiResult.success(List.unmodifiable(mockUpstreamDns));
  }

  @override
  Future<AdGuardApiResult<bool>> addFilterList({
    required String name,
    required String url,
    required bool whitelist,
  }) async {
    addFilterListCallCount++;

    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for addFilterList',
      );
    }

    final targetList = whitelist ? mockWhitelistFilters : mockFilterLists;
    final newId = (mockFilterLists.length + mockWhitelistFilters.length) + 1;
    targetList.add(
      AdGuardFilterList(
        id: newId,
        name: name,
        url: url,
        rulesCount: 100,
        enabled: true,
        lastUpdated: DateTime.now().toIso8601String(),
        whitelist: whitelist,
      ),
    );

    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> setFilterList({
    required String url,
    required String name,
    required String newUrl,
    required bool enabled,
    required bool whitelist,
  }) async {
    setFilterListCallCount++;

    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for setFilterList',
      );
    }

    final targetList = whitelist ? mockWhitelistFilters : mockFilterLists;
    final index = targetList.indexWhere((f) => f.url == url || f.name == url);
    if (index >= 0) {
      final existing = targetList[index];
      targetList[index] = existing.copyWith(
        name: name,
        url: newUrl,
        enabled: enabled,
        whitelist: whitelist,
      );
    }

    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> removeFilterList({
    required String url,
    required bool whitelist,
  }) async {
    removeFilterListCallCount++;

    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for removeFilterList',
      );
    }

    final targetList = whitelist ? mockWhitelistFilters : mockFilterLists;
    targetList.removeWhere((f) => f.url == url || f.name == url);

    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> refreshFilterLists({bool? whitelist}) async {
    refreshFilterListsCallCount++;

    if (simulateNetworkFailure) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Simulated network connection failure',
        ),
      );
    }
    if (simulateTimeout) {
      return AdGuardApiResult.failure(
        const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Simulated request timeout after 5s',
        ),
      );
    }
    if (simulateHttpError) {
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: simulatedHttpErrorCode,
          message: 'Simulated HTTP $simulatedHttpErrorCode',
        ),
      );
    }
    if (requiresAuth && !_isAuthenticated) {
      return AdGuardApiResult.authRequired(
        'AdGuard Home authentication required for refreshFilterLists',
      );
    }

    final now = DateTime.now().toIso8601String();
    if (whitelist == null || !whitelist) {
      for (var i = 0; i < mockFilterLists.length; i++) {
        mockFilterLists[i] = mockFilterLists[i].copyWith(lastUpdated: now);
      }
    }
    if (whitelist == null || whitelist) {
      for (var i = 0; i < mockWhitelistFilters.length; i++) {
        mockWhitelistFilters[i] = mockWhitelistFilters[i].copyWith(
          lastUpdated: now,
        );
      }
    }

    return AdGuardApiResult.success(true);
  }
}
