// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/models/client.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/screens/clients_screen.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/interfaces/auth_service_interface.dart';
import 'package:yala/services/router_service.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/state/controllers/client_controller.dart';

class TestMockApiService implements IApiService {
  Map<String, List<Map<String, dynamic>>> mockStationDetails = {};
  Map<String, dynamic> mockDhcpResult = {
    'dhcp_leases': [
      {
        'ipaddr': '192.168.1.101',
        'macaddr': 'AA:BB:CC:DD:EE:01',
        'hostname': 'Phone-WiFi',
        'expires': 3600,
      },
      {
        'ipaddr': '192.168.1.102',
        'macaddr': 'AA:BB:CC:DD:EE:02',
        'hostname': 'Desktop-LAN',
        'expires': 3600,
      },
    ],
  };
  Map<String, Map<String, dynamic>> mockHostHints = {};
  Map<String, dynamic>? mockNetworkInterfaceDump;

  @override
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAllAssociatedWirelessStationsWithDetailsContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    return mockStationDetails;
  }

  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    final result = <String, Set<String>>{};
    mockStationDetails.forEach((k, v) {
      result[k] = v.map((s) => s['mac'].toString().toUpperCase()).toSet();
    });
    return result;
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
    if (object == 'luci-rpc' && method == 'getDHCPLeases') {
      return [0, mockDhcpResult];
    }
    if (object == 'network.interface' && method == 'dump') {
      return [0, mockNetworkInterfaceDump ?? <String, dynamic>{}];
    }
    return [0, <String, dynamic>{}];
  }

  @override
  Future<Map<String, Map<String, dynamic>>> fetchHostHintsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    return mockHostHints;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestMockAuthService implements IAuthService {
  @override
  String? get sysauth => 'valid-sysauth-token';
  @override
  bool get useHttps => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockClientControllerWithFixedClients extends ClientController {
  final List<Client> fixedClients;
  MockClientControllerWithFixedClients(this.fixedClients)
    : super(
        apiServiceRef: () => TestMockApiService(),
        authServiceRef: () => TestMockAuthService(),
        routerServiceRef: () => RouterService(),
        reviewerModeRef: () => false,
        executeRouterCommandOutput: (cmd, args) async => null,
        processDhcpLeases: (raw) => raw,
      );

  @override
  Future<List<Client>> fetchClientsForSelectedRouter() async => fixedClients;

  @override
  Future<List<Client>> fetchAggregatedClients() async => fixedClients;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Client Model - Traffic & PHY Vitals Formatter Tests', () {
    test('Byte and speed formatting helpers behave correctly', () {
      expect(Client.formatBytes(0), '0 B');
      expect(Client.formatBytes(512), '512 B');
      expect(Client.formatBytes(1024), '1.0 KB');
      expect(Client.formatBytes(1536), '1.5 KB');
      expect(Client.formatBytes(1048576), '1.0 MB');
      expect(Client.formatBytes(52428800), '50.0 MB');
      expect(Client.formatBytes(1073741824), '1.0 GB');

      // Byte unit formatting (default or explicit)
      expect(Client.formatSpeed(0), '0 B/s');
      expect(Client.formatSpeed(500), '500 B/s');
      expect(Client.formatSpeed(1024), '1.0 KB/s');
      expect(Client.formatSpeed(204800), '200.0 KB/s');
      expect(Client.formatSpeed(2097152), '2.0 MB/s');

      // Bit unit formatting ('bits')
      expect(Client.formatSpeed(0, speedUnit: 'bits'), '0 bps');
      expect(Client.formatSpeed(50, speedUnit: 'bits'), '400 bps');
      expect(Client.formatSpeed(125, speedUnit: 'bits'), '1.0 Kbps');
      expect(Client.formatSpeed(12500, speedUnit: 'bits'), '100 Kbps');
      // Live AirtelSetTopBox HD stream sample: ~426.7 KB/s = ~3.4 Mbps
      expect(Client.formatSpeed(426700, speedUnit: 'bits'), '3.4 Mbps');
      expect(Client.formatSpeed(2500000, speedUnit: 'bits'), '20.0 Mbps');
    });

    test('Signal quality label classification', () {
      final clientGood = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        signalDbm: -55,
      );
      expect(clientGood.signalQualityLabel, 'Good');
      expect(clientGood.formattedSignalWithQuality, '-55 dBm (Good)');

      final clientExcellent = clientGood.copyWith(signalDbm: -45);
      expect(clientExcellent.signalQualityLabel, 'Excellent');

      final clientFair = clientGood.copyWith(signalDbm: -70);
      expect(clientFair.signalQualityLabel, 'Fair');

      final clientWeak = clientGood.copyWith(signalDbm: -82);
      expect(clientWeak.signalQualityLabel, 'Weak');

      final clientNone = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
      );
      expect(clientNone.signalQualityLabel, null);
      expect(clientNone.formattedSignalWithQuality, null);
    });

    test('PHY rate formatting maps kbit/s accurately', () {
      final clientPhy = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        rxRate: 866700,
        txRate: 866700,
      );
      expect(clientPhy.formattedPhyRate, '↓ 867 Mbps • ↑ 867 Mbps');

      final clientDownloadOnly = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        txRate: 300000,
      );
      expect(clientDownloadOnly.formattedPhyRate, '↓ 300 Mbps');

      final clientUploadOnly = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        rxRate: 72200,
      );
      expect(clientUploadOnly.formattedPhyRate, '↑ 72.2 Mbps');
    });

    test('Speed getters and session transfer formatting', () {
      final client = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        rxBytes: 15728640, // 15 MB uploaded by client to router
        txBytes: 104857600, // 100 MB downloaded from router by client
        rxSpeed: 102400, // 100 KB/s upload
        txSpeed: 2097152, // 2.0 MB/s download
        connectedTime: 3665, // 1h 1m
      );

      expect(client.formattedTotalUploaded, '15.0 MB');
      expect(client.formattedTotalDownloaded, '100 MB');
      expect(client.formattedUploadSpeed, '100.0 KB/s');
      expect(client.formattedDownloadSpeed, '2.0 MB/s');
      expect(client.formattedUploadSpeedWithUnit('bits'), '819 Kbps');
      expect(client.formattedDownloadSpeedWithUnit('bits'), '16.8 Mbps');
      expect(client.formattedUploadSpeedWithUnit('bytes'), '100.0 KB/s');
      expect(client.formattedDownloadSpeedWithUnit('bytes'), '2.0 MB/s');
      expect(client.formattedConnectedTime, '1h 1m');
      expect(client.hasTrafficData, isTrue);
    });
  });

  group('ClientController - Bandwidth Monitoring & Speed Delta Tests', () {
    late TestMockApiService mockApi;
    late TestMockAuthService mockAuth;
    late RouterService routerService;
    late ClientController clientController;
    Future<String?> Function(String cmd, List<String> args)? mockExecuteCommand;

    setUp(() async {
      mockExecuteCommand = null;
      mockApi = TestMockApiService();
      mockAuth = TestMockAuthService();
      routerService = RouterService();
      final router = model.Router(
        id: 'test-router-1',
        name: 'Main Router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      );
      await routerService.addRouter(router);
      await routerService.selectRouter(router.id);

      clientController = ClientController(
        apiServiceRef: () => mockApi,
        authServiceRef: () => mockAuth,
        routerServiceRef: () => routerService,
        reviewerModeRef: () => false,
        executeRouterCommandOutput: (cmd, args) async {
          if (mockExecuteCommand != null) {
            return mockExecuteCommand!(cmd, args);
          }
          return null;
        },
        processDhcpLeases: (raw) => raw,
      );
      AppState.instance.clientControllerForTesting = clientController;
    });

    test(
      'Associates wireless station vitals and computes speed delta on refresh',
      () async {
        mockApi.mockStationDetails = {
          'wlan0|Home-WiFi': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'signal': -52,
              'noise': -95,
              'thr': 450000,
              'connected_time': 1800,
              'rx': {'bytes': 1000000, 'packets': 1000, 'rate': 866700},
              'tx': {'bytes': 5000000, 'packets': 4000, 'rate': 866700},
            },
          ],
        };

        // First pass establishes traffic baseline
        final firstFetch = await clientController
            .fetchClientsForSelectedRouter();
        final wifiClientFirst = firstFetch.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:01',
        );
        expect(wifiClientFirst.connectionType, ConnectionType.wireless);
        expect(wifiClientFirst.rxBytes, 1000000);
        expect(wifiClientFirst.txBytes, 5000000);
        expect(wifiClientFirst.signalDbm, -52);
        expect(wifiClientFirst.rxSpeed, isNull);
        expect(wifiClientFirst.txSpeed, isNull);

        // Advance by 600ms and provide new byte totals
        await Future<void>.delayed(const Duration(milliseconds: 600));
        mockApi.mockStationDetails = {
          'wlan0|Home-WiFi': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'signal': -50,
              'noise': -95,
              'thr': 450000,
              'connected_time': 1801,
              'rx': {
                'bytes': 1600000,
                'packets': 1500,
                'rate': 866700,
              }, // +600 KB
              'tx': {
                'bytes': 6200000,
                'packets': 4900,
                'rate': 866700,
              }, // +1.2 MB
            },
          ],
        };

        final secondFetch = await clientController
            .fetchClientsForSelectedRouter();
        final wifiClientSecond = secondFetch.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:01',
        );
        expect(wifiClientSecond.rxBytes, 1600000);
        expect(wifiClientSecond.txBytes, 6200000);
        expect(wifiClientSecond.rxSpeed, isNotNull);
        expect(wifiClientSecond.txSpeed, isNotNull);
        expect(wifiClientSecond.rxSpeed!, greaterThan(0));
        expect(wifiClientSecond.txSpeed!, greaterThan(0));
      },
    );

    test(
      'Counter rollback / station reconnection does not cause negative speed or crash',
      () async {
        mockApi.mockStationDetails = {
          'wlan0|Home-WiFi': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'signal': -52,
              'rx': {'bytes': 50000000},
              'tx': {'bytes': 80000000},
            },
          ],
        };
        await clientController.fetchClientsForSelectedRouter();

        await Future<void>.delayed(const Duration(milliseconds: 600));
        // Reconnected station: byte counters reset to 1000
        mockApi.mockStationDetails = {
          'wlan0|Home-WiFi': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'signal': -52,
              'rx': {'bytes': 1000},
              'tx': {'bytes': 1000},
            },
          ],
        };

        final rolledBack = await clientController
            .fetchClientsForSelectedRouter();
        final client = rolledBack.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:01',
        );
        expect(client.rxBytes, 1000);
        expect(client.txBytes, 1000);
        expect(client.rxSpeed, isNull);
        expect(client.txSpeed, isNull);
      },
    );

    test('Wired clients do not receive fake wireless stats', () async {
      mockApi.mockStationDetails = {};
      final clients = await clientController.fetchClientsForSelectedRouter();
      final wiredClient = clients.firstWhere(
        (c) => c.macAddress == 'AA:BB:CC:DD:EE:02',
      );
      expect(wiredClient.connectionType, ConnectionType.wired);
      expect(wiredClient.hasTrafficData, isFalse);
      expect(wiredClient.formattedDownloadSpeed, isNull);
      expect(wiredClient.formattedPhyRate, isNull);
    });

    test(
      'WAN upstream gateway and WAN interface devices are excluded from client list',
      () async {
        mockApi.mockStationDetails = {};
        mockApi.mockNetworkInterfaceDump = {
          'interface': [
            {
              'interface': 'wan',
              'device': 'eth1',
              'l3_device': 'eth1',
              'ipv4-address': [
                {'address': '172.16.0.50'},
              ],
              'route': [
                {'nexthop': '172.16.0.1'},
              ],
            },
          ],
        };
        mockApi.mockHostHints = {
          '14:C3:5E:26:6F:21': {
            'ipaddrs': ['172.16.0.1'],
            'name': 'ISP-Gateway',
          },
        };

        mockExecuteCommand = (cmd, args) async {
          if (args.contains('neigh')) {
            return '172.16.0.1 dev eth1 lladdr 14:c3:5e:26:6f:21 REACHABLE\n'
                '192.168.1.102 dev br-lan lladdr aa:bb:cc:dd:ee:02 REACHABLE';
          }
          return null;
        };

        final clients = await clientController.fetchClientsForSelectedRouter();

        // WAN gateway 14:C3:5E:26:6F:21 must NOT be in clients
        expect(
          clients.any((c) => c.macAddress.toUpperCase() == '14:C3:5E:26:6F:21'),
          isFalse,
        );
        expect(clients.any((c) => c.ipAddress == '172.16.0.1'), isFalse);

        // Normal LAN client 192.168.1.102 must remain
        expect(
          clients.any((c) => c.macAddress.toUpperCase() == 'AA:BB:CC:DD:EE:02'),
          isTrue,
        );
      },
    );
  });

  group('ClientsScreen UI - Vitals and Badges Rendering', () {
    testWidgets(
      'Renders wired badge for wired client and live speed badge for wireless client',
      (tester) async {
        final wirelessClient = Client(
          ipAddress: '192.168.1.101',
          macAddress: 'AA:BB:CC:DD:EE:01',
          hostname: 'Laptop-WiFi',
          connectionType: ConnectionType.wireless,
          isConnected: true,
          ssid: 'Main-5G',
          signalDbm: -54,
          rxSpeed: 250000,
          txSpeed: 2500000,
          rxBytes: 10485760,
          txBytes: 104857600,
          rxRate: 866700,
          txRate: 866700,
          connectedTime: 3600,
        );

        final wiredClient = Client(
          ipAddress: '192.168.1.102',
          macAddress: 'AA:BB:CC:DD:EE:02',
          hostname: 'Desktop-LAN',
          connectionType: ConnectionType.wired,
          isConnected: true,
        );

        final appState = AppState.instance;
        appState.clients = [wirelessClient, wiredClient];
        appState.clientControllerForTesting =
            MockClientControllerWithFixedClients([wirelessClient, wiredClient]);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: [Locale('en')],
              home: ClientsScreen(isTabActive: true),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Wireless card checks:
        expect(
          find.textContaining('Wi-Fi • Main-5G • -54 dBm'),
          findsOneWidget,
        );
        expect(
          find.textContaining('20.0 Mbps'),
          findsWidgets,
        ); // Download speed in pill (default bits mode)
        expect(
          find.textContaining('2.0 Mbps'),
          findsWidgets,
        ); // Upload speed in pill (default bits mode)

        // Wired card checks:
        expect(find.text('Wired (LAN Port)'), findsWidgets);

        // Tap card to expand and verify detailed PHY & transfer vitals
        await tester.tap(find.text('Laptop-WiFi'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('↓ 867 Mbps • ↑ 867 Mbps'),
          findsOneWidget,
        ); // PHY rate in details
        expect(
          find.textContaining('-54 dBm (Good)'),
          findsOneWidget,
        ); // Signal with quality
        expect(
          find.textContaining('↓ 100 MB  ↑ 10.0 MB'),
          findsOneWidget,
        ); // Total session transfer
        expect(find.textContaining('1h'), findsOneWidget); // Connected duration
      },
    );

    testWidgets(
      'Offline clients do not display redundant Connected via Wired detail row',
      (tester) async {
        final offlineClient = Client(
          ipAddress: '10.0.0.61',
          macAddress: 'AA:BB:CC:DD:EE:61',
          hostname: 'MITV',
          connectionType: ConnectionType.wired,
          isConnected: false,
        );

        final appState = AppState.instance;
        appState.clients = [offlineClient];
        appState.clientControllerForTesting =
            MockClientControllerWithFixedClients([offlineClient]);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: [Locale('en')],
              home: ClientsScreen(isTabActive: true),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Card is rendered with offline indicator (no wired badge)
        expect(find.text('Wired (LAN Port)'), findsNothing);

        // Tap card to expand
        await tester.tap(find.text('MITV'));
        await tester.pumpAndSettle();

        // Verify that "Connected via" or "Wired (LAN Port)" is NOT displayed in the expanded details
        expect(find.text('Connected via'), findsNothing);
        expect(find.text('Wired (LAN Port)'), findsNothing);
      },
    );
  });
}
