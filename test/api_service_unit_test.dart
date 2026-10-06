// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/api_service.dart';

void main() {
  late RealApiService apiService;

  setUp(() {
    apiService = RealApiService();
  });

  group('RealApiService fileExec Helpers', () {
    test('fileExecParams generates correct payload structure', () {
      final res = RealApiService.fileExecParams('/bin/sh', ['-c', 'uptime']);
      expect(res['command'], equals('/bin/sh'));
      expect(res['params'], equals(['-c', 'uptime']));
      expect(res.containsKey('args'), isFalse);
    });

    test('fileExecArgs generates legacy payload structure', () {
      final res = RealApiService.fileExecArgs('/bin/sh', ['-c', 'uptime']);
      expect(res['command'], equals('/bin/sh'));
      expect(res['args'], equals(['-c', 'uptime']));
      expect(res.containsKey('params'), isFalse);
    });
  });

  group('RealApiService execSucceeded Tests', () {
    test('Identifies successful process results with code 0', () {
      expect(
        apiService.execSucceeded([
          0,
          {'code': 0, 'stdout': 'ok'},
        ]),
        isTrue,
      );
      expect(apiService.execSucceeded({'code': 0}), isTrue);
      expect(apiService.execSucceeded({'rc': 0}), isTrue);
      expect(apiService.execSucceeded([0]), isTrue);
      expect(apiService.execSucceeded(0), isTrue);
    });

    test('Identifies failed process results correctly', () {
      expect(
        apiService.execSucceeded([
          0,
          {'code': 1, 'stderr': 'error'},
        ]),
        isFalse,
      );
      expect(
        apiService.execSucceeded([
          0,
          {'code': 127},
        ]),
        isFalse,
      );
      expect(apiService.execSucceeded({'code': 1}), isFalse);
      expect(apiService.execSucceeded({'rc': -1}), isFalse);
      expect(apiService.execSucceeded([1]), isFalse);
      expect(apiService.execSucceeded(1), isFalse);
      expect(apiService.execSucceeded(null), isFalse);
      expect(apiService.execSucceeded([]), isFalse);
    });
  });

  group('RealApiService isUciSuccessful Tests', () {
    test('Correctly identifies successful UCI return formats', () {
      expect(apiService.isUciSuccessful([0]), isTrue);
      expect(apiService.isUciSuccessful({'result': [0]}), isTrue);
      expect(apiService.isUciSuccessful({'code': 0}), isTrue);
      expect(apiService.isUciSuccessful({'rc': 0}), isTrue);
      expect(apiService.isUciSuccessful({'success': true}), isTrue);
      expect(apiService.isUciSuccessful({}), isTrue);
      expect(apiService.isUciSuccessful(0), isTrue);
    });

    test('Correctly identifies failed UCI return formats', () {
      expect(apiService.isUciSuccessful([1]), isFalse);
      expect(apiService.isUciSuccessful({'error': 'Section not found'}), isFalse);
      expect(apiService.isUciSuccessful({'result': [1]}), isFalse);
      expect(apiService.isUciSuccessful({'code': 1}), isFalse);
      expect(apiService.isUciSuccessful({'rc': 1}), isFalse);
      expect(apiService.isUciSuccessful(null), isFalse);
      expect(apiService.isUciSuccessful([]), isFalse);
    });
  });

  group('RealApiService sanitizeOpenWrtLeaseTime Tests', () {
    test('Handles null and empty strings', () {
      expect(RealApiService.sanitizeOpenWrtLeaseTime(null), isNull);
      expect(RealApiService.sanitizeOpenWrtLeaseTime(''), isNull);
      expect(RealApiService.sanitizeOpenWrtLeaseTime('   '), isNull);
    });

    test('Preserves infinite lease keyword', () {
      expect(
        RealApiService.sanitizeOpenWrtLeaseTime('infinite'),
        equals('infinite'),
      );
      expect(
        RealApiService.sanitizeOpenWrtLeaseTime(' INFINITE '),
        equals('infinite'),
      );
    });

    test('Converts weeks (w) to days (d) for dnsmasq compatibility', () {
      expect(RealApiService.sanitizeOpenWrtLeaseTime('1w'), equals('7d'));
      expect(RealApiService.sanitizeOpenWrtLeaseTime('2w'), equals('14d'));
      expect(RealApiService.sanitizeOpenWrtLeaseTime('4w'), equals('28d'));
    });

    test('Converts seconds (s) to minutes (m) with safety floor', () {
      expect(RealApiService.sanitizeOpenWrtLeaseTime('3600s'), equals('60m'));
      expect(RealApiService.sanitizeOpenWrtLeaseTime('120s'), equals('2m'));
      expect(RealApiService.sanitizeOpenWrtLeaseTime('30s'), equals('2m'));
    });

    test('Preserves valid standard unit formats (m, h, d)', () {
      expect(RealApiService.sanitizeOpenWrtLeaseTime('12h'), equals('12h'));
      expect(RealApiService.sanitizeOpenWrtLeaseTime('30m'), equals('30m'));
      expect(RealApiService.sanitizeOpenWrtLeaseTime('3d'), equals('3d'));
    });

    test('Converts plain numeric seconds to minutes', () {
      expect(RealApiService.sanitizeOpenWrtLeaseTime('7200'), equals('120m'));
      expect(RealApiService.sanitizeOpenWrtLeaseTime('60'), equals('2m'));
    });

    test('Falls back to 12h default on malformed strings', () {
      expect(RealApiService.sanitizeOpenWrtLeaseTime('invalid'), equals('12h'));
      expect(RealApiService.sanitizeOpenWrtLeaseTime('abc123xyz'), equals('12h'));
    });
  });

  group('RealApiService isValidIpv4Candidate Tests', () {
    test('Validates well-formed IPv4 addresses', () {
      expect(RealApiService.isValidIpv4Candidate('192.168.1.1'), isTrue);
      expect(RealApiService.isValidIpv4Candidate('10.0.0.1'), isTrue);
      expect(RealApiService.isValidIpv4Candidate('172.16.0.1'), isTrue);
      expect(RealApiService.isValidIpv4Candidate('255.255.255.255'), isTrue);
      expect(RealApiService.isValidIpv4Candidate('1.1.1.1'), isTrue);
    });

    test('Rejects malformed or out-of-range IP strings', () {
      expect(RealApiService.isValidIpv4Candidate('256.0.0.1'), isFalse);
      expect(RealApiService.isValidIpv4Candidate('192.168.1'), isFalse);
      expect(RealApiService.isValidIpv4Candidate('192.168.1.1.1'), isFalse);
      expect(RealApiService.isValidIpv4Candidate('hostname.local'), isFalse);
      expect(RealApiService.isValidIpv4Candidate(''), isFalse);
      expect(RealApiService.isValidIpv4Candidate('192.168.-1.1'), isFalse);
    });
  });

  group('RealApiService extractProcessList Tests', () {
    test('Extracts process list from nested OpenWrt RPC responses', () {
      final procA = {'PID': 1, 'COMMAND': '/sbin/init'};
      final procB = {'PID': 100, 'COMMAND': '/usr/sbin/dropbear'};

      expect(
        apiService.extractProcessList([0, [procA, procB]]),
        equals([procA, procB]),
      );
      expect(
        apiService.extractProcessList([[procA, procB]]),
        equals([procA, procB]),
      );
      expect(
        apiService.extractProcessList({
          'result': [procA, procB],
        }),
        equals([procA, procB]),
      );
    });

    test('Handles empty or invalid process responses gracefully', () {
      expect(apiService.extractProcessList(null), isNull);
      expect(apiService.extractProcessList([]), isNull);
      expect(apiService.extractProcessList({}), isNull);
    });
  });

  group('RealApiService Permissions Fix Script & ACL Contract Tests', () {
    test('Generates complete shell script with fallback mount and pkg managers', () {
      final script = RealApiService.getPermissionsFixScript();

      expect(script, contains('/usr/share/rpcd/acl.d/'));
      expect(script, contains('mount -t tmpfs tmpfs /usr/share/rpcd/acl.d'));
      expect(script, contains('apk update'));
      expect(script, contains('opkg update'));
      expect(script, contains('luci-mod-rpc'));
      expect(script, contains('rpcd-mod-iwinfo'));
      expect(script, contains('/etc/init.d/rpcd restart'));
    });

    test('Full ACL JSON contains complete access permissions for YALA', () {
      expect(RealApiService.fullAclJson, contains('"read"'));
      expect(RealApiService.fullAclJson, contains('"write"'));
      expect(RealApiService.fullAclJson, contains('"uci": [ "*" ]'));
      expect(RealApiService.fullAclJson, contains('file": [ "*" ]'));
    });
  });
}
