// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import '../models/bandwidth_data.dart';

enum BandwidthSortMode { downloadSpeed, uploadSpeed, totalUsage, name, ip }

class BandwidthMonitorState {
  final bool isLoading;
  final bool isStreaming;
  final int pollingIntervalSeconds;
  final List<DeviceBandwidthItem> devices;
  final List<UsageStatsItem> usageStats;
  final BandwidthSummary summary;
  final List<RealtimeTrafficPoint> trafficHistory;
  final String trafficInterface;
  final List<String> availableInterfaces;
  final bool isNlbwmonInstalled;
  final NlbwmonReport? nlbwmonReport;
  final List<String> nlbwmonPeriods;
  final String? selectedPeriod;
  final String searchQuery;
  final BandwidthSortMode sortMode;
  final String? errorMessage;

  const BandwidthMonitorState({
    this.isLoading = true,
    this.isStreaming = true,
    this.pollingIntervalSeconds = 2,
    this.devices = const [],
    this.usageStats = const [],
    this.summary = const BandwidthSummary(),
    this.trafficHistory = const [],
    this.trafficInterface = 'wan',
    this.availableInterfaces = const ['wan', 'lan'],
    this.isNlbwmonInstalled = false,
    this.nlbwmonReport,
    this.nlbwmonPeriods = const [],
    this.selectedPeriod,
    this.searchQuery = '',
    this.sortMode = BandwidthSortMode.name,
    this.errorMessage,
  });

  List<DeviceBandwidthItem> get filteredAndSortedDevices {
    var list = devices;
    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((item) {
        return item.displayName.toLowerCase().contains(query) ||
            item.ipAddress.contains(query) ||
            item.macAddress.toLowerCase().contains(query) ||
            (item.ssid != null && item.ssid!.toLowerCase().contains(query)) ||
            (item.topProtocol != null &&
                item.topProtocol!.toLowerCase().contains(query));
      }).toList();
    }

    final sorted = List<DeviceBandwidthItem>.from(list);
    switch (sortMode) {
      case BandwidthSortMode.downloadSpeed:
        sorted.sort((a, b) {
          final cmp = b.downloadSpeed.compareTo(a.downloadSpeed);
          if (cmp != 0) return cmp;
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        });
        break;
      case BandwidthSortMode.uploadSpeed:
        sorted.sort((a, b) {
          final cmp = b.uploadSpeed.compareTo(a.uploadSpeed);
          if (cmp != 0) return cmp;
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        });
        break;
      case BandwidthSortMode.totalUsage:
        sorted.sort((a, b) {
          final cmp = (b.totalDownloaded + b.totalUploaded).compareTo(
            a.totalDownloaded + a.totalUploaded,
          );
          if (cmp != 0) return cmp;
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        });
        break;
      case BandwidthSortMode.name:
        sorted.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
        break;
      case BandwidthSortMode.ip:
        sorted.sort((a, b) {
          final aParts = a.ipAddress
              .split('.')
              .map((p) => int.tryParse(p) ?? 0)
              .toList();
          final bParts = b.ipAddress
              .split('.')
              .map((p) => int.tryParse(p) ?? 0)
              .toList();
          for (int i = 0; i < aParts.length && i < bParts.length; i++) {
            final cmp = aParts[i].compareTo(bParts[i]);
            if (cmp != 0) return cmp;
          }
          return a.ipAddress.compareTo(b.ipAddress);
        });
        break;
    }
    return sorted;
  }

  BandwidthMonitorState copyWith({
    bool? isLoading,
    bool? isStreaming,
    int? pollingIntervalSeconds,
    List<DeviceBandwidthItem>? devices,
    List<UsageStatsItem>? usageStats,
    BandwidthSummary? summary,
    List<RealtimeTrafficPoint>? trafficHistory,
    String? trafficInterface,
    List<String>? availableInterfaces,
    bool? isNlbwmonInstalled,
    NlbwmonReport? nlbwmonReport,
    List<String>? nlbwmonPeriods,
    String? selectedPeriod,
    bool clearSelectedPeriod = false,
    String? searchQuery,
    BandwidthSortMode? sortMode,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return BandwidthMonitorState(
      isLoading: isLoading ?? this.isLoading,
      isStreaming: isStreaming ?? this.isStreaming,
      pollingIntervalSeconds:
          pollingIntervalSeconds ?? this.pollingIntervalSeconds,
      devices: devices ?? this.devices,
      usageStats: usageStats ?? this.usageStats,
      summary: summary ?? this.summary,
      trafficHistory: trafficHistory ?? this.trafficHistory,
      trafficInterface: trafficInterface ?? this.trafficInterface,
      availableInterfaces: availableInterfaces ?? this.availableInterfaces,
      isNlbwmonInstalled: isNlbwmonInstalled ?? this.isNlbwmonInstalled,
      nlbwmonReport: nlbwmonReport ?? this.nlbwmonReport,
      nlbwmonPeriods: nlbwmonPeriods ?? this.nlbwmonPeriods,
      selectedPeriod: clearSelectedPeriod
          ? null
          : (selectedPeriod ?? this.selectedPeriod),
      searchQuery: searchQuery ?? this.searchQuery,
      sortMode: sortMode ?? this.sortMode,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

class BandwidthMonitorController extends StateNotifier<BandwidthMonitorState> {
  final Ref _ref;
  final IApiService? _injectedApiService;
  Timer? _pollTimer;
  bool _isPolling = false;

  // Previous sample state for calculating per-device live speeds
  final Map<String, ({int downBytes, int upBytes, DateTime timestamp})>
  _previousDeviceTraffic = {};

  // Track historical peaks
  double _peakDownloadSpeed = 0.0;
  double _peakUploadSpeed = 0.0;
  final Map<String, double> _devicePeakDownload = {};
  final Map<String, double> _devicePeakUpload = {};

  BandwidthMonitorController(
    this._ref, {
    IApiService? apiService,
    bool autoStart = true,
  }) : _injectedApiService = apiService,
       super(
         BandwidthMonitorState(isLoading: autoStart, isStreaming: autoStart),
       ) {
    if (autoStart) {
      _initAndStart();
    }
  }

  AppState get _appState => _ref.read(appStateProvider);
  IApiService? get _apiService =>
      _injectedApiService ??
      _appState.apiService ??
      (_appState.reviewerModeEnabled ? MockApiService() : null);

  String? get _ip =>
      _appState.selectedRouter?.ipAddress ??
      (_appState.reviewerModeEnabled
          ? '192.168.1.1'
          : (_injectedApiService != null ? '192.168.1.1' : null));
  String? get _sysauth =>
      _appState.sysauth ??
      (_appState.reviewerModeEnabled
          ? 'mock_auth_token'
          : (_injectedApiService != null ? 'mock_auth_token' : null));
  bool get _useHttps => _appState.selectedRouter?.useHttps ?? false;

  void _initAndStart() {
    refreshData();
    startStreaming();
  }

  void startStreaming() {
    _pollTimer?.cancel();
    state = state.copyWith(isStreaming: true);
    _pollTimer = Timer.periodic(
      Duration(seconds: state.pollingIntervalSeconds),
      (_) => pollTick(),
    );
  }

  void pauseStreaming() {
    _pollTimer?.cancel();
    _pollTimer = null;
    state = state.copyWith(isStreaming: false);
  }

  void toggleStreaming() {
    if (state.isStreaming) {
      pauseStreaming();
    } else {
      startStreaming();
    }
  }

  void setPollingInterval(int seconds) {
    final clamped = seconds.clamp(1, 10);
    if (state.pollingIntervalSeconds == clamped) return;
    state = state.copyWith(pollingIntervalSeconds: clamped);
    if (state.isStreaming) {
      startStreaming();
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSortMode(BandwidthSortMode mode) {
    state = state.copyWith(sortMode: mode);
  }

  void setTrafficInterface(String iface) {
    if (state.trafficInterface == iface) return;
    state = state.copyWith(trafficInterface: iface, trafficHistory: const []);
    _fetchTrafficHistory();
  }

  void setSelectedPeriod(String? period) {
    state = state.copyWith(
      selectedPeriod: period,
      clearSelectedPeriod: period == null,
    );
    _fetchNlbwmonData();
  }

  String _resolveDeviceForInterface(String logicalIface) {
    // Check dashboard data for network interface mapping
    final dashboardData = _appState.dashboardData;
    if (dashboardData != null) {
      final rawNet = dashboardData['network'];
      if (rawNet is Map) {
        // Pass 1: exact match
        for (final entry in rawNet.entries) {
          if (entry.key.toString() == logicalIface) {
            final val = entry.value;
            if (val is Map) {
              final dev = val['device'] ?? val['l3_device'];
              if (dev != null && dev.toString().isNotEmpty) {
                return dev.toString();
              }
            }
          }
        }
        // Pass 2: prefix/substring match
        for (final entry in rawNet.entries) {
          final k = entry.key.toString().toLowerCase();
          if ((logicalIface == 'wan' && k.startsWith('wan')) ||
              (logicalIface == 'lan' && k.startsWith('lan'))) {
            final val = entry.value;
            if (val is Map) {
              final dev = val['device'] ?? val['l3_device'];
              if (dev != null && dev.toString().isNotEmpty) {
                return dev.toString();
              }
            }
          }
        }
      }
    }
    // Standard defaults on OpenWrt
    if (logicalIface == 'lan') return 'br-lan';
    if (logicalIface == 'wan') return 'eth1';
    return logicalIface;
  }

  Future<void> pollTick() async {
    if (_isPolling) return;
    _isPolling = true;
    try {
      await _fetchConnectedDevices();
    } finally {
      _isPolling = false;
    }
  }

  Future<void> refreshData() async {
    if (!mounted || _isPolling) return;
    _isPolling = true;
    try {
      state = state.copyWith(isLoading: state.devices.isEmpty);
      await _checkNlbwmon();
      if (!mounted) return;
      if (state.isNlbwmonInstalled) {
        await _fetchNlbwmonData();
      }
      if (!mounted) return;
      await _fetchConnectedDevices();
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    } finally {
      _isPolling = false;
    }
  }

  Future<void> _checkNlbwmon() async {
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null || auth == null || api == null) return;

    try {
      final isInstalled = await api.checkNlbwmonInstalled(ip, auth, _useHttps);
      if (!mounted) return;
      List<String> periods = const [];
      if (isInstalled) {
        periods = await api.fetchNlbwmonPeriods(ip, auth, _useHttps);
      }
      if (!mounted) return;
      state = state.copyWith(
        isNlbwmonInstalled: isInstalled,
        nlbwmonPeriods: periods,
      );
    } catch (_) {}
  }

  Future<void> _fetchNlbwmonData() async {
    if (!mounted) return;
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null ||
        auth == null ||
        api == null ||
        !state.isNlbwmonInstalled) {
      return;
    }

    try {
      final report = await api.fetchNlbwmonData(
        ip,
        auth,
        _useHttps,
        groupBy: 'mac',
        period: state.selectedPeriod,
      );
      if (!mounted) return;
      state = state.copyWith(nlbwmonReport: report);
    } catch (_) {}
  }

  Future<void> _fetchTrafficHistory() async {
    if (!mounted) return;
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;
    if (ip == null || auth == null || api == null) return;

    try {
      final deviceName = _resolveDeviceForInterface(state.trafficInterface);
      final history = await api.fetchRealtimeStats(
        ip,
        auth,
        _useHttps,
        mode: 'interface',
        device: deviceName,
      );
      if (!mounted) return;
      if (history.isNotEmpty) {
        state = state.copyWith(trafficHistory: history);
      }
    } catch (_) {}
  }

  Future<void> _fetchConnectedDevices() async {
    try {
      final rawClients = await _appState.fetchClientsForSelectedRouter();
      if (!mounted) return;
      final now = DateTime.now();

      // Check if we have nlbwmon report to enrich clients with active connections & layer7
      final nlbwMap = <String, NlbwmonHostRecord>{};
      if (state.nlbwmonReport != null) {
        for (final rec in state.nlbwmonReport!.records) {
          nlbwMap[rec.mac.toUpperCase()] = rec;
        }
      }

      double currentTotalDown = 0.0;
      double currentTotalUp = 0.0;
      int totalBytesDown = 0;
      int totalBytesUp = 0;
      int activeTrafficCount = 0;

      final items = <DeviceBandwidthItem>[];

      // Only include actively connected clients in the live bandwidth monitor
      final activeClients = rawClients.where((c) => c.isConnected).toList();
      final activeMacs = activeClients.map((c) => c.normalizedMac).toSet();
      _previousDeviceTraffic.removeWhere((mac, _) => !activeMacs.contains(mac));

      for (final client in activeClients) {
        final mac = client.normalizedMac;
        final nlbwRec = nlbwMap[mac];

        final isWireless =
            client.connectionType == ConnectionType.wireless ||
            client.rxBytes != null ||
            client.txBytes != null;

        // Cumulative bytes:
        // For wireless stations: AP tx is client download, AP rx is client upload
        // For wired (nlbwmon): router tx to host is client download, router rx from host is client upload
        final int downBytes = isWireless
            ? (client.txBytes ?? nlbwRec?.txBytes ?? 0)
            : (nlbwRec?.txBytes ?? client.txBytes ?? 0);
        final int upBytes = isWireless
            ? (client.rxBytes ?? nlbwRec?.rxBytes ?? 0)
            : (nlbwRec?.rxBytes ?? client.rxBytes ?? 0);

        totalBytesDown += downBytes;
        totalBytesUp += upBytes;

        // Calculate live speed deltas
        double downSpeed = 0.0;
        double upSpeed = 0.0;

        final prev = _previousDeviceTraffic[mac];
        if (prev != null && (downBytes > 0 || upBytes > 0)) {
          final deltaSeconds =
              now.difference(prev.timestamp).inMilliseconds / 1000.0;
          if (deltaSeconds >= 0.4 && deltaSeconds <= 60.0) {
            // Download (router TX to wireless client or router TX to wired host)
            if (downBytes >= prev.downBytes) {
              downSpeed = (downBytes - prev.downBytes) / deltaSeconds;
            } else if (prev.downBytes > 0x7FFFFFFF && downBytes < 0x20000000) {
              final candidate =
                  ((4294967296 - prev.downBytes) + downBytes) / deltaSeconds;
              // 10 Gbps cap to reject false counter reset spikes on client reconnection
              if (candidate <= 1250000000.0) {
                downSpeed = candidate;
              }
            }

            // Upload (router RX from wireless client or router RX from wired host)
            if (upBytes >= prev.upBytes) {
              upSpeed = (upBytes - prev.upBytes) / deltaSeconds;
            } else if (prev.upBytes > 0x7FFFFFFF && upBytes < 0x20000000) {
              final candidate =
                  ((4294967296 - prev.upBytes) + upBytes) / deltaSeconds;
              if (candidate <= 1250000000.0) {
                upSpeed = candidate;
              }
            }
          }
        } else if (prev == null) {
          // Fallback to client model speeds only on first sample when no previous baseline exists
          if (client.txSpeed != null) {
            downSpeed = client.txSpeed!;
          }
          if (client.rxSpeed != null) {
            upSpeed = client.rxSpeed!;
          }
        }

        if (downSpeed > 1250000000.0) downSpeed = 0.0;
        if (upSpeed > 1250000000.0) upSpeed = 0.0;
        downSpeed = max(0.0, downSpeed);
        upSpeed = max(0.0, upSpeed);

        // Record for next cycle
        _previousDeviceTraffic[mac] = (
          downBytes: downBytes,
          upBytes: upBytes,
          timestamp: now,
        );

        // Update peak speeds
        final currentPeakDown = max(_devicePeakDownload[mac] ?? 0.0, downSpeed);
        final currentPeakUp = max(_devicePeakUpload[mac] ?? 0.0, upSpeed);
        _devicePeakDownload[mac] = currentPeakDown;
        _devicePeakUpload[mac] = currentPeakUp;

        if (downSpeed > 512 || upSpeed > 512) {
          activeTrafficCount++;
        }

        currentTotalDown += downSpeed;
        currentTotalUp += upSpeed;

        items.add(
          DeviceBandwidthItem(
            client: client,
            downloadSpeed: downSpeed,
            uploadSpeed: upSpeed,
            totalDownloaded: downBytes,
            totalUploaded: upBytes,
            peakDownloadSpeed: currentPeakDown,
            peakUploadSpeed: currentPeakUp,
            activeConnections: nlbwRec?.conns,
            topProtocol: nlbwRec?.layer7,
          ),
        );
      }

      _peakDownloadSpeed = max(_peakDownloadSpeed, currentTotalDown);
      _peakUploadSpeed = max(_peakUploadSpeed, currentTotalUp);

      final summary = BandwidthSummary(
        totalDownloadSpeed: currentTotalDown,
        totalUploadSpeed: currentTotalUp,
        peakDownloadSpeed: _peakDownloadSpeed,
        peakUploadSpeed: _peakUploadSpeed,
        totalSessionDownload: totalBytesDown,
        totalSessionUpload: totalBytesUp,
        connectedDevicesCount: activeClients.length,
        activeTrafficDevicesCount: activeTrafficCount,
      );

      // Build comprehensive usage stats covering BOTH connected and not-connected clients
      final usageStatsList = <UsageStatsItem>[];
      final seenMacs = <String>{};

      // 1. Add records from persistent nlbwmon report if available
      if (state.nlbwmonReport != null) {
        for (final rec in state.nlbwmonReport!.records) {
          final macNorm = rec.mac.toUpperCase().replaceAll('-', ':');
          seenMacs.add(macNorm);

          Client? matchingClient;
          for (final c in rawClients) {
            if (c.normalizedMac == macNorm ||
                (rec.ip != null && c.ipAddress == rec.ip)) {
              matchingClient = c;
              break;
            }
          }

          final displayName =
              matchingClient?.displayName ??
              (rec.ip != null ? rec.ip! : rec.mac);
          final isConnected = matchingClient?.isConnected ?? false;
          // In nlbwmon (host perspective): host rx is client download, host tx is client upload
          usageStatsList.add(
            UsageStatsItem(
              mac: rec.mac,
              ip: rec.ip ?? matchingClient?.ipAddress,
              displayName: displayName,
              isConnected: isConnected,
              downloadBytes: rec.rxBytes,
              uploadBytes: rec.txBytes,
              totalBytes: rec.totalBytes,
              conns: rec.conns,
              layer7: rec.layer7,
              connectionType:
                  matchingClient?.connectionType ?? ConnectionType.unknown,
              fromNlbwmon: true,
            ),
          );
        }
      }

      // 2. Add or merge any known clients from rawClients (including disconnected / offline clients!)
      for (final client in rawClients) {
        final macNorm = client.normalizedMac;
        if (seenMacs.contains(macNorm)) continue;

        final isWireless =
            client.connectionType == ConnectionType.wireless ||
            client.rxBytes != null ||
            client.txBytes != null;
        final int downBytes = isWireless
            ? (client.txBytes ?? 0)
            : (client.rxBytes ?? 0);
        final int upBytes = isWireless
            ? (client.rxBytes ?? 0)
            : (client.txBytes ?? 0);
        final totalBytes = downBytes + upBytes;

        // Include any client that has recorded traffic or is a known offline/static lease client
        if (totalBytes > 0 || !client.isConnected || client.isStaticLease) {
          usageStatsList.add(
            UsageStatsItem(
              mac: client.macAddress,
              ip: client.ipAddress,
              displayName: client.displayName,
              isConnected: client.isConnected,
              downloadBytes: downBytes,
              uploadBytes: upBytes,
              totalBytes: totalBytes,
              conns: 0,
              layer7: null,
              connectionType: client.connectionType,
              fromNlbwmon: false,
            ),
          );
        }
      }

      // Sort usage stats by totalBytes descending, then by displayName
      usageStatsList.sort((a, b) {
        final cmp = b.totalBytes.compareTo(a.totalBytes);
        if (cmp != 0) return cmp;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

      if (!mounted) return;
      state = state.copyWith(
        devices: items,
        usageStats: usageStatsList,
        summary: summary,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }
}

final bandwidthMonitorProvider =
    StateNotifierProvider.autoDispose<
      BandwidthMonitorController,
      BandwidthMonitorState
    >((ref) {
      return BandwidthMonitorController(ref);
    });
