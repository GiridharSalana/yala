// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/sqm/models/sqm_overview.dart';
import 'package:yala/modules/sqm/models/sqm_preset.dart';
import 'package:yala/modules/sqm/models/sqm_queue.dart';

void main() {
  group('SqmPreset Model & Matching Tests', () {
    test('Standard default templates are correctly defined', () {
      expect(SqmPreset.cakeFiber.qdisc, equals('cake'));
      expect(SqmPreset.cakeFiber.script, equals('piece_of_cake.qos'));
      expect(SqmPreset.cakeFiber.overhead, equals(0));
      expect(SqmPreset.cakeFiber.linklayer, equals('none'));

      expect(SqmPreset.vdslPppoe.qdisc, equals('cake'));
      expect(SqmPreset.vdslPppoe.script, equals('piece_of_cake.qos'));
      expect(SqmPreset.vdslPppoe.overhead, equals(44));
      expect(SqmPreset.vdslPppoe.linklayer, equals('ethernet'));

      expect(SqmPreset.layerCake.qdisc, equals('cake'));
      expect(SqmPreset.layerCake.script, equals('layer_cake.qos'));
      expect(SqmPreset.layerCake.qdiscAdvanced, isTrue);

      expect(SqmPreset.docsisCable.overhead, equals(34));
      expect(SqmPreset.docsisCable.linklayer, equals('ethernet'));

      expect(SqmPreset.lowCpu.qdisc, equals('fq_codel'));
      expect(SqmPreset.lowCpu.script, equals('simplest.qos'));

      expect(SqmPreset.adslAtm.linklayer, equals('atm'));
      expect(SqmPreset.adslAtm.overhead, equals(40));
    });

    test('Accurately matches queues against default templates', () {
      const qFiber = SqmQueue(
        name: 'test',
        interface: 'wan',
        qdisc: 'cake',
        script: 'piece_of_cake.qos',
        linklayer: 'none',
        overhead: 0,
      );
      expect(SqmPreset.match(qFiber)?.id, equals('cake_fiber'));

      const qPppoe = SqmQueue(
        name: 'test',
        interface: 'pppoe-wan',
        qdisc: 'cake',
        script: 'piece_of_cake.qos',
        linklayer: 'ethernet',
        overhead: 44,
      );
      expect(SqmPreset.match(qPppoe)?.id, equals('vdsl_pppoe'));

      const qGaming = SqmQueue(
        name: 'test',
        interface: 'eth1',
        qdisc: 'cake',
        script: 'layer_cake.qos',
      );
      expect(SqmPreset.match(qGaming)?.id, equals('layer_cake'));

      const qLowCpu = SqmQueue(
        name: 'test',
        interface: 'eth0',
        qdisc: 'fq_codel',
        script: 'simplest.qos',
      );
      expect(SqmPreset.match(qLowCpu)?.id, equals('low_cpu'));
    });
  });

  group('Accurate Interface Mapping Across All Router Setups', () {
    test('PPPoE Router Setup: prioritizes pppoe-wan L3 interface over eth1', () {
      final data = {
        'wan': {
          'interface': 'wan',
          'device': 'eth1',
          'l3_device': 'pppoe-wan',
        },
        'interfaceDump': {
          'interface': [
            {
              'interface': 'wan',
              'device': 'eth1',
              'l3_device': 'pppoe-wan',
              'route': [
                {'target': '0.0.0.0', 'mask': 0},
              ],
            },
            {
              'interface': 'lan',
              'device': 'br-lan',
              'l3_device': 'br-lan',
            },
          ],
        },
      };

      final overview = SqmOverview.fromDashboardData(data);
      expect(overview.primaryWanInterface, equals('pppoe-wan'));
      expect(overview.networkInterfaces, contains('pppoe-wan'));
      expect(overview.networkInterfaces, contains('eth1'));
      expect(overview.networkInterfaces, contains('br-lan'));

      expect(
        overview.interfaceLabel('pppoe-wan'),
        contains('Active PPPoE WAN (Recommended)'),
      );
      expect(
        overview.interfaceLabel('br-lan'),
        contains('LAN / Dumb AP Bridge'),
      );
    });

    test('Standard DHCP WAN: detects wan/eth0 as primary WAN', () {
      final data = {
        'interfaceDump': {
          'interface': [
            {
              'interface': 'wan',
              'device': 'eth0',
              'route': [
                {'target': '0.0.0.0', 'mask': 0},
              ],
            },
          ],
        },
      };

      final overview = SqmOverview.fromDashboardData(data);
      expect(overview.primaryWanInterface, equals('eth0'));
      expect(overview.interfaceLabel('eth0'), contains('Active WAN'));
    });

    test('Dumb AP / Secondary Router Setup: falls back to br-lan bridge', () {
      final data = {
        'interfaceDump': {
          'interface': [
            {
              'interface': 'lan',
              'device': 'br-lan',
              'l3_device': 'br-lan',
            },
          ],
        },
        'networkDevices': [
          {'name': 'br-lan'},
          {'name': 'eth0'},
        ],
      };

      final overview = SqmOverview.fromDashboardData(data);
      expect(overview.primaryWanInterface, equals('br-lan'));
      expect(
        overview.interfaceLabel('br-lan'),
        contains('Active WAN (Recommended)'),
      );
    });

    test('Cellular / LTE / Modem Setup: detects and formats wwan0 / usb0', () {
      final data = {
        'networkDevices': [
          {'name': 'wwan0'},
          {'name': 'usb0'},
          {'name': 'br-lan'},
        ],
      };

      final overview = SqmOverview.fromDashboardData(data);
      expect(overview.networkInterfaces, contains('wwan0'));
      expect(overview.networkInterfaces, contains('usb0'));
      expect(
        overview.interfaceLabel('wwan0'),
        contains('Cellular / USB Modem'),
      );
    });

    test('VLAN Tagged WAN: preserves and parses eth0.2', () {
      final data = {
        'networkDevices': [
          {'name': 'eth0.2'},
          {'name': 'br-lan'},
        ],
        'sqm': {
          'cfg01': {
            'interface': 'eth0.2',
            'download': '100000',
            'upload': '20000',
          },
        },
      };

      final overview = SqmOverview.fromDashboardData(data);
      expect(overview.networkInterfaces, contains('eth0.2'));
      expect(overview.primaryWanInterface, equals('eth0.2'));
    });
  });

  group('Template Handling & Existing Queue Preservation', () {
    test('Identifies OpenWrt anonymous section cfg01b68a as default template', () {
      const q = SqmQueue(
        name: 'cfg01b68a',
        enabled: false,
        interface: 'pppoe-wan',
        download: 0,
        upload: 0,
      );

      expect(q.isDefaultTemplate, isTrue);
      expect(q.isConfigured, isFalse);
      expect(
        q.displayName(primaryWanInterface: 'pppoe-wan'),
        equals('Primary WAN Queue (pppoe-wan)'),
      );
    });

    test('Identifies named queue correctly', () {
      const q = SqmQueue(
        name: 'guest_shaper',
        enabled: true,
        interface: 'br-guest',
        download: 10000,
        upload: 2000,
      );

      expect(q.isDefaultTemplate, isFalse);
      expect(q.isConfigured, isTrue);
      expect(q.displayName(), equals('guest_shaper'));
    });

    test('SqmOverview extracts router template queue cleanly', () {
      final data = {
        'sqm': {
          'cfg01b68a': {
            '.anonymous': true,
            '.type': 'queue',
            'enabled': '0',
            'interface': 'pppoe-wan',
            'download': '228000',
            'upload': '228000',
            'qdisc': 'cake',
            'script': 'piece_of_cake.qos',
            'linklayer': 'ethernet',
            'overhead': '44',
          },
        },
      };

      final overview = SqmOverview.fromDashboardData(data);
      expect(overview.hasExistingTemplate, isTrue);
      expect(overview.defaultTemplateQueue, isNotNull);
      expect(overview.defaultTemplateQueue!.name, equals('cfg01b68a'));
      expect(overview.defaultTemplateQueue!.interface, equals('pppoe-wan'));
      expect(overview.defaultTemplateQueue!.download, equals(228000));
      expect(overview.defaultTemplateQueue!.upload, equals(228000));
      expect(overview.defaultTemplateQueue!.overhead, equals(44));
    });
  });
}
