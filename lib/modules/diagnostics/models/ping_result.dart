// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class PingPacketReply {
  final int seq;
  final int? ttl;
  final double timeMs;
  final String? ip;

  const PingPacketReply({
    required this.seq,
    this.ttl,
    required this.timeMs,
    this.ip,
  });

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'ttl': ttl,
    'timeMs': timeMs,
    'ip': ip,
  };

  factory PingPacketReply.fromJson(Map<String, dynamic> json) =>
      PingPacketReply(
        seq: json['seq'] as int? ?? 0,
        ttl: json['ttl'] as int?,
        timeMs: (json['timeMs'] as num?)?.toDouble() ?? 0.0,
        ip: json['ip'] as String?,
      );
}

class PingResult {
  final String target;
  final bool isSuccess;
  final int packetsTransmitted;
  final int packetsReceived;
  final double packetLossPercent;
  final double? minRttMs;
  final double? avgRttMs;
  final double? maxRttMs;
  final double? mdevRttMs;
  final List<PingPacketReply> replies;
  final String rawOutput;
  final String? errorMessage;
  final DateTime timestamp;

  const PingResult({
    required this.target,
    required this.isSuccess,
    this.packetsTransmitted = 0,
    this.packetsReceived = 0,
    this.packetLossPercent = 100.0,
    this.minRttMs,
    this.avgRttMs,
    this.maxRttMs,
    this.mdevRttMs,
    this.replies = const [],
    required this.rawOutput,
    this.errorMessage,
    required this.timestamp,
  });

  factory PingResult.failure({
    required String target,
    required String errorMessage,
    String rawOutput = '',
  }) => PingResult(
    target: target,
    isSuccess: false,
    errorMessage: errorMessage,
    rawOutput: rawOutput,
    timestamp: DateTime.now(),
  );

  /// Parses OpenWrt BusyBox or iputils ping stdout.
  factory PingResult.parse(
    String target,
    String stdout, {
    String? stderr,
    int exitCode = 0,
  }) {
    final cleanStdout = stdout.trim();
    if (cleanStdout.isEmpty && (stderr != null && stderr.trim().isNotEmpty)) {
      return PingResult.failure(
        target: target,
        errorMessage: stderr.trim(),
        rawOutput: stderr,
      );
    }

    final replies = <PingPacketReply>[];
    int transmitted = 0;
    int received = 0;
    double lossPercent = 100.0;
    double? minRtt;
    double? avgRtt;
    double? maxRtt;
    double? mdevRtt;

    final lines = cleanStdout.split('\n');
    final replyRegex = RegExp(
      r'(?:from\s+([0-9a-fA-F.:]+).*?)?(?:icmp_seq|seq)=(\d+)(?:.*?ttl=(\d+))?.*?time=([0-9.]+)\s*ms',
      caseSensitive: false,
    );
    final statsRegex = RegExp(
      r'(\d+)\s+packets\s+transmitted,\s+(\d+)\s+(?:packets\s+)?received.*?(?:([0-9.]+)%\s+packet\s+loss)?',
      caseSensitive: false,
    );
    final rttRegex = RegExp(
      r'(?:round-trip\s+)?(?:min/avg/max(?:/mdev)?|rtt\s+min/avg/max/mdev)\s*=\s*([0-9.]+)/([0-9.]+)/([0-9.]+)(?:/([0-9.]+))?',
      caseSensitive: false,
    );

    for (final line in lines) {
      final trimmed = line.trim();
      final replyMatch = replyRegex.firstMatch(trimmed);
      if (replyMatch != null) {
        final rawIp = replyMatch.group(1);
        final ip = rawIp?.replaceAll(RegExp(r':$'), '');
        final seq = int.tryParse(replyMatch.group(2) ?? '0') ?? 0;
        final ttl = int.tryParse(replyMatch.group(3) ?? '');
        final timeMs = double.tryParse(replyMatch.group(4) ?? '0') ?? 0.0;
        replies.add(
          PingPacketReply(seq: seq, ttl: ttl, timeMs: timeMs, ip: ip),
        );
        continue;
      }

      final statsMatch = statsRegex.firstMatch(trimmed);
      if (statsMatch != null) {
        transmitted = int.tryParse(statsMatch.group(1) ?? '0') ?? 0;
        received = int.tryParse(statsMatch.group(2) ?? '0') ?? 0;
        if (statsMatch.group(3) != null) {
          lossPercent = double.tryParse(statsMatch.group(3)!) ?? 0.0;
        } else if (transmitted > 0) {
          lossPercent = ((transmitted - received) / transmitted) * 100.0;
        }
        continue;
      }

      final rttMatch = rttRegex.firstMatch(trimmed);
      if (rttMatch != null) {
        minRtt = double.tryParse(rttMatch.group(1) ?? '');
        avgRtt = double.tryParse(rttMatch.group(2) ?? '');
        maxRtt = double.tryParse(rttMatch.group(3) ?? '');
        mdevRtt = double.tryParse(rttMatch.group(4) ?? '');
      }
    }

    if (replies.isNotEmpty && transmitted == 0) {
      transmitted = replies.length;
      received = replies.length;
      lossPercent = 0.0;
    }

    final isSuccess = exitCode == 0 && received > 0;

    return PingResult(
      target: target,
      isSuccess: isSuccess,
      packetsTransmitted: transmitted,
      packetsReceived: received,
      packetLossPercent: lossPercent,
      minRttMs: minRtt,
      avgRttMs: avgRtt,
      maxRttMs: maxRtt,
      mdevRttMs: mdevRtt,
      replies: replies,
      rawOutput: cleanStdout,
      errorMessage: !isSuccess ? (stderr ?? 'Ping failed or timed out') : null,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'target': target,
    'isSuccess': isSuccess,
    'packetsTransmitted': packetsTransmitted,
    'packetsReceived': packetsReceived,
    'packetLossPercent': packetLossPercent,
    'minRttMs': minRttMs,
    'avgRttMs': avgRttMs,
    'maxRttMs': maxRttMs,
    'mdevRttMs': mdevRttMs,
    'replies': replies.map((r) => r.toJson()).toList(),
    'rawOutput': rawOutput,
    'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
  };

  factory PingResult.fromJson(Map<String, dynamic> json) => PingResult(
    target: json['target'] as String? ?? '',
    isSuccess: json['isSuccess'] as bool? ?? false,
    packetsTransmitted: json['packetsTransmitted'] as int? ?? 0,
    packetsReceived: json['packetsReceived'] as int? ?? 0,
    packetLossPercent: (json['packetLossPercent'] as num?)?.toDouble() ?? 100.0,
    minRttMs: (json['minRttMs'] as num?)?.toDouble(),
    avgRttMs: (json['avgRttMs'] as num?)?.toDouble(),
    maxRttMs: (json['maxRttMs'] as num?)?.toDouble(),
    mdevRttMs: (json['mdevRttMs'] as num?)?.toDouble(),
    replies:
        (json['replies'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(PingPacketReply.fromJson)
            .toList() ??
        const [],
    rawOutput: json['rawOutput'] as String? ?? '',
    errorMessage: json['errorMessage'] as String?,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
  );
}
