// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/ssh_service.dart';
import 'package:yet_another_luci_app/services/mock_ssh_service.dart';

void main() {
  group('MockSshService Tests', () {
    test('MockSshService returns successful result by default', () async {
      final mock = MockSshService();
      final res = await mock.executeCommand(
        host: '127.0.0.1',
        username: 'root',
        password: 'password',
        command: 'echo test',
      );

      expect(res.success, isTrue);
      expect(res.exitCode, equals(0));
      expect(res.stdout, equals('OK'));
      expect(res.errorMessage, isNull);
    });

    test('MockSshService handles failure mode', () async {
      final mock = MockSshService(
        shouldSucceed: false,
        mockExitCode: 1,
        mockError: 'Authentication failed',
      );
      final res = await mock.executeCommand(
        host: '127.0.0.1',
        username: 'root',
        password: 'wrong_password',
        command: 'echo test',
      );

      expect(res.success, isFalse);
      expect(res.exitCode, equals(1));
      expect(res.errorMessage, equals('Authentication failed'));
    });
  });

  group('RealSshService Network Integration (Test Router 192.168.1.1)', () {
    test(
      'Executes simple command on test router',
      () async {
        try {
          final socket = await Socket.connect(
            '192.168.1.1',
            22,
            timeout: const Duration(seconds: 2),
          );
          await socket.close();
        } catch (_) {
          // Router unreachable in current environment
          return;
        }

        final service = RealSshService();
        final password =
            Platform.environment['TEST_ROUTER_PASSWORD'] ?? 'Qwerty@1234';
        final res = await service.executeCommand(
          host: '192.168.1.1',
          username: 'root',
          password: password,
          command: 'echo "hello from dartssh2"',
        );

        expect(res.success, isTrue);
        expect(res.exitCode, equals(0));
        expect(res.stdout.trim(), equals('hello from dartssh2'));
      },
      skip: Platform.environment.containsKey('CI')
          ? 'Skipped on CI runners (requires local test router)'
          : false,
    );
  });
}
