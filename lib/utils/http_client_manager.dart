// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'logger.dart';
import 'sha256.dart';

/// HTTP client manager that provides secure client instances with proper
/// certificate validation and connection pooling
class HttpClientManager {
  static final HttpClientManager _instance = HttpClientManager._internal();
  factory HttpClientManager() => _instance;
  Future<void>? _initFuture;

  /// Ensures accepted certificates are fully loaded from secure storage before network calls
  Future<void> ensureInitialized() {
    _initFuture ??= _loadAcceptedCertificates();
    return _initFuture!;
  }

  HttpClientManager._internal() {
    ensureInitialized();
  }

  final Map<String, Dio> _clients = {};

  /// Maps canonical 'host:port' key → accepted SHA-256 fingerprint (hex).
  ///
  /// On every TLS connection the presented certificate's fingerprint is compared
  /// to the stored fingerprint. A mismatch requires a new explicit user decision.
  final Map<String, String> _acceptedCertFingerprints = {};

  static const String _acceptedCertsKey = 'accepted_certificates';

  /// Canonical client cache key: `hostWithPort-useHttps`
  String _cacheKey(String hostWithPort, bool useHttps) =>
      '$hostWithPort-$useHttps';

  /// Creates or returns a cached HTTP client for the given host
  /// In production builds, certificate validation is enforced with user warnings
  /// In debug builds, self-signed certificates can be allowed automatically
  Dio getClient(String hostWithPort, bool useHttps, {BuildContext? context}) {
    final key = _cacheKey(hostWithPort, useHttps);
    if (_clients.containsKey(key)) {
      return _clients[key]!;
    }

    // Extract just the hostname without port for certificate validation
    final host = _extractHostname(hostWithPort);
    final client = _createSecureClient(
      host,
      hostWithPort,
      useHttps,
      context: context,
    );
    _clients[key] = client;
    return client;
  }

  String _extractHostname(String hostWithPort) {
    // Remove port if present (handles both IPv4 and IPv6)
    if (hostWithPort.startsWith('[')) {
      // IPv6 address
      final endBracket = hostWithPort.indexOf(']');
      if (endBracket != -1) {
        return hostWithPort.substring(0, endBracket + 1);
      }
    } else {
      // IPv4 or hostname
      final colonIndex = hostWithPort.lastIndexOf(':');
      if (colonIndex != -1) {
        // Check if what follows the colon is a port number
        final portPart = hostWithPort.substring(colonIndex + 1);
        if (int.tryParse(portPart) != null) {
          return hostWithPort.substring(0, colonIndex);
        }
      }
    }
    return hostWithPort;
  }

  /// Extract port from a hostWithPort string. Defaults to 443.
  int _extractPort(String hostWithPort) {
    if (hostWithPort.startsWith('[')) {
      // IPv6: [addr]:port
      final closeBracket = hostWithPort.indexOf(']');
      if (closeBracket != -1 && closeBracket + 1 < hostWithPort.length) {
        final rest = hostWithPort.substring(closeBracket + 1);
        if (rest.startsWith(':')) {
          return int.tryParse(rest.substring(1)) ?? 443;
        }
      }
    } else {
      final colonIndex = hostWithPort.lastIndexOf(':');
      if (colonIndex != -1) {
        final portPart = hostWithPort.substring(colonIndex + 1);
        final port = int.tryParse(portPart);
        if (port != null) return port;
      }
    }
    return 443;
  }

  /// Compute the SHA-256 fingerprint of a certificate's DER bytes as a hex string.
  static String _certFingerprint(X509Certificate cert) {
    return Sha256.hex(cert.der);
  }

  Dio _createSecureClient(
    String host,
    String hostWithPort,
    bool useHttps, {
    BuildContext? context,
  }) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
        // Status is validated per request when needed (e.g., handle 302 on login)
      ),
    );

    // Automatically evict dead cached clients on socket/connection errors
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          Logger.error(
            'HTTP ${e.requestOptions.method} ${e.requestOptions.uri} failed',
            e,
            e.stackTrace,
          );

          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionError ||
              e.error is SocketException) {
            Logger.info(
              'Network transition or socket failure detected for $host. Evicting stale client.',
            );
            disposeClient(hostWithPort, useHttps, forceCloseAdapter: false);
          }

          handler.next(e);
        },
      ),
    );

    final adapter = IOHttpClientAdapter();
    adapter.createHttpClient = () {
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 15);
      httpClient.badCertificateCallback = (cert, certHost, port) {
        // Local/private router hosts bypass certificate validation.
        // Self-signed SSL certificates are standard on local OpenWrt routers.
        if (_isLocalOrPrivateHost(certHost) || _isLocalOrPrivateHost(host)) {
          return true;
        }

        final certKey = '$certHost:$port';
        final storedFingerprint = _acceptedCertFingerprints[certKey];
        if (storedFingerprint != null) {
          // Verify the presented certificate matches the previously accepted one.
          final presentedFingerprint = _certFingerprint(cert);
          if (presentedFingerprint == storedFingerprint) {
            return true;
          }
          // Certificate changed — require a new user decision. Evict stale acceptance.
          Logger.warning(
            'Certificate fingerprint mismatch for $certKey. '
            'Stored: $storedFingerprint, Presented: $presentedFingerprint',
          );
          _acceptedCertFingerprints.remove(certKey);
        }

        return false;
      };
      return httpClient;
    };
    dio.httpClientAdapter = adapter;

    return dio;
  }

  /// Helper to check if a hostname/IP belongs to private/local router networks
  static bool _isLocalOrPrivateHost(String host) {
    if (host.isEmpty) return false;
    var lowerHost = host.toLowerCase().trim();
    if (lowerHost.startsWith('[') && lowerHost.endsWith(']')) {
      lowerHost = lowerHost.substring(1, lowerHost.length - 1).trim();
    }

    // Check for localhost / local domains
    if (lowerHost == 'localhost' ||
        lowerHost == 'openwrt' ||
        lowerHost.endsWith('.local') ||
        lowerHost.endsWith('.lan')) {
      return true;
    }

    // Try parsing as IPv4
    try {
      final parts = host.split('.');
      if (parts.length == 4) {
        final octets = parts.map(int.tryParse).toList();
        if (octets.every((o) => o != null && o >= 0 && o <= 255)) {
          final o0 = octets[0]!;
          final o1 = octets[1]!;

          // 127.0.0.0/8 (Loopback)
          if (o0 == 127) return true;
          // 10.0.0.0/8 (Private Class A)
          if (o0 == 10) return true;
          // 172.16.0.0/12 (Private Class B)
          if (o0 == 172 && o1 >= 16 && o1 <= 31) return true;
          // 192.168.0.0/16 (Private Class C)
          if (o0 == 192 && o1 == 168) return true;
          // 169.254.0.0/16 (Link-Local)
          if (o0 == 169 && o1 == 254) return true;
        }
      }
    } catch (_) {}

    // Try parsing as IPv6 (link-local fe80::, unique local fc00::/fd00::, loopback ::1)
    if (host.contains(':')) {
      if (lowerHost == '::1' ||
          lowerHost.startsWith('fe80:') ||
          lowerHost.startsWith('fc00:') ||
          lowerHost.startsWith('fd00:')) {
        return true;
      }
    }

    return false;
  }

  /// Load accepted certificate fingerprints from secure storage.
  ///
  /// Backward-compat: entries with a boolean `true` value (old format, pre-fingerprint)
  /// are silently dropped so the user is re-prompted on next connection.
  Future<void> _loadAcceptedCertificates() async {
    try {
      const storage = FlutterSecureStorage();
      final certsJson = await storage.read(key: _acceptedCertsKey);
      if (certsJson != null) {
        final certs = Map<String, dynamic>.from(jsonDecode(certsJson));
        _acceptedCertFingerprints.clear();
        certs.forEach((key, value) {
          // Only load string fingerprints (new format).
          // Old boolean 'true' entries are discarded — user will be re-prompted.
          if (value is String && value.isNotEmpty) {
            _acceptedCertFingerprints[key] = value;
          }
        });
      }
    } catch (e) {
      Logger.warning('Error loading accepted certificate fingerprints: $e');
    }
  }

  /// Save accepted certificate fingerprints to secure storage
  Future<void> _saveAcceptedCertificates() async {
    try {
      const storage = FlutterSecureStorage();
      await storage.write(
        key: _acceptedCertsKey,
        value: jsonEncode(_acceptedCertFingerprints),
      );
    } catch (e) {
      Logger.warning('Error saving accepted certificate fingerprints: $e');
    }
  }

  /// Disposes of a specific cached HTTP client.
  ///
  /// Uses exact key matching — disposing `192.168.1.1` does NOT affect
  /// `192.168.1.10`, `192.168.1.100`, etc.
  void disposeClient(
    String hostWithPort,
    bool useHttps, {
    bool forceCloseAdapter = false,
  }) {
    final hostname = _extractHostname(hostWithPort);

    // Exact key match only. Keys are in the form '<hostWithPort>-<bool>' or
    // '<hostname>-<bool>' depending on how they were inserted.
    final exactKeys = [
      _cacheKey(hostWithPort, useHttps),
      _cacheKey(hostname, useHttps),
    ];

    final keysToRemove = _clients.keys
        .where((k) => exactKeys.contains(k))
        .toList();

    for (final key in keysToRemove) {
      final dio = _clients.remove(key);
      if (forceCloseAdapter) {
        final adapter = dio?.httpClientAdapter;
        if (adapter is IOHttpClientAdapter) {
          adapter.close(force: true);
        }
      }
    }
  }

  /// Disposes of all cached clients
  void disposeAll({bool forceCloseAdapter = false}) {
    for (final dio in _clients.values) {
      if (forceCloseAdapter) {
        final adapter = dio.httpClientAdapter;
        if (adapter is IOHttpClientAdapter) {
          adapter.close(force: true);
        }
      }
    }
    _clients.clear();
    // Don't clear accepted certificates on dispose
  }

  /// Clear accepted certificates (useful for logout or security reset)
  Future<void> clearAcceptedCertificates() async {
    // Clear in-memory certificates
    _acceptedCertFingerprints.clear();

    // Clear all cached HTTP clients
    disposeAll(forceCloseAdapter: true);

    // Delete from secure storage
    try {
      const storage = FlutterSecureStorage();
      await storage.delete(key: _acceptedCertsKey);
    } catch (e) {
      Logger.warning('Error clearing accepted certificates: $e');
    }
  }

  /// Clear certificates for a specific host.
  ///
  /// Uses exact key comparison — clearing `192.168.1.1` does NOT affect
  /// `192.168.1.10`, `192.168.1.100`, etc.
  Future<void> clearCertificatesForHost(String host) async {
    final hostname = _extractHostname(host);

    // Remove fingerprints for this exact host across all ports.
    // Matches 'host' exactly or 'host:port' (port-qualified entries).
    _acceptedCertFingerprints.removeWhere(
      (key, _) => key == hostname || key.startsWith('$hostname:'),
    );

    // Close and remove cached HTTP clients for this exact host.
    // Keys have the form '<hostWithPort>-<bool>'.
    final keysToRemove = _clients.keys.where((key) {
      // Split at the last '-' to get the cache suffix (-true / -false)
      final lastDash = key.lastIndexOf('-');
      if (lastDash == -1) return false;
      final keyHost = key.substring(0, lastDash);
      final keyHostname = _extractHostname(keyHost);
      return keyHostname == hostname;
    }).toList();

    for (final key in keysToRemove) {
      _clients[key]?.close();
      _clients.remove(key);
    }

    // Save the updated fingerprints
    await _saveAcceptedCertificates();
  }

  /// Prompts user to accept certificate for a given host.
  ///
  /// On acceptance, stores the SHA-256 fingerprint of the presented certificate
  /// so that subsequent connections verify the certificate hasn't changed.
  ///
  /// Returns true if user accepts, false otherwise.
  Future<bool> promptForCertificateAcceptance({
    required BuildContext context,
    required String hostWithPort,
    required bool useHttps,
  }) async {
    if (!useHttps) return true; // Non-HTTPS doesn't need certificate acceptance
    if (!context.mounted) return false;

    final host = _extractHostname(hostWithPort);
    final port = _extractPort(hostWithPort);

    final certKey = '$host:$port';

    // If already accepted and fingerprint is stored, allow.
    if (_acceptedCertFingerprints.containsKey(certKey)) return true;

    // Local/private router hosts bypass the dialog.
    if (_isLocalOrPrivateHost(host)) return true;

    // Try to make a test connection to trigger certificate validation
    final testClient = HttpClient();
    testClient.connectionTimeout = const Duration(seconds: 15);

    X509Certificate? presentedCert;
    String? presentedFingerprint;

    // Capture the certificate for display and fingerprinting.
    testClient.badCertificateCallback = (cert, certHost, certPort) {
      presentedCert = cert;
      presentedFingerprint = _certFingerprint(cert);
      return false; // Reject — we only want to capture, not allow automatically.
    };

    try {
      final uri = Uri.parse('https://$hostWithPort');
      final request = await testClient.getUrl(uri);
      await request.close();
      // If we reach here the cert was already valid (system-trusted) — allow.
      return true;
    } catch (e) {
      if (e is HandshakeException && presentedCert != null && context.mounted) {
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => CertificateWarningDialog(
            certificate: presentedCert!,
            fingerprint: presentedFingerprint ?? '',
            host: host,
            port: port,
          ),
        );

        if (result == true && presentedFingerprint != null) {
          // Bind acceptance to the specific certificate fingerprint.
          _acceptedCertFingerprints[certKey] = presentedFingerprint!;
          await _saveAcceptedCertificates();
          // Evict any stale cached client so the next getClient() call
          // creates a fresh one that will check the stored fingerprint.
          disposeClient(hostWithPort, useHttps, forceCloseAdapter: true);
          return true;
        }
      }
    } finally {
      testClient.close();
    }

    return false;
  }
}

/// Dialog for warning users about untrusted certificates.
///
/// Displays certificate details (subject, issuer, validity) and the SHA-256
/// fingerprint, allowing users to make an informed trust decision.
class CertificateWarningDialog extends StatelessWidget {
  final X509Certificate certificate;
  final String fingerprint;
  final String host;
  final int port;

  const CertificateWarningDialog({
    super.key,
    required this.certificate,
    required this.fingerprint,
    required this.host,
    required this.port,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      icon: Icon(
        Icons.warning_amber_rounded,
        color: colorScheme.error,
        size: 32,
      ),
      title: Text(l10n?.httpCertWarningTitle ?? 'Certificate Warning'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The certificate for $host:$port is not trusted by your device. This could indicate a security risk.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Certificate Details:',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCertDetail('Subject', certificate.subject),
                  _buildCertDetail('Issuer', certificate.issuer),
                  _buildCertDetail(
                    'Valid From',
                    certificate.startValidity.toLocal().toString().split(
                      '.',
                    )[0],
                  ),
                  _buildCertDetail(
                    'Valid Until',
                    certificate.endValidity.toLocal().toString().split('.')[0],
                  ),
                  if (fingerprint.isNotEmpty)
                    _buildCertDetail('SHA-256', fingerprint),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colorScheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Only proceed if you trust this router and understand the security implications.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: Text(l10n?.httpCertAcceptRisk ?? 'Accept Risk'),
        ),
      ],
    );
  }

  Widget _buildCertDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.geistMono(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
