// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'internet_reachability.dart';
import 'routing_neighbor_info.dart';

class DiagnosticReport {
  final String hostname;
  final String model;
  final String architecture;
  final String target;
  final String kernelVersion;
  final String firmwareVersion;
  final String uptime;
  final String loadAverage;
  final String memorySummary;
  final String? temperatureSummary;
  final String storageSummary;
  final InternetReachability internetStatus;
  final List<RouteEntry> routes;
  final List<NeighborEntry> neighbors;
  final ConntrackInfo? conntrack;
  final String wanInfo;
  final String lanInfo;
  final String recentSyslog;
  final String recentDmesg;
  final DateTime generatedAt;

  const DiagnosticReport({
    required this.hostname,
    required this.model,
    required this.architecture,
    required this.target,
    required this.kernelVersion,
    required this.firmwareVersion,
    required this.uptime,
    required this.loadAverage,
    required this.memorySummary,
    this.temperatureSummary,
    required this.storageSummary,
    required this.internetStatus,
    required this.routes,
    required this.neighbors,
    this.conntrack,
    required this.wanInfo,
    required this.lanInfo,
    required this.recentSyslog,
    required this.recentDmesg,
    required this.generatedAt,
  });

  /// Checks if an IP or route destination is private, loopback, multicast, or standard wildcard.
  static bool isPrivateIp(String ip) {
    var clean = ip.trim();
    if (clean.isEmpty ||
        clean == 'default' ||
        clean == '0.0.0.0' ||
        clean == '0.0.0.0/0' ||
        clean == '*' ||
        clean == '-') {
      return true;
    }
    // Strip CIDR mask if present
    if (clean.contains('/')) {
      clean = clean.split('/')[0];
    }
    if (clean == '127.0.0.1' || clean == 'localhost' || clean == '::1') {
      return true;
    }
    if (clean.startsWith('10.')) return true;
    if (clean.startsWith('192.168.')) return true;
    if (clean.startsWith('172.')) {
      final parts = clean.split('.');
      if (parts.length > 1) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 16 && second <= 31) return true;
      }
    }
    // Carrier-grade NAT (100.64.0.0/10)
    if (clean.startsWith('100.')) {
      final parts = clean.split('.');
      if (parts.length > 1) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 64 && second <= 127) return true;
      }
    }
    // Link local (169.254.0.0/16)
    if (clean.startsWith('169.254.')) return true;
    // Multicast & broadcast
    if (clean.startsWith('224.') ||
        clean.startsWith('239.') ||
        clean == '255.255.255.255') {
      return true;
    }
    // Well-known public DNS servers (safe & helpful to keep visible in diagnostic reports)
    const wellKnownDns = {
      '1.1.1.1',
      '1.0.0.1',
      '8.8.8.8',
      '8.8.4.4',
      '9.9.9.9',
      '149.112.112.112',
      '208.67.222.222',
      '208.67.220.220',
    };
    if (wellKnownDns.contains(clean)) return true;

    return false;
  }

  /// Masks public IP addresses while keeping private IPs and CIDR masks readable.
  static String maskIp(String ip) {
    final clean = ip.trim();
    if (clean.isEmpty) return clean;
    if (isPrivateIp(clean)) return clean;

    final hasCidr = clean.contains('/');
    final baseIp = hasCidr ? clean.split('/')[0] : clean;
    final cidrSuffix = hasCidr ? '/${clean.split('/')[1]}' : '';

    // Mask last two octets of IPv4: 203.0.113.195 -> 203.0.xxx.xxx
    final parts = baseIp.split('.');
    if (parts.length == 4) {
      final octets = parts.map((p) => int.tryParse(p)).toList();
      if (octets.every((o) => o != null && o >= 0 && o <= 255)) {
        return '${parts[0]}.${parts[1]}.xxx.xxx$cidrSuffix';
      }
    }
    // IPv6 masking
    if (baseIp.contains(':')) {
      final v6Parts = baseIp.split(':');
      if (v6Parts.length > 2) {
        return '${v6Parts[0]}:${v6Parts[1]}:xxxx:xxxx::xxxx$cidrSuffix';
      }
    }
    return '[REDACTED_IP]$cidrSuffix';
  }

  /// Masks MAC address for privacy: e4:a8:df:ca:41:8c -> e4:a8:df:xx:xx:xx
  static String maskMac(String mac) {
    final clean = mac.trim();
    final parts = clean.split(':');
    if (parts.length == 6) {
      return '${parts[0]}:${parts[1]}:${parts[2]}:xx:xx:xx';
    }
    return '[REDACTED_MAC]';
  }

  /// Replaces sensitive IP and MAC occurrences throughout a text block.
  static String redactText(String text) {
    // Redact MACs: xx:xx:xx:xx:xx:xx
    final macRegex = RegExp(r'\b([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})\b');
    var redacted = text.replaceAllMapped(macRegex, (m) {
      return maskMac(m.group(1)!);
    });

    // Redact public IPv4s
    final ipv4Regex = RegExp(r'\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b');
    redacted = redacted.replaceAllMapped(ipv4Regex, (m) {
      final ip = m.group(1)!;
      return maskIp(ip);
    });

    return redacted;
  }

  /// Generates clean, structured Markdown ready to export or paste to forums.
  String generateMarkdown({bool redact = true}) {
    final buf = StringBuffer();
    buf.writeln('# OpenWrt Router Diagnostic Report');
    buf.writeln('Generated: ${generatedAt.toUtc().toIso8601String()} (UTC)');
    buf.writeln(
      'Privacy Redaction: ${redact ? "Enabled (Public IPs and MACs masked)" : "Disabled"}',
    );
    buf.writeln();

    buf.writeln('## 1. System Information');
    buf.writeln('- **Hostname**: $hostname');
    buf.writeln('- **Hardware Model**: $model');
    buf.writeln('- **Architecture / Target**: $architecture / $target');
    buf.writeln('- **Firmware / Release**: $firmwareVersion');
    buf.writeln('- **Kernel Version**: $kernelVersion');
    buf.writeln('- **System Uptime**: $uptime');
    buf.writeln('- **Load Average**: $loadAverage');
    buf.writeln('- **Memory**: $memorySummary');
    if (temperatureSummary != null) {
      buf.writeln('- **Temperature**: $temperatureSummary');
    }
    buf.writeln('- **Storage**: $storageSummary');
    buf.writeln();

    buf.writeln('## 2. Internet Reachability & WAN');
    buf.writeln('- **Status**: ${internetStatus.statusMessage}');
    buf.writeln('- **WAN Interface**: ${internetStatus.wanInterface ?? "N/A"}');
    buf.writeln(
      '- **WAN IP**: ${redact ? (internetStatus.wanIp != null ? maskIp(internetStatus.wanIp!) : "N/A") : (internetStatus.wanIp ?? "N/A")}',
    );
    final gwDisplay = internetStatus.gatewayIp != null
        ? (redact
              ? maskIp(internetStatus.gatewayIp!)
              : internetStatus.gatewayIp!)
        : "N/A";
    buf.writeln(
      '- **Default Gateway**: $gwDisplay (Reachable: ${internetStatus.gatewayReachable ? "Yes" : "No"}${internetStatus.gatewayLatencyMs != null ? ", ${internetStatus.gatewayLatencyMs!.toStringAsFixed(1)} ms" : ""})',
    );
    buf.writeln(
      '- **Public DNS (1.1.1.1)**: Reachable: ${internetStatus.publicDnsReachable ? "Yes" : "No"}${internetStatus.publicDnsLatencyMs != null ? ", ${internetStatus.publicDnsLatencyMs!.toStringAsFixed(1)} ms" : ""}',
    );
    buf.writeln(
      '- **DNS Resolution**: ${internetStatus.dnsResolving ? "Operational" : "Failed / Unreachable"}',
    );
    buf.writeln();

    buf.writeln('### Network Interfaces');
    buf.writeln('```');
    buf.writeln('WAN: ${redact ? redactText(wanInfo) : wanInfo}');
    buf.writeln('LAN: ${redact ? redactText(lanInfo) : lanInfo}');
    buf.writeln('```');
    buf.writeln();

    buf.writeln('## 3. Kernel Routing Table');
    if (routes.isEmpty) {
      buf.writeln('_No routing entries found._');
    } else {
      buf.writeln('| Destination | Gateway | Interface | Table |');
      buf.writeln('| :--- | :--- | :--- | :--- |');
      for (final r in routes) {
        final dest = redact ? maskIp(r.destination) : r.destination;
        final gw = r.gateway != null
            ? (redact ? maskIp(r.gateway!) : r.gateway!)
            : '-';
        buf.writeln(
          '| $dest | $gw | ${r.interface ?? "-"} | ${r.table ?? "main"} |',
        );
      }
    }
    buf.writeln();

    buf.writeln('## 4. ARP Neighbors & Active Connections');
    if (conntrack != null) {
      buf.writeln(
        '- **NAT Connections**: ${conntrack!.count} / ${conntrack!.max} (${conntrack!.utilizationPercent.toStringAsFixed(1)}%)',
      );
    }
    if (neighbors.isEmpty) {
      buf.writeln('_No ARP neighbor entries found._');
    } else {
      buf.writeln('| IP Address | MAC Address | Interface | State |');
      buf.writeln('| :--- | :--- | :--- | :--- |');
      for (final n in neighbors) {
        final ip = redact ? maskIp(n.ip) : n.ip;
        final mac = n.mac != null ? (redact ? maskMac(n.mac!) : n.mac!) : '-';
        buf.writeln('| $ip | $mac | ${n.interface ?? "-"} | ${n.state} |');
      }
    }
    buf.writeln();

    buf.writeln('## 5. Recent System Log');
    buf.writeln('```');
    final logOutput = redact ? redactText(recentSyslog) : recentSyslog;
    buf.writeln(
      logOutput.trim().isNotEmpty
          ? logOutput.trim()
          : 'No recent syslog entries.',
    );
    buf.writeln('```');
    buf.writeln();

    buf.writeln('## 6. Recent Kernel Log (dmesg)');
    buf.writeln('```');
    final dmesgOutput = redact ? redactText(recentDmesg) : recentDmesg;
    buf.writeln(
      dmesgOutput.trim().isNotEmpty
          ? dmesgOutput.trim()
          : 'No recent dmesg entries.',
    );
    buf.writeln('```');
    buf.writeln();

    return buf.toString();
  }

  /// Generates plain text format.
  String generatePlainText({bool redact = true}) {
    return generateMarkdown(redact: redact);
  }
}
