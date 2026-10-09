// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';
import 'dart:math';

class ThroughputService {
  final Queue<double> _rxHistory = Queue<double>();
  final Queue<double> _txHistory = Queue<double>();

  double _currentRxRate = 0;
  double _currentTxRate = 0;
  Map<String, dynamic>? _lastStats;
  DateTime? _lastTimestamp;

  // Per-interface tracking
  final Map<String, Queue<double>> _rxHistoryPerInterface = {};
  final Map<String, Queue<double>> _txHistoryPerInterface = {};
  final Map<String, double> _currentRxRatePerInterface = {};
  final Map<String, double> _currentTxRatePerInterface = {};
  final Map<String, Map<String, dynamic>?> _lastStatsPerInterface = {};
  final Map<String, DateTime?> _lastTimestampPerInterface = {};

  static const int _maxHistoryLength = 50;
  static const double _maxRate = 1000.0 * 1024.0 * 1024.0; // 1 GB/s
  static const double _minElapsedSeconds = 0.1;
  static const double _maxElapsedSeconds =
      15.0; // Discontinuity threshold for paused app or tab gaps

  List<double> get rxHistory => _rxHistory.toList();
  List<double> get txHistory => _txHistory.toList();
  double get currentRxRate => _currentRxRate;
  double get currentTxRate => _currentTxRate;

  // Interface-specific getters
  List<double> getRxHistoryForInterface(String interface) {
    if (_rxHistoryPerInterface.containsKey(interface)) {
      return _rxHistoryPerInterface[interface]!.toList();
    }
    if (interface == 'lan' && _rxHistoryPerInterface.containsKey('br-lan')) {
      return _rxHistoryPerInterface['br-lan']!.toList();
    }
    if (interface == 'wan' && _rxHistoryPerInterface.containsKey('eth0')) {
      return _rxHistoryPerInterface['eth0']!.toList();
    }
    return [];
  }

  List<double> getTxHistoryForInterface(String interface) {
    if (_txHistoryPerInterface.containsKey(interface)) {
      return _txHistoryPerInterface[interface]!.toList();
    }
    if (interface == 'lan' && _txHistoryPerInterface.containsKey('br-lan')) {
      return _txHistoryPerInterface['br-lan']!.toList();
    }
    if (interface == 'wan' && _txHistoryPerInterface.containsKey('eth0')) {
      return _txHistoryPerInterface['eth0']!.toList();
    }
    return [];
  }

  double getCurrentRxRateForInterface(String interface) {
    if (_currentRxRatePerInterface.containsKey(interface)) {
      return _currentRxRatePerInterface[interface]!;
    }
    if (interface == 'lan' &&
        _currentRxRatePerInterface.containsKey('br-lan')) {
      return _currentRxRatePerInterface['br-lan']!;
    }
    if (interface == 'wan' && _currentRxRatePerInterface.containsKey('eth0')) {
      return _currentRxRatePerInterface['eth0']!;
    }
    return 0.0;
  }

  double getCurrentTxRateForInterface(String interface) {
    if (_currentTxRatePerInterface.containsKey(interface)) {
      return _currentTxRatePerInterface[interface]!;
    }
    if (interface == 'lan' &&
        _currentTxRatePerInterface.containsKey('br-lan')) {
      return _currentTxRatePerInterface['br-lan']!;
    }
    if (interface == 'wan' && _currentTxRatePerInterface.containsKey('eth0')) {
      return _currentTxRatePerInterface['eth0']!;
    }
    return 0.0;
  }

  static num _byteCounter(Map<String, dynamic> device, String key) {
    final stats = device['stats'];
    if (stats is Map) {
      final value = stats[key];
      if (value is num) return value;
    }
    final direct = device[key];
    if (direct is num) return direct;
    return 0;
  }

  void updateThroughput(
    Map<String, dynamic>? networkData,
    Set<String> wanDeviceNames, {
    String? specificInterface,
  }) {
    final now = DateTime.now();

    // Always update per-interface throughput for all interfaces
    if (networkData != null) {
      networkData.forEach((devName, devData) {
        _updateInterfaceThroughput(devName, devData, now);
      });
    }

    // Update overall throughput
    String? matchedSpecificKey;
    if (specificInterface != null && specificInterface.isNotEmpty) {
      matchedSpecificKey = _resolveInterfaceKey(networkData, specificInterface);
    }

    if (matchedSpecificKey != null && networkData != null) {
      _updateSpecificInterfaceThroughput(
        matchedSpecificKey,
        networkData[matchedSpecificKey],
        now,
      );
    } else {
      // Update combined throughput as before
      if (_lastStats == null || _lastTimestamp == null) {
        _lastStats = networkData;
        _lastTimestamp = now;
        // Only seed an initial zero-rate data point if history is completely empty
        if (_rxHistory.isEmpty && _txHistory.isEmpty) {
          _addToHistory(0.0, 0.0);
        }
        return;
      }

      final elapsedSeconds =
          now.difference(_lastTimestamp!).inMilliseconds / 1000.0;

      // Handle timing gaps (e.g. app paused in background, tab switched away, or device slept)
      if (elapsedSeconds > _maxElapsedSeconds) {
        _lastStats = networkData;
        _lastTimestamp = now;
        return;
      }

      // Only calculate throughput if we have a reasonable time difference
      if (elapsedSeconds >= _minElapsedSeconds) {
        num diffRx = 0;
        num diffTx = 0;

        if (networkData != null && _lastStats != null) {
          var diffs = _sumDeviceByteDiffs(
            networkData,
            _lastStats!,
            wanDeviceNames,
            elapsedSeconds,
          );
          diffRx = diffs.diffRx;
          diffTx = diffs.diffTx;
          if (diffRx == 0 &&
              diffTx == 0 &&
              wanDeviceNames.isNotEmpty &&
              !_anyWanDeviceMatched(networkData, wanDeviceNames)) {
            diffs = _sumDeviceByteDiffs(
              networkData,
              _lastStats!,
              const {},
              elapsedSeconds,
            );
            diffRx = diffs.diffRx;
            diffTx = diffs.diffTx;
          }
        }

        // Calculate rates with a reasonable maximum to prevent spikes
        final rxRate = max(0, diffRx / elapsedSeconds);
        final txRate = max(0, diffTx / elapsedSeconds);

        // Cap the rates to prevent unrealistic spikes
        _currentRxRate = min(rxRate.toDouble(), _maxRate);
        _currentTxRate = min(txRate.toDouble(), _maxRate);

        _addToHistory(_currentRxRate, _currentTxRate);

        _lastStats = networkData;
        _lastTimestamp = now;
      }
    }
  }

  static String? _resolveInterfaceKey(
    Map<String, dynamic>? networkData,
    String specificInterface,
  ) {
    if (networkData == null || networkData.isEmpty) return null;
    if (networkData.containsKey(specificInterface)) {
      return specificInterface;
    }
    for (final entry in networkData.entries) {
      final devName = entry.key;
      if (devName == specificInterface ||
          (specificInterface == 'lan' && devName == 'br-lan') ||
          (specificInterface == 'wan' &&
              (devName == 'eth0' || devName == 'wan'))) {
        return devName;
      }
      final devData = entry.value;
      if (devData is Map<String, dynamic>) {
        if (devData['device'] == specificInterface ||
            devData['l3_device'] == specificInterface) {
          return devName;
        }
      }
    }
    for (final key in networkData.keys) {
      if (key == specificInterface ||
          key.startsWith('$specificInterface@') ||
          key.startsWith('$specificInterface.')) {
        return key;
      }
    }
    return null;
  }

  static Set<String> _effectiveDevices(
    Map<String, dynamic> networkData,
    Set<String> wanDeviceNames,
  ) {
    if (wanDeviceNames.isNotEmpty) return wanDeviceNames;
    for (final key in ['wan', 'pppoe-wan', 'br-lan', 'eth0', 'eth1', 'eth2']) {
      if (networkData.containsKey(key)) {
        return {key};
      }
    }
    return const {};
  }

  static bool _anyWanDeviceMatched(
    Map<String, dynamic> networkData,
    Set<String> wanDeviceNames,
  ) {
    for (final devName in networkData.keys) {
      if (devName == 'lo' || devName == 'loopback') continue;
      final devData = networkData[devName];
      if (devData is! Map<String, dynamic>) continue;
      final deviceField = devData['device'] as String?;
      if (wanDeviceNames.contains(devName) ||
          (deviceField != null && wanDeviceNames.contains(deviceField))) {
        return true;
      }
    }
    return false;
  }

  static ({num diffRx, num diffTx}) _sumDeviceByteDiffs(
    Map<String, dynamic> networkData,
    Map<String, dynamic> lastStats,
    Set<String> wanDeviceNames,
    double elapsedSeconds,
  ) {
    num diffRx = 0;
    num diffTx = 0;
    final effectiveDevices = _effectiveDevices(networkData, wanDeviceNames);

    networkData.forEach((devName, devData) {
      if (devName == 'lo' || devName == 'loopback') return;
      if (devData is! Map<String, dynamic>) return;
      final deviceField = devData['device'] as String?;
      final included =
          effectiveDevices.isEmpty ||
          effectiveDevices.contains(devName) ||
          (deviceField != null && effectiveDevices.contains(deviceField));
      if (!included) return;

      final lastDevData = lastStats[devName];
      if (lastDevData is! Map<String, dynamic>) return;

      final lastDevRx = _byteCounter(lastDevData, 'rx_bytes');
      final lastDevTx = _byteCounter(lastDevData, 'tx_bytes');
      final currentDevRx = _byteCounter(devData, 'rx_bytes');
      final currentDevTx = _byteCounter(devData, 'tx_bytes');

      num dRx = currentDevRx - lastDevRx;
      num dTx = currentDevTx - lastDevTx;

      const num uint32Max = 4294967296;
      if (dRx < 0) {
        if (lastDevRx > 3221225472 &&
            currentDevRx < 1073741824 &&
            (currentDevRx + uint32Max - lastDevRx) <
                _maxRate * elapsedSeconds) {
          dRx = currentDevRx + uint32Max - lastDevRx;
        } else {
          dRx = 0;
        }
      }
      if (dTx < 0) {
        if (lastDevTx > 3221225472 &&
            currentDevTx < 1073741824 &&
            (currentDevTx + uint32Max - lastDevTx) <
                _maxRate * elapsedSeconds) {
          dTx = currentDevTx + uint32Max - lastDevTx;
        } else {
          dTx = 0;
        }
      }

      diffRx += dRx;
      diffTx += dTx;
    });

    return (diffRx: diffRx, diffTx: diffTx);
  }

  void _updateInterfaceThroughput(
    String interface,
    dynamic devData,
    DateTime now,
  ) {
    if (devData == null || devData is! Map<String, dynamic>) return;

    final lastStats = _lastStatsPerInterface[interface];
    final lastTimestamp = _lastTimestampPerInterface[interface];

    if (lastTimestamp != null && !now.isAfter(lastTimestamp)) {
      return;
    }

    if (lastStats == null || lastTimestamp == null) {
      _lastStatsPerInterface[interface] = devData;
      _lastTimestampPerInterface[interface] = now;

      // Initialize history for this interface only if empty
      final rxQ = _rxHistoryPerInterface.putIfAbsent(
        interface,
        () => Queue<double>(),
      );
      final txQ = _txHistoryPerInterface.putIfAbsent(
        interface,
        () => Queue<double>(),
      );
      if (rxQ.isEmpty && txQ.isEmpty) {
        rxQ.add(0.0);
        txQ.add(0.0);
      }
      return;
    }

    final elapsedSeconds =
        now.difference(lastTimestamp).inMilliseconds / 1000.0;

    // Handle timing gaps for per-interface tracking
    if (elapsedSeconds > _maxElapsedSeconds) {
      _lastStatsPerInterface[interface] = devData;
      _lastTimestampPerInterface[interface] = now;
      return;
    }

    if (elapsedSeconds >= _minElapsedSeconds) {
      // Handle both formats: stats.rx_bytes and direct rx_bytes
      final lastRx =
          (lastStats['stats']?['rx_bytes'] ?? lastStats['rx_bytes'] ?? 0)
              as num;
      final lastTx =
          (lastStats['stats']?['tx_bytes'] ?? lastStats['tx_bytes'] ?? 0)
              as num;
      final currentRx =
          (devData['stats']?['rx_bytes'] ?? devData['rx_bytes'] ?? 0) as num;
      final currentTx =
          (devData['stats']?['tx_bytes'] ?? devData['tx_bytes'] ?? 0) as num;

      num diffRx = currentRx - lastRx;
      num diffTx = currentTx - lastTx;

      if (diffRx < 0 || diffTx < 0) {
        const num uint32Max = 4294967296;
        bool validRxRollover = false;
        if (diffRx < 0 &&
            lastRx > 3221225472 &&
            currentRx < 1073741824 &&
            (currentRx + uint32Max - lastRx) < _maxRate * elapsedSeconds) {
          diffRx = currentRx + uint32Max - lastRx;
          validRxRollover = true;
        }
        bool validTxRollover = false;
        if (diffTx < 0 &&
            lastTx > 3221225472 &&
            currentTx < 1073741824 &&
            (currentTx + uint32Max - lastTx) < _maxRate * elapsedSeconds) {
          diffTx = currentTx + uint32Max - lastTx;
          validTxRollover = true;
        }
        if ((diffRx < 0 && !validRxRollover) ||
            (diffTx < 0 && !validTxRollover)) {
          _lastStatsPerInterface[interface] = devData;
          _lastTimestampPerInterface[interface] = now;
          _currentRxRatePerInterface[interface] = 0.0;
          _currentTxRatePerInterface[interface] = 0.0;
          return;
        }
      }

      final rxRate = max(0, diffRx / elapsedSeconds);
      final txRate = max(0, diffTx / elapsedSeconds);

      _currentRxRatePerInterface[interface] = min(rxRate.toDouble(), _maxRate);
      _currentTxRatePerInterface[interface] = min(txRate.toDouble(), _maxRate);

      _addToInterfaceHistory(
        interface,
        _currentRxRatePerInterface[interface]!,
        _currentTxRatePerInterface[interface]!,
      );

      _lastStatsPerInterface[interface] = devData;
      _lastTimestampPerInterface[interface] = now;
    }
  }

  void _updateSpecificInterfaceThroughput(
    String interface,
    dynamic devData,
    DateTime now,
  ) {
    if (devData == null || devData is! Map<String, dynamic>) return;

    final rxRate = _currentRxRatePerInterface[interface] ?? 0.0;
    final txRate = _currentTxRatePerInterface[interface] ?? 0.0;

    _currentRxRate = rxRate;
    _currentTxRate = txRate;

    // Use the interface's history for the main display
    final rxHist = _rxHistoryPerInterface[interface];
    final txHist = _txHistoryPerInterface[interface];

    if (rxHist != null && txHist != null && rxHist.isNotEmpty) {
      _rxHistory.clear();
      _txHistory.clear();
      _rxHistory.addAll(rxHist);
      _txHistory.addAll(txHist);
    }
  }

  void _addToInterfaceHistory(String interface, double rxRate, double txRate) {
    final rxHist = _rxHistoryPerInterface.putIfAbsent(
      interface,
      () => Queue<double>(),
    );
    final txHist = _txHistoryPerInterface.putIfAbsent(
      interface,
      () => Queue<double>(),
    );

    rxHist.add(rxRate);
    txHist.add(txRate);

    // Maintain fixed queue size
    if (rxHist.length > _maxHistoryLength) {
      rxHist.removeFirst();
    }
    if (txHist.length > _maxHistoryLength) {
      txHist.removeFirst();
    }
  }

  void _addToHistory(double rxRate, double txRate) {
    _rxHistory.add(rxRate);
    _txHistory.add(txRate);

    // Maintain fixed queue size for O(1) performance
    if (_rxHistory.length > _maxHistoryLength) {
      _rxHistory.removeFirst();
    }
    if (_txHistory.length > _maxHistoryLength) {
      _txHistory.removeFirst();
    }
  }

  /// Resets the baseline timestamp and stats without clearing historical rate queues.
  /// Used when resuming from background or tab switching after an interruption.
  void resetBaseline() {
    _lastStats = null;
    _lastTimestamp = null;
    _lastStatsPerInterface.clear();
    _lastTimestampPerInterface.clear();
  }

  void clear() {
    _rxHistory.clear();
    _txHistory.clear();
    _currentRxRate = 0;
    _currentTxRate = 0;
    _lastStats = null;
    _lastTimestamp = null;

    // Clear per-interface data
    _rxHistoryPerInterface.clear();
    _txHistoryPerInterface.clear();
    _currentRxRatePerInterface.clear();
    _currentTxRatePerInterface.clear();
    _lastStatsPerInterface.clear();
    _lastTimestampPerInterface.clear();
  }
}
