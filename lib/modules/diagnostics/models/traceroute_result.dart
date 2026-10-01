// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class TracerouteHop {
  final int hopNumber;
  final String? host;
  final String? ip;
  final List<double> rttMs;
  final bool isTimeout;

  const TracerouteHop({
    required this.hopNumber,
    this.host,
    this.ip,
    this.rttMs = const [],
    this.isTimeout = false,
  });

  double? get avgRttMs {
    if (rttMs.isEmpty) return null;
    return rttMs.reduce((a, b) => a + b) / rttMs.length;
  }

  String get displayAddress => ip ?? host ?? '*';

  Map<String, dynamic> toJson() => {
    'hopNumber': hopNumber,
    'host': host,
    'ip': ip,
    'rttMs': rttMs,
    'isTimeout': isTimeout,
  };

  factory TracerouteHop.fromJson(Map<String, dynamic> json) => TracerouteHop(
    hopNumber: json['hopNumber'] as int? ?? 1,
    host: json['host'] as String?,
    ip: json['ip'] as String?,
    rttMs:
        (json['rttMs'] as List?)
            ?.whereType<num>()
            .map((e) => e.toDouble())
            .toList() ??
        const [],
    isTimeout: json['isTimeout'] as bool? ?? false,
  );
}

class TracerouteResult {
  final String target;
  final bool isSuccess;
  final int maxHops;
  final List<TracerouteHop> hops;
  final String rawOutput;
  final String? errorMessage;
  final DateTime timestamp;

  const TracerouteResult({
    required this.target,
    required this.isSuccess,
    this.maxHops = 30,
    this.hops = const [],
    required this.rawOutput,
    this.errorMessage,
    required this.timestamp,
  });

  factory TracerouteResult.failure({
    required String target,
    required String errorMessage,
    String rawOutput = '',
  }) => TracerouteResult(
    target: target,
    isSuccess: false,
    errorMessage: errorMessage,
    rawOutput: rawOutput,
    timestamp: DateTime.now(),
  );

  /// Parses OpenWrt BusyBox or standard traceroute output.
  factory TracerouteResult.parse(
    String target,
    String stdout, {
    String? stderr,
    int exitCode = 0,
    int maxHops = 30,
  }) {
    final cleanStdout = stdout.trim();
    if (cleanStdout.isEmpty && (stderr != null && stderr.trim().isNotEmpty)) {
      return TracerouteResult.failure(
        target: target,
        errorMessage: stderr.trim(),
        rawOutput: stderr,
      );
    }

    final hops = <TracerouteHop>[];
    final lines = cleanStdout.split('\n');

    // Hop line regex matches:
    // " 1  10.0.0.1 (10.0.0.1)  0.571 ms"
    // " 2  router.lan (192.168.1.1)  1.234 ms  1.100 ms"
    // " 3  *"
    // " 4  202.88.156.197  3.468 ms"
    final hopRegex = RegExp(r'^\s*(\d+)\s+(.+)$');
    final rttRegex = RegExp(r'([0-9.]+)\s*ms');

    for (final line in lines) {
      final trimmed = line.trim();
      final match = hopRegex.firstMatch(trimmed);
      if (match == null) continue;

      final hopNum = int.tryParse(match.group(1) ?? '');
      if (hopNum == null) continue;

      final rest = match.group(2)!.trim();
      if (rest.startsWith('*') && !rest.contains('ms')) {
        hops.add(TracerouteHop(hopNumber: hopNum, isTimeout: true));
        continue;
      }

      // Extract all RTT values
      final rtts = <double>[];
      for (final rttMatch in rttRegex.allMatches(rest)) {
        final val = double.tryParse(rttMatch.group(1) ?? '');
        if (val != null) rtts.add(val);
      }

      // Extract host and IP
      String? host;
      String? ip;

      // Pattern: hostname (IP) ...
      final hostIpRegex = RegExp(r'^([^\s(]+)\s+\(([^)]+)\)');
      final hostIpMatch = hostIpRegex.firstMatch(rest);
      if (hostIpMatch != null) {
        host = hostIpMatch.group(1);
        ip = hostIpMatch.group(2);
      } else {
        // Pattern: IP or host without parens
        final firstWord = rest.split(RegExp(r'\s+')).first;
        if (RegExp(r'^[0-9a-fA-F.:]+$').hasMatch(firstWord)) {
          ip = firstWord;
        } else {
          host = firstWord;
        }
      }

      hops.add(
        TracerouteHop(
          hopNumber: hopNum,
          host: host,
          ip: ip,
          rttMs: rtts,
          isTimeout: rtts.isEmpty,
        ),
      );
    }

    final isSuccess = exitCode == 0 || hops.isNotEmpty;

    return TracerouteResult(
      target: target,
      isSuccess: isSuccess,
      maxHops: maxHops,
      hops: hops,
      rawOutput: cleanStdout,
      errorMessage: !isSuccess ? (stderr ?? 'Traceroute failed') : null,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'target': target,
    'isSuccess': isSuccess,
    'maxHops': maxHops,
    'hops': hops.map((h) => h.toJson()).toList(),
    'rawOutput': rawOutput,
    'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
  };

  factory TracerouteResult.fromJson(Map<String, dynamic> json) =>
      TracerouteResult(
        target: json['target'] as String? ?? '',
        isSuccess: json['isSuccess'] as bool? ?? false,
        maxHops: json['maxHops'] as int? ?? 30,
        hops:
            (json['hops'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(TracerouteHop.fromJson)
                .toList() ??
            const [],
        rawOutput: json['rawOutput'] as String? ?? '',
        errorMessage: json['errorMessage'] as String?,
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}
