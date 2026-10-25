// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:yala/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/services/secure_storage_service.dart';
import 'package:yala/utils/http_client_manager.dart';
import 'package:yala/utils/logger.dart';

/// Abstract contract for AdGuard Home REST API interactions.
abstract class IAdGuardApiService {
  /// The router ID this service instance is scoped to.
  String get routerId;

  /// The unique instance ID this service is scoped to.
  String get instanceId;

  /// Whether the service is currently authenticated with AdGuard Home.
  bool get isAuthenticated;

  /// Whether the last probe or request indicated authentication is required.
  bool get isAuthRequired;

  /// Active credentials currently held in memory for this session.
  AdGuardCredentials? get activeCredentials;

  /// Updates or clears active in-memory credentials.
  void setCredentials(AdGuardCredentials? credentials);

  /// Tests connectivity and authentication against the AdGuard Home instance.
  Future<AdGuardConnectionStatus> testConnection({
    AdGuardCredentials? credentials,
  });

  /// Probes or retrieves status from `GET /control/status`.
  ///
  /// Flow:
  /// 1. If [forceProbe] is true or active credentials are absent, probes without credentials.
  /// 2. If 200 OK + valid payload -> authentication not required.
  /// 3. If 401 -> attempts stored router-scoped credentials (`agh_creds_${router.id}`).
  /// 4. If stored credentials absent or rejected:
  ///    - If [allowFallbackToRouterCredentials] is true and [routerCredentials] provided,
  ///      retries with router credentials.
  ///    - Otherwise, returns [AdGuardApiResult.authRequired].
  Future<AdGuardApiResult<AdGuardStatus>> getStatus({
    bool forceProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  });

  /// Retrieves DNS statistics from `GET /control/stats`.
  ///
  /// If [recent] is provided, attempts query with `?recent=ms`. If the server returns
  /// 400 Bad Request (unsupported in older versions), automatically retries without the parameter.
  Future<AdGuardApiResult<AdGuardStats>> getStats({Duration? recent});

  /// Retrieves filtering status and rules from `GET /control/filtering/status`.
  Future<AdGuardApiResult<AdGuardFilteringStatus>> getFilteringStatus();

  /// Toggles or pauses protection via `POST /control/protection`.
  Future<AdGuardApiResult<bool>> setProtection({
    required bool enabled,
    Duration? duration,
  });

  /// Helper method applying Phase 2.1 [AdGuardProtectionState] tri-state semantics.
  Future<AdGuardApiResult<bool>> setProtectionState(
    AdGuardProtectionState state, {
    Duration? pauseDuration,
  });

  /// Sets custom filtering user rules via `POST /control/filtering/set_rules`.
  Future<AdGuardApiResult<bool>> setUserRules(List<String> rules);

  /// Retrieves configured clients from `GET /control/clients`.
  Future<AdGuardApiResult<List<AdGuardClient>>> getClients();

  /// Adds a new configured client via `POST /control/clients/add`.
  Future<AdGuardApiResult<bool>> addClient(AdGuardClient client);

  /// Updates an existing configured client via `POST /control/clients/update`.
  Future<AdGuardApiResult<bool>> updateClient(
    String oldName,
    AdGuardClient client,
  );

  /// Retrieves configured upstream DNS servers from `GET /control/dns_info`.
  Future<AdGuardApiResult<List<String>>> getUpstreamDns();

  /// Adds a new filter subscription or allowlist via `POST /control/filtering/add_url`.
  Future<AdGuardApiResult<bool>> addFilterList({
    required String name,
    required String url,
    required bool whitelist,
  });

  /// Updates an existing filter list via `POST /control/filtering/set_url`.
  Future<AdGuardApiResult<bool>> setFilterList({
    required String url,
    required String name,
    required String newUrl,
    required bool enabled,
    required bool whitelist,
  });

  /// Removes an existing filter subscription or allowlist via `POST /control/filtering/remove_url`.
  Future<AdGuardApiResult<bool>> removeFilterList({
    required String url,
    required bool whitelist,
  });

  /// Triggers a manual update of filtering subscriptions via `POST /control/filtering/refresh`.
  Future<AdGuardApiResult<bool>> refreshFilterLists({bool? whitelist});
}

/// Production implementation of [IAdGuardApiService] using [HttpClientManager].
///
/// Features:
/// - Preemptive HTTP Basic Authentication via per-request `Authorization` headers.
/// - Never mutates shared Dio default headers or connection pools.
/// - AdGuard HTTP 401 errors are strictly isolated and never trigger router session renewal.
/// - Strict 5-second per-request timeout with explicit deadline handling.
/// - Defensive multi-version payload and schema validation.
/// - Router-scoped credential persistence via `SecureStorageService`.
class AdGuardApiService implements IAdGuardApiService {
  @override
  final String routerId;
  final String? _instanceId;

  @override
  String get instanceId => _instanceId ?? routerId;

  final String host;
  final int port;
  final bool useHttps;
  final HttpClientManager httpClientManager;
  final SecureStorageService? secureStorageService;
  final Dio? dioOverride;

  AdGuardCredentials? _activeCredentials;
  bool _isAuthenticated = false;
  bool _isAuthRequired = false;

  AdGuardApiService({
    required this.routerId,
    String? instanceId,
    required this.host,
    this.port = 3000,
    this.useHttps = false,
    HttpClientManager? httpClientManager,
    this.secureStorageService,
    this.dioOverride,
  }) : _instanceId = instanceId,
       httpClientManager = httpClientManager ?? HttpClientManager();

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
      _isAuthRequired = false;
    }
  }

  /// Formats host and port, enclosing IPv6 addresses in brackets if needed.
  String get hostWithPort {
    if (host.startsWith('[')) {
      return '$host:$port';
    } else if (host.contains(':')) {
      return '[$host]:$port';
    } else {
      return '$host:$port';
    }
  }

  /// Base URL for AdGuard Home REST API endpoints.
  String get baseUrl => '${useHttps ? "https" : "http"}://$hostWithPort';

  Dio get _dio =>
      dioOverride ?? httpClientManager.getClient(hostWithPort, useHttps);

  /// Key for instance-scoped credential storage.
  String get storageCredsKey => 'agh_creds_$instanceId';

  /// Whether this instance represents the local router AdGuard Home service.
  bool get isCanonicalLocal =>
      instanceId == 'local_$routerId' || instanceId == routerId;

  /// Reads stored AdGuard credentials from SecureStorage for this instance.
  Future<AdGuardCredentials?> getStoredCredentials() async {
    if (secureStorageService == null) return null;
    try {
      final raw = await secureStorageService!.readValue(storageCredsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return AdGuardCredentials.fromJson(decoded);
        }
      }
    } catch (e, stack) {
      Logger.error(
        'Failed to read stored AdGuard credentials for instance $instanceId',
        e,
        stack,
      );
    }
    return null;
  }

  /// Persists AdGuard credentials for this instance in SecureStorage.
  Future<void> saveStoredCredentials(AdGuardCredentials creds) async {
    if (secureStorageService == null) return;
    try {
      await secureStorageService!.writeValue(
        storageCredsKey,
        jsonEncode(creds.toJson()),
      );
    } catch (e, stack) {
      Logger.error(
        'Failed to save AdGuard credentials for instance $instanceId',
        e,
        stack,
      );
      rethrow;
    }
  }

  /// Removes stored AdGuard credentials for this instance from SecureStorage.
  Future<void> clearStoredCredentials() async {
    if (secureStorageService == null) return;
    try {
      await secureStorageService!.deleteValue(storageCredsKey);
    } catch (e, stack) {
      Logger.error(
        'Failed to clear AdGuard credentials for instance $instanceId',
        e,
        stack,
      );
    }
  }

  @override
  Future<AdGuardConnectionStatus> testConnection({
    AdGuardCredentials? credentials,
  }) async {
    try {
      final credsToUse =
          credentials ?? _activeCredentials ?? await getStoredCredentials();
      final headers = <String, dynamic>{};
      if (credsToUse != null) {
        headers['Authorization'] = credsToUse.toBasicAuthHeader();
      }
      final response = await _dio.get(
        '$baseUrl/control/status',
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode != null &&
          response.statusCode! >= 300 &&
          response.statusCode! < 400) {
        return AdGuardConnectionStatus.invalidEndpoint;
      }

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> &&
            AdGuardStatus.isValidStatusPayload(data)) {
          return AdGuardConnectionStatus.authenticated;
        } else if (data is String) {
          try {
            final parsed = jsonDecode(data);
            if (parsed is Map<String, dynamic> &&
                AdGuardStatus.isValidStatusPayload(parsed)) {
              return AdGuardConnectionStatus.authenticated;
            }
          } catch (_) {}
          return AdGuardConnectionStatus.invalidEndpoint;
        }
        return AdGuardConnectionStatus.invalidEndpoint;
      } else if (response.statusCode == 401) {
        return AdGuardConnectionStatus.authRequired;
      } else {
        return AdGuardConnectionStatus.invalidEndpoint;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return AdGuardConnectionStatus.authRequired;
      }
      if (e.response?.statusCode != null &&
          e.response!.statusCode! >= 300 &&
          e.response!.statusCode! < 400) {
        return AdGuardConnectionStatus.invalidEndpoint;
      }
      return AdGuardConnectionStatus.apiUnreachable;
    } catch (_) {
      return AdGuardConnectionStatus.apiUnreachable;
    }
  }

  /// Executes an HTTP request with per-request Basic Auth and strict 5s timeout.
  Future<Response<dynamic>> _executeRequest({
    required String path,
    String method = 'GET',
    dynamic data,
    Map<String, dynamic>? queryParameters,
    AdGuardCredentials? credentials,
    bool skipAuth = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final uri = '$baseUrl$path';
    final headers = <String, String>{'Accept': 'application/json'};
    if (data != null) {
      headers['Content-Type'] = 'application/json';
    }

    if (!skipAuth) {
      final creds =
          credentials ?? _activeCredentials ?? await getStoredCredentials();
      if (creds != null) {
        _activeCredentials ??= creds;
        headers['Authorization'] = creds.toBasicAuthHeader();
      }
    }

    final options = Options(
      method: method,
      headers: headers,
      sendTimeout: timeout,
      receiveTimeout: timeout,
      followRedirects: false,
      validateStatus: (status) => true,
    );

    try {
      return await _dio
          .request(
            uri,
            data: data,
            queryParameters: queryParameters,
            options: options,
          )
          .timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              'AdGuard Home request to $path timed out after ${timeout.inSeconds}s',
            ),
          );
    } on TimeoutException catch (e) {
      throw AdGuardApiException(
        type: AdGuardApiErrorType.timeout,
        message: 'Request timed out: $e',
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw AdGuardApiException(
          type: AdGuardApiErrorType.timeout,
          message: 'HTTP timeout communicating with AdGuard Home',
          underlyingError: e,
        );
      }
      if (e.type == DioExceptionType.connectionError ||
          e.error is SocketException) {
        throw AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Network connection failure communicating with AdGuard Home',
          underlyingError: e,
        );
      }
      throw AdGuardApiException(
        type: AdGuardApiErrorType.networkFailure,
        message: 'Network error communicating with AdGuard Home: ${e.message}',
        underlyingError: e,
      );
    } catch (e) {
      if (e is AdGuardApiException) rethrow;
      throw AdGuardApiException(
        type: AdGuardApiErrorType.unknown,
        message: 'Unexpected error communicating with AdGuard Home: $e',
        underlyingError: e,
      );
    }
  }

  Map<String, dynamic>? _parseJsonObject(dynamic rawData) {
    if (rawData == null) return null;
    if (rawData is Map<String, dynamic>) return rawData;
    if (rawData is Map) {
      return rawData.map((k, v) => MapEntry(k.toString(), v));
    }
    if (rawData is String) {
      final trimmed = rawData.trim();
      if (trimmed.isEmpty) return null;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (e) {
        throw AdGuardApiException(
          type: AdGuardApiErrorType.malformedJson,
          message: 'Malformed JSON payload from server',
          underlyingError: e,
        );
      }
    }
    return null;
  }

  Duration? _parseRetryAfter(Headers headers) {
    final raw = headers.value('retry-after');
    if (raw == null || raw.trim().isEmpty) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }
    try {
      final date = HttpDate.parse(raw.trim());
      final diff = date.difference(DateTime.now());
      if (diff.isNegative) return Duration.zero;
      return diff;
    } catch (_) {
      return null;
    }
  }

  AdGuardApiException _buildHttpException(Response response, String endpoint) {
    final statusCode = response.statusCode;
    final retryAfter = _parseRetryAfter(response.headers);
    if (statusCode == 429) {
      return AdGuardApiException(
        type: AdGuardApiErrorType.rateLimited,
        statusCode: 429,
        retryAfter: retryAfter,
        message: 'Rate limit exceeded (HTTP 429) for $endpoint',
      );
    }
    if (statusCode == 503) {
      return AdGuardApiException(
        type: AdGuardApiErrorType.serviceUnavailable,
        statusCode: 503,
        retryAfter: retryAfter,
        message: 'Service unavailable (HTTP 503) for $endpoint',
      );
    }
    return AdGuardApiException(
      type: AdGuardApiErrorType.httpError,
      statusCode: statusCode,
      retryAfter: retryAfter,
      message: 'HTTP error $statusCode from $endpoint',
    );
  }

  @override
  Future<AdGuardApiResult<AdGuardStatus>> getStatus({
    bool forceProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  }) async {
    try {
      // 1. If not forcing an unauthenticated probe and active credentials exist, try them directly
      if (!forceProbe && _activeCredentials != null) {
        final res = await _executeRequest(
          path: '/control/status',
          credentials: _activeCredentials,
        );
        if (res.statusCode == 200) {
          final payload = _parseJsonObject(res.data);
          if (AdGuardStatus.isValidStatusPayload(payload)) {
            _isAuthenticated = true;
            _isAuthRequired = false;
            return AdGuardApiResult.success(AdGuardStatus.fromJson(payload!));
          } else {
            _isAuthenticated = false;
            return AdGuardApiResult.failure(
              const AdGuardApiException(
                type: AdGuardApiErrorType.invalidPayload,
                statusCode: 200,
                message:
                    'Endpoint returned 200 OK but payload is not genuine AdGuard Home status',
              ),
            );
          }
        } else if (res.statusCode == 401) {
          // Active credentials were rejected
          _activeCredentials = null;
          _isAuthenticated = false;
          _isAuthRequired = true;
          return AdGuardApiResult.authRequired(
            'AdGuard Home credentials rejected (HTTP 401)',
          );
        } else {
          return AdGuardApiResult.failure(
            _buildHttpException(res, '/control/status'),
          );
        }
      }

      // 2. Unauthenticated probe: query /control/status without credentials
      final probeRes = await _executeRequest(
        path: '/control/status',
        skipAuth: true,
      );

      // 3. 200 OK + valid AdGuard payload -> instance has no authentication required
      if (probeRes.statusCode == 200) {
        final payload = _parseJsonObject(probeRes.data);
        if (AdGuardStatus.isValidStatusPayload(payload)) {
          _isAuthenticated = true;
          _isAuthRequired = false;
          return AdGuardApiResult.success(AdGuardStatus.fromJson(payload!));
        } else {
          _isAuthenticated = false;
          return AdGuardApiResult.failure(
            const AdGuardApiException(
              type: AdGuardApiErrorType.invalidPayload,
              statusCode: 200,
              message:
                  'Endpoint returned 200 OK but payload is not genuine AdGuard Home status',
            ),
          );
        }
      }

      // 4. HTTP 401 Unauthorized -> probe indicates authentication is required
      if (probeRes.statusCode == 401) {
        _isAuthRequired = true;
        _isAuthenticated = false;

        // Retrieve stored credentials for this specific router
        AdGuardCredentials? creds = await getStoredCredentials();

        // Router root credentials are ONLY tried if caller explicitly opted in AND
        // this service is for the canonical local router instance. External profiles
        // MUST NEVER inherit or attempt router credentials.
        if (creds == null &&
            allowFallbackToRouterCredentials &&
            isCanonicalLocal &&
            routerCredentials != null) {
          creds = routerCredentials;
        }

        if (creds != null) {
          final authRes = await _executeRequest(
            path: '/control/status',
            credentials: creds,
          );

          if (authRes.statusCode == 200) {
            final payload = _parseJsonObject(authRes.data);
            if (AdGuardStatus.isValidStatusPayload(payload)) {
              _activeCredentials = creds;
              _isAuthenticated = true;
              _isAuthRequired = false;
              return AdGuardApiResult.success(AdGuardStatus.fromJson(payload!));
            } else {
              return AdGuardApiResult.failure(
                const AdGuardApiException(
                  type: AdGuardApiErrorType.invalidPayload,
                  statusCode: 200,
                  message:
                      'Endpoint returned 200 OK but payload is not genuine AdGuard Home status',
                ),
              );
            }
          } else if (authRes.statusCode == 401) {
            _activeCredentials = null;
            _isAuthenticated = false;
            _isAuthRequired = true;
            return AdGuardApiResult.authRequired(
              'Stored AdGuard Home credentials rejected (HTTP 401)',
            );
          } else {
            return AdGuardApiResult.failure(
              _buildHttpException(authRes, '/control/status'),
            );
          }
        }

        // Stored credentials absent or rejected
        return AdGuardApiResult.authRequired(
          'AdGuard Home requires authentication',
        );
      }

      // Other HTTP error during probe
      return AdGuardApiResult.failure(
        _buildHttpException(probeRes, '/control/status'),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in getStatus()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Unexpected error in getStatus(): $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<AdGuardStats>> getStats({Duration? recent}) async {
    try {
      Response<dynamic> response;
      if (recent != null) {
        response = await _executeRequest(
          path: '/control/stats',
          queryParameters: {'recent': recent.inMilliseconds},
        );
        // If server returns 400 (older version rejects recent), retry without parameter
        if (response.statusCode == 400) {
          Logger.info(
            'AdGuard Home rejected recent query parameter (HTTP 400); retrying without recent',
          );
          response = await _executeRequest(path: '/control/stats');
        }
      } else {
        response = await _executeRequest(path: '/control/stats');
      }

      if (response.statusCode == 200) {
        final payload = _parseJsonObject(response.data);
        if (payload == null) {
          return AdGuardApiResult.failure(
            const AdGuardApiException(
              type: AdGuardApiErrorType.malformedJson,
              message: 'Failed to parse JSON map from /control/stats response',
            ),
          );
        }
        final stats = AdGuardStats.fromJson(payload);
        return AdGuardApiResult.success(stats);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for stats (HTTP 401)',
        );
      }

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message: 'HTTP error ${response.statusCode} from /control/stats',
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in getStats()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to retrieve stats: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<AdGuardFilteringStatus>> getFilteringStatus() async {
    try {
      final response = await _executeRequest(path: '/control/filtering/status');

      if (response.statusCode == 200) {
        final payload = _parseJsonObject(response.data);
        if (payload == null) {
          return AdGuardApiResult.failure(
            const AdGuardApiException(
              type: AdGuardApiErrorType.malformedJson,
              message:
                  'Failed to parse JSON map from /control/filtering/status response',
            ),
          );
        }
        final filtering = AdGuardFilteringStatus.fromJson(payload);
        return AdGuardApiResult.success(filtering);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for filtering status (HTTP 401)',
        );
      }

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message:
              'HTTP error ${response.statusCode} from /control/filtering/status',
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in getFilteringStatus()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to retrieve filtering status: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<bool>> setProtection({
    required bool enabled,
    Duration? duration,
  }) async {
    try {
      final Map<String, dynamic> body = {'enabled': enabled};
      if (!enabled) {
        final durationMs = duration?.inMilliseconds ?? 0;
        body['duration'] = durationMs > 0 ? durationMs : 0;
      }

      final response = await _executeRequest(
        path: '/control/protection',
        method: 'POST',
        data: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return AdGuardApiResult.success(true);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for protection mutation (HTTP 401)',
        );
      }

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message: 'HTTP error ${response.statusCode} from /control/protection',
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in setProtection()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to set protection: $e',
          underlyingError: e,
        ),
      );
    }
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
    try {
      final response = await _executeRequest(
        path: '/control/filtering/set_rules',
        method: 'POST',
        data: {'rules': rules},
      );

      if (response.statusCode == 200) {
        return AdGuardApiResult.success(true);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for updating rules (HTTP 401)',
        );
      }

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message:
              'HTTP error ${response.statusCode} from /control/filtering/set_rules',
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in setUserRules()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to set user rules: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<List<AdGuardClient>>> getClients() async {
    try {
      final response = await _executeRequest(path: '/control/clients');

      if (response.statusCode == 200) {
        final payload = _parseJsonObject(response.data);
        final rawClients = payload?['clients'];
        final clients = <AdGuardClient>[];
        if (rawClients is List) {
          for (final c in rawClients) {
            if (c is Map<String, dynamic>) {
              clients.add(AdGuardClient.fromJson(c));
            } else if (c is Map) {
              clients.add(
                AdGuardClient.fromJson(
                  c.map((k, v) => MapEntry(k.toString(), v)),
                ),
              );
            }
          }
        }
        return AdGuardApiResult.success(clients);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for clients list (HTTP 401)',
        );
      }

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message: 'HTTP error ${response.statusCode} from /control/clients',
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in getClients()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to retrieve clients: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<bool>> addClient(AdGuardClient client) async {
    try {
      final response = await _executeRequest(
        path: '/control/clients/add',
        method: 'POST',
        data: client.toJson(),
      );

      if (response.statusCode == 200) {
        return AdGuardApiResult.success(true);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for adding client (HTTP 401)',
        );
      }

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message:
              'HTTP error ${response.statusCode} from /control/clients/add',
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in addClient()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to add client: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<bool>> updateClient(
    String oldName,
    AdGuardClient client,
  ) async {
    try {
      final response = await _executeRequest(
        path: '/control/clients/update',
        method: 'POST',
        data: {'name': oldName, 'data': client.toJson()},
      );

      if (response.statusCode == 200) {
        return AdGuardApiResult.success(true);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for updating client (HTTP 401)',
        );
      }

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message:
              'HTTP error ${response.statusCode} from /control/clients/update',
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in updateClient()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to update client: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<List<String>>> getUpstreamDns() async {
    try {
      final response = await _executeRequest(
        path: '/control/dns_info',
        method: 'GET',
      );

      if (response.statusCode == 200) {
        if (response.data is Map) {
          final map = response.data as Map;
          final rawUpstreams = map['upstream_dns'];
          final upstreams = <String>[];
          if (rawUpstreams is List) {
            for (final u in rawUpstreams) {
              if (u != null) {
                final s = u.toString().trim();
                if (s.isNotEmpty) upstreams.add(s);
              }
            }
          }
          return AdGuardApiResult.success(List.unmodifiable(upstreams));
        }
        return AdGuardApiResult.success(const []);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for DNS info (HTTP 401)',
        );
      }

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message: 'HTTP error ${response.statusCode} from /control/dns_info',
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in getUpstreamDns()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to retrieve upstream DNS: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<bool>> addFilterList({
    required String name,
    required String url,
    required bool whitelist,
  }) async {
    try {
      final response = await _executeRequest(
        path: '/control/filtering/add_url',
        method: 'POST',
        data: {'name': name.trim(), 'url': url.trim(), 'whitelist': whitelist},
      );

      if (response.statusCode == 200) {
        return AdGuardApiResult.success(true);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for adding filter list (HTTP 401)',
        );
      }

      final errorMsg = response.data is String
          ? response.data.toString()
          : (response.data is Map &&
                    (response.data as Map).containsKey('message')
                ? (response.data as Map)['message'].toString()
                : 'HTTP error ${response.statusCode} from /control/filtering/add_url');

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message: errorMsg,
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in addFilterList()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to add filter list: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<bool>> setFilterList({
    required String url,
    required String name,
    required String newUrl,
    required bool enabled,
    required bool whitelist,
  }) async {
    try {
      final response = await _executeRequest(
        path: '/control/filtering/set_url',
        method: 'POST',
        data: {
          'url': url.trim(),
          'data': {
            'name': name.trim(),
            'url': newUrl.trim(),
            'enabled': enabled,
          },
          'whitelist': whitelist,
        },
      );

      if (response.statusCode == 200) {
        return AdGuardApiResult.success(true);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for setting filter list (HTTP 401)',
        );
      }

      final errorMsg = response.data is String
          ? response.data.toString()
          : (response.data is Map &&
                    (response.data as Map).containsKey('message')
                ? (response.data as Map)['message'].toString()
                : 'HTTP error ${response.statusCode} from /control/filtering/set_url');

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message: errorMsg,
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in setFilterList()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to set filter list: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<bool>> removeFilterList({
    required String url,
    required bool whitelist,
  }) async {
    try {
      final response = await _executeRequest(
        path: '/control/filtering/remove_url',
        method: 'POST',
        data: {'url': url.trim(), 'whitelist': whitelist},
      );

      if (response.statusCode == 200) {
        return AdGuardApiResult.success(true);
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        _isAuthRequired = true;
        return AdGuardApiResult.authRequired(
          'AdGuard Home authentication required for removing filter list (HTTP 401)',
        );
      }

      final errorMsg = response.data is String
          ? response.data.toString()
          : (response.data is Map &&
                    (response.data as Map).containsKey('message')
                ? (response.data as Map)['message'].toString()
                : 'HTTP error ${response.statusCode} from /control/filtering/remove_url');

      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.httpError,
          statusCode: response.statusCode,
          message: errorMsg,
        ),
      );
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in removeFilterList()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to remove filter list: $e',
          underlyingError: e,
        ),
      );
    }
  }

  @override
  Future<AdGuardApiResult<bool>> refreshFilterLists({bool? whitelist}) async {
    try {
      if (whitelist != null) {
        final response = await _executeRequest(
          path: '/control/filtering/refresh',
          method: 'POST',
          data: {'whitelist': whitelist},
        );

        if (response.statusCode == 200) {
          return AdGuardApiResult.success(true);
        }

        if (response.statusCode == 401) {
          _isAuthenticated = false;
          _isAuthRequired = true;
          return AdGuardApiResult.authRequired(
            'AdGuard Home authentication required for refreshing filter lists (HTTP 401)',
          );
        }

        final errorMsg = response.data is String
            ? response.data.toString()
            : (response.data is Map &&
                      (response.data as Map).containsKey('message')
                  ? (response.data as Map)['message'].toString()
                  : 'HTTP error ${response.statusCode} from /control/filtering/refresh');

        return AdGuardApiResult.failure(
          AdGuardApiException(
            type: AdGuardApiErrorType.httpError,
            statusCode: response.statusCode,
            message: errorMsg,
          ),
        );
      } else {
        // Refresh blocklists first
        final respBlock = await _executeRequest(
          path: '/control/filtering/refresh',
          method: 'POST',
          data: {'whitelist': false},
        );
        if (respBlock.statusCode == 401) {
          _isAuthenticated = false;
          _isAuthRequired = true;
          return AdGuardApiResult.authRequired(
            'AdGuard Home authentication required for refreshing filter lists (HTTP 401)',
          );
        }
        if (respBlock.statusCode != 200) {
          final errorMsg = respBlock.data is String
              ? respBlock.data.toString()
              : (respBlock.data is Map &&
                        (respBlock.data as Map).containsKey('message')
                    ? (respBlock.data as Map)['message'].toString()
                    : 'HTTP error ${respBlock.statusCode} from /control/filtering/refresh');
          return AdGuardApiResult.failure(
            AdGuardApiException(
              type: AdGuardApiErrorType.httpError,
              statusCode: respBlock.statusCode,
              message: errorMsg,
            ),
          );
        }

        // Then refresh allowlists
        final respAllow = await _executeRequest(
          path: '/control/filtering/refresh',
          method: 'POST',
          data: {'whitelist': true},
        );
        if (respAllow.statusCode == 401) {
          _isAuthenticated = false;
          _isAuthRequired = true;
          return AdGuardApiResult.authRequired(
            'AdGuard Home authentication required for refreshing filter lists (HTTP 401)',
          );
        }
        if (respAllow.statusCode != 200) {
          final errorMsg = respAllow.data is String
              ? respAllow.data.toString()
              : (respAllow.data is Map &&
                        (respAllow.data as Map).containsKey('message')
                    ? (respAllow.data as Map)['message'].toString()
                    : 'HTTP error ${respAllow.statusCode} from /control/filtering/refresh');
          return AdGuardApiResult.failure(
            AdGuardApiException(
              type: AdGuardApiErrorType.httpError,
              statusCode: respAllow.statusCode,
              message: errorMsg,
            ),
          );
        }

        return AdGuardApiResult.success(true);
      }
    } on AdGuardApiException catch (e) {
      return AdGuardApiResult.failure(e);
    } catch (e, stack) {
      Logger.error('Unexpected error in refreshFilterLists()', e, stack);
      return AdGuardApiResult.failure(
        AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Failed to refresh filter lists: $e',
          underlyingError: e,
        ),
      );
    }
  }
}
