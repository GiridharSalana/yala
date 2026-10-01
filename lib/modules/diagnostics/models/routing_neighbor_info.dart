// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class RouteEntry {
  final String destination;
  final String? gateway;
  final String? interface;
  final String? source;
  final String? table;
  final String? metric;
  final bool isDefault;

  const RouteEntry({
    required this.destination,
    this.gateway,
    this.interface,
    this.source,
    this.table,
    this.metric,
    this.isDefault = false,
  });

  /// Parses output lines from `ip -4 route show table all` or `ip route show`.
  static List<RouteEntry> parseList(String raw) {
    final list = <RouteEntry>[];
    final lines = raw.trim().split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final tokens = trimmed.split(RegExp(r'\s+'));
      if (tokens.isEmpty) continue;

      final dest = tokens[0];
      final isDef = dest == 'default';

      String? gw;
      String? dev;
      String? src;
      String? tbl;
      String? met;

      for (int i = 0; i < tokens.length - 1; i++) {
        final key = tokens[i];
        final next = tokens[i + 1];
        if (key == 'via') gw = next;
        if (key == 'dev') dev = next;
        if (key == 'src') src = next;
        if (key == 'table') tbl = next;
        if (key == 'metric') met = next;
      }

      list.add(
        RouteEntry(
          destination: dest,
          gateway: gw,
          interface: dev,
          source: src,
          table: tbl,
          metric: met,
          isDefault: isDef,
        ),
      );
    }
    return list;
  }

  Map<String, dynamic> toJson() => {
    'destination': destination,
    'gateway': gateway,
    'interface': interface,
    'source': source,
    'table': table,
    'metric': metric,
    'isDefault': isDefault,
  };

  factory RouteEntry.fromJson(Map<String, dynamic> json) => RouteEntry(
    destination: json['destination'] as String? ?? '',
    gateway: json['gateway'] as String?,
    interface: json['interface'] as String?,
    source: json['source'] as String?,
    table: json['table'] as String?,
    metric: json['metric'] as String?,
    isDefault: json['isDefault'] as bool? ?? false,
  );
}

class NeighborEntry {
  final String ip;
  final String? mac;
  final String? interface;
  final String state;

  const NeighborEntry({
    required this.ip,
    this.mac,
    this.interface,
    required this.state,
  });

  /// Parses lines from `ip -4 neigh show`.
  static List<NeighborEntry> parseList(String raw) {
    final list = <NeighborEntry>[];
    final lines = raw.trim().split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final tokens = trimmed.split(RegExp(r'\s+'));
      if (tokens.isEmpty) continue;

      final ip = tokens[0];
      String? dev;
      String? mac;
      String state = 'UNKNOWN';

      for (int i = 0; i < tokens.length - 1; i++) {
        if (tokens[i] == 'dev') dev = tokens[i + 1];
        if (tokens[i] == 'lladdr') mac = tokens[i + 1];
      }

      state = tokens.last.toUpperCase();

      list.add(NeighborEntry(ip: ip, mac: mac, interface: dev, state: state));
    }
    return list;
  }

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'mac': mac,
    'interface': interface,
    'state': state,
  };

  factory NeighborEntry.fromJson(Map<String, dynamic> json) => NeighborEntry(
    ip: json['ip'] as String? ?? '',
    mac: json['mac'] as String?,
    interface: json['interface'] as String?,
    state: json['state'] as String? ?? 'UNKNOWN',
  );
}

class ConntrackInfo {
  final int count;
  final int max;

  const ConntrackInfo({required this.count, required this.max});

  double get utilizationPercent => max > 0 ? (count / max) * 100.0 : 0.0;

  Map<String, dynamic> toJson() => {'count': count, 'max': max};

  factory ConntrackInfo.fromJson(Map<String, dynamic> json) => ConntrackInfo(
    count: json['count'] as int? ?? 0,
    max: json['max'] as int? ?? 0,
  );
}
