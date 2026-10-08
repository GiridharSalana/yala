// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/models/client.dart';
import 'package:yala/modules/bandwidth_monitor/controllers/bandwidth_monitor_controller.dart';
import 'package:yala/modules/bandwidth_monitor/models/bandwidth_data.dart';
import 'package:yala/modules/bandwidth_monitor/screens/bandwidth_monitor_screen.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('RealtimeTrafficPoint Model Tests', () {
    test('Parses luci-bwc raw array correctly', () {
      final raw = [1711800000, 1048576, 100, 524288, 50];
      final pt = RealtimeTrafficPoint.fromList(raw);

      expect(pt.timestamp, equals(1711800000));
      expect(pt.rxBytes, equals(1048576));
      expect(pt.rxPackets, equals(100));
      expect(pt.txBytes, equals(524288));
      expect(pt.txPackets, equals(50));
      expect(pt.rxRate, equals(0.0));
      expect(pt.txRate, equals(0.0));
    });

    test('Handles short or empty list gracefully without throwing', () {
      final pt1 = RealtimeTrafficPoint.fromList([]);
      expect(pt1.timestamp, equals(0));
      expect(pt1.rxBytes, equals(0));

      final pt2 = RealtimeTrafficPoint.fromList([1711800000, 500]);
      expect(pt2.timestamp, equals(1711800000));
      expect(pt2.rxBytes, equals(500));
      expect(pt2.txBytes, equals(0));
    });

    test('Calculates rates correctly between two consecutive points', () {
      const prev = RealtimeTrafficPoint(
        timestamp: 1711800000,
        rxBytes: 1000000,
        txBytes: 500000,
        rxPackets: 100,
        txPackets: 50,
      );

      final next = RealtimeTrafficPoint.fromList(
        [
          1711800002,
          3000000,
          200,
          1500000,
          100,
        ], // 2s delta, +2,000,000 rx, +1,000,000 tx
        previousPoint: prev,
      );

      expect(next.rxRate, equals(1000000.0));
      expect(next.txRate, equals(500000.0));
    });

    test('Handles counter reset/rollover gracefully', () {
      const prev = RealtimeTrafficPoint(
        timestamp: 1711800000,
        rxBytes: 5000000,
        txBytes: 5000000,
        rxPackets: 500,
        txPackets: 500,
      );

      final next = RealtimeTrafficPoint.fromList(
        [1711800001, 1000, 1, 2000, 2], // rolled over
        previousPoint: prev,
      );

      expect(next.rxRate, equals(0.0));
      expect(next.txRate, equals(0.0));
    });
  });

  group('NlbwmonHostRecord & Report Model Tests', () {
    test('Parses nlbwmon host record via fromColumns correctly', () {
      final columns = [
        'mac',
        'ip',
        'layer7',
        'conns',
        'rx_bytes',
        'rx_pkts',
        'tx_bytes',
        'tx_pkts',
      ];
      final row = [
        'AA:BB:CC:DD:EE:FF',
        '192.168.1.105',
        'https',
        42,
        10485760,
        8000,
        5242880,
        4000,
      ];

      final record = NlbwmonHostRecord.fromColumns(columns, row);

      expect(record.ip, equals('192.168.1.105'));
      expect(record.mac, equals('AA:BB:CC:DD:EE:FF'));
      expect(record.layer7, equals('https'));
      expect(record.conns, equals(42));
      expect(record.rxBytes, equals(10485760));
      expect(record.txBytes, equals(5242880));
      expect(record.totalBytes, equals(15728640));
    });

    test('Parses nlbwmon report with period and host list', () {
      final json = {
        'period': '2026-03',
        'columns': [
          'mac',
          'ip',
          'layer7',
          'conns',
          'rx_bytes',
          'rx_pkts',
          'tx_bytes',
          'tx_pkts',
        ],
        'data': [
          [
            '11:22:33:44:55:66',
            '192.168.1.100',
            'http',
            10,
            1000,
            10,
            2000,
            20,
          ],
          ['AA:BB:CC:DD:EE:FF', '192.168.1.101', 'ssh', 20, 3000, 30, 4000, 40],
        ],
      };

      final report = NlbwmonReport.fromJson(json, '2026-03');

      expect(report.period, equals('2026-03'));
      expect(report.records.length, equals(2));
      expect(report.records[0].ip, equals('192.168.1.100'));
      expect(report.records[1].ip, equals('192.168.1.101'));
      expect(report.records[0].rxBytes, equals(1000));
      expect(report.records[1].txBytes, equals(4000));
    });
  });

  group('DeviceBandwidthItem Model Tests', () {
    test('Calculates live and session formatted strings correctly', () {
      final client = Client(
        ipAddress: '192.168.1.50',
        macAddress: 'AA:BB:CC:DD:EE:01',
        hostname: 'Work-Laptop',
        connectionType: ConnectionType.wireless,
        signalDbm: -55,
        rxRate: 866000,
      );

      final item = DeviceBandwidthItem(
        client: client,
        downloadSpeed: 2097152, // 2 MB/s
        uploadSpeed: 524288, // 512 KB/s
        peakDownloadSpeed: 4194304,
        peakUploadSpeed: 1048576,
        totalDownloaded: 1073741824, // 1 GB
        totalUploaded: 268435456, // 256 MB
      );

      expect(item.hasActiveSpeed, isTrue);
      expect(item.formattedDownloadSpeed('MB/s'), contains('MB/s'));
      expect(item.formattedUploadSpeed('KB/s'), contains('KB/s'));
      expect(item.formattedTotalDownloaded, contains('GB'));
      expect(item.formattedTotalUploaded, contains('MB'));
      expect(item.displayName, equals('Work-Laptop'));
      expect(item.ipAddress, equals('192.168.1.50'));
      expect(item.macAddress, equals('AA:BB:CC:DD:EE:01'));
    });

    test('Correctly identifies inactive devices below active threshold', () {
      final client = Client(
        ipAddress: '192.168.1.51',
        macAddress: 'AA:BB:CC:DD:EE:02',
        hostname: 'Idle-Phone',
      );

      final item = DeviceBandwidthItem(
        client: client,
        downloadSpeed: 50,
        uploadSpeed: 40,
      );

      expect(item.hasActiveSpeed, isFalse);
    });
  });

  group('BandwidthSummary Model Tests', () {
    test('Computes aggregate speeds and session totals', () {
      const summary = BandwidthSummary(
        totalDownloadSpeed: 5242880,
        totalUploadSpeed: 1048576,
        peakDownloadSpeed: 10485760,
        peakUploadSpeed: 2097152,
        totalSessionDownload: 5000000000,
        totalSessionUpload: 1000000000,
        connectedDevicesCount: 5,
        activeTrafficDevicesCount: 3,
      );

      expect(summary.formattedDownloadSpeed('MB/s'), contains('MB/s'));
      expect(summary.formattedUploadSpeed('MB/s'), contains('MB/s'));
      expect(summary.formattedPeakDownload('MB/s'), contains('MB/s'));
      expect(summary.formattedPeakUpload('MB/s'), contains('MB/s'));
      expect(summary.formattedTotalDownloaded, isNotEmpty);
      expect(summary.formattedTotalUploaded, isNotEmpty);
    });
  });

  group('BandwidthMonitorState Filtering & Sorting Tests', () {
    test('Sorts and filters devices correctly', () {
      final dev1 = DeviceBandwidthItem(
        client: Client(
          macAddress: 'AA:BB:CC:11:11:11',
          ipAddress: '192.168.1.10',
          hostname: 'Alpha-Phone',
        ),
        downloadSpeed: 500000,
        uploadSpeed: 100000,
        totalDownloaded: 2000000,
        totalUploaded: 500000,
      );

      final dev2 = DeviceBandwidthItem(
        client: Client(
          macAddress: 'AA:BB:CC:22:22:22',
          ipAddress: '192.168.1.20',
          hostname: 'Beta-Laptop',
        ),
        downloadSpeed: 1000000,
        uploadSpeed: 50000,
        totalDownloaded: 5000000,
        totalUploaded: 1000000,
      );

      final dev3 = DeviceBandwidthItem(
        client: Client(
          macAddress: 'AA:BB:CC:33:33:33',
          ipAddress: '192.168.1.30',
          hostname: 'Gamma-TV',
        ),
        downloadSpeed: 200000,
        uploadSpeed: 300000,
        totalDownloaded: 8000000,
        totalUploaded: 2000000,
      );

      var state = BandwidthMonitorState(
        devices: [dev1, dev2, dev3],
        sortMode: BandwidthSortMode.downloadSpeed,
      );

      // Sort by download speed descending (default)
      var sorted = state.filteredAndSortedDevices;
      expect(sorted[0].displayName, equals('Beta-Laptop'));
      expect(sorted[1].displayName, equals('Alpha-Phone'));
      expect(sorted[2].displayName, equals('Gamma-TV'));

      // Sort by upload speed descending
      state = state.copyWith(sortMode: BandwidthSortMode.uploadSpeed);
      sorted = state.filteredAndSortedDevices;
      expect(sorted[0].displayName, equals('Gamma-TV'));
      expect(sorted[1].displayName, equals('Alpha-Phone'));
      expect(sorted[2].displayName, equals('Beta-Laptop'));

      // Sort by total usage descending
      state = state.copyWith(sortMode: BandwidthSortMode.totalUsage);
      sorted = state.filteredAndSortedDevices;
      expect(sorted[0].displayName, equals('Gamma-TV'));
      expect(sorted[1].displayName, equals('Beta-Laptop'));
      expect(sorted[2].displayName, equals('Alpha-Phone'));

      // Search query filtering
      state = state.copyWith(searchQuery: 'laptop');
      sorted = state.filteredAndSortedDevices;
      expect(sorted.length, equals(1));
      expect(sorted[0].displayName, equals('Beta-Laptop'));

      // Search by IP
      state = state.copyWith(searchQuery: '192.168.1.30');
      sorted = state.filteredAndSortedDevices;
      expect(sorted.length, equals(1));
      expect(sorted[0].displayName, equals('Gamma-TV'));

      // Clear search
      state = state.copyWith(searchQuery: '');
      sorted = state.filteredAndSortedDevices;
      expect(sorted.length, equals(3));
    });
    test(
      'Default sortMode is BandwidthSortMode.name and sorts alphabetically',
      () {
        const defaultState = BandwidthMonitorState();
        expect(defaultState.sortMode, equals(BandwidthSortMode.name));

        final dev1 = DeviceBandwidthItem(
          client: Client(
            ipAddress: '192.168.1.10',
            macAddress: '11:22:33:44:55:66',
            hostname: 'Beta-Phone',
          ),
        );
        final dev2 = DeviceBandwidthItem(
          client: Client(
            ipAddress: '192.168.1.20',
            macAddress: '22:33:44:55:66:77',
            hostname: 'Alpha-Laptop',
          ),
        );
        final state = BandwidthMonitorState(
          devices: [dev1, dev2],
          sortMode: BandwidthSortMode.name,
        );
        final sorted = state.filteredAndSortedDevices;
        expect(sorted[0].displayName, equals('Alpha-Laptop'));
        expect(sorted[1].displayName, equals('Beta-Phone'));
      },
    );
  });

  group('BandwidthMonitorController Integration Tests', () {
    test('Loads usage stats and nlbwmon data from MockApiService', () async {
      final mockApi = MockApiService();
      final appState = AppState.instance;

      final container = ProviderContainer(
        overrides: [
          appStateProvider.overrideWith((ref) => appState),
          bandwidthMonitorProvider.overrideWith((ref) {
            return BandwidthMonitorController(
              ref,
              apiService: mockApi,
              autoStart: false,
            );
          }),
        ],
      );

      final controller = container.read(bandwidthMonitorProvider.notifier);

      await controller.refreshData();

      final state = container.read(bandwidthMonitorProvider);
      expect(state.usageStats, isNotEmpty);
      expect(state.isNlbwmonInstalled, isTrue);
      expect(state.nlbwmonReport, isNotNull);
      expect(state.nlbwmonPeriods, isNotEmpty);

      container.dispose();
    });

    test(
      'Excludes disconnected static clients from live devices list but includes them in usage stats',
      () async {
        final mockApi = MockApiService();
        final appState = AppState.instance;

        // Seed clients: 1 active wireless client, 1 disconnected static client
        appState.clients = [
          Client(
            ipAddress: '192.168.1.10',
            macAddress: '11:22:33:44:55:66',
            hostname: 'ActivePhone',
            isConnected: true,
            connectionType: ConnectionType.wireless,
          ),
          Client(
            ipAddress: '192.168.1.50',
            macAddress: 'AA:BB:CC:DD:EE:FF',
            hostname: 'OfflineServer',
            isConnected: false,
            isStaticLease: true,
            staticLeaseName: 'NAS',
            connectionType: ConnectionType.wired,
          ),
        ];

        final container = ProviderContainer(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
            bandwidthMonitorProvider.overrideWith((ref) {
              return BandwidthMonitorController(
                ref,
                apiService: mockApi,
                autoStart: false,
              );
            }),
          ],
        );

        final controller = container.read(bandwidthMonitorProvider.notifier);
        await controller.refreshData();

        final state = container.read(bandwidthMonitorProvider);
        // Only the connected client should be present in live devices
        expect(state.devices.length, equals(1));
        expect(state.devices.first.macAddress, equals('11:22:33:44:55:66'));
        expect(state.devices.first.isConnected, isTrue);

        // But usage stats MUST include both connected and disconnected/offline clients
        expect(
          state.usageStats.any(
            (u) => u.mac == 'AA:BB:CC:DD:EE:FF' && !u.isConnected,
          ),
          isTrue,
        );

        container.dispose();
      },
    );
  });

  group('BandwidthMonitorScreen Widget Tests', () {
    testWidgets(
      'Renders Bandwidth Monitor screen with 2 tabs and summary header',
      (tester) async {
        final mockApi = MockApiService();
        final appState = AppState.instance;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith((ref) => appState),
              bandwidthMonitorProvider.overrideWith((ref) {
                return BandwidthMonitorController(
                  ref,
                  apiService: mockApi,
                  autoStart: false,
                );
              }),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: BandwidthMonitorScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify screen title / app bar
        expect(find.byType(BandwidthMonitorScreen), findsOneWidget);

        // Verify Tab items: Only Live Devices and Usage Stats (Traffic History removed)
        expect(find.text('Live Devices'), findsOneWidget);
        expect(find.text('Traffic History'), findsNothing);
        expect(find.text('Usage Stats'), findsOneWidget);

        // Verify Summary card headers (Download / Upload)
        expect(find.text('Download'), findsAtLeastNWidgets(1));
        expect(find.text('Upload'), findsAtLeastNWidgets(1));

        // Tap on Usage Stats Tab
        await tester.tap(find.text('Usage Stats'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Return to Live Devices tab
        await tester.tap(find.text('Live Devices'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      },
    );

    testWidgets(
      'Usage Stats displays resolved static name or hostname and supports offline devices',
      (tester) async {
        final mockApi = MockApiService();
        final appState = AppState.instance;

        appState.clients = [
          Client(
            ipAddress: '192.168.1.100',
            macAddress: 'AA:BB:CC:DD:EE:01',
            hostname: 'DHCP-Laptop',
            staticLeaseName: 'WorkStation',
            isConnected: true,
          ),
          Client(
            ipAddress: '192.168.1.101',
            macAddress: 'AA:BB:CC:DD:EE:02',
            hostname: 'LivingRoom-TV',
            isConnected: false,
          ),
        ];

        late BandwidthMonitorController controller;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith((ref) => appState),
              bandwidthMonitorProvider.overrideWith((ref) {
                controller = BandwidthMonitorController(
                  ref,
                  apiService: mockApi,
                  autoStart: false,
                );
                return controller;
              }),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: BandwidthMonitorScreen(),
            ),
          ),
        );

        await controller.refreshData();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Switch to Usage Stats tab
        await tester.tap(find.text('Usage Stats'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Expect to see resolved static name 'WorkStation' for connected device
        expect(find.text('WorkStation'), findsOneWidget);
        expect(find.text('AA:BB:CC:DD:EE:01'), findsOneWidget);
        expect(find.text('192.168.1.101'), findsOneWidget);

        // Expect to see hostname 'LivingRoom-TV' for disconnected/offline device
        expect(find.text('LivingRoom-TV'), findsOneWidget);
        expect(find.text('AA:BB:CC:DD:EE:02'), findsOneWidget);
        expect(find.text('192.168.1.102'), findsOneWidget);

        // Verify connection badge pills are removed
        expect(find.text('Connected'), findsNothing);
        expect(find.text('Not Connected'), findsNothing);
      },
    );
  });
}
