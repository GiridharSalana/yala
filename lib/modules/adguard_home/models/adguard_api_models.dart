// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Stored or in-memory credentials for AdGuard Home HTTP Basic Authentication.
///
/// Preemptive HTTP Basic Auth is the authoritative authentication mechanism
/// for AdGuard Home REST API endpoints across all supported versions.
@immutable
class AdGuardCredentials {
  final String username;
  final String password;
  final bool useRouterCredentials;
  final DateTime? updatedAt;

  const AdGuardCredentials({
    required this.username,
    required this.password,
    this.useRouterCredentials = false,
    this.updatedAt,
  });

  /// Serializes credentials for storage in FlutterSecureStorage (`agh_creds_${router.id}`).
  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    'useRouterCredentials': useRouterCredentials,
    'updatedAt':
        updatedAt?.toIso8601String() ??
        DateTime.now().toUtc().toIso8601String(),
  };

  /// Deserializes credentials from JSON storage.
  factory AdGuardCredentials.fromJson(Map<String, dynamic> json) =>
      AdGuardCredentials(
        username: json['username']?.toString() ?? '',
        password: json['password']?.toString() ?? '',
        useRouterCredentials: json['useRouterCredentials'] == true,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'].toString())
            : null,
      );

  /// Generates the preemptive HTTP Basic Authentication header:
  /// `Basic <base64(username:password)>`.
  String toBasicAuthHeader() {
    final bytes = utf8.encode('$username:$password');
    return 'Basic ${base64Encode(bytes)}';
  }

  /// Explicitly redacts password from string representations to eliminate
  /// credential leakage in logs, diagnostics, and debug inspection.
  @override
  String toString() =>
      'AdGuardCredentials(username: $username, useRouterCredentials: $useRouterCredentials, password: [REDACTED])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdGuardCredentials &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          password == other.password &&
          useRouterCredentials == other.useRouterCredentials;

  @override
  int get hashCode => Object.hash(username, password, useRouterCredentials);
}

/// Router-scoped configuration parameters for AdGuard Home connection.
@immutable
class AdGuardConfig {
  final String? customHost;
  final int customPort;
  final bool useHttps;
  final int pollingIntervalSeconds;

  const AdGuardConfig({
    this.customHost,
    this.customPort = 3000,
    this.useHttps = false,
    this.pollingIntervalSeconds = 10,
  });

  Map<String, dynamic> toJson() => {
    'customHost': customHost,
    'customPort': customPort,
    'useHttps': useHttps,
    'pollingIntervalSeconds': pollingIntervalSeconds,
  };

  factory AdGuardConfig.fromJson(Map<String, dynamic> json) => AdGuardConfig(
    customHost: json['customHost']?.toString(),
    customPort: (json['customPort'] as num?)?.toInt() ?? 3000,
    useHttps: json['useHttps'] == true,
    pollingIntervalSeconds:
        (json['pollingIntervalSeconds'] as num?)?.toInt() ?? 10,
  );

  @override
  String toString() =>
      'AdGuardConfig(customHost: $customHost, customPort: $customPort, useHttps: $useHttps, pollingIntervalSeconds: $pollingIntervalSeconds)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdGuardConfig &&
          runtimeType == other.runtimeType &&
          customHost == other.customHost &&
          customPort == other.customPort &&
          useHttps == other.useHttps &&
          pollingIntervalSeconds == other.pollingIntervalSeconds;

  @override
  int get hashCode =>
      Object.hash(customHost, customPort, useHttps, pollingIntervalSeconds);
}

/// Categories of AdGuard Home API errors.
enum AdGuardApiErrorType {
  /// Socket error, DNS resolution failure, or connection refused.
  networkFailure,

  /// Request deadline or connection timeout expired.
  timeout,

  /// HTTP 401 Unauthorized — AdGuard requires credentials or rejected provided credentials.
  authRequired,

  /// Other HTTP status errors (e.g. 404, 500, 502).
  httpError,

  /// Server returned HTTP 200 but response is not genuine AdGuard Home data.
  invalidPayload,

  /// Unparseable JSON or schema incompatibility.
  malformedJson,

  /// Endpoint or parameter not supported by daemon version.
  unsupportedEndpoint,

  /// HTTP 429 Too Many Requests — server rate limit exceeded.
  rateLimited,

  /// HTTP 503 Service Unavailable — server temporarily overloaded.
  serviceUnavailable,

  /// General / unexpected error.
  unknown,
}

/// An AdGuard Home specific API exception that strictly redacts credentials.
class AdGuardApiException implements Exception {
  final AdGuardApiErrorType type;
  final String message;
  final int? statusCode;
  final dynamic underlyingError;
  final Duration? retryAfter;

  const AdGuardApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.underlyingError,
    this.retryAfter,
  });

  @override
  String toString() =>
      'AdGuardApiException(type: $type, statusCode: $statusCode, retryAfter: $retryAfter, message: $message)';
}

/// Generic outcome wrapper for AdGuard Home API operations.
@immutable
class AdGuardApiResult<T> {
  final T? data;
  final AdGuardApiException? error;
  final bool isSuccess;

  const AdGuardApiResult._({this.data, this.error, required this.isSuccess});

  /// Creates a successful API result containing [data].
  factory AdGuardApiResult.success(T data) =>
      AdGuardApiResult._(data: data, isSuccess: true);

  /// Creates a failed API result containing [error].
  factory AdGuardApiResult.failure(AdGuardApiException error) =>
      AdGuardApiResult._(error: error, isSuccess: false);

  /// Helper factory for HTTP 401 authentication required.
  factory AdGuardApiResult.authRequired([
    String message = 'AdGuard Home authentication required',
  ]) => AdGuardApiResult._(
    error: AdGuardApiException(
      type: AdGuardApiErrorType.authRequired,
      statusCode: 401,
      message: message,
    ),
    isSuccess: false,
  );

  /// Whether this result indicates authentication is required or rejected.
  bool get isAuthRequired => error?.type == AdGuardApiErrorType.authRequired;

  /// Retrieves the successful data, or throws the underlying [AdGuardApiException].
  T get requireData {
    if (isSuccess && data != null) return data!;
    throw error ??
        const AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Operation failed without error detail',
        );
  }
}
