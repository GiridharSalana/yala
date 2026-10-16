// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

/// Provides test router credentials securely from local git-ignored config files
/// or environment variables, avoiding hardcoding sensitive credentials in source code.
class TestCredentials {
  static Map<String, dynamic>? _cached;

  static void _ensureLoaded() {
    if (_cached != null) return;
    _cached = {};

    final candidatePaths = [
      '.private/test_routers.json',
      '../.private/test_routers.json',
      '.test_credentials.json',
      'test_credentials.local.json',
    ];

    for (final path in candidatePaths) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          final content = file.readAsStringSync();
          final parsed = jsonDecode(content);
          if (parsed is Map<String, dynamic>) {
            _cached = parsed;
            return;
          }
        } catch (_) {}
      }
    }
  }

  static String? _getRouterField(String ip, String field) {
    _ensureLoaded();
    final list = _cached?['test_routers'];
    if (list is List) {
      for (final item in list) {
        if (item is Map && (item['ip'] == ip || item['ipAddress'] == ip)) {
          final val = item[field]?.toString();
          if (val != null && val.isNotEmpty) {
            return val;
          }
        }
      }
    }
    return null;
  }

  /// IP address for read-write test router (default: '192.168.1.1').
  static String get testRouterIp =>
      Platform.environment['TEST_ROUTER_IP'] ??
      _getRouterField('192.168.1.1', 'ip') ??
      '192.168.1.1';

  /// Username for read-write test router (default: 'root').
  static String get testRouterUsername =>
      Platform.environment['TEST_ROUTER_USER'] ??
      _getRouterField('192.168.1.1', 'username') ??
      'root';

  /// Password for read-write test router.
  /// Fetches from environment or local git-ignored config file, falling back
  /// to a safe dummy mock string.
  static String get testRouterPassword =>
      Platform.environment['TEST_ROUTER_PASSWORD'] ??
      _getRouterField('192.168.1.1', 'password') ??
      'mock_test_password';

  /// IP address for read-only production test router (default: '10.0.0.1').
  static String get prodRouterIp =>
      Platform.environment['PROD_ROUTER_IP'] ??
      _getRouterField('10.0.0.1', 'ip') ??
      '10.0.0.1';

  /// Username for read-only production test router (default: 'root').
  static String get prodRouterUsername =>
      Platform.environment['PROD_ROUTER_USER'] ??
      _getRouterField('10.0.0.1', 'username') ??
      'root';

  /// Password for read-only production test router.
  /// Fetches from environment or local git-ignored config file, falling back
  /// to a safe dummy mock string.
  static String get prodRouterPassword =>
      Platform.environment['PROD_ROUTER_PASSWORD'] ??
      _getRouterField('10.0.0.1', 'password') ??
      'mock_prod_password';
}
