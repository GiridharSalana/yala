// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/system_monitoring/models/router_temperature.dart';
import 'package:yala/modules/system_monitoring/models/system_metrics.dart';

void main() {
  group('ThermalStatus and Normalization Tests', () {
    test('ThermalStatus fromTemperature maps correctly to thresholds', () {
      expect(
        ThermalStatus.fromTemperature(null),
        equals(ThermalStatus.unknown),
      );
      expect(ThermalStatus.fromTemperature(35.0), equals(ThermalStatus.cool));
      expect(ThermalStatus.fromTemperature(49.9), equals(ThermalStatus.cool));
      expect(ThermalStatus.fromTemperature(50.0), equals(ThermalStatus.normal));
      expect(ThermalStatus.fromTemperature(58.5), equals(ThermalStatus.normal));
      expect(ThermalStatus.fromTemperature(65.0), equals(ThermalStatus.normal));
      expect(ThermalStatus.fromTemperature(65.1), equals(ThermalStatus.warm));
      expect(ThermalStatus.fromTemperature(75.0), equals(ThermalStatus.warm));
      expect(ThermalStatus.fromTemperature(75.1), equals(ThermalStatus.hot));
      expect(ThermalStatus.fromTemperature(85.0), equals(ThermalStatus.hot));
      expect(
        ThermalStatus.fromTemperature(85.1),
        equals(ThermalStatus.critical),
      );
      expect(
        ThermalStatus.fromTemperature(105.0),
        equals(ThermalStatus.critical),
      );
    });

    test('ThermalStatus display labels', () {
      expect(ThermalStatus.cool.label, equals('Cool'));
      expect(ThermalStatus.normal.label, equals('Normal'));
      expect(ThermalStatus.warm.label, equals('Warm'));
      expect(ThermalStatus.hot.label, equals('Hot'));
      expect(ThermalStatus.critical.label, equals('Critical'));
      expect(ThermalStatus.unknown.label, equals('Unknown'));
    });

    test('normalizeTemperature handles millidegrees and direct degrees', () {
      // Millidegrees (typical Linux sysfs: 54000 = 54.0°C)
      expect(RouterTemperature.normalizeTemperature(54000), equals(54.0));
      expect(RouterTemperature.normalizeTemperature(67500), equals(67.5));
      expect(RouterTemperature.normalizeTemperature(0), equals(0.0));

      // Direct degrees
      expect(RouterTemperature.normalizeTemperature(45.2), equals(45.2));
      expect(RouterTemperature.normalizeTemperature(60), equals(60.0));

      // String inputs
      expect(RouterTemperature.normalizeTemperature('54000'), equals(54.0));
      expect(RouterTemperature.normalizeTemperature('62.5'), equals(62.5));
      expect(
        RouterTemperature.normalizeTemperature('  71000 \n'),
        equals(71.0),
      );

      // Out-of-bounds sanity check (-40°C to 150°C)
      expect(RouterTemperature.normalizeTemperature(999000), isNull);
      expect(RouterTemperature.normalizeTemperature(-500000), isNull);
      expect(RouterTemperature.normalizeTemperature(200.0), isNull);
      expect(RouterTemperature.normalizeTemperature(-60.0), isNull);

      // Non-numeric or empty
      expect(RouterTemperature.normalizeTemperature(''), isNull);
      expect(RouterTemperature.normalizeTemperature('N/A'), isNull);
      expect(RouterTemperature.normalizeTemperature('invalid_temp'), isNull);
    });
  });

  group('RouterTemperature sysfs Output Parsing', () {
    test('Parses pipe-delimited hwmon sysfs output with multiple sensors', () {
      const probeOutput = '''
hwmon|ath10k_hwmon|hwmon0/temp1_input|54000
hwmon|ath10k_hwmon|hwmon1/temp1_input|67000
hwmon|ath10k_hwmon|hwmon2/temp1_input|65000
''';

      final result = RouterTemperature.parse(probeOutput);
      expect(result.isSupported, isTrue);
      expect(result.sensors.length, equals(3));

      // Peak should be 67.0°C
      expect(result.peakTemperature, equals(67.0));
      // Without CPU sensor, main sensor should be peak (67.0°C)
      expect(result.mainTemperature, equals(67.0));
      expect(result.formattedTemperature, equals('67°C'));
      expect(result.formattedTemperaturePrecise, equals('67.0°C'));
      expect(result.status, equals(ThermalStatus.warm));

      // Check humanized sensor name
      expect(result.sensors[0].name, equals('Qualcomm Wi-Fi (Radio 1)'));
    });

    test('Prefers CPU/SoC sensor as primary temperature when available', () {
      const probeOutput = '''
thermal|cpu-thermal|thermal_zone0/temp|48000
hwmon|ath10k_hwmon|hwmon0/temp1_input|62000
''';

      final result = RouterTemperature.parse(probeOutput);
      expect(result.isSupported, isTrue);
      expect(result.sensors.length, equals(2));

      // Main temperature should be CPU sensor (48.0°C)
      expect(result.mainTemperature, equals(48.0));
      // Peak temperature should be ath10k (62.0°C)
      expect(result.peakTemperature, equals(62.0));
      expect(result.formattedTemperaturePrecise, equals('48.0°C'));
      expect(result.status, equals(ThermalStatus.cool));
    });

    test('Parses colon-delimited fallback sysfs output', () {
      const probeOutput = '''
cpu-thermal: 52000
mt7915_hwmon: 58000
''';

      final result = RouterTemperature.parse(probeOutput);
      expect(result.isSupported, isTrue);
      expect(result.sensors.length, equals(2));
      expect(result.mainTemperature, equals(52.0));
      expect(result.peakTemperature, equals(58.0));
      expect(result.sensors[1].name, equals('MediaTek Wi-Fi Radio'));
    });

    test(
      'Handles out-of-bounds, corrupt lines, or empty strings gracefully',
      () {
        const corruptOutput = '''
thermal|broken_sensor|thermal_zone0/temp|99999999
corrupt_line_without_delimiter
hwmon|ath10k_hwmon|hwmon0/temp1_input|invalid
hwmon|ath10k_hwmon|hwmon1/temp1_input|55000
''';

        final result = RouterTemperature.parse(corruptOutput);
        expect(result.isSupported, isTrue);
        // Only the valid sensor (55000) should be included
        expect(result.sensors.length, equals(1));
        expect(result.mainTemperature, equals(55.0));
        expect(result.peakTemperature, equals(55.0));
      },
    );

    test(
      'Returns unavailable when output is empty or contains no valid sensors',
      () {
        final emptyResult = RouterTemperature.parse('');
        expect(emptyResult.isSupported, isFalse);
        expect(emptyResult.mainTemperature, isNull);
        expect(emptyResult.peakTemperature, isNull);
        expect(emptyResult.formattedTemperature, equals('N/A'));
        expect(emptyResult.status, equals(ThermalStatus.unknown));
        expect(emptyResult.errorMessage, isNotNull);

        final noSensorResult = RouterTemperature.parse('foo: bar\nbaz: qux\n');
        expect(noSensorResult.isSupported, isFalse);
        expect(noSensorResult.mainTemperature, isNull);
        expect(noSensorResult.formattedTemperature, equals('N/A'));
      },
    );
  });

  group('RouterTemperature JSON / Map Parsing', () {
    test('Parses luci-app-temp-status sensors structure', () {
      final json = {
        'sensors': {
          '0': [
            {
              'title': 'ath10k_hwmon',
              'sources': [
                {'label': 'temp1', 'temp': 56000},
              ],
            },
          ],
          '1': [
            {
              'title': 'cpu-thermal',
              'sources': [
                {'label': 'temp1', 'temp': 49500},
              ],
            },
          ],
        },
      };

      final result = RouterTemperature.parse(json);
      expect(result.isSupported, isTrue);
      expect(result.sensors.length, equals(2));
      expect(result.mainTemperature, equals(49.5)); // CPU preferred
      expect(result.peakTemperature, equals(56.0));
    });

    test('Parses direct key-value map format', () {
      final map = {'cpu_temp': 51000};

      final result = RouterTemperature.parse(map);
      expect(result.isSupported, isTrue);
      expect(result.sensors.length, equals(1));
      expect(result.mainTemperature, equals(51.0));
      expect(result.peakTemperature, equals(51.0));
    });

    test('Handles serialization to/from JSON roundtrip', () {
      final original = RouterTemperature(
        isSupported: true,
        sensors: const [
          ThermalSensor(
            id: 'hwmon0/temp1_input',
            name: 'ath10k_hwmon',
            rawName: 'ath10k_hwmon',
            type: 'wifi',
            value: 54.0,
          ),
        ],
        mainTemperature: 54.0,
        updatedAt: DateTime.now(),
      );

      final json = original.toJson();
      final restored = RouterTemperature.fromJson(json);

      expect(restored.isSupported, isTrue);
      expect(restored.sensors.length, equals(1));
      expect(restored.sensors[0].name, equals('ath10k_hwmon'));
      expect(restored.sensors[0].value, equals(54.0));
      expect(restored.mainTemperature, equals(54.0));
      expect(restored.status, equals(ThermalStatus.normal));
    });
  });

  group('SystemMetrics Thermal Integration', () {
    test('SystemMetrics safely handles null temperature', () {
      final metrics = SystemMetrics.fromSysInfo(null);
      expect(metrics.temperature, isNull);
      expect(metrics.formattedTemperature, equals('N/A'));
    });

    test('SystemMetrics parses RouterTemperature instance', () {
      final temp = RouterTemperature.mock();
      final metrics = SystemMetrics.fromSysInfo(null, temperature: temp);

      expect(metrics.temperature, isNotNull);
      expect(metrics.temperature!.isSupported, isTrue);
      expect(metrics.formattedTemperature, contains('°C'));
    });

    test('SystemMetrics parses raw map or string temperature', () {
      const probeOutput = 'hwmon|ath10k_hwmon|hwmon0/temp1_input|54000';
      final metrics = SystemMetrics.fromSysInfo(null, temperature: probeOutput);

      expect(metrics.temperature, isNotNull);
      expect(metrics.temperature!.isSupported, isTrue);
      expect(metrics.temperature!.mainTemperature, equals(54.0));
      expect(metrics.formattedTemperature, equals('54°C'));
      expect(
        metrics.temperature!.formattedTemperaturePrecise,
        equals('54.0°C'),
      );
    });

    test(
      'SystemMetrics handles invalid temperature payload without crashing',
      () {
        final metrics = SystemMetrics.fromSysInfo(null, temperature: 12345);
        expect(metrics.temperature?.isSupported, isFalse);
        expect(metrics.formattedTemperature, equals('N/A'));
      },
    );
  });

  group('Temperature Unit Conversion & Formatting Tests', () {
    test('Converts between Celsius and Fahrenheit accurately', () {
      expect(RouterTemperature.toFahrenheit(0.0), equals(32.0));
      expect(RouterTemperature.toFahrenheit(100.0), equals(212.0));
      expect(RouterTemperature.toFahrenheit(50.0), equals(122.0));
      expect(RouterTemperature.toCelsius(32.0), equals(0.0));
      expect(RouterTemperature.toCelsius(212.0), equals(100.0));
    });

    test('ThermalSensor formats correctly for Celsius and Fahrenheit', () {
      const sensor = ThermalSensor(
        id: 'hwmon0/temp1_input',
        name: 'ath10k_hwmon',
        rawName: 'ath10k_hwmon',
        type: 'wifi',
        value: 54.0,
      );

      expect(sensor.formattedValue, equals('54.0°C'));
      expect(sensor.formattedValueForUnit('celsius'), equals('54.0°C'));
      expect(sensor.formattedValueForUnit('fahrenheit'), equals('129.2°F'));
    });

    test(
      'RouterTemperature formats with and without precision for both units',
      () {
        final temp = RouterTemperature.mock(); // 51.5°C
        // 51.5 * 1.8 + 32 = 124.7°F

        expect(temp.formattedTemperature, equals('52°C'));
        expect(temp.formattedTemperaturePrecise, equals('51.5°C'));
        expect(temp.formattedTemperatureForUnit('celsius'), equals('52°C'));
        expect(
          temp.formattedTemperatureForUnit('celsius', precise: true),
          equals('51.5°C'),
        );
        expect(temp.formattedTemperatureForUnit('fahrenheit'), equals('125°F'));
        expect(
          temp.formattedTemperatureForUnit('fahrenheit', precise: true),
          equals('124.7°F'),
        );
      },
    );

    test(
      'SystemMetrics formattedTemperatureForUnit respects selected unit',
      () {
        final temp = RouterTemperature.mock();
        final metrics = SystemMetrics.fromSysInfo(null, temperature: temp);

        expect(metrics.formattedTemperatureForUnit('celsius'), equals('52°C'));
        expect(
          metrics.formattedTemperatureForUnit('fahrenheit'),
          equals('125°F'),
        );
        expect(
          metrics.formattedTemperatureForUnit('fahrenheit', precise: true),
          equals('124.7°F'),
        );
      },
    );
  });

  group('Native RPC Handler and Hardware Sensor State Tests', () {
    test('RouterTemperature.unavailable defaults to unsupported hardware', () {
      final unavail = RouterTemperature.unavailable();
      expect(unavail.isSupported, isFalse);
      expect(unavail.hasPhysicalSensors, isFalse);
      expect(unavail.isHandlerInstalled, isFalse);
      expect(unavail.isHardwareUnsupported, isTrue);
      expect(unavail.needsNativeHandler, isFalse);
      expect(unavail.isFullySupported, isFalse);
      expect(unavail.errorMessage, isNotNull);
    });

    test(
      'RouterTemperature indicates needsNativeHandler when physical sensors exist but handler missing',
      () {
        final pending = RouterTemperature.unavailable(
          hasPhysicalSensors: true,
          isHandlerInstalled: false,
          reason: 'Handler missing',
        );
        expect(pending.isSupported, isFalse);
        expect(pending.hasPhysicalSensors, isTrue);
        expect(pending.isHandlerInstalled, isFalse);
        expect(pending.needsNativeHandler, isTrue);
        expect(pending.isHardwareUnsupported, isFalse);
        expect(pending.isFullySupported, isFalse);
      },
    );

    test(
      'RouterTemperature indicates isFullySupported when supported and valid',
      () {
        final temp = RouterTemperature.mock();
        expect(temp.isSupported, isTrue);
        expect(temp.hasPhysicalSensors, isTrue);
        expect(temp.isHandlerInstalled, isTrue);
        expect(temp.isFullySupported, isTrue);
        expect(temp.needsNativeHandler, isFalse);
        expect(temp.isHardwareUnsupported, isFalse);
      },
    );

    test('copyWith properly updates properties', () {
      final initial = RouterTemperature.unavailable(
        hasPhysicalSensors: true,
        isHandlerInstalled: false,
      );
      final updated = initial.copyWith(
        isSupported: true,
        isHandlerInstalled: true,
        mainTemperature: 60.0,
      );

      expect(updated.isSupported, isTrue);
      expect(updated.hasPhysicalSensors, isTrue);
      expect(updated.isHandlerInstalled, isTrue);
      expect(updated.mainTemperature, equals(60.0));
      expect(updated.isFullySupported, isTrue);
    });

    test(
      'JSON serialization preserves hasPhysicalSensors and isHandlerInstalled',
      () {
        final temp = RouterTemperature(
          isSupported: false,
          hasPhysicalSensors: true,
          isHandlerInstalled: false,
          errorMessage: 'Needs handler',
          updatedAt: DateTime.now(),
        );

        final json = temp.toJson();
        expect(json['hasPhysicalSensors'], isTrue);
        expect(json['isHandlerInstalled'], isFalse);

        final restored = RouterTemperature.fromJson(json);
        expect(restored.hasPhysicalSensors, isTrue);
        expect(restored.isHandlerInstalled, isFalse);
        expect(restored.needsNativeHandler, isTrue);
      },
    );
  });
}
