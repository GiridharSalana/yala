// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/services/mock_ssh_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Automated Temperature Handler SSH Fallback Tests', () {
    late MockSshService mockSsh;
    late AppState appState;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      mockSsh = MockSshService();
      appState = AppState.instance;
      appState.setSshServiceForTesting(mockSsh);
    });

    test('Falls back to SSH installation when HTTP RPC fails', () async {
      final router = Router(
        id: 'test_router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'test_password',
        useHttps: false,
      );
      await appState.routerService?.addRouter(router);
      await appState.routerService?.selectRouter(router.id);

      mockSsh.shouldSucceed = true;

      // Sysauth is null in this unauthenticated state, which simulates RPC unavailable/denied,
      // and triggers the SSH fallback branch directly.
      final success = await appState.installNativeTemperatureHandler();
      expect(success, isTrue);
    });

    test('Reports failure if SSH execution fails', () async {
      final router = Router(
        id: 'test_router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'test_password',
        useHttps: false,
      );
      await appState.routerService?.addRouter(router);
      await appState.routerService?.selectRouter(router.id);

      mockSsh.shouldSucceed = false;

      final success = await appState.installNativeTemperatureHandler();
      expect(success, isFalse);
    });
  });
}
