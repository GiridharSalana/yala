// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'interfaces/ssh_service_interface.dart';

class MockSshService implements ISshService {
  bool shouldSucceed;
  int mockExitCode;
  String mockStdout;
  String mockStderr;
  String? mockError;

  MockSshService({
    this.shouldSucceed = true,
    this.mockExitCode = 0,
    this.mockStdout = 'OK',
    this.mockStderr = '',
    this.mockError,
  });

  @override
  Future<SshCommandResult> executeCommand({
    required String host,
    required String username,
    required String password,
    required String command,
    int port = 22,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!shouldSucceed) {
      return SshCommandResult(
        exitCode: mockExitCode != 0 ? mockExitCode : -1,
        stdout: mockStdout,
        stderr: mockStderr,
        success: false,
        errorMessage: mockError ?? 'Mock SSH connection failed',
      );
    }
    return SshCommandResult(
      exitCode: mockExitCode,
      stdout: mockStdout,
      stderr: mockStderr,
      success: mockExitCode == 0,
    );
  }
}
