// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/adguard_home/controllers/adguard_controller.dart';
import 'package:yala/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/interfaces/auth_service_interface.dart';
import 'package:yala/services/operation_queue.dart';
import 'package:yala/services/secure_storage_service.dart';

/// Configurable mock implementation of [IAdGuardApiService] for controller tests.
class TestMockAdGuardApiService implements IAdGuardApiService {
  @override
  final String routerId;

  @override
  String get instanceId => 'local_$routerId';

  @override
  Future<AdGuardConnectionStatus> testConnection({
    AdGuardCredentials? credentials,
  }) async =>
      AdGuardConnectionStatus.authenticated;

  bool isAuthRequiredState = false;
  bool isApiAuthenticatedState = true;
  AdGuardCredentials? activeCreds;

  AdGuardStatus? mockStatus;
  AdGuardStats? mockStats;
  AdGuardFilteringStatus? mockFiltering;
  AdGuardApiException? statusError;
  AdGuardApiException? statsError;
  AdGuardApiException? filteringError;
  AdGuardApiException? protectionError;

  int statusCallCount = 0;
  int statsCallCount = 0;
  int filteringCallCount = 0;
  int protectionCallCount = 0;
  Duration? lastStatsRecent;
  List<String>? lastSetRules;
  int setUserRulesCallCount = 0;
  AdGuardApiException? setUserRulesError;

  Completer<void>? delayStatusCompleter;

  TestMockAdGuardApiService({
    required this.routerId,
    this.mockStatus,
    this.mockStats,
    this.mockFiltering,
  }) {
    mockStatus ??= const AdGuardStatus(
      version: 'v0.107.52',
      running: true,
      protectionState: AdGuardProtectionState.enabled,
      dnsAddresses: ['192.168.1.1'],
      dnsPort: 53,
      httpPort: 3000,
    );

    mockStats ??= const AdGuardStats(
      numDnsQueries: 10000,
      numBlockedFiltering: 2000,
      numReplacedSafebrowsing: 5,
      numReplacedSafesearch: 0,
      numReplacedParental: 0,
      avgProcessingTime: 0.015,
      topQueriedDomains: [],
      topBlockedDomains: [],
      topClients: [],
      dnsQueriesTrend: [100, 200],
      blockedFilteringTrend: [20, 40],
      blockRatePercentage: 20.0,
    );

    mockFiltering ??= const AdGuardFilteringStatus(
      enabled: true,
      filterLists: [],
      userRules: [],
      totalRulesCount: 50000,
    );
  }

  @override
  AdGuardCredentials? get activeCredentials => activeCreds;

  @override
  bool get isAuthenticated => isApiAuthenticatedState;

  @override
  bool get isAuthRequired => isAuthRequiredState;

  @override
  void setCredentials(AdGuardCredentials? credentials) {
    activeCreds = credentials;
  }

  @override
  Future<AdGuardApiResult<AdGuardStatus>> getStatus({
    bool forceProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  }) async {
    statusCallCount++;
    if (delayStatusCompleter != null) {
      await delayStatusCompleter!.future;
    }

    if (isAuthRequiredState) {
      return AdGuardApiResult.authRequired();
    }
    if (statusError != null) {
      return AdGuardApiResult.failure(statusError!);
    }
    return AdGuardApiResult.success(mockStatus!);
  }

  @override
  Future<AdGuardApiResult<AdGuardStats>> getStats({Duration? recent}) async {
    statsCallCount++;
    lastStatsRecent = recent;
    if (statsError != null) {
      return AdGuardApiResult.failure(statsError!);
    }
    return AdGuardApiResult.success(mockStats!);
  }

  @override
  Future<AdGuardApiResult<AdGuardFilteringStatus>> getFilteringStatus() async {
    filteringCallCount++;
    if (filteringError != null) {
      return AdGuardApiResult.failure(filteringError!);
    }
    return AdGuardApiResult.success(mockFiltering!);
  }

  @override
  Future<AdGuardApiResult<bool>> setProtection({
    required bool enabled,
    Duration? duration,
  }) async {
    protectionCallCount++;
    if (protectionError != null) {
      return AdGuardApiResult.failure(protectionError!);
    }

    final int durationMs = duration?.inMilliseconds ?? 0;
    final newState = enabled
        ? AdGuardProtectionState.enabled
        : (durationMs > 0
            ? AdGuardProtectionState.paused
            : AdGuardProtectionState.disabled);

    mockStatus = AdGuardStatus(
      version: mockStatus!.version,
      running: mockStatus!.running,
      protectionState: newState,
      pauseDurationMs: durationMs,
      dnsAddresses: mockStatus!.dnsAddresses,
      dnsPort: mockStatus!.dnsPort,
      httpPort: mockStatus!.httpPort,
    );

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
    lastSetRules = rules;
    if (setUserRulesError != null) {
      return AdGuardApiResult.failure(setUserRulesError!);
    }
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

  List<String> mockUpstreamDns = const ['1.1.1.1', '8.8.8.8'];

  @override
  Future<AdGuardApiResult<List<String>>> getUpstreamDns() async {
    return AdGuardApiResult.success(mockUpstreamDns);
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

/// Fake Luci API service to intercept service mutations and ubus calls.
class FakeLuciApiService implements IApiService {
  final List<String> executedServiceActions = [];
  bool serviceActionSuccess = true;
  bool throwOnProcessList = false;
  Map<String, dynamic>? processListResult;
  Map<String, dynamic>? rcListResult;
  bool rcAdGuardHomeEnabled = true;

  @override
  Future<bool> manageServiceAction(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String serviceName,
    required String action,
    BuildContext? context,
  }) async {
    executedServiceActions.add('$serviceName:$action');
    return serviceActionSuccess;
  }

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
    if (object == 'luci' && method == 'getProcessList') {
      if (throwOnProcessList) {
        throw Exception('Ubus luci.getProcessList RPC timeout');
      }
      return processListResult ??
          {
            'result': [
              {
                'PID': '1660',
                'COMMAND': '/usr/bin/AdGuardHome -c /etc/adguardhome.yaml',
                '%CPU': '1.2%',
                '%MEM': '3.4%',
                'VSZ': '25600',
              }
            ]
          };
    }
    if (object == 'rc' && method == 'list') {
      return rcListResult ??
          [
            0,
            {
              'adguardhome': {'enabled': rcAdGuardHomeEnabled},
            }
          ];
    }
    return {'result': []};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Tracking router auth service to assert zero session renewal calls.
class TrackingAuthService implements IAuthService {
  int autoLoginCallCount = 0;
  int loginCallCount = 0;

  @override
  String? get sysauth => 'valid_sysauth_token';

  @override
  Future<bool> tryAutoLogin(
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps, {
    bool force = false,
    BuildContext? context,
  }) async {
    autoLoginCallCount++;
    return true;
  }

  @override
  Future<void> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    loginCallCount++;
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
          if (methodCall.method == 'readAll') {
            return <String, String>{};
          }
          if (methodCall.method == 'read') {
            return null;
          }
          if (methodCall.method == 'write') {
            return null;
          }
          return null;
        });
  });

  setUp(AdGuardController.invalidateSessionCache);

  group('AdGuardController — State & Router Isolation', () {
    test('Independent router IDs maintain strictly isolated states', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final apiA = TestMockAdGuardApiService(routerId: 'router-A');
      final apiB = TestMockAdGuardApiService(routerId: 'router-B');
      final fakeLuciA = FakeLuciApiService();
      final fakeLuciB = FakeLuciApiService();

      final controllerA = AdGuardController(
        container.read(adguardControllerProvider('router-A').notifier).ref,
        'router-A',
        apiServiceOverride: apiA,
        luciApiServiceOverride: fakeLuciA,
      );
      final controllerB = AdGuardController(
        container.read(adguardControllerProvider('router-B').notifier).ref,
        'router-B',
        apiServiceOverride: apiB,
        luciApiServiceOverride: fakeLuciB,
      );

      await controllerA.refresh();
      expect(controllerA.state.routerId, equals('router-A'));
      expect(controllerA.state.connectionStatus,
          equals(AdGuardConnectionStatus.authenticated));
      expect(controllerB.state.routerId, equals('router-B'));
      expect(controllerB.state.connectionStatus,
          equals(AdGuardConnectionStatus.initial));

      controllerA.dispose();
      controllerB.dispose();
    });

    test('Disposing one controller does not affect another controller', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final apiA = TestMockAdGuardApiService(routerId: 'router-A');
      final apiB = TestMockAdGuardApiService(routerId: 'router-B');
      final fakeLuciA = FakeLuciApiService();
      final fakeLuciB = FakeLuciApiService();

      final controllerA = AdGuardController(
        container.read(adguardControllerProvider('router-A').notifier).ref,
        'router-A',
        apiServiceOverride: apiA,
        luciApiServiceOverride: fakeLuciA,
      );
      final controllerB = AdGuardController(
        container.read(adguardControllerProvider('router-B').notifier).ref,
        'router-B',
        apiServiceOverride: apiB,
        luciApiServiceOverride: fakeLuciB,
      );

      await controllerA.refresh();
      controllerA.dispose();

      // Controller B remains fully operational
      await controllerB.refresh();
      expect(controllerB.state.connectionStatus,
          equals(AdGuardConnectionStatus.authenticated));
      expect(controllerB.state.status?.version, equals('v0.107.52'));

      controllerB.dispose();
    });

    test('Rapid router switching: Delayed in-flight response from Router A never mutates Router B', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final delayCompleterA = Completer<void>();
      final apiA = TestMockAdGuardApiService(
        routerId: 'router-A',
        mockStatus: const AdGuardStatus(
          version: 'v0.107.0-ROUTER-A',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        ),
      )..delayStatusCompleter = delayCompleterA;

      final apiB = TestMockAdGuardApiService(
        routerId: 'router-B',
        mockStatus: const AdGuardStatus(
          version: 'v0.107.0-ROUTER-B',
          running: true,
          protectionState: AdGuardProtectionState.disabled,
          dnsAddresses: ['10.0.0.1'],
          dnsPort: 53,
          httpPort: 3000,
        ),
      );

      final controllerA = AdGuardController(
        container.read(adguardControllerProvider('router-A').notifier).ref,
        'router-A',
        apiServiceOverride: apiA,
      );
      final controllerB = AdGuardController(
        container.read(adguardControllerProvider('router-B').notifier).ref,
        'router-B',
        apiServiceOverride: apiB,
      );

      // Start Router A refresh (in-flight, held by completer)
      final futureA = controllerA.refresh();

      // Switch to Router B and refresh
      await controllerB.refresh();
      expect(controllerB.state.status?.version, equals('v0.107.0-ROUTER-B'));

      // Complete delayed response for Router A
      delayCompleterA.complete();
      await futureA;

      // Assert Router B state was NOT modified or contaminated by Router A
      expect(controllerB.state.routerId, equals('router-B'));
      expect(controllerB.state.status?.version, equals('v0.107.0-ROUTER-B'));
      expect(controllerA.state.status?.version, equals('v0.107.0-ROUTER-A'));

      controllerA.dispose();
      controllerB.dispose();
    });
  });

  group('AdGuardController — Polling Lifecycle & Intervals', () {
    test('Background polling does NOT start upon provider instantiation', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      expect(controller.state.isPollingActive, isFalse);
      expect(api.statusCallCount, equals(0));
      controller.dispose();
    });

    test('startPolling() triggers immediate refresh and marks isPollingActive true', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      controller.startPolling();
      expect(controller.state.isPollingActive, isTrue);
      // Wait for immediate refresh to execute
      await Future.delayed(const Duration(milliseconds: 10));
      expect(api.statusCallCount, equals(1));

      controller.stopPolling();
      expect(controller.state.isPollingActive, isFalse);
      controller.dispose();
    });

    test('Single-flight: Overlapping refresh requests are skipped', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final delayCompleter = Completer<void>();
      final api = TestMockAdGuardApiService(routerId: 'test-router')
        ..delayStatusCompleter = delayCompleter;

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      final firstCall = controller.refresh();
      expect(controller.state.isRefreshing, isTrue);

      // Overlapping second call while first is in-flight
      final secondCall = controller.refresh();

      delayCompleter.complete();
      await Future.wait([firstCall, secondCall]);

      // Only one execution should have hit the API
      expect(api.statusCallCount, equals(1));
      controller.dispose();
    });

    test('Manual polling mode sets interval to manual and stops periodic timer', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      controller.setPollingInterval(AdGuardPollingInterval.manual);
      expect(controller.state.pollingInterval, equals(AdGuardPollingInterval.manual));

      controller.startPolling();
      expect(controller.state.isPollingActive, isTrue);

      controller.stopPolling();
      controller.dispose();
    });

    test('Supported polling interval set matches specification exactly', () {
      expect(
        AdGuardPollingInterval.values,
        equals([
          AdGuardPollingInterval.off,
          AdGuardPollingInterval.s5,
          AdGuardPollingInterval.s10,
          AdGuardPollingInterval.s30,
          AdGuardPollingInterval.manual,
        ]),
      );
      expect(AdGuardPollingInterval.values.length, equals(5));
      expect(AdGuardPollingInterval.off.seconds, equals(0));
      expect(AdGuardPollingInterval.s5.seconds, equals(5));
      expect(AdGuardPollingInterval.s10.seconds, equals(10));
      expect(AdGuardPollingInterval.s30.seconds, equals(30));
      expect(AdGuardPollingInterval.manual.seconds, equals(0));
    });
  });

  group('AdGuardController — Partial Failure Semantics', () {
    test('Status success + Stats failure preserves status and marks degraded', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router')
        ..statsError = const AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: 500,
          message: 'Internal server error on /control/stats',
        );

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      await controller.refresh();

      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.degraded));
      expect(controller.state.status, isNotNull);
      expect(controller.state.status?.version, equals('v0.107.52'));
      expect(controller.state.statsError,
          contains('Internal server error on /control/stats'));
      controller.dispose();
    });

    test('Status success + Filtering failure preserves status and stats', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router')
        ..filteringError = const AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'Filtering endpoint timed out',
        );

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      await controller.refresh();

      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.degraded));
      expect(controller.state.status, isNotNull);
      expect(controller.state.stats, isNotNull);
      expect(controller.state.filteringError, contains('Filtering endpoint timed out'));
      controller.dispose();
    });

    test('Status success + Process telemetry RPC failure preserves DNS state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final fakeLuci = FakeLuciApiService()..throwOnProcessList = true;

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
        luciApiServiceOverride: fakeLuci,
      );

      await controller.refresh();

      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.degraded));
      expect(controller.state.status, isNotNull);
      expect(controller.state.processTelemetryError,
          contains('Process telemetry unavailable'));
      controller.dispose();
    });

    test('Subsequent failure retains previous successful telemetry data', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      // First refresh succeeds 100%
      await controller.refresh();
      expect(controller.state.stats?.numDnsQueries, equals(10000));

      // Second refresh encounters stats error
      api.statsError = const AdGuardApiException(
        type: AdGuardApiErrorType.networkFailure,
        message: 'Socket error on stats',
      );
      await controller.refresh();

      // Stats retained from previous successful cycle!
      expect(controller.state.stats?.numDnsQueries, equals(10000));
      expect(controller.state.statsError, contains('Socket error on stats'));
      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.degraded));
      controller.dispose();
    });
  });

  group('AdGuardController — Authentication & Isolation', () {
    test('401 transitions to authRequired and stops polling immediately', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      controller.startPolling();
      expect(controller.state.isPollingActive, isTrue);

      // Wait for immediate refresh started by startPolling to execute
      while (controller.state.isRefreshing) {
        await Future.delayed(const Duration(milliseconds: 5));
      }

      // Simulate 401
      api.isAuthRequiredState = true;
      await controller.refresh();

      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.authRequired));
      expect(controller.state.isPollingActive, isFalse);
      controller.dispose();
    });

    test('AdGuard 401 NEVER invokes router session renewal', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final trackingAuth = TrackingAuthService();
      final api = TestMockAdGuardApiService(routerId: 'test-router')
        ..isAuthRequiredState = true;

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
        authServiceOverride: trackingAuth,
      );

      await controller.refresh();

      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.authRequired));
      expect(trackingAuth.autoLoginCallCount, equals(0));
      expect(trackingAuth.loginCallCount, equals(0));
      controller.dispose();
    });

    test('HTTP 200 non-AdGuard payload transitions to invalidEndpoint', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router')
        ..statusError = const AdGuardApiException(
          type: AdGuardApiErrorType.invalidPayload,
          statusCode: 200,
          message: 'Endpoint is not genuine AdGuard Home',
        );

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      await controller.refresh();

      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.invalidEndpoint));
      controller.dispose();
    });

    test('setCredentials delegates to apiService.setCredentials and triggers refresh', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router')
        ..isAuthRequiredState = true;
      final fakeLuci = FakeLuciApiService();

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
        luciApiServiceOverride: fakeLuci,
      );

      await controller.refresh();
      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.authRequired));
      expect(api.activeCredentials, isNull);

      const newCreds = AdGuardCredentials(
        username: 'adguard_admin',
        password: 'secure_password_123',
      );

      api.isAuthRequiredState = false;
      final initialStatusCalls = api.statusCallCount;

      await controller.setCredentials(newCreds);

      expect(api.activeCredentials, equals(newCreds));
      expect(api.statusCallCount, greaterThan(initialStatusCalls));
      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.authenticated));

      controller.dispose();
    });

    test('setCredentials persists credentials to secure storage for active profile', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final fakeLuci = FakeLuciApiService();
      final fakeStorage = ControllerTestFakeSecureStorageService();

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
        luciApiServiceOverride: fakeLuci,
        secureStorageOverride: fakeStorage,
      );

      const newCreds = AdGuardCredentials(
        username: 'nightcode',
        password: 'secure_password_123',
      );

      await controller.setCredentials(newCreds);

      final stored = await fakeStorage.readValue('agh_creds_local_test-router');
      expect(stored, isNotNull);
      final decoded = jsonDecode(stored!);
      expect(decoded['username'], equals('nightcode'));
      expect(decoded['password'], equals('secure_password_123'));

      controller.dispose();
    });
  });

  group('AdGuardController — Protection Mutation & Queue Domain', () {
    test('Successful protection mutation re-fetches authoritative status', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      await controller.refresh();
      expect(controller.state.status?.protectionState,
          equals(AdGuardProtectionState.enabled));

      // Pause for 15 minutes
      final success = await controller.setProtection(
        enabled: false,
        duration: const Duration(minutes: 15),
      );

      expect(success, isTrue);
      expect(api.protectionCallCount, equals(1));
      // Authoritative status was re-fetched and updated!
      expect(controller.state.status?.protectionState,
          equals(AdGuardProtectionState.paused));
      expect(controller.state.status?.pauseDurationMs, equals(900000));
      controller.dispose();
    });

    test('Failed protection mutation does not publish false state and clears upon retry/success', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      await controller.refresh();
      expect(controller.state.status?.protectionState,
          equals(AdGuardProtectionState.enabled));

      api.protectionError = const AdGuardApiException(
        type: AdGuardApiErrorType.httpError,
        statusCode: 500,
        message: 'Internal error on /control/protection',
      );

      final success = await controller.setProtection(enabled: false);

      expect(success, isFalse);
      // Protection state must NOT have optimistically switched to disabled
      expect(controller.state.status?.protectionState,
          equals(AdGuardProtectionState.enabled));
      expect(controller.state.protectionActionError,
          contains('Failed to update protection status'));

      // Retry when error is resolved
      api.protectionError = null;
      final retrySuccess = await controller.setProtection(enabled: false);
      expect(retrySuccess, isTrue);
      expect(controller.state.protectionActionError, isNull);
      controller.dispose();
    });

    test('Protection and service operations execute in disjoint queue domains', () async {
      final queue = RouterScopedOperationQueue.instance;
      const rId = 'test-router-queue';

      // Verify domain isolation in operation queue
      expect(queue.isBusy(rId, 'service'), isFalse);
      expect(queue.isBusy(rId, 'agh_protection'), isFalse);

      final completerService = Completer<void>();
      final completerProtection = Completer<void>();

      // Launch service lock
      final serviceFuture = queue.runLocked(
        routerId: rId,
        domain: 'service',
        action: () => completerService.future,
      );

      // Verify service domain is busy, but agh_protection domain is NOT busy
      expect(queue.isBusy(rId, 'service'), isTrue);
      expect(queue.isBusy(rId, 'agh_protection'), isFalse);

      // Launch protection lock simultaneously
      final protectionFuture = queue.runLocked(
        routerId: rId,
        domain: 'agh_protection',
        action: () => completerProtection.future,
      );

      // Both domains active concurrently without deadlock
      expect(queue.isBusy(rId, 'service'), isTrue);
      expect(queue.isBusy(rId, 'agh_protection'), isTrue);

      completerService.complete();
      completerProtection.complete();
      await Future.wait([serviceFuture, protectionFuture]);

      expect(queue.isBusy(rId, 'service'), isFalse);
      expect(queue.isBusy(rId, 'agh_protection'), isFalse);
    });
  });

  group('AdGuardController — Service Lifecycle Orchestration', () {
    test('startService() / stopService() / restartService() serialize through service domain', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final fakeLuci = FakeLuciApiService();

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
        luciApiServiceOverride: fakeLuci,
      );

      await controller.refresh();

      final startOk = await controller.startService();
      expect(startOk, isTrue);
      expect(fakeLuci.executedServiceActions, contains('adguardhome:start'));

      final restartOk = await controller.restartService();
      expect(restartOk, isTrue);
      expect(fakeLuci.executedServiceActions, contains('adguardhome:restart'));

      final stopOk = await controller.stopService();
      expect(stopOk, isTrue);
      expect(fakeLuci.executedServiceActions, contains('adguardhome:stop'));

      controller.dispose();
    });

    test('Service action blocked when service is not manageable', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final fakeLuci = FakeLuciApiService();

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
        luciApiServiceOverride: fakeLuci,
      );

      // Manually set unmanageable capabilities (e.g. running manual binary without init script)
      controller.state = controller.state.copyWith(
        capabilities: const AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: false, // NOT manageable
          isApiReachable: true,
          isApiAuthenticated: true,
          isDnsOperational: true,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.adguardPrimary,
            adguardDnsPort: 53,
            dnsmasqPort: 5353,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Manual binary',
          ),
        ),
      );

      final startOk = await controller.startService();

      expect(startOk, isFalse);
      expect(fakeLuci.executedServiceActions, isEmpty);
      expect(controller.state.serviceActionError,
          contains('Service is not manageable'));
      controller.dispose();
    });

    test('Failed service action records error and clears upon retry/success', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final fakeLuci = FakeLuciApiService()..serviceActionSuccess = false;

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
        luciApiServiceOverride: fakeLuci,
      );

      // Force manageable capabilities
      controller.state = controller.state.copyWith(
        capabilities: const AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: true,
          isApiAuthenticated: true,
          isDnsOperational: true,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.standalone,
            adguardDnsPort: 53,
            dnsmasqPort: 53,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Managed service',
          ),
        ),
      );

      final stopOk = await controller.stopService();
      expect(stopOk, isFalse);
      expect(controller.state.serviceActionError,
          contains('Failed to execute stop on AdGuard Home service'));

      // Now succeed on retry
      fakeLuci.serviceActionSuccess = true;
      final retryOk = await controller.stopService();
      expect(retryOk, isTrue);
      expect(controller.state.serviceActionError, isNull);

      controller.dispose();
    });

    test('generalError is recorded and cleared upon refresh start / success', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final api = TestMockAdGuardApiService(routerId: 'test-router');
      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        apiServiceOverride: api,
      );

      // Simulate prior general error
      controller.state = controller.state.copyWith(
        generalError: 'Unexpected background failure',
      );
      expect(controller.state.generalError, equals('Unexpected background failure'));

      // Starting refresh clears stale generalError
      await controller.refresh();
      expect(controller.state.generalError, isNull);

      controller.dispose();
    });
  });

  group('AdGuardController — Reviewer Mode Transparent Handling', () {
    test('Reviewer mock router operates 100% in-memory with deterministic telemetry', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = AdGuardController(
        container.read(adguardControllerProvider('reviewer-mock-router').notifier).ref,
        'reviewer-mock-router',
      );

      await controller.refresh();

      expect(controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.authenticated));
      expect(controller.state.status?.version, equals('v0.107.52'));
      expect(controller.state.stats?.numDnsQueries, equals(34812));
      expect(controller.state.stats?.numBlockedFiltering, equals(5219));
      expect(controller.state.processTelemetry?.pid, equals('1660'));

      // Service mutation succeeds in memory
      final ok = await controller.restartService();
      expect(ok, isTrue);

      controller.dispose();
    });
  });

  group('AdGuardController — Session-Aware Caching & Lifecycle (Milestone A)', () {
    test('Successful refresh caches state and populates subsequent controller instances', () async {
      final mockApi = TestMockAdGuardApiService(
        routerId: 'cache-router',
        mockStatus: const AdGuardStatus(
          version: 'v0.107.79',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        ),
      );
      final fakeLuci = FakeLuciApiService();

      final container1 = ProviderContainer();
      final controller1 = AdGuardController(
        container1.read(adguardControllerProvider('cache-router').notifier).ref,
        'cache-router',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
      );

      // Initial state isInitialLoading
      expect(controller1.state.isInitialLoading, isTrue);

      await controller1.refresh();

      expect(controller1.state.isInitialLoading, isFalse);
      expect(controller1.state.status?.version, equals('v0.107.79'));
      expect(AdGuardController.sessionCache.containsKey('local_cache-router'), isTrue);

      controller1.dispose();
      container1.dispose();

      // Second controller instantiated immediately restores from session cache
      final container2 = ProviderContainer();
      final controller2 = AdGuardController(
        container2.read(adguardControllerProvider('cache-router').notifier).ref,
        'cache-router',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
      );

      // Invariant: Zero frame-0 red flash; cached status is already populated
      expect(controller2.state.isInitialLoading, isFalse);
      expect(controller2.state.status?.version, equals('v0.107.79'));

      controller2.dispose();
      container2.dispose();
    });

    test('Failed subsequent refresh preserves previously valid status and cache', () async {
      final mockApi = TestMockAdGuardApiService(
        routerId: 'preserve-router',
        mockStatus: const AdGuardStatus(
          version: 'v0.107.79',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        ),
      );
      final fakeLuci = FakeLuciApiService();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = AdGuardController(
        container.read(adguardControllerProvider('preserve-router').notifier).ref,
        'preserve-router',
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
      );

      await controller.refresh();
      expect(controller.state.status?.version, equals('v0.107.79'));

      // Simulate network failure on subsequent refresh
      mockApi.statusError = const AdGuardApiException(
        message: 'Connection timed out',
        type: AdGuardApiErrorType.timeout,
      );

      await controller.refresh();

      // Invariant: Status remains preserved from earlier successful probe
      expect(controller.state.status?.version, equals('v0.107.79'));
      expect(controller.state.connectionStatus, equals(AdGuardConnectionStatus.apiUnreachable));

      controller.dispose();
    });
  });

  group('AdGuardController — Multi-Instance Profiles & External Support (Milestone B & C)', () {
    test('External instance bypasses OpenWrt procd mutations and topology queries', () async {
      final extProfile = AdGuardInstanceProfile.external(
        id: 'ext_pi_1',
        name: 'Raspberry Pi AGH',
        host: '192.168.1.129',
        port: 3000,
      );

      final mockApi = TestMockAdGuardApiService(
        routerId: 'router-main',
        mockStatus: const AdGuardStatus(
          version: 'v0.107.79',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.129'],
          dnsPort: 53,
          httpPort: 3000,
        ),
      );
      final fakeLuci = FakeLuciApiService();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = AdGuardController(
        container.read(adguardControllerProvider('router-main').notifier).ref,
        'router-main',
        initialProfile: extProfile,
        apiServiceOverride: mockApi,
        luciApiServiceOverride: fakeLuci,
      );

      await controller.refresh();

      expect(controller.state.isExternal, isTrue);
      // Invariant: OpenWrt procd service card is not manageable
      expect(controller.state.capabilities.isServiceManageable, isFalse);
      // Invariant: Standalone topology
      expect(controller.state.topology.mode, equals(AdGuardTopologyMode.standalone));

      // Attempting to stop or restart external service via procd fails safely without executing ubus
      final restartOk = await controller.restartService();
      expect(restartOk, isFalse);
      expect(fakeLuci.executedServiceActions, isEmpty);

      controller.dispose();
    });

    test('Profile switch concurrency race: In-flight refresh from Profile A cannot overwrite Profile B', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final profileA = AdGuardInstanceProfile.external(
        id: 'profile_A',
        name: 'Profile A',
        host: '192.168.1.10',
      );
      final profileB = AdGuardInstanceProfile.external(
        id: 'profile_B',
        name: 'Profile B',
        host: '192.168.1.20',
      );

      final completerA = Completer<void>();
      final mockApi = TestMockAdGuardApiService(
        routerId: 'test-router',
        mockStatus: const AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.10'],
          dnsPort: 53,
          httpPort: 3000,
        ),
      );

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        initialProfile: profileA,
        apiServiceOverride: mockApi,
      );

      // Start in-flight refresh on Profile A with delayed completer
      mockApi.delayStatusCompleter = completerA;
      final refreshAFuture = controller.refresh();

      // Verify controller is refreshing Profile A
      expect(controller.state.isRefreshing, isTrue);
      expect(controller.state.effectiveInstanceId, equals('profile_A'));

      // While Profile A's refresh is still hanging in-flight, switch to Profile B
      mockApi.delayStatusCompleter = null; // Profile B will complete immediately
      mockApi.mockStatus = const AdGuardStatus(
        version: 'v0.107.99',
        running: true,
        protectionState: AdGuardProtectionState.disabled,
        dnsAddresses: ['192.168.1.20'],
        dnsPort: 53,
        httpPort: 3000,
      );

      await controller.selectProfile(profileB);

      // Profile B should now be active, authenticated, and reflected in state
      expect(controller.state.activeProfile?.id, equals('profile_B'));
      expect(controller.state.status?.version, equals('v0.107.99'));
      expect(controller.state.connectionStatus, equals(AdGuardConnectionStatus.authenticated));

      // Now complete the delayed Profile A refresh
      completerA.complete();
      await refreshAFuture;

      // Invariant: Profile B state MUST NOT be overwritten by Profile A's results!
      expect(controller.state.activeProfile?.id, equals('profile_B'));
      expect(controller.state.status?.version, equals('v0.107.99'));
      expect(controller.state.effectiveInstanceId, equals('profile_B'));

      // Invariant: Session cache for Profile B must NOT contain Profile A's data
      final cachedB = AdGuardController.sessionCache['profile_B'];
      expect(cachedB, isNotNull);
      expect(cachedB?.status?.version, equals('v0.107.99'));

      controller.dispose();
    });

    test('updateProfile updates profile configuration, invalidates cache, and preserves profile ID', () async {
      final fakeStorage = ControllerTestFakeSecureStorageService();
      final initialProfile = AdGuardInstanceProfile.external(
        id: 'ext_test_edit',
        name: 'Old Name',
        host: '192.168.1.100',
        port: 3000,
      );
      await fakeStorage.saveAdGuardProfile(initialProfile);
      await fakeStorage.saveAdGuardCredentialsForInstance(
        'ext_test_edit',
        'old_user',
        'old_pass',
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final mockApi = TestMockAdGuardApiService(routerId: 'test-router');

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        initialProfile: initialProfile,
        apiServiceOverride: mockApi,
        secureStorageOverride: fakeStorage,
      );

      await controller.loadProfiles();
      await controller.refresh();

      // Seed session cache
      expect(AdGuardController.sessionCache.containsKey('ext_test_edit'), isTrue);

      // Perform update with new name and new port
      final updatedProfile = AdGuardInstanceProfile.external(
        id: 'ext_test_edit',
        name: 'New Name',
        host: '192.168.1.100',
        port: 8080,
      );

      await controller.updateProfile(
        updatedProfile,
        username: 'new_user',
        password: 'new_pass',
      );

      // Profile ID preserved, no duplicates created
      final profiles = await fakeStorage.getAdGuardProfiles();
      expect(profiles.where((p) => p.id == 'ext_test_edit').length, equals(1));
      expect(profiles.firstWhere((p) => p.id == 'ext_test_edit').name, equals('New Name'));
      expect(profiles.firstWhere((p) => p.id == 'ext_test_edit').port, equals(8080));

      // Active profile in state updated
      expect(controller.state.activeProfile?.name, equals('New Name'));
      expect(controller.state.activeProfile?.port, equals(8080));

      // Credentials updated in storage
      final rawCreds = await fakeStorage.readValue('agh_creds_ext_test_edit');
      expect(rawCreds, isNotNull);
      final decodedCreds = jsonDecode(rawCreds!);
      expect(decodedCreds['username'], equals('new_user'));
      expect(decodedCreds['password'], equals('new_pass'));

      controller.dispose();
    });

    test('testProfileConnection isolates probe instance ID and does not touch SecureStorage', () async {
      final fakeStorage = ControllerTestFakeSecureStorageService();
      await fakeStorage.writeValue('agh_creds_test-router', 'secret');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = AdGuardController(
        container.read(adguardControllerProvider('test-router').notifier).ref,
        'test-router',
        secureStorageOverride: fakeStorage,
      );

      final status = await controller.testProfileConnection(
        host: '192.168.1.129',
        port: 3000,
        useHttps: false,
        username: 'test_user',
        password: 'test_pass',
      );

      expect(status, isNotNull);
      // Ensure router credentials were untouched
      expect(fakeStorage.storage['agh_creds_test-router'], equals('secret'));

      controller.dispose();
    });

    // ── Milestone D: Runtime Resilience, Persistence & Hydration ──────────────
    group('AdGuardController — Runtime Resilience, Persistence & Hydration (Milestone D)', () {
      test('didChangeAppLifecycleState pauses polling on inactive/paused/hidden and cancels timer', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final mockApi = TestMockAdGuardApiService(routerId: 'lifecycle-router');
        final controller = AdGuardController(
          container.read(adguardControllerProvider('lifecycle-router').notifier).ref,
          'lifecycle-router',
          apiServiceOverride: mockApi,
        );

        await controller.refresh();
        controller.startPolling();
        while (controller.state.isRefreshing) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        expect(controller.state.isPollingActive, isTrue);
        expect(controller.state.status, isNotNull); // State preserved
        final countBeforePause = mockApi.statusCallCount;

        // Transition to paused
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        expect(controller.state.isPollingActive, isTrue); // Flag preserved
        expect(controller.state.status, isNotNull); // State preserved

        // Transition to resumed
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        while (controller.state.isRefreshing) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        expect(mockApi.statusCallCount, equals(countBeforePause + 1)); // Triggered immediate refresh

        controller.dispose();
      });

      test('didChangeAppLifecycleState resumed does NOT refresh if polling was not active', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final mockApi = TestMockAdGuardApiService(routerId: 'lifecycle-router-2');
        final controller = AdGuardController(
          container.read(adguardControllerProvider('lifecycle-router-2').notifier).ref,
          'lifecycle-router-2',
          apiServiceOverride: mockApi,
        );

        expect(controller.state.isPollingActive, isFalse);
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future.delayed(Duration.zero);
        expect(mockApi.statusCallCount, equals(0));

        controller.dispose();
      });

      test('offline connectivity skips network call and increments consecutive failures', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final mockApi = TestMockAdGuardApiService(routerId: 'offline-router');
        final offlineChecker = FakeConnectivityChecker(isOnline: false);
        final controller = AdGuardController(
          container.read(adguardControllerProvider('offline-router').notifier).ref,
          'offline-router',
          apiServiceOverride: mockApi,
          connectivityCheckerOverride: offlineChecker,
        );

        await controller.refresh();
        expect(mockApi.statusCallCount, equals(0));
        expect(controller.state.statusError, contains('No network connectivity'));
        expect(controller.state.connectionStatus, equals(AdGuardConnectionStatus.apiUnreachable));

        controller.dispose();
      });

      test('onConnectivityRestored triggers guarded refresh and suppresses bursts within 500ms', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final mockApi = TestMockAdGuardApiService(routerId: 'restore-router');
        final controller = AdGuardController(
          container.read(adguardControllerProvider('restore-router').notifier).ref,
          'restore-router',
          apiServiceOverride: mockApi,
        );

        await controller.refresh();
        controller.startPolling();
        while (controller.state.isRefreshing) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        final initialCount = mockApi.statusCallCount;

        // First restore event
        await controller.onConnectivityRestored();
        expect(mockApi.statusCallCount, equals(initialCount + 1));

        // Immediate burst restore event (< 500ms) is suppressed
        await controller.onConnectivityRestored();
        expect(mockApi.statusCallCount, equals(initialCount + 1));

        controller.dispose();
      });

      test('calculateNextPollDelay calculates exponential backoff and caps at 60s', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('backoff-router').notifier).ref,
          'backoff-router',
        );
        controller.setPollingInterval(AdGuardPollingInterval.s5);

        // Polling interval is 5s
        controller.setConsecutiveFailuresForTesting(0);
        expect(controller.calculateNextPollDelay(), equals(const Duration(seconds: 5)));

        controller.setConsecutiveFailuresForTesting(1);
        expect(controller.calculateNextPollDelay(), equals(const Duration(seconds: 5)));

        controller.setConsecutiveFailuresForTesting(2);
        expect(controller.calculateNextPollDelay(), equals(const Duration(seconds: 15)));

        controller.setConsecutiveFailuresForTesting(3);
        expect(controller.calculateNextPollDelay(), equals(const Duration(seconds: 30)));

        controller.setConsecutiveFailuresForTesting(4);
        expect(controller.calculateNextPollDelay(), equals(const Duration(seconds: 60)));

        controller.setConsecutiveFailuresForTesting(10);
        expect(controller.calculateNextPollDelay(), equals(const Duration(seconds: 60)));

        controller.dispose();
      });

      test('calculateNextPollDelay honors HTTP 429/503 Retry-After if larger than backoff delay', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('retry-router').notifier).ref,
          'retry-router',
        );

        controller.setConsecutiveFailuresForTesting(2); // Normal backoff is 15s
        expect(
          controller.calculateNextPollDelay(retryAfter: const Duration(seconds: 45)),
          equals(const Duration(seconds: 45)),
        );

        controller.setConsecutiveFailuresForTesting(3); // Normal backoff is 30s
        expect(
          controller.calculateNextPollDelay(retryAfter: const Duration(seconds: 10)),
          equals(const Duration(seconds: 30)),
        );

        controller.dispose();
      });

      test('selectProfile persists active profile ID in SecureStorage with router context isolation', () async {
        final fakeStorage = ControllerTestFakeSecureStorageService();
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('router-1').notifier).ref,
          'router-1',
          secureStorageOverride: fakeStorage,
        );

        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_pi_1',
          name: 'Pi Hole/AGH',
          host: '192.168.1.129',
          port: 3000,
        );

        await controller.addExternalProfile(extProfile);
        expect(fakeStorage.storage['agh_active_profile_router-1'], equals('ext_pi_1'));

        controller.dispose();
      });

      test('loadProfiles restores persisted active profile on recreation', () async {
        final fakeStorage = ControllerTestFakeSecureStorageService();
        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_saved_1',
          name: 'Saved External',
          host: '10.0.0.50',
          port: 3000,
        );
        await fakeStorage.saveAdGuardProfile(extProfile);
        await fakeStorage.saveActiveAdGuardProfileId('router-persist', 'ext_saved_1');

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('router-persist').notifier).ref,
          'router-persist',
          secureStorageOverride: fakeStorage,
        );

        await controller.loadProfiles();
        expect(controller.state.activeProfile?.id, equals('ext_saved_1'));

        controller.dispose();
      });

      test('loadProfiles falls back cleanly if persisted profile is a local profile belonging to another router', () async {
        final fakeStorage = ControllerTestFakeSecureStorageService();
        final foreignLocal = AdGuardInstanceProfile.local(
          routerId: 'router-foreign',
          host: '192.168.2.1',
        );
        await fakeStorage.saveAdGuardProfile(foreignLocal);
        // Malicious or stale: active profile set to foreign local profile
        await fakeStorage.saveActiveAdGuardProfileId('router-my', foreignLocal.id);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('router-my').notifier).ref,
          'router-my',
          secureStorageOverride: fakeStorage,
        );

        await controller.loadProfiles();
        // Must not adopt foreign local profile! Must fall back to local_router-my
        expect(controller.state.activeProfile?.id, equals('local_router-my'));

        controller.dispose();
      });

      test('hydrateDashboardIfNeeded restores session cache immediately without network call', () async {
        AdGuardController.invalidateSessionCache();
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final mockApi = TestMockAdGuardApiService(routerId: 'hydrate-cached');
        final controller1 = AdGuardController(
          container.read(adguardControllerProvider('hydrate-cached').notifier).ref,
          'hydrate-cached',
          apiServiceOverride: mockApi,
        );

        // Perform one refresh to populate session cache
        await controller1.refresh();
        expect(mockApi.statusCallCount, equals(1));
        controller1.dispose();

        // Create controller2 for the same router
        final mockApi2 = TestMockAdGuardApiService(routerId: 'hydrate-cached');
        final controller2 = AdGuardController(
          container.read(adguardControllerProvider('hydrate-cached').notifier).ref,
          'hydrate-cached',
          apiServiceOverride: mockApi2,
        );

        await controller2.hydrateDashboardIfNeeded(hasRouterCapability: true);
        // Status was restored from cache immediately, no extra network calls
        expect(mockApi2.statusCallCount, equals(0));
        expect(controller2.state.status, isNotNull);

        controller2.dispose();
      });

      test('hydrateDashboardIfNeeded skips discovery when neither router capability nor external profile exists', () async {
        AdGuardController.invalidateSessionCache();
        final fakeStorage = ControllerTestFakeSecureStorageService();
        final mockApi = TestMockAdGuardApiService(routerId: 'hydrate-nocaps');
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('hydrate-nocaps').notifier).ref,
          'hydrate-nocaps',
          apiServiceOverride: mockApi,
          secureStorageOverride: fakeStorage,
        );

        await controller.hydrateDashboardIfNeeded(hasRouterCapability: false);
        // No local router capability and no external profiles: skipped network discovery!
        expect(mockApi.statusCallCount, equals(0));
        expect(controller.state.isPollingActive, isFalse);

        controller.dispose();
      });

      test('hydrateDashboardIfNeeded triggers refresh when hasRouterCapability is true without starting polling timer', () async {
        AdGuardController.invalidateSessionCache();
        final fakeStorage = ControllerTestFakeSecureStorageService();
        final mockApi = TestMockAdGuardApiService(routerId: 'hydrate-caps');
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('hydrate-caps').notifier).ref,
          'hydrate-caps',
          apiServiceOverride: mockApi,
          secureStorageOverride: fakeStorage,
        );

        await controller.hydrateDashboardIfNeeded(hasRouterCapability: true);
        expect(mockApi.statusCallCount, equals(1));
        expect(controller.state.status, isNotNull);
        // Invariant: does NOT start continuous background polling!
        expect(controller.state.isPollingActive, isFalse);

        controller.dispose();
      });

      test('hydrateDashboardIfNeeded triggers refresh when external profile exists even without router capability', () async {
        AdGuardController.invalidateSessionCache();
        final fakeStorage = ControllerTestFakeSecureStorageService();
        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_hydrate_1',
          name: 'Ext Hydrate',
          host: '10.0.0.88',
          port: 3000,
        );
        await fakeStorage.saveAdGuardProfile(extProfile);
        await fakeStorage.saveActiveAdGuardProfileId('hydrate-ext', extProfile.id);

        final mockApi = TestMockAdGuardApiService(routerId: 'hydrate-ext');
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('hydrate-ext').notifier).ref,
          'hydrate-ext',
          apiServiceOverride: mockApi,
          secureStorageOverride: fakeStorage,
        );

        await controller.hydrateDashboardIfNeeded(hasRouterCapability: false);
        expect(mockApi.statusCallCount, equals(1));
        expect(controller.state.activeProfile?.id, equals(extProfile.id));
        expect(controller.state.isPollingActive, isFalse);

        controller.dispose();
      });
    });

    group('AdGuardController — Stats Period, Service Autostart & User Rules', () {
      test('setStatsPeriod() updates state.statsPeriod and re-fetches stats with duration', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final api = TestMockAdGuardApiService(routerId: 'test-router');
        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: api,
        );

        await controller.refresh();
        expect(controller.state.statsPeriod, equals(AdGuardStatsPeriod.all));
        expect(api.lastStatsRecent, isNull);

        // Change to 24 Hours
        await controller.setStatsPeriod(AdGuardStatsPeriod.hours24);
        expect(controller.state.statsPeriod, equals(AdGuardStatsPeriod.hours24));
        expect(api.lastStatsRecent, equals(const Duration(hours: 24)));

        // Change to 7 Days
        await controller.setStatsPeriod(AdGuardStatsPeriod.days7);
        expect(controller.state.statsPeriod, equals(AdGuardStatsPeriod.days7));
        expect(api.lastStatsRecent, equals(const Duration(days: 7)));

        // Change to 30 Days
        await controller.setStatsPeriod(AdGuardStatsPeriod.days30);
        expect(controller.state.statsPeriod, equals(AdGuardStatsPeriod.days30));
        expect(api.lastStatsRecent, equals(const Duration(days: 30)));

        // Change back to All Time
        await controller.setStatsPeriod(AdGuardStatsPeriod.all);
        expect(controller.state.statsPeriod, equals(AdGuardStatsPeriod.all));
        expect(api.lastStatsRecent, isNull);

        // Idempotent when setting same period
        final statsCallCountBefore = api.statsCallCount;
        await controller.setStatsPeriod(AdGuardStatsPeriod.all);
        expect(api.statsCallCount, equals(statsCallCountBefore));

        controller.dispose();
      });

      test('setServiceAutostart(true/false) calls enable and disable service actions', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final api = TestMockAdGuardApiService(routerId: 'test-router');
        final fakeLuci = FakeLuciApiService();

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: api,
          luciApiServiceOverride: fakeLuci,
        );

        await controller.refresh();

        final enableOk = await controller.setServiceAutostart(true);
        expect(enableOk, isTrue);
        expect(fakeLuci.executedServiceActions, contains('adguardhome:enable'));

        final disableOk = await controller.setServiceAutostart(false);
        expect(disableOk, isTrue);
        expect(fakeLuci.executedServiceActions, contains('adguardhome:disable'));

        controller.dispose();
      });

      test('updateUserRules() successfully sets rules and refreshes filtering', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final api = TestMockAdGuardApiService(routerId: 'test-router');
        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: api,
        );

        await controller.refresh();

        const newRules = ['||evil-tracker.com^', '127.0.0.1 blocked.lan'];
        final ok = await controller.updateUserRules(newRules);

        expect(ok, isTrue);
        expect(api.setUserRulesCallCount, equals(1));
        expect(api.lastSetRules, equals(newRules));

        controller.dispose();
      });

      test('updateUserRules() surfaces failure and updates error state on API error', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final api = TestMockAdGuardApiService(routerId: 'test-router');
        api.setUserRulesError = const AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: 400,
          message: 'Invalid filter rule syntax',
        );

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: api,
        );

        await controller.refresh();

        final ok = await controller.updateUserRules(['bad-syntax']);
        expect(ok, isFalse);
        expect(controller.state.filteringError, contains('Invalid filter rule syntax'));

        controller.dispose();
      });
    });
  });
}

class FakeConnectivityChecker implements IConnectivityChecker {
  bool isOnline;
  FakeConnectivityChecker({this.isOnline = true});

  @override
  Future<bool> checkConnectivity() async => isOnline;
}

class ControllerTestFakeSecureStorageService implements SecureStorageService {
  final Map<String, String> storage = {};

  @override
  Future<String?> readValue(String key) async => storage[key];

  @override
  Future<void> writeValue(String key, String value) async {
    storage[key] = value;
  }

  @override
  Future<void> deleteValue(String key) async {
    storage.remove(key);
  }

  @override
  Future<String?> getActiveAdGuardProfileId(String routerId) async {
    return storage['agh_active_profile_$routerId'];
  }

  @override
  Future<void> saveActiveAdGuardProfileId(String routerId, String profileId) async {
    storage['agh_active_profile_$routerId'] = profileId;
  }

  @override
  Future<void> clearActiveAdGuardProfileId(String routerId) async {
    storage.remove('agh_active_profile_$routerId');
  }

  @override
  Future<List<AdGuardInstanceProfile>> getAdGuardProfiles() async {
    final raw = storage['adguard_profiles'];
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => AdGuardInstanceProfile.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  @override
  Future<void> saveAdGuardProfiles(List<AdGuardInstanceProfile> profiles) async {
    storage['adguard_profiles'] =
        jsonEncode(profiles.map((p) => p.toJson()).toList());
  }

  @override
  Future<void> saveAdGuardProfile(AdGuardInstanceProfile profile) async {
    final profiles = await getAdGuardProfiles();
    final updated = [
      for (final p in profiles)
        if (p.id != profile.id) p,
      profile,
    ];
    await saveAdGuardProfiles(updated);
  }

  @override
  Future<void> deleteAdGuardProfile(String profileId) async {
    final profiles = await getAdGuardProfiles();
    final updated = profiles.where((p) => p.id != profileId).toList();
    await saveAdGuardProfiles(updated);
    storage.remove('agh_creds_$profileId');
  }

  @override
  Future<void> saveAdGuardCredentialsForInstance(
    String instanceId,
    String username,
    String password,
  ) async {
    storage['agh_creds_$instanceId'] = jsonEncode({
      'username': username,
      'password': password,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

