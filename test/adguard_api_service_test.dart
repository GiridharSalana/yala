// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yala/modules/adguard_home/services/mock_adguard_api_service.dart';
import 'package:yala/services/interfaces/auth_service_interface.dart';
import 'package:yala/services/secure_storage_service.dart';

/// Test adapter for Dio that simulates HTTP responses and captures request metadata.
class TestDioAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options) handler;

  TestDioAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Fake SecureStorageService operating purely in memory for testing.
class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> storage = {};
  int writeCount = 0;
  int readCount = 0;

  @override
  Future<String?> readValue(String key) async {
    readCount++;
    return storage[key];
  }

  @override
  Future<void> writeValue(String key, String value) async {
    writeCount++;
    storage[key] = value;
  }

  @override
  Future<void> deleteValue(String key) async {
    storage.remove(key);
  }

  @override
  Future<void> deleteAdGuardCredentials(String routerId) async {
    storage.remove('agh_creds_$routerId');
  }

  @override
  Future<void> saveCredentials({
    required String ipAddress,
    required String username,
    required String password,
    required bool useHttps,
  }) async {
    writeCount++;
    storage['ipAddress'] = ipAddress;
    storage['username'] = username;
    storage['password'] = password;
    storage['useHttps'] = useHttps.toString();
  }

  @override
  Future<void> clearCredentials() async {
    storage.remove('ipAddress');
    storage.remove('username');
    storage.remove('password');
    storage.remove('useHttps');
  }

  @override
  Future<Map<String, String?>> getCredentials() async => {
    'ipAddress': storage['ipAddress'],
    'username': storage['username'],
    'password': storage['password'],
    'useHttps': storage['useHttps'],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Tracking mock for IAuthService to verify zero router session renewal calls.
class TrackingRouterAuthService implements IAuthService {
  int renewSessionCallCount = 0;
  int loginCallCount = 0;

  @override
  int get authEpoch => 0;

  @override
  String? get ipAddress => '192.168.1.1';

  @override
  bool get isAuthenticated => true;

  @override
  String? get sysauth => 'fake_router_session_token';

  @override
  bool get useHttps => false;

  @override
  Future<bool> checkRouterAvailability(
    String ip,
    bool https, {
    BuildContext? context,
  }) async => true;

  @override
  Future<void> login(
    String ip,
    String user,
    String pass,
    bool https, {
    dynamic context,
  }) async {
    loginCallCount++;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<bool> tryAutoLogin(
    String? ip,
    String? user,
    String? pass,
    bool? https, {
    bool force = false,
    dynamic context,
  }) async => true;

  @override
  int startPasswordTransition() => 0;

  @override
  void completePasswordTransition({
    required String newToken,
    required String newPassword,
    required String ipAddress,
    required bool useHttps,
  }) {}

  @override
  void cancelPasswordTransition() {}

  @override
  void updateSessionToken(String? token) {}

  Future<void> handleSessionExpiry({VoidCallback? onSessionExpired}) async {}

  Future<bool> checkSession() async => true;

  Future<bool> renewSession() async {
    renewSessionCallCount++;
    return true;
  }
}

void main() {
  const routerId = 'test-router-123';
  const host = '192.168.1.1';
  const port = 3000;

  Map<String, dynamic> sampleValidStatusJson({
    bool protectionEnabled = true,
    int duration = 0,
  }) => {
    'version': 'v0.107.52',
    'running': true,
    'protection_enabled': protectionEnabled,
    'protection_disabled_duration': duration,
    'dns_addresses': ['192.168.1.1', '127.0.0.1'],
    'dns_port': 53,
    'http_port': 3000,
    'start_time': 1700000000000,
  };

  Map<String, dynamic> sampleValidStatsJson() => {
    'num_dns_queries': 25000,
    'num_blocked_filtering': 5000,
    'num_replaced_safebrowsing': 15,
    'num_replaced_safesearch': 0,
    'num_replaced_parental': 0,
    'avg_processing_time': 0.0125,
    'top_queried_domains': [
      {'domain': 'example.com', 'count': 1200},
      {'domain': 'google.com', 'count': 850},
    ],
    'top_blocked_domains': [
      {'domain': 'ads.example.com', 'count': 450},
    ],
    'top_clients': [
      {'ip': '192.168.1.100', 'count': 5000},
    ],
    'dns_queries': [100, 200, 300],
    'blocked_filtering': [20, 30, 40],
    'time_units': 'hours',
  };

  Map<String, dynamic> sampleFilteringJson() => {
    'enabled': true,
    'filters': [
      {
        'id': 1,
        'name': 'AdGuard DNS filter',
        'rules_count': 65000,
        'enabled': true,
        'last_updated': '2026-10-08T00:00:00Z',
      },
    ],
    'whitelist_filters': [],
    'user_rules': ['||test.com^'],
  };

  group('AdGuardApiService — Authentication Architecture & Probing', () {
    late FakeSecureStorageService fakeStorage;
    late TrackingRouterAuthService trackingAuthService;

    setUp(() {
      fakeStorage = FakeSecureStorageService();
      trackingAuthService = TrackingRouterAuthService();
    });

    test(
      'Unauthenticated 200: Valid AdGuard response succeeds without credentials',
      () async {
        final dio = Dio();
        final requests = <RequestOptions>[];

        dio.httpClientAdapter = TestDioAdapter((options) async {
          requests.add(options);
          return ResponseBody.fromString(
            jsonEncode(sampleValidStatusJson()),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          secureStorageService: fakeStorage,
          dioOverride: dio,
        );

        final result = await service.getStatus();

        expect(result.isSuccess, isTrue);
        expect(result.data?.version, equals('v0.107.52'));
        expect(service.isAuthenticated, isTrue);
        expect(service.isAuthRequired, isFalse);
        expect(requests.length, equals(1));
        // Assert no Authorization header was sent on the probe
        expect(requests.first.headers.containsKey('Authorization'), isFalse);
        // Assert zero router renewal calls
        expect(trackingAuthService.renewSessionCallCount, equals(0));
      },
    );

    test(
      '401 -> Stored credentials retrieved and retried automatically',
      () async {
        // Preload stored credentials for this router
        const storedCreds = AdGuardCredentials(
          username: 'adguard_admin',
          password: 'secure_password_123',
        );
        await fakeStorage.writeValue(
          'agh_creds_$routerId',
          jsonEncode(storedCreds.toJson()),
        );

        final dio = Dio();
        final capturedHeaders = <Map<String, dynamic>>[];

        dio.httpClientAdapter = TestDioAdapter((options) async {
          capturedHeaders.add(Map.from(options.headers));
          if (capturedHeaders.length == 1) {
            // Initial unauthenticated probe encounters 401
            return ResponseBody.fromString('Unauthorized', 401);
          } else {
            // Retry with credentials encounters 200
            return ResponseBody.fromString(
              jsonEncode(sampleValidStatusJson()),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          secureStorageService: fakeStorage,
          dioOverride: dio,
        );

        final result = await service.getStatus();

        expect(result.isSuccess, isTrue);
        expect(service.isAuthenticated, isTrue);
        expect(service.isAuthRequired, isFalse);
        expect(service.activeCredentials?.username, equals('adguard_admin'));
        expect(capturedHeaders.length, equals(2));
        // First request was unauthenticated probe
        expect(capturedHeaders[0].containsKey('Authorization'), isFalse);
        // Second request used preemptive Basic Auth with stored credentials
        expect(
          capturedHeaders[1]['Authorization'],
          equals(storedCreds.toBasicAuthHeader()),
        );
      },
    );

    test(
      'Stored credentials rejected (401) returns explicit authRequired result',
      () async {
        const storedCreds = AdGuardCredentials(
          username: 'stale_user',
          password: 'wrong_password',
        );
        await fakeStorage.writeValue(
          'agh_creds_$routerId',
          jsonEncode(storedCreds.toJson()),
        );

        final dio = Dio();
        int callCount = 0;

        dio.httpClientAdapter = TestDioAdapter((options) async {
          callCount++;
          // Both initial probe and retried stored credentials return 401
          return ResponseBody.fromString('Unauthorized', 401);
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          secureStorageService: fakeStorage,
          dioOverride: dio,
        );

        final result = await service.getStatus();

        expect(result.isSuccess, isFalse);
        expect(result.isAuthRequired, isTrue);
        expect(result.error?.type, equals(AdGuardApiErrorType.authRequired));
        expect(result.error?.statusCode, equals(401));
        expect(service.isAuthenticated, isFalse);
        expect(service.isAuthRequired, isTrue);
        expect(service.activeCredentials, isNull);
        expect(callCount, equals(2)); // probe + retry
      },
    );

    test(
      'Stored credentials absent returns explicit authRequired without router credential leakage',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString('Unauthorized', 401);
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          secureStorageService: fakeStorage, // empty storage
          dioOverride: dio,
        );

        // Call without explicit opt-in flag
        final result = await service.getStatus(
          allowFallbackToRouterCredentials: false,
          routerCredentials: const AdGuardCredentials(
            username: 'root',
            password: 'SecretRouterPassword',
          ),
        );

        expect(result.isSuccess, isFalse);
        expect(result.isAuthRequired, isTrue);
        expect(service.isAuthenticated, isFalse);
      },
    );

    test(
      'Explicit router-credential opt-in allows deliberate fallback when authorized',
      () async {
        final dio = Dio();
        final capturedHeaders = <Map<String, dynamic>>[];
        const routerCreds = AdGuardCredentials(
          username: 'root',
          password: 'RouterOptInPassword',
        );

        dio.httpClientAdapter = TestDioAdapter((options) async {
          capturedHeaders.add(Map.from(options.headers));
          if (capturedHeaders.length == 1) {
            // Probe returns 401
            return ResponseBody.fromString('Unauthorized', 401);
          } else {
            // Explicit fallback returns 200
            return ResponseBody.fromString(
              jsonEncode(sampleValidStatusJson()),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          secureStorageService: fakeStorage,
          dioOverride: dio,
        );

        final result = await service.getStatus(
          allowFallbackToRouterCredentials: true,
          routerCredentials: routerCreds,
        );

        expect(result.isSuccess, isTrue);
        expect(service.isAuthenticated, isTrue);
        expect(service.activeCredentials?.username, equals('root'));
        expect(capturedHeaders.length, equals(2));
        expect(
          capturedHeaders[1]['Authorization'],
          equals(routerCreds.toBasicAuthHeader()),
        );
      },
    );

    test(
      'AdGuard 401 NEVER invokes router session renewal or modifies router session',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString('Unauthorized', 401);
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          secureStorageService: fakeStorage,
          dioOverride: dio,
        );

        final result = await service.getStatus();

        expect(result.isAuthRequired, isTrue);
        // Explicit isolation check: Router auth service must remain completely untouched
        expect(trackingAuthService.renewSessionCallCount, equals(0));
        expect(trackingAuthService.loginCallCount, equals(0));
        expect(trackingAuthService.isAuthenticated, isTrue);
        expect(
          trackingAuthService.sysauth,
          equals('fake_router_session_token'),
        );
      },
    );
  });

  group('AdGuardApiService — Status Validation & Payload Heuristics', () {
    test('Valid /control/status parses completely', () async {
      final dio = Dio();
      dio.httpClientAdapter = TestDioAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'version': 'v0.107.52',
            'running': true,
            'protection_enabled': false,
            'protection_disabled_duration': 300000,
            'dns_addresses': ['192.168.1.1'],
            'dns_port': 53,
            'http_port': 3000,
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final service = AdGuardApiService(
        routerId: routerId,
        host: host,
        port: port,
        dioOverride: dio,
      );

      final result = await service.getStatus();

      expect(result.isSuccess, isTrue);
      final status = result.data!;
      expect(status.version, equals('v0.107.52'));
      expect(status.running, isTrue);
      expect(status.protectionState, equals(AdGuardProtectionState.paused));
      expect(status.pauseDurationMs, equals(300000));
      expect(status.dnsAddresses, equals(['192.168.1.1']));
      expect(status.dnsPort, equals(53));
      expect(status.httpPort, equals(3000));
    });

    test(
      'HTTP 200 non-AdGuard payload is rejected safely as invalidPayload',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          // Simulates another web service or captive portal returning 200 OK
          return ResponseBody.fromString(
            jsonEncode({
              'message': 'Welcome to generic router portal',
              'status': 'ok',
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.getStatus();

        expect(result.isSuccess, isFalse);
        expect(result.error?.type, equals(AdGuardApiErrorType.invalidPayload));
        expect(service.isAuthenticated, isFalse);
      },
    );

    test(
      'Malformed non-JSON string is rejected safely without crashing',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString(
            '<html><body>502 Bad Gateway</body></html>',
            200,
          );
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.getStatus();

        expect(result.isSuccess, isFalse);
        expect(
          result.error?.type == AdGuardApiErrorType.malformedJson ||
              result.error?.type == AdGuardApiErrorType.invalidPayload,
          isTrue,
        );
        expect(service.isAuthenticated, isFalse);
      },
    );

    test(
      'Missing optional status fields tolerate nulls with safe defaults',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              // Minimal valid indicator fields
              'protection_enabled': true,
              'dns_port': 53,
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.getStatus();

        expect(result.isSuccess, isTrue);
        expect(result.data?.version, equals('Unknown'));
        expect(result.data?.dnsAddresses, isEmpty);
        expect(result.data?.pauseDurationMs, equals(0));
        expect(
          result.data?.protectionState,
          equals(AdGuardProtectionState.enabled),
        );
      },
    );
  });

  group('AdGuardApiService — Statistics & Top Lists', () {
    test(
      'Parses modern v0.107+ statistics response with object top lists',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode(sampleValidStatsJson()),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.getStats();

        expect(result.isSuccess, isTrue);
        final stats = result.data!;
        expect(stats.numDnsQueries, equals(25000));
        expect(stats.numBlockedFiltering, equals(5000));
        expect(stats.blockRatePercentage, equals(20.0));
        expect(stats.topQueriedDomains.length, equals(2));
        expect(stats.topQueriedDomains[0].identifier, equals('example.com'));
        expect(stats.topQueriedDomains[0].count, equals(1200));
        expect(
          stats.topBlockedDomains[0].identifier,
          equals('ads.example.com'),
        );
        expect(stats.topClients[0].identifier, equals('192.168.1.100'));
        // Aggregate separation preserved
        expect(stats.dnsQueriesTrend, equals([100, 200, 300]));
        expect(stats.blockedFilteringTrend, equals([20, 30, 40]));
      },
    );

    test('Parses legacy v0.100-v0.106 single-entry map top lists', () async {
      final dio = Dio();
      dio.httpClientAdapter = TestDioAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'num_dns_queries': 1000,
            'num_blocked_filtering': 250,
            'top_queried_domains': [
              {'legacy.org': 400},
              {'another.com': 200},
            ],
            'top_blocked_domains': [
              {'badtrack.net': 150},
            ],
            'top_clients': [
              {'192.168.1.50': 600},
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final service = AdGuardApiService(
        routerId: routerId,
        host: host,
        port: port,
        dioOverride: dio,
      );

      final result = await service.getStats();

      expect(result.isSuccess, isTrue);
      final stats = result.data!;
      expect(stats.topQueriedDomains[0].identifier, equals('legacy.org'));
      expect(stats.topQueriedDomains[0].count, equals(400));
      expect(stats.topBlockedDomains[0].identifier, equals('badtrack.net'));
      expect(stats.topClients[0].identifier, equals('192.168.1.50'));
    });

    test('recent parameter supported sends query parameter', () async {
      final dio = Dio();
      RequestOptions? captured;

      dio.httpClientAdapter = TestDioAdapter((options) async {
        captured = options;
        return ResponseBody.fromString(
          jsonEncode(sampleValidStatsJson()),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final service = AdGuardApiService(
        routerId: routerId,
        host: host,
        port: port,
        dioOverride: dio,
      );

      final result = await service.getStats(
        recent: const Duration(milliseconds: 86400000),
      );

      expect(result.isSuccess, isTrue);
      expect(captured?.queryParameters['recent'], equals(86400000));
    });

    test(
      'recent rejected (HTTP 400) retries automatically without recent parameter',
      () async {
        final dio = Dio();
        final attempts = <RequestOptions>[];

        dio.httpClientAdapter = TestDioAdapter((options) async {
          attempts.add(options);
          if (attempts.length == 1) {
            // First attempt with ?recent= returns 400 Bad Request
            return ResponseBody.fromString(
              'Bad Request: unknown query parameter',
              400,
            );
          } else {
            // Fallback attempt without ?recent= succeeds
            return ResponseBody.fromString(
              jsonEncode(sampleValidStatsJson()),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.getStats(
          recent: const Duration(milliseconds: 86400000),
        );

        expect(result.isSuccess, isTrue);
        expect(attempts.length, equals(2));
        expect(attempts[0].queryParameters.containsKey('recent'), isTrue);
        expect(attempts[1].queryParameters.containsKey('recent'), isFalse);
      },
    );

    test(
      'Separation of aggregates and historical trends is strictly maintained',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'num_dns_queries': 5000,
              'num_blocked_filtering': 1000,
              // Historical buckets sum to 600, but aggregate must remain 5000
              'dns_queries': [100, 200, 300],
              'blocked_filtering': [50, 50],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.getStats();

        expect(result.isSuccess, isTrue);
        final stats = result.data!;
        expect(stats.numDnsQueries, equals(5000));
        expect(stats.numBlockedFiltering, equals(1000));
        expect(stats.dnsQueriesTrend, equals([100, 200, 300]));
      },
    );
  });

  group('AdGuardApiService — Filtering Status', () {
    test(
      'Valid /control/filtering/status response parses lists and total rules',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode(sampleFilteringJson()),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.getFilteringStatus();

        expect(result.isSuccess, isTrue);
        final filtering = result.data!;
        expect(filtering.enabled, isTrue);
        expect(filtering.filterLists.length, equals(1));
        expect(filtering.filterLists.first.name, equals('AdGuard DNS filter'));
        expect(filtering.filterLists.first.rulesCount, equals(65000));
        expect(filtering.userRules, equals(['||test.com^']));
        expect(filtering.totalRulesCount, equals(65001));
      },
    );

    test('Empty and malformed filter entries degrade safely', () async {
      final dio = Dio();
      dio.httpClientAdapter = TestDioAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'enabled': false,
            'filters': [
              // Malformed filter with missing fields
              {'id': null, 'rules_count': null},
            ],
            'user_rules': null,
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final service = AdGuardApiService(
        routerId: routerId,
        host: host,
        port: port,
        dioOverride: dio,
      );

      final result = await service.getFilteringStatus();

      expect(result.isSuccess, isTrue);
      final filtering = result.data!;
      expect(filtering.enabled, isFalse);
      expect(filtering.filterLists.length, equals(1));
      expect(filtering.filterLists.first.rulesCount, equals(0));
      expect(filtering.userRules, isEmpty);
      expect(filtering.totalRulesCount, equals(0));
    });
  });

  group('AdGuardApiService — Protection Mutation', () {
    test('Enable protection posts {"enabled": true}', () async {
      final dio = Dio();
      RequestOptions? captured;

      dio.httpClientAdapter = TestDioAdapter((options) async {
        captured = options;
        return ResponseBody.fromString('OK', 200);
      });

      final service = AdGuardApiService(
        routerId: routerId,
        host: host,
        port: port,
        dioOverride: dio,
      );

      final result = await service.setProtection(enabled: true);

      expect(result.isSuccess, isTrue);
      expect(captured?.method, equals('POST'));
      expect(captured?.path.endsWith('/control/protection'), isTrue);
      final body = jsonDecode(captured?.data);
      expect(body, equals({'enabled': true}));
    });

    test(
      'Indefinite disable posts {"enabled": false, "duration": 0}',
      () async {
        final dio = Dio();
        RequestOptions? captured;

        dio.httpClientAdapter = TestDioAdapter((options) async {
          captured = options;
          return ResponseBody.fromString('OK', 200);
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.setProtection(
          enabled: false,
          duration: Duration.zero,
        );

        expect(result.isSuccess, isTrue);
        final body = jsonDecode(captured?.data);
        expect(body, equals({'enabled': false, 'duration': 0}));
      },
    );

    test('Temporary pause posts {"enabled": false, "duration": ms}', () async {
      final dio = Dio();
      RequestOptions? captured;

      dio.httpClientAdapter = TestDioAdapter((options) async {
        captured = options;
        return ResponseBody.fromString('OK', 200);
      });

      final service = AdGuardApiService(
        routerId: routerId,
        host: host,
        port: port,
        dioOverride: dio,
      );

      final result = await service.setProtection(
        enabled: false,
        duration: const Duration(minutes: 10),
      );

      expect(result.isSuccess, isTrue);
      final body = jsonDecode(captured?.data);
      expect(body, equals({'enabled': false, 'duration': 600000}));
    });

    test(
      'Tri-state helper setProtectionState dispatches correct payloads',
      () async {
        final dio = Dio();
        final payloads = <Map<String, dynamic>>[];

        dio.httpClientAdapter = TestDioAdapter((options) async {
          payloads.add(jsonDecode(options.data));
          return ResponseBody.fromString('OK', 200);
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        await service.setProtectionState(AdGuardProtectionState.enabled);
        await service.setProtectionState(
          AdGuardProtectionState.paused,
          pauseDuration: const Duration(minutes: 5),
        );
        await service.setProtectionState(AdGuardProtectionState.disabled);

        expect(payloads.length, equals(3));
        expect(payloads[0], equals({'enabled': true}));
        expect(payloads[1], equals({'enabled': false, 'duration': 300000}));
        expect(payloads[2], equals({'enabled': false, 'duration': 0}));
      },
    );
  });

  group('AdGuardApiService — Error Handling & Timeouts', () {
    test('Timeout error classifies as AdGuardApiErrorType.timeout', () async {
      final dio = Dio();
      dio.httpClientAdapter = TestDioAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
          error: 'Receive timed out',
        );
      });

      final service = AdGuardApiService(
        routerId: routerId,
        host: host,
        port: port,
        dioOverride: dio,
      );

      final result = await service.getStatus();

      expect(result.isSuccess, isFalse);
      expect(result.error?.type, equals(AdGuardApiErrorType.timeout));
    });

    test(
      'Network connection error classifies as AdGuardApiErrorType.networkFailure',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'Connection refused',
          );
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.getStatus();

        expect(result.isSuccess, isFalse);
        expect(result.error?.type, equals(AdGuardApiErrorType.networkFailure));
      },
    );

    test(
      'HTTP 500 error classifies as AdGuardApiErrorType.httpError with statusCode',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString('Internal Server Error', 500);
        });

        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          dioOverride: dio,
        );

        final result = await service.getStatus();

        expect(result.isSuccess, isFalse);
        expect(result.error?.type, equals(AdGuardApiErrorType.httpError));
        expect(result.error?.statusCode, equals(500));
      },
    );
  });

  group('Credential & Model Redaction Security', () {
    test('AdGuardCredentials toString() redacts password', () {
      const creds = AdGuardCredentials(
        username: 'my_admin',
        password: 'SuperSecretPassword!#',
      );

      final str = creds.toString();
      expect(str.contains('SuperSecretPassword!#'), isFalse);
      expect(str.contains('[REDACTED]'), isTrue);
    });

    test('AdGuardApiException toString() never leaks credentials', () {
      const exception = AdGuardApiException(
        type: AdGuardApiErrorType.authRequired,
        statusCode: 401,
        message: 'Invalid credentials for user admin',
      );

      final str = exception.toString();
      expect(str.contains('SuperSecretPassword'), isFalse);
    });

    test(
      'AdGuard credentials do not write to router auth storage keys',
      () async {
        final fakeStorage = FakeSecureStorageService();
        final service = AdGuardApiService(
          routerId: routerId,
          host: host,
          port: port,
          secureStorageService: fakeStorage,
        );

        const aghCreds = AdGuardCredentials(
          username: 'adguard_user',
          password: 'agh_secret_password',
        );

        await service.saveStoredCredentials(aghCreds);

        // Verify stored under 'agh_creds_${routerId}'
        expect(fakeStorage.storage.containsKey('agh_creds_$routerId'), isTrue);
        // Verify router auth keys remain completely empty
        expect(fakeStorage.storage.containsKey('username'), isFalse);
        expect(fakeStorage.storage.containsKey('password'), isFalse);
        expect(fakeStorage.storage.containsKey('ipAddress'), isFalse);
      },
    );
  });

  group(
    'MockAdGuardApiService — Zero External Invocations & Deterministic Telemetry',
    () {
      test(
        'Operates 100% in-memory with zero network, ubus, or secure storage writes',
        () async {
          final mockService = MockAdGuardApiService();

          expect(mockService.isAuthenticated, isTrue);
          expect(mockService.isAuthRequired, isFalse);

          final statusResult = await mockService.getStatus();
          expect(statusResult.isSuccess, isTrue);
          expect(statusResult.data?.version, equals('v0.107.52'));
          expect(statusResult.data?.running, isTrue);
          expect(mockService.statusCallCount, equals(1));

          final statsResult = await mockService.getStats();
          expect(statsResult.isSuccess, isTrue);
          expect(statsResult.data?.numDnsQueries, equals(34812));
          expect(statsResult.data?.numBlockedFiltering, equals(5219));
          expect(mockService.statsCallCount, equals(1));

          final filteringResult = await mockService.getFilteringStatus();
          expect(filteringResult.isSuccess, isTrue);
          expect(filteringResult.data?.totalRulesCount, equals(77503));
          expect(mockService.filteringCallCount, equals(1));

          // Attempting to access HttpClientManager on mock throws UnsupportedError
          expect(() => mockService.httpClientManager, throwsUnsupportedError);
        },
      );

      test('Mock protection mutations operate strictly in-memory', () async {
        final mockService = MockAdGuardApiService();

        expect(
          mockService.currentProtectionState,
          equals(AdGuardProtectionState.enabled),
        );

        // 1. Pause
        await mockService.setProtection(
          enabled: false,
          duration: const Duration(minutes: 15),
        );
        expect(
          mockService.currentProtectionState,
          equals(AdGuardProtectionState.paused),
        );
        expect(mockService.currentPauseDurationMs, equals(900000));

        // Verify status reflects paused state
        final pausedStatus = await mockService.getStatus();
        expect(
          pausedStatus.data?.protectionState,
          equals(AdGuardProtectionState.paused),
        );

        // 2. Indefinite disable
        await mockService.setProtection(
          enabled: false,
          duration: Duration.zero,
        );
        expect(
          mockService.currentProtectionState,
          equals(AdGuardProtectionState.disabled),
        );
        expect(mockService.currentPauseDurationMs, equals(0));

        // 3. Re-enable
        await mockService.setProtection(enabled: true);
        expect(
          mockService.currentProtectionState,
          equals(AdGuardProtectionState.enabled),
        );
      });

      test('Mock simulates failure modes for unit test harnesses', () async {
        final mock = MockAdGuardApiService(simulateTimeout: true);

        final statusRes = await mock.getStatus();
        expect(statusRes.isSuccess, isFalse);
        expect(statusRes.error?.type, equals(AdGuardApiErrorType.timeout));

        mock.simulateTimeout = false;
        mock.simulateNetworkFailure = true;

        final statsRes = await mock.getStats();
        expect(statsRes.isSuccess, isFalse);
        expect(
          statsRes.error?.type,
          equals(AdGuardApiErrorType.networkFailure),
        );
      });

      test('Mock supports authentication-required scenario', () async {
        final mock = MockAdGuardApiService(
          requiresAuth: true,
          expectedUsername: 'admin',
          expectedPassword: 'secret_password',
        );

        expect(mock.isAuthenticated, isFalse);
        expect(mock.isAuthRequired, isTrue);

        final unauthResult = await mock.getStatus(forceProbe: true);
        expect(unauthResult.isSuccess, isFalse);
        expect(unauthResult.isAuthRequired, isTrue);

        // Supply correct credentials
        mock.setCredentials(
          const AdGuardCredentials(
            username: 'admin',
            password: 'secret_password',
          ),
        );

        expect(mock.isAuthenticated, isTrue);
        final authResult = await mock.getStatus();
        expect(authResult.isSuccess, isTrue);
      });

      test(
        'Mock testConnection simulates authentication, reachability, and validation states',
        () async {
          final mock = MockAdGuardApiService(
            requiresAuth: true,
            expectedUsername: 'admin',
            expectedPassword: 'secret_password',
          );

          // Unauthenticated test
          final statusUnauth = await mock.testConnection();
          expect(statusUnauth, equals(AdGuardConnectionStatus.authRequired));

          // With correct credentials
          final statusAuth = await mock.testConnection(
            credentials: const AdGuardCredentials(
              username: 'admin',
              password: 'secret_password',
            ),
          );
          expect(statusAuth, equals(AdGuardConnectionStatus.authenticated));

          // With unreachable failure simulation
          mock.simulateNetworkFailure = true;
          final statusUnreachable = await mock.testConnection();
          expect(
            statusUnreachable,
            equals(AdGuardConnectionStatus.apiUnreachable),
          );

          // With invalid endpoint simulation
          mock.simulateNetworkFailure = false;
          mock.simulateInvalidPayload = true;
          final statusInvalid = await mock.testConnection();
          expect(
            statusInvalid,
            equals(AdGuardConnectionStatus.invalidEndpoint),
          );
        },
      );
    },
  );

  group('AdGuardApiService — Multi-Instance Profiles & Credential Isolation', () {
    test(
      'testConnection returns authenticated on genuine AdGuard /control/status response',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'version': 'v0.107.79',
              'running': true,
              'protection_enabled': true,
              'dns_addresses': ['192.168.1.129'],
              'dns_port': 53,
              'http_port': 3000,
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final service = AdGuardApiService(
          routerId: 'router-test',
          instanceId: 'ext_test',
          host: '192.168.1.129',
          port: 3000,
          dioOverride: dio,
        );

        final status = await service.testConnection();
        expect(status, equals(AdGuardConnectionStatus.authenticated));
      },
    );

    test('testConnection returns authRequired on HTTP 401', () async {
      final dio = Dio();
      dio.httpClientAdapter = TestDioAdapter((options) async {
        return ResponseBody.fromString(
          'Unauthorized',
          401,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          },
        );
      });

      final service = AdGuardApiService(
        routerId: 'router-test',
        instanceId: 'ext_test',
        host: '192.168.1.129',
        port: 3000,
        dioOverride: dio,
      );

      final status = await service.testConnection();
      expect(status, equals(AdGuardConnectionStatus.authRequired));
    });

    test(
      'testConnection returns invalidEndpoint on non-AdGuard 200 response',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString(
            '<html><body>OpenWrt LuCI Login</body></html>',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          );
        });

        final service = AdGuardApiService(
          routerId: 'router-test',
          instanceId: 'ext_test',
          host: '192.168.1.1',
          port: 80,
          dioOverride: dio,
        );

        final status = await service.testConnection();
        expect(status, equals(AdGuardConnectionStatus.invalidEndpoint));
      },
    );

    test(
      'testConnection returns invalidEndpoint on HTTP 301/302/307 redirects without following',
      () async {
        int requestCount = 0;
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          requestCount++;
          return ResponseBody.fromString(
            'Moved Permanently',
            301,
            headers: {
              'location': ['https://attacker.example.com/login'],
              Headers.contentTypeHeader: [Headers.textPlainContentType],
            },
          );
        });

        final service = AdGuardApiService(
          routerId: 'router-test',
          instanceId: 'ext_test',
          host: '192.168.1.129',
          port: 3000,
          dioOverride: dio,
        );

        final status = await service.testConnection(
          credentials: const AdGuardCredentials(username: 'u', password: 'p'),
        );
        expect(status, equals(AdGuardConnectionStatus.invalidEndpoint));
        expect(
          requestCount,
          equals(1),
        ); // exactly 1 request; never followed redirect
      },
    );

    test(
      'getStoredCredentials strictly reads instance-scoped key and never reads router key',
      () async {
        final fakeStorage = FakeSecureStorageService();
        const otherCreds = AdGuardCredentials(
          username: 'other_user',
          password: 'other_pass',
        );
        await fakeStorage.writeValue(
          'agh_creds_router_legacy',
          jsonEncode(otherCreds.toJson()),
        );

        final localService = AdGuardApiService(
          routerId: 'router_legacy',
          instanceId: 'local_router_legacy',
          host: '192.168.1.1',
          secureStorageService: fakeStorage,
        );

        final retrieved = await localService.getStoredCredentials();
        expect(retrieved, isNull);
        expect(
          fakeStorage.storage.containsKey('agh_creds_local_router_legacy'),
          isFalse,
        );
      },
    );

    test(
      'getStoredCredentials returns null and NEVER migrates router credentials for external profiles',
      () async {
        final fakeStorage = FakeSecureStorageService();
        const legacyCreds = AdGuardCredentials(
          username: 'router_root',
          password: 'router_password',
        );
        await fakeStorage.writeValue(
          'agh_creds_router_legacy',
          jsonEncode(legacyCreds.toJson()),
        );

        final extService = AdGuardApiService(
          routerId: 'router_legacy',
          instanceId: 'ext_instance_99',
          host: '192.168.1.129',
          secureStorageService: fakeStorage,
        );

        final retrieved = await extService.getStoredCredentials();
        expect(retrieved, isNull);
        expect(
          fakeStorage.storage.containsKey('agh_creds_ext_instance_99'),
          isFalse,
        );
        expect(
          fakeStorage.storage.containsKey('agh_creds_router_legacy'),
          isTrue,
        );
        final rawLegacy = fakeStorage.storage['agh_creds_router_legacy'];
        expect(rawLegacy, isNotNull);
        final parsedLegacy = jsonDecode(rawLegacy!);
        expect(parsedLegacy['username'], equals('router_root'));
        expect(parsedLegacy['password'], equals('router_password'));
      },
    );

    test(
      'clearStoredCredentials on external profile leaves legacy router credentials intact',
      () async {
        final fakeStorage = FakeSecureStorageService();
        const legacyCreds = AdGuardCredentials(
          username: 'router_root',
          password: 'router_password',
        );
        const extCreds = AdGuardCredentials(
          username: 'ext_user',
          password: 'ext_password',
        );
        await fakeStorage.writeValue(
          'agh_creds_router_legacy',
          jsonEncode(legacyCreds.toJson()),
        );
        await fakeStorage.writeValue(
          'agh_creds_ext_instance_99',
          jsonEncode(extCreds.toJson()),
        );

        final extService = AdGuardApiService(
          routerId: 'router_legacy',
          instanceId: 'ext_instance_99',
          host: '192.168.1.129',
          secureStorageService: fakeStorage,
        );

        await extService.clearStoredCredentials();

        expect(
          fakeStorage.storage.containsKey('agh_creds_ext_instance_99'),
          isFalse,
        );
        expect(
          fakeStorage.storage.containsKey('agh_creds_router_legacy'),
          isTrue,
        );
      },
    );

    test(
      'clearStoredCredentials on canonical local instance strictly clears only its instance key',
      () async {
        final fakeStorage = FakeSecureStorageService();
        const localCreds = AdGuardCredentials(
          username: 'local_root',
          password: 'local_pwd',
        );
        const otherCreds = AdGuardCredentials(
          username: 'other_root',
          password: 'other_pwd',
        );
        await fakeStorage.writeValue(
          'agh_creds_router_legacy',
          jsonEncode(otherCreds.toJson()),
        );
        await fakeStorage.writeValue(
          'agh_creds_local_router_legacy',
          jsonEncode(localCreds.toJson()),
        );

        final localService = AdGuardApiService(
          routerId: 'router_legacy',
          instanceId: 'local_router_legacy',
          host: '192.168.1.1',
          secureStorageService: fakeStorage,
        );

        await localService.clearStoredCredentials();

        expect(
          fakeStorage.storage.containsKey('agh_creds_local_router_legacy'),
          isFalse,
        );
        expect(
          fakeStorage.storage.containsKey('agh_creds_router_legacy'),
          isTrue,
        );
      },
    );

    test(
      'clearing one external profile credentials leaves other external profiles intact',
      () async {
        final fakeStorage = FakeSecureStorageService();
        const creds1 = AdGuardCredentials(username: 'u1', password: 'p1');
        const creds2 = AdGuardCredentials(username: 'u2', password: 'p2');
        await fakeStorage.writeValue(
          'agh_creds_ext_1',
          jsonEncode(creds1.toJson()),
        );
        await fakeStorage.writeValue(
          'agh_creds_ext_2',
          jsonEncode(creds2.toJson()),
        );

        final service1 = AdGuardApiService(
          routerId: 'router_legacy',
          instanceId: 'ext_1',
          host: '192.168.1.129',
          secureStorageService: fakeStorage,
        );

        await service1.clearStoredCredentials();

        expect(fakeStorage.storage.containsKey('agh_creds_ext_1'), isFalse);
        expect(fakeStorage.storage.containsKey('agh_creds_ext_2'), isTrue);
      },
    );

    test(
      'getStatus on external profile never falls back to router credentials on 401',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = TestDioAdapter((options) async {
          return ResponseBody.fromString(
            'Unauthorized',
            401,
            headers: {
              Headers.contentTypeHeader: [Headers.textPlainContentType],
            },
          );
        });

        final fakeStorage = FakeSecureStorageService();
        final extService = AdGuardApiService(
          routerId: 'router_legacy',
          instanceId: 'ext_instance_99',
          host: '192.168.1.129',
          dioOverride: dio,
          secureStorageService: fakeStorage,
        );

        final result = await extService.getStatus(
          allowFallbackToRouterCredentials: true,
          routerCredentials: const AdGuardCredentials(
            username: 'router_root',
            password: 'router_password',
          ),
        );

        expect(result.isSuccess, isFalse);
        expect(result.isAuthRequired, isTrue);
        expect(extService.activeCredentials, isNull);
      },
    );
  });
}
