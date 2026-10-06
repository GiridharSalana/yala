// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/throughput_service.dart';
import 'package:yet_another_luci_app/state/controllers/dashboard_controller.dart';
import 'package:yet_another_luci_app/state/controllers/throughput_controller.dart';

class SpyApiService implements IApiService {
  final List<String> recordedCalls = [];
  final List<String> executedCommands = [];

  @override
  Future<dynamic> call(
    String ip,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async {
    recordedCalls.add('$object.$method');
    if (object == 'file' && method == 'exec') {
      final cmd = params?['command']?.toString() ?? '';
      final args = (params?['params'] ?? params?['args'])?.toString() ?? '';
      executedCommands.add('$cmd $args');
    }

    if (object == 'session' && method == 'access') {
      return [
        0,
        {
          'ubus': {
            'file': ['read', 'write', 'list', 'remove', 'exec', 'stat'],
            'iwinfo': ['assoclist', 'countrylist', 'info'],
            'luci-rpc': ['getBoardJSON', 'getWirelessDevices'],
            'uci': ['get', 'set', 'commit'],
            'system': ['info', 'board', 'reboot'],
          },
          'uci': {
            'network': ['read', 'write'],
            'wireless': ['read', 'write'],
          },
        },
      ];
    }
    if (object == 'system' && method == 'board') {
      return [
        0,
        {
          'model': 'TestRouter',
          'board_name': 'test-board',
          'release': {'version': '24.10.0'},
        },
      ];
    }
    if (object == 'system' && method == 'info') {
      return [
        0,
        {
          'memory': {'total': 1000, 'free': 500},
        },
      ];
    }
    return [0, <String, dynamic>{}];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuthService implements IAuthService {
  @override
  String? get sysauth => 'valid_sysauth_token';

  @override
  bool get isAuthenticated => true;

  @override
  bool get useHttps => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'probeRouterCapabilities does not invoke silent permission modification',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final routerService = RouterService();
      final router = model.Router(
        id: 'test-router-id',
        name: 'Test Router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      );
      await routerService.addRouter(router);
      await routerService.selectRouter(router.id);

      final authService = TestAuthService();
      final apiService = SpyApiService();
      final secureStorageService = SecureStorageService();
      final throughputController = ThroughputController(
        throughputService: ThroughputService(),
      );

      final dashboardController = DashboardController(
        apiServiceRef: () => apiService,
        authServiceRef: () => authService,
        routerServiceRef: () => routerService,
        secureStorageServiceRef: () => secureStorageService,
        throughputControllerRef: () => throughputController,
        dashboardPreferencesRef: () => DashboardPreferences(),
        reviewerModeRef: () => false,
        tryAutoLogin:
            ({bool force = false, bool fetchDashboard = true}) async => true,
        fetchPublicIps: () async {},
        setPublicIps: (v4, v6) {},
        setConnectionStatus: (status) {},
        startThroughputTimer: () {},
        processDhcpLeases: (raw) => raw,
        notifyListeners: () {},
      );

      // Run probeRouterCapabilities
      final capabilities = await dashboardController.probeRouterCapabilities();

      // Verify capability probing succeeded with authoritative session.access
      expect(capabilities, isNotNull);
      expect(capabilities.isRpcComplete, isTrue);
      expect(capabilities.hasFileExec, isTrue);
      expect(capabilities.hasLuciRpc, isTrue);
      expect(capabilities.hasUciWriteAccess, isTrue);
      expect(capabilities.uciPermissions['network'], contains('write'));

      // Verify that NO call was made to write/create ACL files silently
      for (final cmd in apiService.executedCommands) {
        expect(
          cmd.contains('yet-another-luci-app.json'),
          isFalse,
          reason:
              'Capabilities probe must never write or touch yet-another-luci-app.json',
        );
        expect(
          cmd.contains('acl.d'),
          isFalse,
          reason: 'Capabilities probe must never modify rpcd ACLs',
        );
      }

      // Verify file.write was never called
      expect(apiService.recordedCalls.contains('file.write'), isFalse);
    },
  );
}
