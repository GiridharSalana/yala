// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/client.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/interfaces/auth_service_interface.dart';
import 'package:yala/services/router_service.dart';
import 'package:yala/state/controllers/client_controller.dart';

class _FakeLazyApiService implements IApiService {
  Map<String, Completer<void>?> delaysByIp = {};
  Map<String, Map<String, List<Map<String, dynamic>>>> wirelessStationsByIp =
      {};
  Map<String, List<Map<String, dynamic>>> dhcpLeasesByIp = {};
  Map<String, Map<String, Map<String, dynamic>>> hostHintsByIp = {};

  @override
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return AuthResult.success('fake-token', actualUseHttps: useHttps);
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAllAssociatedWirelessStationsWithDetailsContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    final completer = delaysByIp[ipAddress];
    if (completer != null) {
      await completer.future;
    }
    return wirelessStationsByIp[ipAddress] ??
        <String, List<Map<String, dynamic>>>{};
  }

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    final completer = delaysByIp[ipAddress];
    if (completer != null) {
      await completer.future;
    }
    if (method == 'getDHCPLeases') {
      return [
        0,
        {
          'dhcp_leases': dhcpLeasesByIp[ipAddress] ?? [],
          'dhcp6_leases': [],
        },
      ];
    }
    return [0, {}];
  }

  @override
  Future<Map<String, Map<String, dynamic>>> fetchHostHintsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    return hostHintsByIp[ipAddress] ?? <String, Map<String, dynamic>>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLazyAuthService implements IAuthService {
  @override
  String? get sysauth => 'fake-token';
  @override
  bool get useHttps => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Client Lazy Loading & Progressive Emission Tests', () {
    late _FakeLazyApiService fakeApi;
    late _FakeLazyAuthService fakeAuth;
    late RouterService routerService;
    late ClientController clientController;
    int clientUpdatedCallbacksCount = 0;

    final mainRouter = model.Router(
      id: 'main-router-1',
      name: 'ncxRouter',
      ipAddress: '10.0.0.1',
      username: 'root',
      password: 'password',
      useHttps: false,
    );

    final dumbApRouter = model.Router(
      id: 'dumb-ap-2',
      name: 'ncxTest',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: 'password',
      useHttps: false,
    );

    setUp(() async {
      fakeApi = _FakeLazyApiService();
      fakeAuth = _FakeLazyAuthService();
      routerService = RouterService();
      clientUpdatedCallbacksCount = 0;
      await routerService.clearAllRouters();
      await routerService.addRouter(mainRouter);
      await routerService.addRouter(dumbApRouter);
      await routerService.selectRouter(mainRouter.id);

      clientController = ClientController(
        apiServiceRef: () => fakeApi,
        authServiceRef: () => fakeAuth,
        routerServiceRef: () => routerService,
        reviewerModeRef: () => false,
        executeRouterCommandOutput: (cmd, args) async => null,
        processDhcpLeases: (raw) => raw,
        onClientsUpdated: () {
          clientUpdatedCallbacksCount++;
        },
      );
    });

    test(
      'Main router clients are emitted right away while Dumb AP is still loading',
      () async {
        // Main router (10.0.0.1) responds immediately with 1 wireless client
        fakeApi.wirelessStationsByIp['10.0.0.1'] = {
          'wlan0': [
            {
              'mac': '11:22:33:44:55:01',
              'ssid': 'ncxRouter_5G',
              'signal': -50,
            },
          ],
        };
        fakeApi.dhcpLeasesByIp['10.0.0.1'] = [
          {
            'ipaddr': '10.0.0.50',
            'macaddr': '11:22:33:44:55:01',
            'hostname': 'MainPhone',
            'expires': 43200,
          },
        ];

        // Secondary router (192.168.1.1) is delayed via Completer (simulating slow Dumb AP)
        final dumbApCompleter = Completer<void>();
        fakeApi.delaysByIp['192.168.1.1'] = dumbApCompleter;

        fakeApi.wirelessStationsByIp['192.168.1.1'] = {
          'wlan0': [
            {
              'mac': '11:22:33:44:55:02',
              'ssid': 'ncxTest_2G',
              'signal': -60,
            },
          ],
        };
        fakeApi.dhcpLeasesByIp['10.0.0.1']!.add({
          'ipaddr': '10.0.0.51',
          'macaddr': '11:22:33:44:55:02',
          'hostname': 'DumbApTablet',
          'expires': 43200,
        });

        final emissionSnapshots = <List<Client>>[];

        final fetchFuture = clientController.fetchAggregatedClients(
          onIncrementalUpdate: (incrementalList) {
            emissionSnapshots.add(List<Client>.from(incrementalList));
          },
        );

        // Allow microtasks for Main router to complete
        await Future.delayed(const Duration(milliseconds: 50));

        // 1. Verify Main Router clients were emitted right away
        expect(
          emissionSnapshots.length,
          1,
          reason: 'Main router clients should emit before Dumb AP finishes',
        );
        expect(emissionSnapshots.first.length, 2);
        final mainPhone = emissionSnapshots.first.firstWhere(
          (c) => c.macAddress == '11:22:33:44:55:01',
        );
        expect(mainPhone.hostname, 'MainPhone');
        expect(mainPhone.isDumbApClient, isFalse);
        expect(clientUpdatedCallbacksCount, 1);
        expect(
          clientController.lastFetchedClients?.where((c) => c.isDumbApClient),
          isEmpty,
        );

        // 2. Now complete the secondary Dumb AP request
        dumbApCompleter.complete();
        final finalClients = await fetchFuture;

        // 3. Verify second emission arrived with Dumb AP client merged
        expect(
          emissionSnapshots.length,
          2,
          reason: 'Second emission should occur when Dumb AP finishes',
        );
        expect(emissionSnapshots[1].length, 2);

        final dumbClient = emissionSnapshots[1].firstWhere(
          (c) => c.macAddress == '11:22:33:44:55:02',
        );
        expect(dumbClient.isDumbApClient, isTrue);
        expect(dumbClient.apName, 'ncxTest');

        final dumbCount =
            finalClients.where((c) => c.isDumbApClient).length;
        expect(dumbCount, 1);
        expect(clientUpdatedCallbacksCount, 2);
      },
    );

    test(
      'Router profile switch / resetState discards in-flight delayed responses via epoch guard',
      () async {
        fakeApi.dhcpLeasesByIp['10.0.0.1'] = [
          {
            'ipaddr': '10.0.0.100',
            'macaddr': 'AA:BB:CC:DD:EE:FF',
            'hostname': 'OldRouterClient',
            'expires': 43200,
          },
        ];

        final mainCompleter = Completer<void>();
        fakeApi.delaysByIp['10.0.0.1'] = mainCompleter;

        final emissionSnapshots = <List<Client>>[];

        final fetchFuture = clientController.fetchAggregatedClients(
          onIncrementalUpdate: (incrementalList) {
            emissionSnapshots.add(List<Client>.from(incrementalList));
          },
        );

        // Simulate user immediately switching profile or logging out
        clientController.resetState();
        expect(clientController.lastFetchedClients, isNull);

        // Now complete the delayed response from the previous router
        mainCompleter.complete();
        await fetchFuture;

        // The stale fetch must NOT have published any clients or updated state
        expect(emissionSnapshots, isEmpty);
        expect(clientController.lastFetchedClients, isNull);
      },
    );
  });
}
