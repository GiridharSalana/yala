// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yala/modules/firewall_security/models/firewall_info.dart';
import 'package:yala/services/api_service.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/state/app_state.dart';

class SpyApiService extends MockApiService {
  int uciApplyCalls = 0;
  int uciConfirmCalls = 0;
  bool applyReturnValue = true;
  bool confirmReturnValue = true;
  String? lastIp;
  bool? lastRollback;
  int? lastTimeout;

  @override
  Future<bool> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    bool rollback = true,
    int timeout = 30,
  }) async {
    uciApplyCalls++;
    lastIp = ipAddress;
    lastRollback = rollback;
    lastTimeout = timeout;
    return applyReturnValue;
  }

  @override
  Future<bool> uciConfirm(
    String ipAddress,
    String sysauth,
    bool useHttps,
  ) async {
    uciConfirmCalls++;
    lastIp = ipAddress;
    return confirmReturnValue;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('UCI Transaction Tests', () {
    test('MockApiService default handles uciApply and uciConfirm', () async {
      final mockApi = MockApiService();

      final applyResult = await mockApi.uciApply(
        '192.168.1.1',
        'test-token',
        false,
        rollback: true,
        timeout: 30,
      );
      expect(applyResult, isTrue);

      final confirmResult = await mockApi.uciConfirm(
        '192.168.1.1',
        'test-token',
        false,
      );
      expect(confirmResult, isTrue);
    });

    test('AppState delegates uciApply and uciConfirm through operationQueue with parameters', () async {
      final appState = AppState.instance;
      final spyApi = SpyApiService();
      appState.setApiServiceForTesting(spyApi);

      final applySuccess = await appState.uciApply(
        ipAddress: '192.168.1.1',
        sysauth: 'test-token',
        useHttps: false,
        rollback: true,
        timeout: 30,
      );

      expect(applySuccess, isTrue);
      expect(spyApi.uciApplyCalls, equals(1));
      expect(spyApi.lastIp, equals('192.168.1.1'));
      expect(spyApi.lastRollback, isTrue);
      expect(spyApi.lastTimeout, equals(30));

      final confirmSuccess = await appState.uciConfirm(
        ipAddress: '192.168.1.1',
        sysauth: 'test-token',
        useHttps: false,
      );

      expect(confirmSuccess, isTrue);
      expect(spyApi.uciConfirmCalls, equals(1));
      expect(spyApi.lastIp, equals('192.168.1.1'));
    });

    test('AppState uciApply handles missing target IP gracefully', () async {
      final appState = AppState.instance;
      // When no router is selected and no ip is provided
      final result = await appState.uciApply(ipAddress: '');
      expect(result, isFalse);
    });

    test('AppState uciConfirm handles missing target IP gracefully', () async {
      final appState = AppState.instance;
      // When no router is selected and no ip is provided
      final result = await appState.uciConfirm(ipAddress: '');
      expect(result, isFalse);
    });
  });

  group('RealApiService Authoritative State Verification Helpers', () {
    test('extractUciValuesMap extracts nested values or falls back cleanly', () {
      final nested = {'values': {'rule1': {'name': 'r1'}}};
      expect(RealApiService.extractUciValuesMap(nested), equals({'rule1': {'name': 'r1'}}));

      final flat = {'rule2': {'name': 'r2'}};
      expect(RealApiService.extractUciValuesMap(flat), equals({'rule2': {'name': 'r2'}}));

      expect(RealApiService.extractUciValuesMap(null), isEmpty);
      expect(RealApiService.extractUciValuesMap([]), isEmpty);
    });

    test('findUciSection finds section by direct key or by .name property', () {
      final uci = {
        'cfg01': {'.name': 'cfg01', 'name': 'First'},
        'my_alias': {'.name': 'cfg02', 'name': 'Second'},
      };

      expect(RealApiService.findUciSection(uci, 'cfg01')?['name'], equals('First'));
      expect(RealApiService.findUciSection(uci, 'cfg02')?['name'], equals('Second'));
      expect(RealApiService.findUciSection(uci, 'cfg99'), isNull);
    });

    test('hasUciSection reports presence accurately', () {
      final uci = {
        'rule_a': {'.name': 'rule_a'},
      };
      expect(RealApiService.hasUciSection(uci, 'rule_a'), isTrue);
      expect(RealApiService.hasUciSection(uci, 'rule_b'), isFalse);
    });
  });

  group('RealApiService Protected Mutation Authoritative Verification Tests', () {
    test('deleteFirewallPortForward rolls back and rejects confirm if section still present', () async {
      final mock = ControllableTxRealApiService();
      // Configure uci.get to report section 'pf_1' is still present after delete
      mock.customResponses['uci.get'] = [
        0,
        {
          'values': {
            'pf_1': {'.name': 'pf_1', '.type': 'redirect', 'name': 'Web'},
          }
        }
      ];

      final result = await mock.deleteFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        sectionKey: 'pf_1',
      );

      expect(result, isFalse);
      expect(mock.uciRevertCalls, equals(1));
      expect(mock.uciConfirmCalls, equals(0)); // Confirm MUST NOT be reached!
    });

    test('deleteFirewallPortForward confirms when section is verified absent', () async {
      final mock = ControllableTxRealApiService();
      // Configure uci.get to report empty values (section absent)
      mock.customResponses['uci.get'] = [
        0,
        {'values': <String, dynamic>{}}
      ];

      final result = await mock.deleteFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        sectionKey: 'pf_1',
      );

      expect(result, isTrue);
      expect(mock.uciRevertCalls, equals(0));
      expect(mock.uciConfirmCalls, equals(1));
    });

    test('updateFirewallPortForward rolls back if section is missing or properties mismatch', () async {
      final mock = ControllableTxRealApiService();
      // Missing section
      mock.customResponses['uci.get'] = [
        0,
        {'values': <String, dynamic>{}}
      ];

      final resMissing = await mock.updateFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        portForward: const FirewallPortForwarding(
          sectionKey: 'pf_1',
          name: 'Web-Server',
          srcZone: 'wan',
          srcPort: '8080',
          destZone: 'lan',
          destIp: '192.168.1.50',
          destPort: '80',
          proto: 'tcp',
          target: 'DNAT',
        ),
      );
      expect(resMissing, isFalse);
      expect(mock.uciRevertCalls, equals(1));
      expect(mock.uciConfirmCalls, equals(0));

      // Property mismatch (name mismatch)
      mock.uciRevertCalls = 0;
      mock.customResponses['uci.get'] = [
        0,
        {
          'values': {
            'pf_1': {
              '.name': 'pf_1',
              '.type': 'redirect',
              'name': 'Old-Name',
              'target': 'DNAT',
            }
          }
        }
      ];

      final resMismatch = await mock.updateFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        portForward: const FirewallPortForwarding(
          sectionKey: 'pf_1',
          name: 'Web-Server',
          srcZone: 'wan',
          srcPort: '8080',
          destZone: 'lan',
          destIp: '192.168.1.50',
          destPort: '80',
          proto: 'tcp',
          target: 'DNAT',
        ),
      );
      expect(resMismatch, isFalse);
      expect(mock.uciRevertCalls, equals(1));
      expect(mock.uciConfirmCalls, equals(0));
    });

    test('updateFirewallPortForward confirms when section and updated properties match', () async {
      final mock = ControllableTxRealApiService();
      mock.customResponses['uci.get'] = [
        0,
        {
          'values': {
            'pf_1': {
              '.name': 'pf_1',
              '.type': 'redirect',
              'name': 'Web-Server',
              'target': 'DNAT',
            }
          }
        }
      ];

      final result = await mock.updateFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        portForward: const FirewallPortForwarding(
          sectionKey: 'pf_1',
          name: 'Web-Server',
          srcZone: 'wan',
          srcPort: '8080',
          destZone: 'lan',
          destIp: '192.168.1.50',
          destPort: '80',
          proto: 'tcp',
          target: 'DNAT',
        ),
      );
      expect(result, isTrue);
      expect(mock.uciRevertCalls, equals(0));
      expect(mock.uciConfirmCalls, equals(1));
    });

    test('deleteFirewallCustomRule rolls back and rejects confirm if rule still present', () async {
      final mock = ControllableTxRealApiService();
      mock.customResponses['uci.get'] = [
        0,
        {
          'values': {
            'rule_1': {'.name': 'rule_1', '.type': 'rule', 'name': 'Block-Bad'},
          }
        }
      ];

      final result = await mock.deleteFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        sectionKey: 'rule_1',
      );

      expect(result, isFalse);
      expect(mock.uciRevertCalls, equals(1));
      expect(mock.uciConfirmCalls, equals(0));
    });

    test('deleteFirewallCustomRule confirms when rule is verified absent', () async {
      final mock = ControllableTxRealApiService();
      mock.customResponses['uci.get'] = [
        0,
        {'values': <String, dynamic>{}}
      ];

      final result = await mock.deleteFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        sectionKey: 'rule_1',
      );

      expect(result, isTrue);
      expect(mock.uciRevertCalls, equals(0));
      expect(mock.uciConfirmCalls, equals(1));
    });

    test('updateFirewallCustomRule rolls back if section is missing or target mismatches', () async {
      final mock = ControllableTxRealApiService();
      mock.customResponses['uci.get'] = [
        0,
        {
          'values': {
            'rule_1': {
              '.name': 'rule_1',
              '.type': 'rule',
              'name': 'My-Rule',
              'target': 'REJECT', // Mismatched from ACCEPT
            }
          }
        }
      ];

      final result = await mock.updateFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        rule: const FirewallCustomRule(
          sectionKey: 'rule_1',
          name: 'My-Rule',
          srcZone: 'lan',
          destZone: 'wan',
          target: 'ACCEPT',
          enabled: true,
        ),
      );

      expect(result, isFalse);
      expect(mock.uciRevertCalls, equals(1));
      expect(mock.uciConfirmCalls, equals(0));
    });

    test('updateFirewallCustomRule confirms when rule and updated properties match', () async {
      final mock = ControllableTxRealApiService();
      mock.customResponses['uci.get'] = [
        0,
        {
          'values': {
            'rule_1': {
              '.name': 'rule_1',
              '.type': 'rule',
              'name': 'My-Rule',
              'target': 'ACCEPT',
            }
          }
        }
      ];

      final result = await mock.updateFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        rule: const FirewallCustomRule(
          sectionKey: 'rule_1',
          name: 'My-Rule',
          srcZone: 'lan',
          destZone: 'wan',
          target: 'ACCEPT',
          enabled: true,
        ),
      );

      expect(result, isTrue);
      expect(mock.uciRevertCalls, equals(0));
      expect(mock.uciConfirmCalls, equals(1));
    });

    test('addFirewallPortForward rolls back if returned section ID is missing after apply', () async {
      final mock = ControllableTxRealApiService();
      // uci.add returns section key 'cfg_new_pf'
      mock.customResponses['uci.add'] = [
        0,
        {'section': 'cfg_new_pf'}
      ];
      // But uci.get does not contain 'cfg_new_pf'
      mock.customResponses['uci.get'] = [
        0,
        {'values': <String, dynamic>{}}
      ];

      final result = await mock.addFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        portForward: const FirewallPortForwarding(
          sectionKey: '',
          name: 'New-Forward',
          srcZone: 'wan',
          srcPort: '8080',
          destZone: 'lan',
          destIp: '192.168.1.60',
          destPort: '80',
          proto: 'tcp',
        ),
      );

      expect(result, isFalse);
      expect(mock.uciRevertCalls, equals(1));
      expect(mock.uciConfirmCalls, equals(0));
    });

    test('addFirewallPortForward confirms when returned section ID is present after apply', () async {
      final mock = ControllableTxRealApiService();
      mock.customResponses['uci.add'] = [
        0,
        {'section': 'cfg_new_pf'}
      ];
      mock.customResponses['uci.get'] = [
        0,
        {
          'values': {
            'cfg_new_pf': {
              '.name': 'cfg_new_pf',
              '.type': 'redirect',
              'name': 'New-Forward',
            }
          }
        }
      ];

      final result = await mock.addFirewallPortForward(
        '192.168.1.1',
        'auth_token',
        false,
        portForward: const FirewallPortForwarding(
          sectionKey: '',
          name: 'New-Forward',
          srcZone: 'wan',
          srcPort: '8080',
          destZone: 'lan',
          destIp: '192.168.1.60',
          destPort: '80',
          proto: 'tcp',
        ),
      );

      expect(result, isTrue);
      expect(mock.uciRevertCalls, equals(0));
      expect(mock.uciConfirmCalls, equals(1));
    });

    test('Verification RPC timeout or error triggers rollback and disallows confirm', () async {
      final mock = ControllableTxRealApiService();
      // uci.get returns error / failure code
      mock.customResponses['uci.get'] = [-1];

      final result = await mock.deleteFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        sectionKey: 'rule_1',
      );

      expect(result, isFalse);
      expect(mock.uciRevertCalls, equals(1));
      expect(mock.uciConfirmCalls, equals(0));
    });

    test('Confirmation failure aborts transaction and returns false without claiming success', () async {
      final mock = ControllableTxRealApiService();
      mock.confirmResult = false; // confirm RPC fails or times out
      mock.customResponses['uci.get'] = [
        0,
        {'values': <String, dynamic>{}}
      ];

      final result = await mock.deleteFirewallCustomRule(
        '192.168.1.1',
        'auth_token',
        false,
        sectionKey: 'rule_1',
      );

      expect(result, isFalse);
      expect(mock.uciConfirmCalls, equals(1));
    });
  });
}

class ControllableTxRealApiService extends RealApiService {
  final Map<String, dynamic> customResponses = {};
  int uciApplyCalls = 0;
  int uciConfirmCalls = 0;
  int uciRevertCalls = 0;
  bool applyResult = true;
  bool confirmResult = true;

  @override
  Future<dynamic> callWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
    bool isRetry = false,
  }) async {
    final key = '$object.$method';
    if (customResponses.containsKey(key)) {
      return customResponses[key];
    }
    return [0, {}];
  }

  @override
  Future<bool> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    bool rollback = true,
    int timeout = 30,
  }) async {
    uciApplyCalls++;
    return applyResult;
  }

  @override
  Future<bool> uciConfirm(
    String ipAddress,
    String sysauth,
    bool useHttps,
  ) async {
    uciConfirmCalls++;
    return confirmResult;
  }

  @override
  Future<dynamic> uciRevert(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    uciRevertCalls++;
    return [0];
  }
}

