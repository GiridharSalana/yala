// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/client_controller.dart';

class _FakeAggregationApiService implements IApiService {
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

class _FakeAggregationAuthService implements IAuthService {
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

  group('Client Dumb AP Properties & Methods', () {
    test('Client default constructor defaults isDumbApClient to false', () {
      final client = Client(
        ipAddress: '192.168.1.10',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'MyPhone',
        isConnected: true,
      );

      expect(client.isDumbApClient, isFalse);
      expect(client.apName, isNull);
    });

    test('Client constructor accepts isDumbApClient and apName', () {
      final client = Client(
        ipAddress: '10.0.0.15',
        macAddress: 'AA:BB:CC:DD:EE:01',
        hostname: 'SmartSpeaker',
        isConnected: true,
        isDumbApClient: true,
        apName: 'TP-Link Archer C60',
      );

      expect(client.isDumbApClient, isTrue);
      expect(client.apName, 'TP-Link Archer C60');
    });

    test('Client.fromWirelessStation accepts isDumbApClient and apName', () {
      final client = Client.fromWirelessStation(
        '11:22:33:44:55:66',
        isDumbApClient: true,
        apName: 'Dumb AP 5GHz',
      );

      expect(client.macAddress, '11:22:33:44:55:66');
      expect(client.connectionType, ConnectionType.wireless);
      expect(client.isDumbApClient, isTrue);
      expect(client.apName, 'Dumb AP 5GHz');
    });

    test('Client.copyWith retains or updates isDumbApClient and apName', () {
      final original = Client(
        ipAddress: '10.0.0.50',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Laptop',
        isConnected: true,
      );

      final updated = original.copyWith(
        isDumbApClient: true,
        apName: 'Secondary AP',
      );

      expect(updated.isDumbApClient, isTrue);
      expect(updated.apName, 'Secondary AP');
      expect(updated.macAddress, original.macAddress);
      expect(updated.ipAddress, original.ipAddress);

      final preserved = updated.copyWith(hostname: 'New Laptop');
      expect(preserved.isDumbApClient, isTrue);
      expect(preserved.apName, 'Secondary AP');
      expect(preserved.hostname, 'New Laptop');
    });
  });

  group('ClientCategoryFilter.dumbAp filtering logic', () {
    final regularWired = Client(
      ipAddress: '10.0.0.10',
      macAddress: 'AA:11:11:11:11:11',
      hostname: 'Desktop',
      isConnected: true,
      connectionType: ConnectionType.wired,
    );

    final regularWireless = Client(
      ipAddress: '10.0.0.11',
      macAddress: 'AA:22:22:22:22:22',
      hostname: 'Phone-Main',
      isConnected: true,
      connectionType: ConnectionType.wireless,
    );

    final dumbApClient = Client(
      ipAddress: '10.0.0.12',
      macAddress: 'AA:33:33:33:33:33',
      hostname: 'Phone-AP',
      isConnected: true,
      connectionType: ConnectionType.wireless,
      isDumbApClient: true,
      apName: 'Archer C60 (AP)',
    );

    final allClients = [regularWired, regularWireless, dumbApClient];

    test('Filter by dumbAp returns only clients connected to the Dumb AP', () {
      final filtered = allClients.where((c) => c.isDumbApClient).toList();

      expect(filtered, hasLength(1));
      expect(filtered.first.macAddress, 'AA:33:33:33:33:33');
      expect(filtered.first.hostname, 'Phone-AP');
      expect(filtered.first.apName, 'Archer C60 (AP)');
    });

    test('Filter by all includes Dumb AP clients as well', () {
      expect(allClients, hasLength(3));
      expect(allClients.any((c) => c.isDumbApClient), isTrue);
    });

    test('Search query matches client by apName', () {
      const query = 'archer';
      final matching = allClients.where((c) {
        return (c.apName != null &&
            c.apName!.toLowerCase().contains(query.toLowerCase()));
      }).toList();

      expect(matching, hasLength(1));
      expect(matching.first.hostname, 'Phone-AP');
    });
  });

  group('AppState Dumb AP context-aware getters', () {
    test('AppState hasDumbAp reflects clients or controller state', () {
      final appState = AppState.instance;

      // Set clients with one Dumb AP client
      appState.clients = [
        Client(
          ipAddress: '10.0.0.2',
          macAddress: '00:11:22:33:44:55',
          hostname: 'Tablet',
          isConnected: true,
          isDumbApClient: true,
          apName: 'Dumb AP Bedroom',
        ),
        Client(
          ipAddress: '10.0.0.3',
          macAddress: '00:11:22:33:44:66',
          hostname: 'PC',
          isConnected: true,
        ),
      ];

      expect(appState.dumbApClients, hasLength(1));
      expect(appState.dumbApClientsCount, 1);
      expect(appState.dumbApClients.first.hostname, 'Tablet');
      expect(appState.dumbApClients.first.apName, 'Dumb AP Bedroom');
    });

    test(
      'AppState hasDumbAp is false when no clients are dumb AP clients and router is primary',
      () {
        final appState = AppState.instance;
        appState.clients = [
          Client(
            ipAddress: '192.168.1.200',
            macAddress: 'D2:04:46:30:05:F1',
            hostname: 'SM-L330',
            isConnected: true,
            connectionType: ConnectionType.wireless,
            isDumbApClient: false,
          ),
        ];

        expect(appState.dumbApClients, isEmpty);
        expect(appState.dumbApClientsCount, 0);
        expect(appState.clients.first.isDumbApClient, isFalse);
      },
    );

    test(
      'Primary router wireless clients are never tagged as Dumb AP clients',
      () {
        final primaryClient = Client(
          ipAddress: '192.168.1.100',
          macAddress: 'AA:BB:CC:DD:EE:01',
          hostname: 'Galaxy-S24',
          connectionType: ConnectionType.wireless,
          isConnected: true,
          isDumbApClient: false,
        );

        final copied = primaryClient.copyWith(ipAddress: '192.168.1.101');
        expect(copied.isDumbApClient, isFalse);
        expect(copied.apName, isNull);
      },
    );
  });

  group('Multi-Router Aggregation & Main Router Authoritative Resolution', () {
    late _FakeAggregationApiService fakeApi;
    late _FakeAggregationAuthService fakeAuth;
    late RouterService routerService;
    late ClientController clientController;

    final mainRouter = model.Router(
      id: 'main-router-1',
      name: 'ncxRouter',
      ipAddress: '10.0.0.1',
      username: 'root',
      password: 'password',
      useHttps: false,
    );

    final dumbApRouter = model.Router(
      id: 'test-router-2',
      name: 'ncxTest',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: 'password',
      useHttps: false,
    );

    setUp(() async {
      fakeApi = _FakeAggregationApiService();
      fakeAuth = _FakeAggregationAuthService();
      routerService = RouterService();
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
      );
    });

    test(
      'Main router wireless client is never tagged as Dumb AP client even if secondary AP has matching MAC',
      () async {
        // Main router (10.0.0.1) has ncxS24 connected wirelessly
        fakeApi.wirelessStationsByIp['10.0.0.1'] = {
          'wlan0': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'ssid': 'ncxRouter_5G',
              'signal': -55,
            },
          ],
        };
        fakeApi.dhcpLeasesByIp['10.0.0.1'] = [
          {
            'ipaddr': '10.0.0.50',
            'macaddr': 'AA:BB:CC:DD:EE:01',
            'hostname': 'ncxS24',
            'expires': 43200,
          },
        ];

        // Secondary AP (192.168.1.1) also observed the same MAC (e.g. in ARP or wireless)
        fakeApi.wirelessStationsByIp['192.168.1.1'] = {
          'wlan1': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'ssid': 'ncxTest_2G',
              'signal': -75,
            },
          ],
        };

        final clients = await clientController.fetchAggregatedClients();
        final s24 = clients.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:01',
        );

        expect(s24.isDumbApClient, isFalse);
        expect(s24.apName, isNull);
        expect(s24.hostname, 'ncxS24');
      },
    );

    test(
      'Main router wired client is never tagged as Dumb AP client even if secondary AP reports it in host hints',
      () async {
        // Main router (10.0.0.1) has wired client ncxLaptop
        fakeApi.dhcpLeasesByIp['10.0.0.1'] = [
          {
            'ipaddr': '10.0.0.100',
            'macaddr': 'AA:BB:CC:DD:EE:02',
            'hostname': 'ncxLaptop',
            'expires': 43200,
          },
        ];

        // Secondary AP (192.168.1.1) saw ncxLaptop on uplink WAN/ARP
        fakeApi.hostHintsByIp['192.168.1.1'] = {
          'AA:BB:CC:DD:EE:02': {
            'ip': '10.0.0.100',
            'name': 'ncxLaptop',
          },
        };

        final clients = await clientController.fetchAggregatedClients();
        final laptop = clients.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:02',
        );

        expect(laptop.isDumbApClient, isFalse);
        expect(laptop.apName, isNull);
        expect(laptop.connectionType, ConnectionType.wired);
      },
    );

    test(
      'Client connected wirelessly only to secondary AP receives isDumbApClient = true and apName = ncxTest',
      () async {
        // Main router (10.0.0.1) provides DHCP lease for secondary AP client
        fakeApi.dhcpLeasesByIp['10.0.0.1'] = [
          {
            'ipaddr': '10.0.0.150',
            'macaddr': 'AA:BB:CC:DD:EE:03',
            'hostname': 'BedroomTablet',
            'expires': 43200,
          },
        ];

        // Secondary AP (192.168.1.1) has the wireless association
        fakeApi.wirelessStationsByIp['192.168.1.1'] = {
          'wlan0': [
            {
              'mac': 'AA:BB:CC:DD:EE:03',
              'ssid': 'ncxTest_5G',
              'signal': -60,
            },
          ],
        };

        final clients = await clientController.fetchAggregatedClients();
        final tablet = clients.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:03',
        );

        expect(tablet.isDumbApClient, isTrue);
        expect(tablet.apName, 'ncxTest');
        expect(tablet.connectionType, ConnectionType.wireless);
      },
    );

    test(
      'Switching selected router makes the newly selected router the Main Router',
      () async {
        // Switch selected router to dumbApRouter (192.168.1.1)
        await routerService.selectRouter(dumbApRouter.id);

        fakeApi.wirelessStationsByIp['192.168.1.1'] = {
          'wlan0': [
            {
              'mac': 'AA:BB:CC:DD:EE:04',
              'ssid': 'ncxTest_2G',
              'signal': -50,
            },
          ],
        };

        final clients = await clientController.fetchAggregatedClients();
        final clientOnTest = clients.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:04',
        );

        // Since ncxTest is now the logged-in Main Router, its client is not a Dumb AP client
        expect(clientOnTest.isDumbApClient, isFalse);
        expect(clientOnTest.apName, isNull);
      },
    );
  });
}
