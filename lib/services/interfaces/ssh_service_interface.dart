// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

abstract class ISshService {
  Future<SshCommandResult> executeCommand({
    required String host,
    required String username,
    required String password,
    required String command,
    int port = 22,
    Duration timeout = const Duration(seconds: 15),
  });
}

class SshCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool success;
  final String? errorMessage;

  const SshCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.success,
    this.errorMessage,
  });

  @override
  String toString() =>
      'SshCommandResult(exitCode: $exitCode, success: $success, stdout: $stdout, stderr: $stderr, error: $errorMessage)';
}
