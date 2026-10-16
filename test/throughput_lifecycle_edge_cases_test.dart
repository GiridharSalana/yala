// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/services/throughput_service.dart';
import 'package:yala/state/controllers/throughput_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThroughputService Lifecycle & Edge Cases', () {
    late ThroughputService service;

    setUp(() {
      service = ThroughputService();
    });

    test('Initial seeding only occurs when history is empty', () {
      expect(service.rxHistory, isEmpty);
      expect(service.txHistory, isEmpty);

      final netData1 = {
        'eth0': {
          'device': 'eth0',
          'stats': {'rx_bytes': 1000, 'tx_bytes': 500},
        },
      };

      // First tick establishes baseline and seeds (0.0, 0.0)
      service.updateThroughput(netData1, {'eth0'});
      expect(service.rxHistory, [0.0]);
      expect(service.txHistory, [0.0]);

      // Reset baseline (like on tab or app resume)
      service.resetBaseline();

      // Second baseline establishment must NOT append another 0.0 into non-empty history
      service.updateThroughput(netData1, {'eth0'});
      expect(service.rxHistory, [0.0]);
      expect(service.txHistory, [0.0]);
    });

    test('History is preserved across resetBaseline calls', () {
      final netData1 = {
        'eth0': {
          'device': 'eth0',
          'stats': {'rx_bytes': 1000000, 'tx_bytes': 500000},
        },
      };
      service.updateThroughput(netData1, {'eth0'});

      // Simulate normal update: 1MB rx, 500KB tx over 1 second = 1,000,000 B/s rx
      final netData2 = {
        'eth0': {
          'device': 'eth0',
          'stats': {'rx_bytes': 2000000, 'tx_bytes': 1000000},
        },
      };
      service.updateThroughput(netData2, {'eth0'});

      expect(service.rxHistory.length, greaterThanOrEqualTo(1));
      final initialHistoryLength = service.rxHistory.length;

      // Simulate app switch or tab switch: baseline reset
      service.resetBaseline();

      // History must remain intact
      expect(service.rxHistory.length, equals(initialHistoryLength));
      expect(service.txHistory.length, equals(initialHistoryLength));
    });

    test(
      'Large timing gap (> 15s) re-establishes baseline without distorted rate',
      () async {
        final netData1 = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 1000000, 'tx_bytes': 500000},
          },
        };
        service.updateThroughput(netData1, {'eth0'});
        expect(service.rxHistory, [0.0]);

        // Reset baseline simulates gap
        service.resetBaseline();

        final netDataGap = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 50000000, 'tx_bytes': 25000000},
          },
        };
        service.updateThroughput(netDataGap, {'eth0'});

        // History should not be polluted with a diluted multi-minute average
        expect(service.rxHistory.length, equals(1));
        expect(service.rxHistory.first, equals(0.0));
      },
    );

    test(
      '32-bit counter rollover is detected and calculated correctly',
      () async {
        // 2^32 = 4,294,967,296
        const num uint32Max = 4294967296;
        final netData1 = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': uint32Max - 500000, 'tx_bytes': 1000},
          },
        };
        service.updateThroughput(netData1, {'eth0'});

        await Future.delayed(const Duration(milliseconds: 150));

        // Counter rolls over past 0 to 500,000 bytes (total 1,000,000 bytes transferred)
        final netData2 = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 500000, 'tx_bytes': 2000},
          },
        };

        service.updateThroughput(netData2, {'eth0'});

        // Should not throw or crash, and rate should be non-negative
        expect(service.currentRxRate, greaterThan(0.0));
        expect(service.rxHistory.length, equals(2));
      },
    );

    test(
      'Counter reset or router reboot re-establishes baseline without error',
      () {
        final netData1 = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 999999999, 'tx_bytes': 888888888},
          },
        };
        service.updateThroughput(netData1, {'eth0'});

        // Router reboots: counters drop to 1000 without rollover plausibility
        final netData2 = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 1000, 'tx_bytes': 1000},
          },
        };

        // Should re-establish baseline gracefully
        service.updateThroughput(netData2, {'eth0'});
        expect(service.currentRxRate, equals(0.0));
      },
    );

    test(
      'Interface counter reset from 50MB to 1KB over non-zero elapsed does not synthesize 4GB spike',
      () async {
        final netData1 = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 50000000, 'tx_bytes': 20000000},
          },
        };
        service.updateThroughput(netData1, {'eth0'});

        await Future.delayed(const Duration(milliseconds: 150));

        // Interface resets/reconnects: rx drops to 1000
        final netData2 = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 1000, 'tx_bytes': 1000},
          },
        };
        service.updateThroughput(netData2, {'eth0'});

        // Rate must NOT be calculated as (1000 + 4GB - 50MB) / 0.15s (~28 GB/s or capped 1 GB/s)
        // Rate must be 0.0 without any ghost spike!
        expect(service.currentRxRate, equals(0.0));
        expect(service.currentTxRate, equals(0.0));
      },
    );

    test(
      'Newly appeared interface does not inject cumulative lifetime bytes as a speed spike',
      () async {
        final netData1 = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 100000, 'tx_bytes': 100000},
          },
        };
        service.updateThroughput(netData1, {'eth0'});

        await Future.delayed(const Duration(milliseconds: 150));

        // WireGuard tunnel or dynamic interface wg0 appears with 200MB already transferred
        final netData2 = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 101000, 'tx_bytes': 101000},
          },
          'wg0': {
            'device': 'wg0',
            'stats': {'rx_bytes': 200000000, 'tx_bytes': 200000000},
          },
        };

        service.updateThroughput(netData2, {'eth0', 'wg0'});

        // Only eth0 delta (1000 bytes) should be counted, not wg0 lifetime 200MB!
        // 1000 bytes over ~0.15s is ~6666 B/s, definitely < 100,000 B/s (nowhere near 200MB/s)
        expect(service.currentRxRate, lessThan(100000.0));
        expect(service.currentTxRate, lessThan(100000.0));
      },
    );

    test(
      'clear() wipes all history and baseline for router switch / logout',
      () {
        final netData = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 1000, 'tx_bytes': 500},
          },
        };
        service.updateThroughput(netData, {'eth0'});
        expect(service.rxHistory, isNotEmpty);

        service.clear();

        expect(service.rxHistory, isEmpty);
        expect(service.txHistory, isEmpty);
        expect(service.currentRxRate, equals(0.0));
        expect(service.currentTxRate, equals(0.0));
      },
    );
  });

  group('ThroughputController Tab and App Switch Lifecycle Tests', () {
    late ThroughputService throughputService;
    late ThroughputController controller;

    setUp(() {
      throughputService = ThroughputService();
      controller = ThroughputController(throughputService: throughputService);
    });

    tearDown(() {
      controller.cancelAndClear();
    });

    test(
      'pauseTimer preserves history and resumeTimer resets baseline without wiping',
      () {
        int tickCount = 0;
        controller.startTimer(isRebooting: false, onTick: () => tickCount++);

        final netData = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 1000, 'tx_bytes': 500},
          },
        };
        controller.updateThroughput(netData, {'eth0'});
        expect(controller.rxHistory, [0.0]);

        // Pause (e.g. app minimized or tab switched)
        controller.pauseTimer();
        expect(controller.isTimerRunning, isFalse);
        expect(controller.isPaused, isTrue);
        expect(controller.rxHistory, [0.0]); // History preserved!

        // Resume (app resumed or tab selected)
        controller.resumeTimer(isRebooting: false, onTick: () => tickCount++);
        expect(controller.isTimerRunning, isTrue);
        expect(controller.isPaused, isFalse);
        expect(controller.rxHistory, [0.0]); // History STILL preserved!
      },
    );

    test('resumeTimer with immediateTick executes onTick microtask', () async {
      int tickCount = 0;
      controller.startTimer(isRebooting: false, onTick: () => tickCount++);
      controller.pauseTimer();

      controller.resumeTimer(
        isRebooting: false,
        onTick: () => tickCount++,
        immediateTick: true,
      );

      // Await microtask queue
      await Future.microtask(() {});
      expect(tickCount, equals(1));
    });

    test(
      'cancelAndClear completely resets history (used on logout/router switch)',
      () {
        controller.startTimer(isRebooting: false, onTick: () {});
        final netData = {
          'eth0': {
            'device': 'eth0',
            'stats': {'rx_bytes': 1000, 'tx_bytes': 500},
          },
        };
        controller.updateThroughput(netData, {'eth0'});
        expect(controller.rxHistory, isNotEmpty);

        controller.cancelAndClear();

        expect(controller.isTimerRunning, isFalse);
        expect(controller.rxHistory, isEmpty);
        expect(controller.txHistory, isEmpty);
      },
    );
  });

  group('ThroughputController.resolveThroughputDeviceNames', () {
    test('Standard gateway router with WAN and LAN returns only external WAN device', () {
      final interfaceDump = {
        'interface': [
          {'interface': 'loopback', 'device': 'lo', 'l3_device': 'lo'},
          {'interface': 'lan', 'device': 'br-lan', 'l3_device': 'br-lan'},
          {'interface': 'wan', 'proto': 'dhcp', 'device': 'eth1', 'l3_device': 'eth1'},
          {'interface': 'wan6', 'proto': 'dhcpv6', 'device': 'eth1', 'l3_device': null},
        ],
      };

      final devices = ThroughputController.resolveThroughputDeviceNames(interfaceDump);
      expect(devices, equals({'eth1'}));
    });

    test('PPPoE gateway router returns routed l3_device instead of carrier device', () {
      final interfaceDump = {
        'interface': [
          {'interface': 'lan', 'device': 'br-lan', 'l3_device': 'br-lan'},
          {'interface': 'wan', 'proto': 'pppoe', 'device': 'eth1', 'l3_device': 'pppoe-wan'},
        ],
      };

      final devices = ThroughputController.resolveThroughputDeviceNames(interfaceDump);
      expect(devices, equals({'pppoe-wan'}));
    });

    test('Dumb AP mode with no WAN returns primary LAN bridge exclusively', () {
      final interfaceDump = {
        'interface': [
          {'interface': 'loopback', 'device': 'lo', 'l3_device': 'lo'},
          {'interface': 'lan', 'device': 'br-lan', 'l3_device': 'br-lan'},
        ],
      };

      final devices = ThroughputController.resolveThroughputDeviceNames(interfaceDump);
      // Must return br-lan exclusively without member slave ports
      expect(devices, equals({'br-lan'}));
    });

    test('Multi-WAN router aggregates all external WAN devices', () {
      final interfaceDump = {
        'interface': [
          {'interface': 'lan', 'device': 'br-lan', 'l3_device': 'br-lan'},
          {'interface': 'wan', 'proto': 'dhcp', 'device': 'eth1', 'l3_device': 'eth1'},
          {'interface': 'wan_backup', 'proto': 'static', 'device': 'eth2', 'l3_device': 'eth2'},
        ],
      };

      final devices = ThroughputController.resolveThroughputDeviceNames(interfaceDump);
      expect(devices, equals({'eth1', 'eth2'}));
    });

    test('Null or empty interface dump returns empty set safely', () {
      expect(ThroughputController.resolveThroughputDeviceNames(null), isEmpty);
      expect(ThroughputController.resolveThroughputDeviceNames({}), isEmpty);
    });
  });

  group('ThroughputService ghost spike & loopback defense', () {
    test('Loopback device is never included in throughput calculations', () async {
      final service = ThroughputService();
      final netData1 = {
        'lo': {
          'device': 'lo',
          'stats': {'rx_bytes': 1000000, 'tx_bytes': 1000000},
        },
        'eth0': {
          'device': 'eth0',
          'stats': {'rx_bytes': 100, 'tx_bytes': 100},
        },
      };
      service.updateThroughput(netData1, {});

      await Future.delayed(const Duration(milliseconds: 150));

      final netData2 = {
        'lo': {
          'device': 'lo',
          'stats': {'rx_bytes': 50000000, 'tx_bytes': 50000000},
        },
        'eth0': {
          'device': 'eth0',
          'stats': {'rx_bytes': 200, 'tx_bytes': 200},
        },
      };
      service.updateThroughput(netData2, {});

      // Huge loopback jump must NOT contaminate throughput rate!
      expect(service.currentRxRate, lessThan(10000.0));
      expect(service.currentTxRate, lessThan(10000.0));
    });

    test('Fallback when wanDeviceNames is empty prefers single primary device over summing all', () async {
      final service = ThroughputService();
      // On Dumb AP, if wanDeviceNames is empty, br-lan is preferred over summing br-lan + eth0 + eth1
      final netData1 = {
        'br-lan': {
          'device': 'br-lan',
          'stats': {'rx_bytes': 1000, 'tx_bytes': 1000},
        },
        'eth0': {
          'device': 'eth0',
          'stats': {'rx_bytes': 1000, 'tx_bytes': 1000},
        },
        'eth1': {
          'device': 'eth1',
          'stats': {'rx_bytes': 1000, 'tx_bytes': 1000},
        },
      };
      service.updateThroughput(netData1, {});

      await Future.delayed(const Duration(milliseconds: 150));

      final netData2 = {
        'br-lan': {
          'device': 'br-lan',
          'stats': {'rx_bytes': 2000, 'tx_bytes': 2000},
        },
        'eth0': {
          'device': 'eth0',
          'stats': {'rx_bytes': 2000, 'tx_bytes': 2000},
        },
        'eth1': {
          'device': 'eth1',
          'stats': {'rx_bytes': 2000, 'tx_bytes': 2000},
        },
      };
      service.updateThroughput(netData2, {});

      // Delta on br-lan is 1000 bytes over ~0.15s (~6666 B/s).
      // If it summed br-lan + eth0 + eth1, it would be 3000 bytes (~20000 B/s).
      expect(service.currentRxRate, lessThan(12000.0));
    });
  });
}
