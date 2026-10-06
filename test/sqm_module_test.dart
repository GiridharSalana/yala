// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_queue.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_overview.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

void main() {
  group('SqmQueue Model Tests', () {
    test('Parses from standard UCI JSON correctly', () {
      final uciJson = {
        '.type': 'queue',
        '.name': 'eth1',
        'enabled': '1',
        'interface': 'pppoe-wan',
        'download': '100000',
        'upload': '20000',
        'qdisc': 'cake',
        'script': 'piece_of_cake.qos',
        'linklayer': 'ethernet',
        'overhead': '44',
        'qdisc_advanced': '1',
        'squash_dscp': '1',
        'squash_ingress': '1',
        'ingress_ecn': 'ECN',
        'egress_ecn': 'NOECN',
        'debug_logging': '0',
        'verbosity': '5',
      };

      final queue = SqmQueue.fromUci('eth1', uciJson);

      expect(queue.name, equals('eth1'));
      expect(queue.enabled, isTrue);
      expect(queue.interface, equals('pppoe-wan'));
      expect(queue.download, equals(100000));
      expect(queue.downloadMbps, equals(100.0));
      expect(queue.upload, equals(20000));
      expect(queue.uploadMbps, equals(20.0));
      expect(queue.hasIngressShaping, isTrue);
      expect(queue.hasEgressShaping, isTrue);
      expect(queue.qdisc, equals('cake'));
      expect(queue.script, equals('piece_of_cake.qos'));
      expect(queue.linklayer, equals('ethernet'));
      expect(queue.overhead, equals(44));
      expect(queue.qdiscAdvanced, isTrue);
      expect(queue.squashDscp, isTrue);
      expect(queue.squashIngress, isTrue);
      expect(queue.ingressEcn, equals('ECN'));
      expect(queue.egressEcn, equals('NOECN'));
      expect(queue.debugLogging, isFalse);
    });

    test('toUciParams serializes correctly with advanced flags', () {
      const queue = SqmQueue(
        name: 'eth1',
        enabled: true,
        interface: 'eth1',
        download: 50000,
        upload: 10000,
        qdisc: 'cake',
        script: 'piece_of_cake.qos',
        linklayer: 'ethernet',
        overhead: 34,
        qdiscAdvanced: true,
        squashDscp: true,
        squashIngress: false,
        ingressEcn: 'ECN',
        egressEcn: 'ECN',
        debugLogging: false,
      );

      final params = queue.toUciParams();

      expect(params['enabled'], equals('1'));
      expect(params['interface'], equals('eth1'));
      expect(params['download'], equals('50000'));
      expect(params['upload'], equals('10000'));
      expect(params['qdisc'], equals('cake'));
      expect(params['script'], equals('piece_of_cake.qos'));
      expect(params['linklayer'], equals('ethernet'));
      expect(params['overhead'], equals('34'));
      expect(params['qdisc_advanced'], equals('1'));
      expect(params['squash_dscp'], equals('1'));
      expect(params['squash_ingress'], equals('0'));
      expect(params['ingress_ecn'], equals('ECN'));
      expect(params['egress_ecn'], equals('ECN'));
    });

    test('toUciParams sets qdisc_advanced to 0 when disabled', () {
      const queue = SqmQueue(
        name: 'eth1',
        enabled: false,
        interface: 'wan',
        download: 0,
        upload: 0,
        qdiscAdvanced: false,
      );

      final params = queue.toUciParams();

      expect(params['enabled'], equals('0'));
      expect(params['qdisc_advanced'], equals('0'));
      expect(params.containsKey('squash_dscp'), isFalse);
      expect(params.containsKey('ingress_ecn'), isFalse);
    });

    test('copyWith properly overrides specified attributes', () {
      const original = SqmQueue(
        name: 'eth1',
        interface: 'wan',
        download: 10000,
        upload: 5000,
      );

      final modified = original.copyWith(
        download: 20000,
        enabled: false,
        qdisc: 'fq_codel',
      );

      expect(modified.name, equals('eth1'));
      expect(modified.interface, equals('wan'));
      expect(modified.download, equals(20000));
      expect(modified.downloadMbps, equals(20.0));
      expect(modified.upload, equals(5000));
      expect(modified.enabled, isFalse);
      expect(modified.qdisc, equals('fq_codel'));
    });
  });

  group('SqmOverview Model Tests', () {
    test('Reviewer Mode returns active mock SQM overview', () {
      final overview = SqmOverview.fromDashboardData(
        null,
        isReviewerMode: true,
      );

      expect(overview.isInstalled, isTrue);
      expect(overview.isServiceRunning, isTrue);
      expect(overview.isServiceEnabled, isTrue);
      expect(overview.primaryWanInterface, equals('pppoe-wan'));
      expect(overview.queues.length, equals(1));
      expect(overview.queues.first.downloadMbps, equals(100.0));
      expect(overview.queues.first.uploadMbps, equals(20.0));
    });

    test('Returns uninstalled when dashboard data has no SQM references', () {
      final dashboardData = {
        'boardInfo': {'hostname': 'OpenWrt'},
        'installedPackages': ['base-files', 'busybox'],
      };

      final overview = SqmOverview.fromDashboardData(dashboardData);

      expect(overview.isInstalled, isFalse);
      expect(overview.isServiceRunning, isFalse);
      expect(overview.queues, isEmpty);
    });

    test('Detects installed SQM via initScripts and parses UCI queues', () {
      final dashboardData = {
        'initScripts': {
          'sqm': {'running': true, 'enabled': true},
        },
        'interfaceDump': {
          'interface': [
            {
              'interface': 'wan',
              'l3_device': 'eth1',
              'route': [
                {'target': '0.0.0.0', 'mask': 0},
              ],
            },
            {'interface': 'lan', 'l3_device': 'br-lan'},
          ],
        },
        'sqm': {
          'eth1': {
            '.type': 'queue',
            'enabled': '1',
            'interface': 'eth1',
            'download': '50000',
            'upload': '10000',
            'qdisc': 'cake',
            'script': 'piece_of_cake.qos',
          },
        },
      };

      final overview = SqmOverview.fromDashboardData(dashboardData);

      expect(overview.isInstalled, isTrue);
      expect(overview.isServiceRunning, isTrue);
      expect(overview.isServiceEnabled, isTrue);
      expect(overview.primaryWanInterface, equals('eth1'));
      expect(overview.networkInterfaces, containsAll(['eth1', 'br-lan']));
      expect(overview.queues.length, equals(1));
      expect(overview.queues.first.name, equals('eth1'));
      expect(overview.queues.first.downloadMbps, equals(50.0));
    });
  });

  group('Storage Assessment & Edge Case Logic Tests', () {
    const int luciMinBytes = 500 * 1024; // ~500 KB
    const int scriptsMinBytes = 100 * 1024; // ~100 KB

    test('Identifies exhausted storage condition (< 100 KB) in overlay', () {
      // Simulating real test router condition: 56 KB free in /overlay
      final mockMountData = [
        {
          'mount': '/',
          'device': '/dev/root',
          'type': 'squashfs',
          'size': 16777216,
          'avail': 0,
        },
        {
          'mount': '/overlay',
          'device': '/dev/mtdblock6',
          'type': 'jffs2',
          'sizeBytes': 524288, // 512 KB
          'availableBytes': 57344, // 56 KB (< 100 KB)
        },
      ];

      final storage = StorageOverview.fromRpcData(mockMountData);
      final overlay = storage.overlayFs;

      expect(overlay, isNotNull);
      expect(overlay!.availableBytes, equals(57344));

      final bool isStorageExhausted = overlay.availableBytes < scriptsMinBytes;
      final bool isLuciStorageInsufficient =
          overlay.availableBytes < luciMinBytes;

      // Both flags should trigger: storage exhausted blocks all installs
      expect(isStorageExhausted, isTrue);
      expect(isLuciStorageInsufficient, isTrue);
    });

    test(
      'Allows sqm-scripts but restricts luci-app-sqm when storage is between 100 KB and 500 KB',
      () {
        final mockMountData = [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'type': 'jffs2',
            'sizeBytes': 1048576,
            'availableBytes': 256 * 1024, // 256 KB (between 100 KB and 500 KB)
          },
        ];

        final storage = StorageOverview.fromRpcData(mockMountData);
        final overlay = storage.overlayFs;

        expect(overlay, isNotNull);
        final bool isStorageExhausted =
            overlay!.availableBytes < scriptsMinBytes;
        final bool isLuciStorageInsufficient =
            overlay.availableBytes < luciMinBytes;

        expect(isStorageExhausted, isFalse); // sqm-scripts is allowed
        expect(isLuciStorageInsufficient, isTrue); // luci-app-sqm is restricted
      },
    );

    test(
      'Allows both packages when overlay has sufficient free space (>= 500 KB)',
      () {
        final mockMountData = [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'type': 'ext4',
            'size': 33554432, // 32 MB
            'avail': 16777216, // 16 MB free
          },
        ];

        final storage = StorageOverview.fromRpcData(mockMountData);
        final overlay = storage.overlayFs;

        expect(overlay, isNotNull);
        expect(overlay!.availableBytes, greaterThan(500 * 1024));

        final bool isStorageExhausted =
            overlay.availableBytes < scriptsMinBytes;
        final bool isLuciStorageInsufficient =
            overlay.availableBytes < luciMinBytes;
        expect(isStorageExhausted, isFalse);
        expect(isLuciStorageInsufficient, isFalse);
      },
    );

    test('Detects read-only or exhausted storage partition', () {
      final mockMountData = [
        {
          'mount': '/overlay',
          'device': '/dev/mtdblock6',
          'type': 'jffs2',
          'size': 524288,
          'avail': 0, // 0 bytes free
        },
      ];

      final storage = StorageOverview.fromRpcData(mockMountData);
      final overlay = storage.overlayFs;

      expect(overlay, isNotNull);
      expect(overlay!.availableBytes, equals(0));
      expect(overlay.availableBytes < scriptsMinBytes, isTrue);
    });
  });

  group('Queue Naming & Verbosity Tests', () {
    test('SqmQueue serializes and parses verbosity field', () {
      const queue = SqmQueue(
        name: 'sqm1',
        interface: 'wan',
        debugLogging: true,
        verbosity: 8,
      );

      final params = queue.toUciParams();
      expect(params['verbosity'], equals('8'));
      expect(params['debug_logging'], equals('1'));

      final parsed = SqmQueue.fromUci('sqm1', {
        'interface': 'wan',
        'debug_logging': '1',
        'verbosity': '8',
      });
      expect(parsed.verbosity, equals(8));
      expect(parsed.debugLogging, isTrue);

      final modified = queue.copyWith(verbosity: 2);
      expect(modified.verbosity, equals(2));
    });

    test(
      'Queue naming algorithm avoids collisions with existing queues and interfaces',
      () {
        final existingQueues = {'sqm1', 'sqm2'};
        final networkInterfaces = {'sqm3', 'eth0', 'eth1', 'br-lan', 'wan'};

        int counter = 1;
        String newName = 'sqm$counter';
        final existingLower = existingQueues
            .map((q) => q.toLowerCase())
            .toSet();
        final ifaceLower = networkInterfaces
            .map((i) => i.toLowerCase())
            .toSet();

        while (existingLower.contains(newName.toLowerCase()) ||
            ifaceLower.contains(newName.toLowerCase())) {
          counter++;
          newName = 'sqm$counter';
        }

        // sqm1 and sqm2 are in existingQueues, sqm3 is in networkInterfaces -> should select sqm4
        expect(newName, equals('sqm4'));
      },
    );
  });

  group('MockApiService SQM Method Tests', () {
    test(
      'saveSqmQueue, deleteSqmQueue, toggleSqmService execute successfully',
      () async {
        final api = MockApiService();

        const testQueue = SqmQueue(
          name: 'eth1',
          enabled: true,
          interface: 'wan',
          download: 100000,
          upload: 20000,
        );

        final saveResult = await api.saveSqmQueue(
          '192.168.1.1',
          'auth_token',
          false,
          queue: testQueue,
        );
        expect(saveResult, isTrue);

        final toggleResult = await api.toggleSqmService(
          '192.168.1.1',
          'auth_token',
          false,
          enable: true,
        );
        expect(toggleResult, isTrue);

        final deleteResult = await api.deleteSqmQueue(
          '192.168.1.1',
          'auth_token',
          false,
          sectionName: 'eth1',
        );
        expect(deleteResult, isTrue);
      },
    );
  });

  group('Flow Offloading Detection Tests', () {
    test(
      'Correctly detects software flow offloading enabled in firewall defaults',
      () {
        final dashboardData = {
          'uciFirewallConfig': {
            'values': {
              'cfg01e63d': {
                '.type': 'defaults',
                'flow_offloading': '1',
                'flow_offloading_hw': '0',
              },
            },
          },
        };

        final overview = SqmOverview.fromDashboardData(dashboardData);

        expect(overview.isFlowOffloadingEnabled, isTrue);
        expect(overview.isHardwareFlowOffloadingEnabled, isFalse);
        expect(overview.hasAnyFlowOffloading, isTrue);
      },
    );

    test(
      'Correctly detects hardware flow offloading enabled in firewall defaults',
      () {
        final dashboardData = {
          'uciFirewallConfig': {
            'values': {
              'cfg01e63d': {
                '.type': 'defaults',
                'flow_offloading': '0',
                'flow_offloading_hw': '1',
              },
            },
          },
        };

        final overview = SqmOverview.fromDashboardData(dashboardData);

        expect(overview.isFlowOffloadingEnabled, isFalse);
        expect(overview.isHardwareFlowOffloadingEnabled, isTrue);
        expect(overview.hasAnyFlowOffloading, isTrue);
      },
    );

    test('Returns false when flow offloading is disabled or not present', () {
      final dashboardData = {
        'uciFirewallConfig': {
          'values': {
            'cfg01e63d': {'.type': 'defaults', 'syn_flood': '1'},
          },
        },
      };

      final overview = SqmOverview.fromDashboardData(dashboardData);

      expect(overview.isFlowOffloadingEnabled, isFalse);
      expect(overview.isHardwareFlowOffloadingEnabled, isFalse);
      expect(overview.hasAnyFlowOffloading, isFalse);
    });
  });
}
