// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';
import 'package:yet_another_luci_app/models/client.dart';

/// A single time-series point returned by OpenWrt LuCI `luci.getRealtimeStats`
/// (backed by the native `luci-bwc` daemon).
class RealtimeTrafficPoint {
  final int timestamp;
  final int rxBytes;
  final int rxPackets;
  final int txBytes;
  final int txPackets;
  final double rxRate; // Calculated rate in bytes per second
  final double txRate; // Calculated rate in bytes per second

  const RealtimeTrafficPoint({
    required this.timestamp,
    required this.rxBytes,
    required this.rxPackets,
    required this.txBytes,
    required this.txPackets,
    this.rxRate = 0.0,
    this.txRate = 0.0,
  });

  /// Parses a raw array from `luci-bwc`:
  /// `[timestamp, rx_bytes, rx_packets, tx_bytes, tx_packets]`
  factory RealtimeTrafficPoint.fromList(
    List<dynamic> list, {
    RealtimeTrafficPoint? previousPoint,
  }) {
    int parseVal(dynamic v) {
      if (v is num) return v.toInt();
      if (v != null) return num.tryParse('$v')?.toInt() ?? 0;
      return 0;
    }

    final ts = list.isNotEmpty ? parseVal(list[0]) : 0;
    final rxB = list.length > 1 ? parseVal(list[1]) : 0;
    final rxP = list.length > 2 ? parseVal(list[2]) : 0;
    final txB = list.length > 3 ? parseVal(list[3]) : 0;
    final txP = list.length > 4 ? parseVal(list[4]) : 0;

    double calculatedRxRate = 0.0;
    double calculatedTxRate = 0.0;

    if (previousPoint != null) {
      final deltaSec = ts - previousPoint.timestamp;
      if (deltaSec > 0 && deltaSec <= 30) {
        if (rxB >= previousPoint.rxBytes) {
          calculatedRxRate = (rxB - previousPoint.rxBytes) / deltaSec;
        } else if (previousPoint.rxBytes > 0x7FFFFFFF && rxB < 0x20000000) {
          final candidate =
              ((4294967296 - previousPoint.rxBytes) + rxB) / deltaSec;
          // Sanity check: reject candidate if it exceeds 10 Gbps (likely a counter reset / reconnect)
          if (candidate <= 1250000000.0) {
            calculatedRxRate = candidate;
          }
        }

        if (txB >= previousPoint.txBytes) {
          calculatedTxRate = (txB - previousPoint.txBytes) / deltaSec;
        } else if (previousPoint.txBytes > 0x7FFFFFFF && txB < 0x20000000) {
          final candidate =
              ((4294967296 - previousPoint.txBytes) + txB) / deltaSec;
          if (candidate <= 1250000000.0) {
            calculatedTxRate = candidate;
          }
        }
      }
    }

    return RealtimeTrafficPoint(
      timestamp: ts,
      rxBytes: rxB,
      rxPackets: rxP,
      txBytes: txB,
      txPackets: txP,
      rxRate: max(0.0, calculatedRxRate),
      txRate: max(0.0, calculatedTxRate),
    );
  }

  RealtimeTrafficPoint copyWith({
    int? timestamp,
    int? rxBytes,
    int? rxPackets,
    int? txBytes,
    int? txPackets,
    double? rxRate,
    double? txRate,
  }) {
    return RealtimeTrafficPoint(
      timestamp: timestamp ?? this.timestamp,
      rxBytes: rxBytes ?? this.rxBytes,
      rxPackets: rxPackets ?? this.rxPackets,
      txBytes: txBytes ?? this.txBytes,
      txPackets: txPackets ?? this.txPackets,
      rxRate: rxRate ?? this.rxRate,
      txRate: txRate ?? this.txRate,
    );
  }
}

/// A parsed record from OpenWrt `nlbw` (`nlbwmon` Netlink Bandwidth Monitor).
class NlbwmonHostRecord {
  final String mac;
  final String? ip;
  final int conns;
  final int rxBytes;
  final int rxPackets;
  final int txBytes;
  final int txPackets;
  final String? layer7;
  final int? family;
  final String? proto;
  final int? port;

  const NlbwmonHostRecord({
    required this.mac,
    this.ip,
    this.conns = 0,
    this.rxBytes = 0,
    this.rxPackets = 0,
    this.txBytes = 0,
    this.txPackets = 0,
    this.layer7,
    this.family,
    this.proto,
    this.port,
  });

  int get totalBytes => rxBytes + txBytes;
  int get totalPackets => rxPackets + txPackets;

  factory NlbwmonHostRecord.fromColumns(
    List<String> columns,
    List<dynamic> row,
  ) {
    String macVal = '';
    String? ipVal;
    int connsVal = 0;
    int rxB = 0;
    int rxP = 0;
    int txB = 0;
    int txP = 0;
    String? l7;
    int? fam;
    String? protoVal;
    int? portVal;

    for (int i = 0; i < columns.length && i < row.length; i++) {
      final col = columns[i];
      final val = row[i];
      switch (col) {
        case 'mac':
          macVal = val?.toString().toUpperCase() ?? '';
          break;
        case 'ip':
          ipVal = val?.toString();
          break;
        case 'conns':
          connsVal = val is num ? val.toInt() : (int.tryParse('$val') ?? 0);
          break;
        case 'rx_bytes':
          rxB = val is num ? val.toInt() : (int.tryParse('$val') ?? 0);
          break;
        case 'rx_pkts':
          rxP = val is num ? val.toInt() : (int.tryParse('$val') ?? 0);
          break;
        case 'tx_bytes':
          txB = val is num ? val.toInt() : (int.tryParse('$val') ?? 0);
          break;
        case 'tx_pkts':
          txP = val is num ? val.toInt() : (int.tryParse('$val') ?? 0);
          break;
        case 'layer7':
          l7 = val?.toString();
          break;
        case 'family':
          fam = val is num ? val.toInt() : int.tryParse('$val');
          break;
        case 'proto':
          protoVal = val?.toString();
          break;
        case 'port':
          portVal = val is num ? val.toInt() : int.tryParse('$val');
          break;
      }
    }

    return NlbwmonHostRecord(
      mac: macVal,
      ip: ipVal,
      conns: connsVal,
      rxBytes: rxB,
      rxPackets: rxP,
      txBytes: txB,
      txPackets: txP,
      layer7: l7,
      family: fam,
      proto: protoVal,
      port: portVal,
    );
  }
}

/// A complete report loaded from `nlbwmon-action download -f json`.
class NlbwmonReport {
  final List<String> columns;
  final List<NlbwmonHostRecord> records;
  final String? period;

  const NlbwmonReport({
    required this.columns,
    required this.records,
    this.period,
  });

  factory NlbwmonReport.fromJson(Map<String, dynamic> json, [String? period]) {
    final cols = (json['columns'] is List)
        ? (json['columns'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final rows = (json['data'] is List) ? (json['data'] as List) : <dynamic>[];

    final parsedRecords = <NlbwmonHostRecord>[];
    for (final row in rows) {
      if (row is List) {
        parsedRecords.add(NlbwmonHostRecord.fromColumns(cols, row));
      }
    }

    return NlbwmonReport(columns: cols, records: parsedRecords, period: period);
  }
}

/// Normalized bandwidth view for a connected client or host.
class DeviceBandwidthItem {
  final Client client;
  final double downloadSpeed; // Bytes per second (router TX to client)
  final double uploadSpeed; // Bytes per second (router RX from client)
  final int totalDownloaded; // Cumulative bytes downloaded
  final int totalUploaded; // Cumulative bytes uploaded
  final double peakDownloadSpeed;
  final double peakUploadSpeed;
  final int? activeConnections;
  final String? topProtocol;

  const DeviceBandwidthItem({
    required this.client,
    this.downloadSpeed = 0.0,
    this.uploadSpeed = 0.0,
    this.totalDownloaded = 0,
    this.totalUploaded = 0,
    this.peakDownloadSpeed = 0.0,
    this.peakUploadSpeed = 0.0,
    this.activeConnections,
    this.topProtocol,
  });

  String get displayName => client.displayName;
  String get ipAddress => client.ipAddress;
  String get macAddress => client.macAddress;
  String get normalizedMac => client.normalizedMac;
  bool get isConnected => client.isConnected;
  bool get isWireless => client.connectionType == ConnectionType.wireless;
  bool get isWired => client.connectionType == ConnectionType.wired;
  bool get isDumbAp => client.isDumbApClient;
  String? get ssid => client.ssid;
  int? get signalDbm => client.signalDbm;
  String? get signalQuality => client.signalQualityLabel;
  String? get formattedPhyRate => client.formattedPhyRate;
  String? get formattedConnectedTime => client.formattedConnectedTime;

  bool get hasActiveSpeed => downloadSpeed > 512 || uploadSpeed > 512;

  String formattedDownloadSpeed([String unit = 'bits']) =>
      Client.formatSpeed(downloadSpeed, speedUnit: unit);

  String formattedUploadSpeed([String unit = 'bits']) =>
      Client.formatSpeed(uploadSpeed, speedUnit: unit);

  String formattedPeakDownload([String unit = 'bits']) =>
      Client.formatSpeed(peakDownloadSpeed, speedUnit: unit);

  String formattedPeakUpload([String unit = 'bits']) =>
      Client.formatSpeed(peakUploadSpeed, speedUnit: unit);

  String get formattedTotalDownloaded => Client.formatBytes(totalDownloaded);
  String get formattedTotalUploaded => Client.formatBytes(totalUploaded);

  DeviceBandwidthItem copyWith({
    Client? client,
    double? downloadSpeed,
    double? uploadSpeed,
    int? totalDownloaded,
    int? totalUploaded,
    double? peakDownloadSpeed,
    double? peakUploadSpeed,
    int? activeConnections,
    String? topProtocol,
  }) {
    return DeviceBandwidthItem(
      client: client ?? this.client,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      totalDownloaded: totalDownloaded ?? this.totalDownloaded,
      totalUploaded: totalUploaded ?? this.totalUploaded,
      peakDownloadSpeed: peakDownloadSpeed ?? this.peakDownloadSpeed,
      peakUploadSpeed: peakUploadSpeed ?? this.peakUploadSpeed,
      activeConnections: activeConnections ?? this.activeConnections,
      topProtocol: topProtocol ?? this.topProtocol,
    );
  }
}

/// Aggregate summary metrics across all clients and interfaces.
class BandwidthSummary {
  final double totalDownloadSpeed;
  final double totalUploadSpeed;
  final double peakDownloadSpeed;
  final double peakUploadSpeed;
  final int totalSessionDownload;
  final int totalSessionUpload;
  final int connectedDevicesCount;
  final int activeTrafficDevicesCount;

  const BandwidthSummary({
    this.totalDownloadSpeed = 0.0,
    this.totalUploadSpeed = 0.0,
    this.peakDownloadSpeed = 0.0,
    this.peakUploadSpeed = 0.0,
    this.totalSessionDownload = 0,
    this.totalSessionUpload = 0,
    this.connectedDevicesCount = 0,
    this.activeTrafficDevicesCount = 0,
  });

  String formattedDownloadSpeed([String unit = 'bits']) =>
      Client.formatSpeed(totalDownloadSpeed, speedUnit: unit);

  String formattedUploadSpeed([String unit = 'bits']) =>
      Client.formatSpeed(totalUploadSpeed, speedUnit: unit);

  String formattedPeakDownload([String unit = 'bits']) =>
      Client.formatSpeed(peakDownloadSpeed, speedUnit: unit);

  String formattedPeakUpload([String unit = 'bits']) =>
      Client.formatSpeed(peakUploadSpeed, speedUnit: unit);

  String get formattedTotalDownloaded =>
      Client.formatBytes(totalSessionDownload);

  String get formattedTotalUploaded => Client.formatBytes(totalSessionUpload);
}

/// A comprehensive usage statistic item representing past or persistent traffic
/// for a client device (both connected and disconnected/offline).
class UsageStatsItem {
  final String mac;
  final String? ip;
  final String displayName;
  final bool isConnected;
  final int downloadBytes; // Client download (host/AP TX)
  final int uploadBytes; // Client upload (host/AP RX)
  final int totalBytes;
  final int conns;
  final String? layer7;
  final ConnectionType connectionType;
  final bool fromNlbwmon;

  const UsageStatsItem({
    required this.mac,
    this.ip,
    required this.displayName,
    required this.isConnected,
    this.downloadBytes = 0,
    this.uploadBytes = 0,
    required this.totalBytes,
    this.conns = 0,
    this.layer7,
    this.connectionType = ConnectionType.unknown,
    this.fromNlbwmon = false,
  });

  String get formattedTotalBytes => Client.formatBytes(totalBytes);
  String get formattedDownloadBytes => Client.formatBytes(downloadBytes);
  String get formattedUploadBytes => Client.formatBytes(uploadBytes);
}
