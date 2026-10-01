// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// Thermal status categories based on typical router SoC/radio operating temperatures.
enum ThermalStatus {
  cool, // < 50°C
  normal, // 50°C - 65°C
  warm, // 65°C - 75°C
  hot, // 75°C - 85°C
  critical, // > 85°C
  unknown;

  static ThermalStatus fromTemperature(double? temp) {
    if (temp == null) return ThermalStatus.unknown;
    if (temp < 50.0) return ThermalStatus.cool;
    if (temp <= 65.0) return ThermalStatus.normal;
    if (temp <= 75.0) return ThermalStatus.warm;
    if (temp <= 85.0) return ThermalStatus.hot;
    return ThermalStatus.critical;
  }
}

extension ThermalStatusExtension on ThermalStatus {
  String get label {
    switch (this) {
      case ThermalStatus.cool:
        return 'Cool';
      case ThermalStatus.normal:
        return 'Normal';
      case ThermalStatus.warm:
        return 'Warm';
      case ThermalStatus.hot:
        return 'Hot';
      case ThermalStatus.critical:
        return 'Critical';
      case ThermalStatus.unknown:
        return 'Unknown';
    }
  }

  Color color(BuildContext context) {
    switch (this) {
      case ThermalStatus.cool:
        return Colors.teal;
      case ThermalStatus.normal:
        return Colors.green;
      case ThermalStatus.warm:
        return Colors.orange;
      case ThermalStatus.hot:
        return Colors.deepOrange;
      case ThermalStatus.critical:
        return Colors.red;
      case ThermalStatus.unknown:
        return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    }
  }
}

/// Represents an individual hardware thermal sensor on the router.
class ThermalSensor {
  final String id;
  final String name;
  final String rawName;
  final String type;
  final double value; // In degrees Celsius
  final double? criticalTemp; // In degrees Celsius if available
  final double? maxTemp; // In degrees Celsius if available

  const ThermalSensor({
    required this.id,
    required this.name,
    required this.rawName,
    required this.type,
    required this.value,
    this.criticalTemp,
    this.maxTemp,
  });

  String get formattedValue => '${value.toStringAsFixed(1)}°C';

  String formattedValueForUnit(String unit) {
    if (unit.toLowerCase() == 'fahrenheit') {
      final f = RouterTemperature.toFahrenheit(value);
      return '${f.toStringAsFixed(1)}°F';
    }
    return '${value.toStringAsFixed(1)}°C';
  }

  ThermalStatus get status {
    if (criticalTemp != null && value >= criticalTemp!) {
      return ThermalStatus.critical;
    }
    if (maxTemp != null && value >= maxTemp!) {
      return ThermalStatus.hot;
    }
    if (value < 50.0) return ThermalStatus.cool;
    if (value <= 65.0) return ThermalStatus.normal;
    if (value <= 75.0) return ThermalStatus.warm;
    if (value <= 85.0) return ThermalStatus.hot;
    return ThermalStatus.critical;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'rawName': rawName,
    'type': type,
    'value': value,
    'criticalTemp': criticalTemp,
    'maxTemp': maxTemp,
  };

  factory ThermalSensor.fromJson(Map<String, dynamic> json) => ThermalSensor(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Sensor',
    rawName: json['rawName']?.toString() ?? '',
    type: json['type']?.toString() ?? 'sensor',
    value: (json['value'] as num?)?.toDouble() ?? 0.0,
    criticalTemp: (json['criticalTemp'] as num?)?.toDouble(),
    maxTemp: (json['maxTemp'] as num?)?.toDouble(),
  );
}

/// Aggregated thermal model for the router.
class RouterTemperature {
  final bool isSupported;
  final bool hasPhysicalSensors;
  final bool isHandlerInstalled;
  final double? mainTemperature; // Representative temperature in °C
  final List<ThermalSensor> sensors;
  final String? errorMessage;
  final DateTime updatedAt;

  const RouterTemperature({
    required this.isSupported,
    this.hasPhysicalSensors = false,
    this.isHandlerInstalled = false,
    this.mainTemperature,
    this.sensors = const [],
    this.errorMessage,
    required this.updatedAt,
  });

  /// Factory for routers without thermal hardware or when sensors cannot be probed.
  factory RouterTemperature.unavailable({
    String? reason,
    bool hasPhysicalSensors = false,
    bool isHandlerInstalled = false,
  }) => RouterTemperature(
    isSupported: false,
    hasPhysicalSensors: hasPhysicalSensors,
    isHandlerInstalled: isHandlerInstalled,
    errorMessage:
        reason ??
        'Thermal sensors not supported or inaccessible on this router',
    updatedAt: DateTime.now(),
  );

  /// Realistic mock temperature for offline / reviewer testing.
  factory RouterTemperature.mock() => RouterTemperature(
    isSupported: true,
    hasPhysicalSensors: true,
    isHandlerInstalled: true,
    mainTemperature: 51.5,
    sensors: [
      const ThermalSensor(
        id: 'thermal_zone0',
        name: 'CPU Thermal',
        rawName: 'cpu-thermal',
        type: 'thermal_zone',
        value: 51.5,
      ),
      const ThermalSensor(
        id: 'hwmon0/temp1_input',
        name: 'Wi-Fi 5GHz (ath10k)',
        rawName: 'ath10k_hwmon',
        type: 'hwmon',
        value: 54.0,
      ),
      const ThermalSensor(
        id: 'hwmon1/temp1_input',
        name: 'Wi-Fi 2.4GHz (ath10k)',
        rawName: 'ath10k_hwmon',
        type: 'hwmon',
        value: 48.0,
      ),
    ],
    updatedAt: DateTime.now(),
  );

  /// Constructs a RouterTemperature from a list of discovered sensors.
  factory RouterTemperature.fromSensors(
    List<ThermalSensor> sensorList, {
    DateTime? updatedAt,
  }) {
    if (sensorList.isEmpty) {
      return RouterTemperature.unavailable();
    }

    // Pick main representative temperature:
    // 1. Prefer CPU/SoC sensor if available.
    // 2. Otherwise use the highest temperature (peak thermal stress).
    ThermalSensor? primary;
    for (final s in sensorList) {
      final lowerName = '${s.name} ${s.rawName} ${s.id}'.toLowerCase();
      if (lowerName.contains('cpu') ||
          lowerName.contains('soc') ||
          lowerName.contains('core') ||
          lowerName.contains('package')) {
        primary = s;
        break;
      }
    }

    primary ??= sensorList.reduce(
      (curr, next) => curr.value > next.value ? curr : next,
    );

    return RouterTemperature(
      isSupported: true,
      hasPhysicalSensors: true,
      isHandlerInstalled: true,
      mainTemperature: primary.value,
      sensors: sensorList,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Whether thermal monitoring is fully active with valid readings.
  bool get isFullySupported => isSupported && mainTemperature != null;

  /// Whether hardware sensors exist, but native RPC handler/ACL entry is missing.
  bool get needsNativeHandler =>
      hasPhysicalSensors && !isHandlerInstalled && !isSupported;

  /// Whether hardware physically lacks thermal sensors.
  bool get isHardwareUnsupported => !hasPhysicalSensors && !isSupported;

  /// Converts Celsius temperature to Fahrenheit.
  static double toFahrenheit(double celsius) => (celsius * 1.8) + 32.0;

  /// Converts Fahrenheit temperature to Celsius.
  static double toCelsius(double fahrenheit) => (fahrenheit - 32.0) / 1.8;

  /// Formatted display string for specified temperature unit ('celsius' or 'fahrenheit').
  String formattedTemperatureForUnit(String unit, {bool precise = false}) {
    if (!isSupported || mainTemperature == null) return 'N/A';
    if (unit.toLowerCase() == 'fahrenheit') {
      final f = toFahrenheit(mainTemperature!);
      return precise
          ? '${f.toStringAsFixed(1)}°F'
          : '${f.toStringAsFixed(0)}°F';
    }
    return precise
        ? '${mainTemperature!.toStringAsFixed(1)}°C'
        : '${mainTemperature!.toStringAsFixed(0)}°C';
  }

  /// Formatted display string (defaults to Celsius, e.g. "54°C" or "N/A").
  String get formattedTemperature => formattedTemperatureForUnit('celsius');

  /// Formatted display string with 1 decimal place (defaults to Celsius, e.g. "54.2°C").
  String get formattedTemperaturePrecise =>
      formattedTemperatureForUnit('celsius', precise: true);

  ThermalStatus get status {
    if (!isSupported || mainTemperature == null) return ThermalStatus.unknown;
    return ThermalStatus.fromTemperature(mainTemperature);
  }

  String get statusLabel => status.label;

  /// Highest temperature recorded across all discovered sensors.
  double? get peakTemperature => highestSensor?.value;

  /// Helper to get the primary sensor if identifiable.
  ThermalSensor? get primarySensor {
    if (sensors.isEmpty) return null;
    for (final s in sensors) {
      final lower = '${s.name} ${s.rawName} ${s.id}'.toLowerCase();
      if (lower.contains('cpu') ||
          lower.contains('soc') ||
          lower.contains('core') ||
          lower.contains('package')) {
        return s;
      }
    }
    return highestSensor;
  }

  /// Sensor with the highest current temperature reading.
  ThermalSensor? get highestSensor {
    if (sensors.isEmpty) return null;
    return sensors.reduce((a, b) => a.value > b.value ? a : b);
  }

  RouterTemperature copyWith({
    bool? isSupported,
    bool? hasPhysicalSensors,
    bool? isHandlerInstalled,
    double? mainTemperature,
    List<ThermalSensor>? sensors,
    String? errorMessage,
    DateTime? updatedAt,
  }) {
    return RouterTemperature(
      isSupported: isSupported ?? this.isSupported,
      hasPhysicalSensors: hasPhysicalSensors ?? this.hasPhysicalSensors,
      isHandlerInstalled: isHandlerInstalled ?? this.isHandlerInstalled,
      mainTemperature: mainTemperature ?? this.mainTemperature,
      sensors: sensors ?? this.sensors,
      errorMessage: errorMessage ?? this.errorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'isSupported': isSupported,
    'hasPhysicalSensors': hasPhysicalSensors,
    'isHandlerInstalled': isHandlerInstalled,
    'mainTemperature': mainTemperature,
    'sensors': sensors.map((s) => s.toJson()).toList(),
    'errorMessage': errorMessage,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory RouterTemperature.fromJson(Map<String, dynamic> json) {
    final isSupported = json['isSupported'] as bool? ?? false;
    final hasPhysicalSensors =
        json['hasPhysicalSensors'] as bool? ?? isSupported;
    final isHandlerInstalled =
        json['isHandlerInstalled'] as bool? ?? isSupported;
    final mainTemp = (json['mainTemperature'] as num?)?.toDouble();
    final rawSensors = json['sensors'] as List?;
    final sensors = rawSensors != null
        ? rawSensors
              .whereType<Map<String, dynamic>>()
              .map(ThermalSensor.fromJson)
              .toList()
        : <ThermalSensor>[];

    final updated = json['updatedAt'] != null
        ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
        : DateTime.now();

    return RouterTemperature(
      isSupported: isSupported,
      hasPhysicalSensors: hasPhysicalSensors,
      isHandlerInstalled: isHandlerInstalled,
      mainTemperature: mainTemp,
      sensors: sensors,
      errorMessage: json['errorMessage']?.toString(),
      updatedAt: updated,
    );
  }

  /// Normalizes temperature value from millidegrees (e.g. 54000) or direct degrees (e.g. 54.0).
  /// Rejects values outside the reasonable range [-40°C, 150°C].
  static double? normalizeTemperature(dynamic raw) {
    if (raw == null) return null;
    final num? n = raw is num ? raw : num.tryParse(raw.toString().trim());
    if (n == null) return null;
    double val = n.toDouble();

    // Linux kernel sysfs temperature is in millidegrees Celsius
    if (val.abs() >= 1000.0) {
      val = val / 1000.0;
    }

    // Hardware sanity check: router operating temperatures outside [-40, 150] are invalid
    if (val < -40.0 || val > 150.0) return null;
    return val;
  }

  /// Parses diverse raw data payloads from OpenWrt into a [RouterTemperature] object.
  factory RouterTemperature.parse(dynamic rawData) {
    if (rawData == null) {
      return RouterTemperature.unavailable();
    }
    if (rawData is RouterTemperature) {
      return rawData;
    }

    if (rawData is Map) {
      final map = Map<String, dynamic>.from(rawData);
      if (map.containsKey('isSupported')) {
        return RouterTemperature.fromJson(map);
      }

      // Check for luci-app-temp-status ubus response
      if (map.containsKey('sensors')) {
        return _parseLuciTempStatus(map);
      }

      // Check for simple key-value temperature in map (e.g. sysInfo['temperature'] or {'temperature': 54})
      final tempVal =
          map['temperature'] ??
          map['temp'] ??
          map['cpu_temp'] ??
          map['soc_temp'];
      if (tempVal != null) {
        final norm = normalizeTemperature(tempVal);
        if (norm != null) {
          return RouterTemperature.fromSensors([
            ThermalSensor(
              id: 'sysinfo_temp',
              name: 'SoC Temperature',
              rawName: 'sysinfo',
              type: 'system',
              value: norm,
            ),
          ]);
        }
      }

      // Check for file.read output with 'data'
      if (map['data'] != null || map['stdout'] != null) {
        final content = (map['data'] ?? map['stdout']).toString().trim();
        return RouterTemperature.parse(content);
      }
    }

    if (rawData is String) {
      final text = rawData.trim();
      if (text.isEmpty) {
        return RouterTemperature.unavailable();
      }

      // Case A: Pipe-separated output from sysfs probe script:
      // thermal|type|id|temp
      // hwmon|name|id|temp
      if (text.contains('|')) {
        final lines = text.split('\n');
        final sensors = <ThermalSensor>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final parts = trimmed.split('|');
          if (parts.length >= 4) {
            final kind = parts[0].trim();
            final rawName = parts[1].trim();
            final id = parts[2].trim();
            final tempVal = normalizeTemperature(parts[3]);
            if (tempVal != null) {
              sensors.add(
                ThermalSensor(
                  id: id,
                  name: humanizeSensorName(rawName, id, kind: kind),
                  rawName: rawName,
                  type: kind,
                  value: tempVal,
                ),
              );
            }
          }
        }
        if (sensors.isNotEmpty) {
          return RouterTemperature.fromSensors(sensors);
        }
      }

      // Case B: Colon-separated sysfs output (/sys/class/...:54000)
      if (text.contains(':')) {
        final lines = text.split('\n');
        final sensors = <ThermalSensor>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final idx = trimmed.lastIndexOf(':');
          if (idx > 0 && idx < trimmed.length - 1) {
            final path = trimmed.substring(0, idx).trim();
            final valStr = trimmed.substring(idx + 1).trim();
            final tempVal = normalizeTemperature(valStr);
            if (tempVal != null) {
              final id = path.split('/').last;
              sensors.add(
                ThermalSensor(
                  id: id,
                  name: humanizeSensorName(id, path),
                  rawName: id,
                  type: path.contains('thermal') ? 'thermal_zone' : 'hwmon',
                  value: tempVal,
                ),
              );
            }
          }
        }
        if (sensors.isNotEmpty) {
          return RouterTemperature.fromSensors(sensors);
        }
      }

      // Case C: Single numeric temperature string (e.g. "54000" or "54.0")
      final singleTemp = normalizeTemperature(text);
      if (singleTemp != null) {
        return RouterTemperature.fromSensors([
          ThermalSensor(
            id: 'sensor0',
            name: 'Router Thermal',
            rawName: 'sensor0',
            type: 'generic',
            value: singleTemp,
          ),
        ]);
      }
    }

    return RouterTemperature.unavailable();
  }

  /// Parses structured json returned by OpenWrt luci-app-temp-status ubus call.
  static RouterTemperature _parseLuciTempStatus(Map<String, dynamic> data) {
    final sensors = <ThermalSensor>[];
    final sensorsMap = data['sensors'];

    if (sensorsMap is Map) {
      // Group '0': hwmon
      final hwmonList = sensorsMap['0'] ?? sensorsMap[0];
      if (hwmonList is List) {
        for (final item in hwmonList) {
          if (item is Map) {
            final title = item['title']?.toString() ?? 'hwmon';
            final sources = item['sources'];
            if (sources is List) {
              for (final src in sources) {
                if (src is Map) {
                  final rawTemp = src['temp'];
                  final temp = normalizeTemperature(rawTemp);
                  if (temp != null) {
                    final label = src['label']?.toString();
                    final itemStr = src['item']?.toString() ?? 'temp';
                    final id = '${item['item'] ?? 'hwmon'}/$itemStr';

                    double? crit;
                    double? maxT;
                    final tpoints = src['tpoints'];
                    if (tpoints is Map) {
                      for (final tp in tpoints.values) {
                        if (tp is Map) {
                          final tpType = tp['type']?.toString();
                          final tpTemp = normalizeTemperature(tp['temp']);
                          if (tpType == 'critical') crit = tpTemp;
                          if (tpType == 'max') maxT = tpTemp;
                        }
                      }
                    }

                    sensors.add(
                      ThermalSensor(
                        id: id,
                        name: humanizeSensorName(title, id, label: label),
                        rawName: title,
                        type: 'hwmon',
                        value: temp,
                        criticalTemp: crit,
                        maxTemp: maxT,
                      ),
                    );
                  }
                }
              }
            }
          }
        }
      }

      // Group '1': thermal_zone
      final thermalList = sensorsMap['1'] ?? sensorsMap[1];
      if (thermalList is List) {
        for (final item in thermalList) {
          if (item is Map) {
            final title = item['title']?.toString() ?? 'thermal_zone';
            final sources = item['sources'];
            if (sources is List) {
              for (final src in sources) {
                if (src is Map) {
                  final rawTemp = src['temp'];
                  final temp = normalizeTemperature(rawTemp);
                  if (temp != null) {
                    final id = item['item']?.toString() ?? 'thermal_zone';
                    sensors.add(
                      ThermalSensor(
                        id: id,
                        name: humanizeSensorName(title, id, kind: 'thermal'),
                        rawName: title,
                        type: 'thermal_zone',
                        value: temp,
                      ),
                    );
                  }
                }
              }
            }
          }
        }
      }
    }

    if (sensors.isNotEmpty) {
      return RouterTemperature.fromSensors(sensors);
    }

    return RouterTemperature.unavailable();
  }

  /// Translates kernel sysfs identifiers into readable sensor descriptions.
  static String humanizeSensorName(
    String rawName,
    String id, {
    String? label,
    String? kind,
  }) {
    if (label != null && label.trim().isNotEmpty) {
      return label.trim();
    }

    final lower = rawName.toLowerCase();
    final lowerId = id.toLowerCase();

    // Qualcomm Ath10k / Ath11k / Ath12k / IPQ
    if (lower.contains('ath10k') ||
        lower.contains('ath11k') ||
        lower.contains('ath12k') ||
        lower.contains('qcom')) {
      final hwMatch = RegExp(r'hwmon([0-9]+)').firstMatch(lowerId);
      final idx = hwMatch != null ? int.tryParse(hwMatch.group(1)!) : null;
      if (idx != null) {
        return 'Qualcomm Wi-Fi (Radio ${idx + 1})';
      }
      return 'Qualcomm Wi-Fi Radio';
    }

    // MediaTek mt76 / mt79
    if (lower.contains('mt76') || lower.contains('mt79')) {
      final hwMatch = RegExp(r'hwmon([0-9]+)').firstMatch(lowerId);
      final idx = hwMatch != null ? int.tryParse(hwMatch.group(1)!) : null;
      if (idx != null) {
        return 'MediaTek Wi-Fi (Radio ${idx + 1})';
      }
      return 'MediaTek Wi-Fi Radio';
    }

    // CPU / SoC
    if (lower.contains('cpu') ||
        lower.contains('core') ||
        lower.contains('soc') ||
        lower.contains('k10temp') ||
        lower.contains('coretemp')) {
      return 'CPU / SoC';
    }

    // Thermal zones
    if (lowerId.contains('thermal_zone')) {
      final match = RegExp(r'thermal_zone([0-9]+)').firstMatch(lowerId);
      if (match != null) {
        final zoneNum = match.group(1);
        if (rawName.isNotEmpty && rawName != 'thermal_zone') {
          return '${rawName.replaceAll('_', ' ').replaceAll('-', ' ')} (Zone $zoneNum)';
        }
        return 'Thermal Zone $zoneNum';
      }
      return 'SoC Thermal Zone';
    }

    // Default formatting
    if (rawName.isNotEmpty) {
      final clean = rawName
          .replaceAll('_hwmon', '')
          .replaceAll('_thermal', '')
          .replaceAll('_', ' ');
      return clean[0].toUpperCase() + clean.substring(1);
    }

    return 'Thermal Sensor ($id)';
  }
}
