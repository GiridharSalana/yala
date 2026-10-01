// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class DnsLookupResult {
  final String query;
  final String? server;
  final int? serverPort;
  final List<String> ipv4Addresses;
  final List<String> ipv6Addresses;
  final List<String> cnames;
  final bool isSuccess;
  final String rawOutput;
  final String? errorMessage;
  final DateTime timestamp;

  const DnsLookupResult({
    required this.query,
    this.server,
    this.serverPort,
    this.ipv4Addresses = const [],
    this.ipv6Addresses = const [],
    this.cnames = const [],
    required this.isSuccess,
    required this.rawOutput,
    this.errorMessage,
    required this.timestamp,
  });

  List<String> get allAddresses => [...ipv4Addresses, ...ipv6Addresses];

  factory DnsLookupResult.failure({
    required String query,
    required String errorMessage,
    String rawOutput = '',
  }) => DnsLookupResult(
    query: query,
    isSuccess: false,
    errorMessage: errorMessage,
    rawOutput: rawOutput,
    timestamp: DateTime.now(),
  );

  /// Parses OpenWrt BusyBox or bind nslookup stdout.
  factory DnsLookupResult.parse(
    String query,
    String stdout, {
    String? stderr,
    int exitCode = 0,
  }) {
    final cleanStdout = stdout.trim();
    if (cleanStdout.isEmpty && (stderr != null && stderr.trim().isNotEmpty)) {
      return DnsLookupResult.failure(
        query: query,
        errorMessage: stderr.trim(),
        rawOutput: stderr,
      );
    }

    String? server;
    int? serverPort;
    final ipv4s = <String>[];
    final ipv6s = <String>[];
    final cnames = <String>[];

    final lines = cleanStdout.split('\n');
    bool inAnswerSection = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('Server:') || trimmed.startsWith('Server\t:')) {
        final parts = trimmed.split(RegExp(r'[:\t]+'));
        if (parts.length > 1) {
          server = parts.sublist(1).join(':').trim();
        }
        continue;
      }

      if (RegExp(r'^Address(?:\s+\d+)?:').hasMatch(trimmed)) {
        final val = trimmed
            .replaceFirst(RegExp(r'^Address(?:\s+\d+)?:?\s*'), '')
            .trim();
        if (!inAnswerSection && server != null && serverPort == null) {
          // This is the resolver address, may include port like 127.0.0.1:53 or 127.0.0.1#53
          final portMatch = RegExp(r'[:#](\d+)$').firstMatch(val);
          if (portMatch != null) {
            serverPort = int.tryParse(portMatch.group(1) ?? '53');
          }
          continue;
        }

        // Answer section IP
        _categorizeIp(val, ipv4s, ipv6s);
        continue;
      }

      if (trimmed.contains('answer:') || trimmed.startsWith('Name:')) {
        inAnswerSection = true;
      }

      if (trimmed.contains('canonical name =') || trimmed.contains('CNAME')) {
        final parts = trimmed.split('=');
        if (parts.length > 1) {
          cnames.add(parts[1].trim());
        }
      }
    }

    // Fallback regex scan for addresses if loop didn't catch answer section
    if (ipv4s.isEmpty && ipv6s.isEmpty) {
      final addrMatches = RegExp(
        r'Address(?:\s+\d+)?:?\s*([0-9a-fA-F.:]+)',
      ).allMatches(cleanStdout);
      int idx = 0;
      for (final m in addrMatches) {
        idx++;
        // Skip first match if it was likely the server's own address
        if (idx == 1 && server != null) continue;
        final ip = m.group(1)?.split('#').first.split(':').first ?? '';
        if (ip.isNotEmpty) {
          _categorizeIp(ip, ipv4s, ipv6s);
        }
      }
    }

    final isSuccess =
        exitCode == 0 &&
        (ipv4s.isNotEmpty || ipv6s.isNotEmpty || cnames.isNotEmpty);

    return DnsLookupResult(
      query: query,
      server: server,
      serverPort: serverPort ?? 53,
      ipv4Addresses: ipv4s.toSet().toList(),
      ipv6Addresses: ipv6s.toSet().toList(),
      cnames: cnames.toSet().toList(),
      isSuccess: isSuccess,
      rawOutput: cleanStdout,
      errorMessage: !isSuccess ? (stderr ?? 'No DNS records found') : null,
      timestamp: DateTime.now(),
    );
  }

  static void _categorizeIp(
    String raw,
    List<String> ipv4s,
    List<String> ipv6s,
  ) {
    final clean = raw.split('#').first.trim();
    if (clean.contains(':')) {
      ipv6s.add(clean);
    } else if (RegExp(
      r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$',
    ).hasMatch(clean)) {
      ipv4s.add(clean);
    }
  }

  Map<String, dynamic> toJson() => {
    'query': query,
    'server': server,
    'serverPort': serverPort,
    'ipv4Addresses': ipv4Addresses,
    'ipv6Addresses': ipv6Addresses,
    'cnames': cnames,
    'isSuccess': isSuccess,
    'rawOutput': rawOutput,
    'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
  };

  factory DnsLookupResult.fromJson(
    Map<String, dynamic> json,
  ) => DnsLookupResult(
    query: json['query'] as String? ?? '',
    server: json['server'] as String?,
    serverPort: json['serverPort'] as int?,
    ipv4Addresses:
        (json['ipv4Addresses'] as List?)?.whereType<String>().toList() ??
        const [],
    ipv6Addresses:
        (json['ipv6Addresses'] as List?)?.whereType<String>().toList() ??
        const [],
    cnames: (json['cnames'] as List?)?.whereType<String>().toList() ?? const [],
    isSuccess: json['isSuccess'] as bool? ?? false,
    rawOutput: json['rawOutput'] as String? ?? '',
    errorMessage: json['errorMessage'] as String?,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
  );
}
