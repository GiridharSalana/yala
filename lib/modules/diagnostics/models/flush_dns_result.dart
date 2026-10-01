// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class FlushDnsResult {
  final bool isSuccess;
  final List<String> flushedResolvers;
  final String message;
  final String? rawOutput;
  final DateTime timestamp;

  const FlushDnsResult({
    required this.isSuccess,
    required this.flushedResolvers,
    required this.message,
    this.rawOutput,
    required this.timestamp,
  });

  factory FlushDnsResult.success({
    required List<String> flushedResolvers,
    String? message,
    String? rawOutput,
  }) => FlushDnsResult(
    isSuccess: true,
    flushedResolvers: flushedResolvers,
    message:
        message ??
        'DNS cache flushed successfully for: ${flushedResolvers.join(", ")}',
    rawOutput: rawOutput,
    timestamp: DateTime.now(),
  );

  factory FlushDnsResult.failure(String error, {String? rawOutput}) =>
      FlushDnsResult(
        isSuccess: false,
        flushedResolvers: const [],
        message: error,
        rawOutput: rawOutput,
        timestamp: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
    'isSuccess': isSuccess,
    'flushedResolvers': flushedResolvers,
    'message': message,
    'rawOutput': rawOutput,
    'timestamp': timestamp.toIso8601String(),
  };

  factory FlushDnsResult.fromJson(Map<String, dynamic> json) => FlushDnsResult(
    isSuccess: json['isSuccess'] as bool? ?? false,
    flushedResolvers:
        (json['flushedResolvers'] as List?)?.whereType<String>().toList() ??
        const [],
    message: json['message'] as String? ?? '',
    rawOutput: json['rawOutput'] as String?,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
  );
}
