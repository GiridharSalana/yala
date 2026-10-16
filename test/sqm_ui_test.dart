// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/modules/sqm/controllers/sqm_controller.dart';
import 'package:yala/modules/sqm/models/sqm_queue.dart';
import 'package:yala/main.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/models/rpc_result.dart';
import 'package:yala/modules/sqm/models/sqm_telemetry.dart';
import 'package:yala/modules/sqm/screens/sqm_screen.dart';
import 'package:yala/modules/sqm/widgets/sqm_install_card.dart';
import 'package:yala/modules/sqm/widgets/sqm_install_dialog.dart';
import 'package:yala/modules/sqm/widgets/sqm_queue_card.dart';
import 'package:yala/modules/sqm/widgets/sqm_status_card.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/widgets/luci_loading_view.dart';

Widget _wrapWidget({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

class _LifecycleTestController extends SqmController {
  int startTelemetryCalls = 0;
  int stopTelemetryCalls = 0;
  int refreshCalls = 0;

  _LifecycleTestController(super.routerId, {SqmState? initialState}) {
    if (initialState != null) {
      state = initialState;
    }
  }

  @override
  void startLiveTelemetry() {
    startTelemetryCalls++;
  }

  @override
  void stopLiveTelemetry() {
    stopTelemetryCalls++;
  }

  @override
  Future<void> refresh({bool forceTelemetry = false}) async {
    refreshCalls++;
  }

  RpcResult<String>? installResultOverride;

  @override
  Future<RpcResult<String>> installSqmPackage() async {
    if (installResultOverride != null) {
      return installResultOverride!;
    }
    return super.installSqmPackage();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SqmStatusCard Widget Tests', () {
    testWidgets('1. Displays running state, live badge, and active chip', (tester) async {
      const sqmState = SqmState(
        isInstalled: true,
        isServiceRunning: true,
        isServiceEnabled: true,
        operatingState: SqmOperatingState.active,
        isTelemetryPolling: true,
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SqmStatusCard(
            routerId: 'test-router',
            sqmState: sqmState,
            onRefresh: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SQM Daemon Service'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Live (3s)'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Starts automatically at boot'), findsOneWidget);
    });

    testWidgets('2. Displays stopped state with manual start', (tester) async {
      const sqmState = SqmState(
        isInstalled: true,
        isServiceRunning: false,
        isServiceEnabled: false,
        operatingState: SqmOperatingState.inactive,
        isTelemetryPolling: false,
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SqmStatusCard(
            routerId: 'test-router',
            sqmState: sqmState,
            onRefresh: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Manual start only'), findsOneWidget);
      expect(find.text('Live (3s)'), findsNothing);
    });

    testWidgets('3. Displays offloading conflict and telemetry N/A chips correctly', (tester) async {
      // Conflict
      const conflictState = SqmState(
        isInstalled: true,
        isServiceRunning: true,
        operatingState: SqmOperatingState.flowOffloadingConflict,
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SqmStatusCard(
            routerId: 'test-router',
            sqmState: conflictState,
            onRefresh: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offloading Conflict'), findsOneWidget);

      // Telemetry unavailable
      const noTelemState = SqmState(
        isInstalled: true,
        isServiceRunning: true,
        operatingState: SqmOperatingState.telemetryUnavailable,
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SqmStatusCard(
            routerId: 'test-router',
            sqmState: noTelemState,
            onRefresh: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Telemetry N/A'), findsOneWidget);
    });
  });

  group('SqmQueueCard Live Telemetry Presentation Tests', () {
    const baseQueue = SqmQueue(
      name: 'eth0',
      enabled: true,
      interface: 'eth0',
      download: 100000,
      upload: 20000,
      qdisc: 'cake',
      script: 'piece_of_cake.qos',
    );

    testWidgets('4. Displays Clean (0 Backlog) when queue has zero backlog', (tester) async {
      final telemetry = SqmQueueTelemetry(
        interfaceName: 'eth0',
        qdisc: 'cake',
        sentBytes: 1048576, // 1 MB
        sentPackets: 1000,
        droppedPackets: 0,
        overlimits: 0,
        backlogBytes: 0,
        backlogPackets: 0,
        timestamp: DateTime.now(),
      );

      final sqmState = SqmState(
        isInstalled: true,
        isServiceRunning: true,
        operatingState: SqmOperatingState.active,
        queues: [baseQueue],
        telemetryByInterface: {'eth0': telemetry},
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SingleChildScrollView(
            child: SqmQueueCard(
              queue: baseQueue,
              sqmState: sqmState,
              availableInterfaces: const ['eth0', 'eth1'],
              availableQdiscs: const ['cake', 'fq_codel'],
              availableScripts: const ['piece_of_cake.qos'],
              onSaved: () {},
              onDeleted: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Queue Telemetry (eth0)'), findsOneWidget);
      expect(find.text('0 pkts (Clean)'), findsWidgets);
      expect(find.text('1.0 MB'), findsOneWidget);
      expect(find.text('1000 pkts'), findsOneWidget);
      expect(find.text('0.00% rate'), findsOneWidget);
      // Semantic clarity note presence
      expect(find.textContaining('Drops and overlimits are cumulative Linux Traffic Control counters'), findsOneWidget);
    });

    testWidgets('5. Displays Active Backlog and Cumulative Drops and Overlimits', (tester) async {
      final telemetry = SqmQueueTelemetry(
        interfaceName: 'eth0',
        qdisc: 'cake',
        sentBytes: 52428800, // 50 MB
        sentPackets: 45000,
        droppedPackets: 250,
        overlimits: 120,
        requeues: 5,
        backlogBytes: 4500,
        backlogPackets: 3,
        memoryUsedBytes: 65536,
        capacityEstimateBps: 95000000,
        timestamp: DateTime.now(),
      );

      final sqmState = SqmState(
        isInstalled: true,
        isServiceRunning: true,
        operatingState: SqmOperatingState.active,
        queues: [baseQueue],
        telemetryByInterface: {'eth0': telemetry},
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SingleChildScrollView(
            child: SqmQueueCard(
              queue: baseQueue,
              sqmState: sqmState,
              availableInterfaces: const ['eth0', 'eth1'],
              availableQdiscs: const ['cake', 'fq_codel'],
              availableScripts: const ['piece_of_cake.qos'],
              onSaved: () {},
              onDeleted: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 pkts'), findsOneWidget);
      expect(find.text('4.4 KB'), findsOneWidget);
      expect(find.text('250'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('5 requeues'), findsOneWidget);
      expect(find.text('64.0 KB'), findsOneWidget);
      expect(find.text('95.0 Mbps'), findsOneWidget);
    });

    testWidgets('6. Displays Recent Drop Activity badge when sample delta detects new drops', (tester) async {
      final prevTelemetry = SqmQueueTelemetry(
        interfaceName: 'eth0',
        qdisc: 'cake',
        sentBytes: 10000,
        sentPackets: 100,
        droppedPackets: 10,
        overlimits: 5,
        timestamp: DateTime.now().subtract(const Duration(seconds: 3)),
      );

      final currentTelemetry = SqmQueueTelemetry(
        interfaceName: 'eth0',
        qdisc: 'cake',
        sentBytes: 15000,
        sentPackets: 150,
        droppedPackets: 15, // 5 new drops!
        overlimits: 5,
        timestamp: DateTime.now(),
      );

      final sqmState = SqmState(
        isInstalled: true,
        isServiceRunning: true,
        operatingState: SqmOperatingState.active,
        queues: [baseQueue],
        telemetryByInterface: {'eth0': currentTelemetry},
        previousTelemetryByInterface: {'eth0': prevTelemetry},
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SingleChildScrollView(
            child: SqmQueueCard(
              queue: baseQueue,
              sqmState: sqmState,
              availableInterfaces: const ['eth0'],
              availableQdiscs: const ['cake'],
              availableScripts: const ['piece_of_cake.qos'],
              onSaved: () {},
              onDeleted: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent Drop Activity'), findsOneWidget);
    });

    testWidgets('7. Displays CAKE multi-tin breakdown when present', (tester) async {
      final telemetry = SqmQueueTelemetry(
        interfaceName: 'eth0',
        qdisc: 'cake',
        sentBytes: 2000000,
        sentPackets: 1500,
        droppedPackets: 10,
        overlimits: 0,
        tinStats: const [
          CakeTinStats(name: 'Bulk', sentPackets: 500, droppedPackets: 8, backlogPackets: 0),
          CakeTinStats(name: 'Best Effort', sentPackets: 900, droppedPackets: 2, backlogPackets: 1),
          CakeTinStats(name: 'Voice', sentPackets: 100, droppedPackets: 0, backlogPackets: 0),
        ],
        timestamp: DateTime.now(),
      );

      final sqmState = SqmState(
        isInstalled: true,
        isServiceRunning: true,
        operatingState: SqmOperatingState.active,
        queues: [baseQueue],
        telemetryByInterface: {'eth0': telemetry},
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SingleChildScrollView(
            child: SqmQueueCard(
              queue: baseQueue,
              sqmState: sqmState,
              availableInterfaces: const ['eth0'],
              availableQdiscs: const ['cake'],
              availableScripts: const ['piece_of_cake.qos'],
              onSaved: () {},
              onDeleted: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CAKE Priority Tins'), findsOneWidget);
      expect(find.text('Bulk'), findsOneWidget);
      expect(find.text('Best Effort'), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
    });

    testWidgets('8. Displays FQ-CoDel ECN marks and new flows', (tester) async {
      final fqQueue = baseQueue.copyWith(qdisc: 'fq_codel');
      final telemetry = SqmQueueTelemetry(
        interfaceName: 'eth0',
        qdisc: 'fq_codel',
        sentBytes: 10000,
        sentPackets: 100,
        droppedPackets: 0,
        overlimits: 0,
        ecnMarked: 42,
        newFlowCount: 15,
        timestamp: DateTime.now(),
      );

      final sqmState = SqmState(
        isInstalled: true,
        isServiceRunning: true,
        operatingState: SqmOperatingState.active,
        queues: [fqQueue],
        telemetryByInterface: {'eth0': telemetry},
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SingleChildScrollView(
            child: SqmQueueCard(
              queue: fqQueue,
              sqmState: sqmState,
              availableInterfaces: const ['eth0'],
              availableQdiscs: const ['fq_codel'],
              availableScripts: const ['simple.qos'],
              onSaved: () {},
              onDeleted: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ECN Marks'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('New Flows'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('9. Shows waiting placeholder when telemetry is not yet received', (tester) async {
      const sqmState = SqmState(
        isInstalled: true,
        isServiceRunning: true,
        operatingState: SqmOperatingState.active,
        queues: [baseQueue],
        telemetryByInterface: {},
      );

      await tester.pumpWidget(
        _wrapWidget(
          child: SingleChildScrollView(
            child: SqmQueueCard(
              queue: baseQueue,
              sqmState: sqmState,
              availableInterfaces: const ['eth0'],
              availableQdiscs: const ['cake'],
              availableScripts: const ['piece_of_cake.qos'],
              onSaved: () {},
              onDeleted: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Waiting for queue traffic on eth0...'), findsOneWidget);
    });
  });

  group('SqmScreen Lifecycle & Navigation Tests', () {
    testWidgets('10. Calls startLiveTelemetry on mount and stopLiveTelemetry on dispose', (tester) async {
      final mockController = _LifecycleTestController('lifecycle-router', initialState: const SqmState(isInstalled: true));

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider('lifecycle-router').overrideWith((ref) => mockController),
          ],
          child: const SqmScreen(routerId: 'lifecycle-router'),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockController.startTelemetryCalls, equals(1));
      expect(mockController.stopTelemetryCalls, equals(0));

      // Unmount screen
      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider('lifecycle-router').overrideWith((ref) => mockController),
          ],
          child: const SizedBox(),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockController.stopTelemetryCalls, equals(1));
    });

    testWidgets('11. Renders SqmInstallCard when SQM is uninstalled', (tester) async {
      final mockController = _LifecycleTestController(
        'uninstalled-router',
        initialState: const SqmState(isInstalled: false),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider('uninstalled-router').overrideWith((ref) => mockController),
          ],
          child: const SqmScreen(routerId: 'uninstalled-router'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SqmInstallCard), findsOneWidget);
      expect(find.byType(SqmStatusCard), findsNothing);
    });

    testWidgets('12. Renders Flow Offloading warning banner when firewall offloading is active', (tester) async {
      final mockController = _LifecycleTestController(
        'offloading-router',
        initialState: const SqmState(
          isInstalled: true,
          isServiceRunning: true,
          hasSoftwareFlowOffload: true,
          operatingState: SqmOperatingState.flowOffloadingConflict,
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider('offloading-router').overrideWith((ref) => mockController),
          ],
          child: const SqmScreen(routerId: 'offloading-router'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Flow offloading is active in Firewall'), findsOneWidget);
      expect(find.byType(SqmStatusCard), findsOneWidget);
    });

    testWidgets('12a. Renders LuciLoadingView during initial discovery loading instead of premature SqmInstallCard', (tester) async {
      final mockController = _LifecycleTestController(
        'initial-loading-router',
        initialState: const SqmState(
          isLoading: true,
          isInstalled: false,
          lastUpdated: null,
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider('initial-loading-router').overrideWith((ref) => mockController),
          ],
          child: const SqmScreen(routerId: 'initial-loading-router'),
        ),
      );
      await tester.pump();

      expect(find.byType(LuciLoadingView), findsOneWidget);
      expect(find.byType(SqmInstallCard), findsNothing);
      expect(find.byType(SqmStatusCard), findsNothing);
    });

    testWidgets('12b. Renders discovery error view when probe fails and retry discovery button triggers controller refresh', (tester) async {
      final mockController = _LifecycleTestController(
        'probe-failed-router',
        initialState: const SqmState(
          isLoading: false,
          isInstalled: false,
          errorMessage: 'Unable to check SQM status: connection or RPC failed',
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider('probe-failed-router').overrideWith((ref) => mockController),
          ],
          child: const SqmScreen(routerId: 'probe-failed-router'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unable to check SQM status'), findsOneWidget);
      expect(find.text('Retry Discovery'), findsOneWidget);
      expect(find.byType(SqmInstallCard), findsNothing);

      final refreshCallsBefore = mockController.refreshCalls;
      await tester.tap(find.text('Retry Discovery'));
      await tester.pump();

      expect(mockController.refreshCalls, equals(refreshCallsBefore + 1));
    });
  });

  group('SqmInstallDialog Widget Tests', () {
    late AppState appState;

    setUp(() {
      appState = AppState.instance;
      appState.setApiServiceForTesting(MockApiService());
    });

    tearDown(() {
      appState.clearFreeDiskSpaceForTesting();
    });

    testWidgets('13. Renders live storage assessment and enables Install Now when storage is healthy', (tester) async {
      appState.setFreeDiskSpaceForTesting(15 * 1024 * 1024);
      appState.setDashboardDataForTesting({
        'mountPoints': [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'fs': 'jffs2',
            'size': 20971520,
            'used': 5242880,
            'avail': 15728640,
            'options': 'rw,noatime',
          }
        ],
      });
      appState.setCapabilitiesForTesting(RouterCapabilities.conservative('test-router'));

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const SqmInstallDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Install Smart Queue Management'), findsOneWidget);
      expect(find.textContaining('Free space in /overlay: 15.0 MB'), findsOneWidget);
      expect(find.text('sqm-scripts'), findsOneWidget);

      final installBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Install Now'),
      );
      expect(installBtn.onPressed, isNotNull);
    });

    testWidgets('14. Shows read-only banner and disables Install Now when overlay is read-only', (tester) async {
      appState.setDashboardDataForTesting({
        'mountPoints': [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'fs': 'jffs2',
            'size': 10485760,
            'used': 10485760,
            'avail': 0,
            'options': 'ro,relatime',
          }
        ],
      });
      appState.setCapabilitiesForTesting(RouterCapabilities.conservative('test-router'));

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const SqmInstallDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Storage filesystem is read-only or full. Package installation cannot proceed.'),
        findsOneWidget,
      );

      final installBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Install Now'),
      );
      expect(installBtn.onPressed, isNull);
    });

    testWidgets('15. Shows low storage advisory warning without blocking Install Now when < 500 KB', (tester) async {
      appState.setFreeDiskSpaceForTesting(250 * 1024);
      appState.setDashboardDataForTesting({
        'mountPoints': [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'fs': 'jffs2',
            'size': 10485760,
            'used': 10229760,
            'avail': 256000,
            'options': 'rw,noatime',
          }
        ],
      });
      appState.setCapabilitiesForTesting(RouterCapabilities.conservative('test-router'));

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const SqmInstallDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Storage is limited'), findsOneWidget);
      expect(find.textContaining('Package installation requires sufficient flash space'), findsOneWidget);

      final installBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Install Now'),
      );
      expect(installBtn.onPressed, isNotNull);
    });

    testWidgets('16. Shows Fix Permissions button when RPC packages are missing', (tester) async {
      appState.setDashboardDataForTesting({
        'mountPoints': [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'fs': 'jffs2',
            'size': 20971520,
            'used': 5242880,
            'avail': 15728640,
            'options': 'rw,noatime',
          }
        ],
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities(
          routerId: 'test-router',
          probedAt: DateTime.now(),
          ubusObjects: const {'system'},
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const SqmInstallDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Package installation is restricted because router RPC permissions are missing.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Fix Permissions'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Install Now'), findsNothing);
    });

    testWidgets('17. Confirms and returns sqm-scripts when Install Now is tapped', (tester) async {
      appState.setDashboardDataForTesting({
        'mountPoints': [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'fs': 'jffs2',
            'size': 20971520,
            'used': 5242880,
            'avail': 15728640,
            'options': 'rw,noatime',
          }
        ],
      });
      appState.setCapabilitiesForTesting(RouterCapabilities.conservative('test-router'));

      String? dialogResult;

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                dialogResult = await showDialog<String>(
                  context: context,
                  builder: (_) => const SqmInstallDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(SqmInstallDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Install Now'));
      await tester.pumpAndSettle();

      expect(find.byType(SqmInstallDialog), findsNothing);
      expect(dialogResult, equals('sqm-scripts'));
    });

    testWidgets('18. Displays Unavailable and does NOT use stale dashboardData storage when live query returns null', (tester) async {
      appState.setFreeDiskSpaceForTesting(null);
      appState.setDashboardDataForTesting({
        'mountPoints': [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'fs': 'jffs2',
            'size': 20971520,
            'used': 5242880,
            'avail': 15728640,
            'options': 'rw,noatime',
          }
        ],
      });
      appState.setCapabilitiesForTesting(RouterCapabilities.conservative('test-router'));

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const SqmInstallDialog(),
        ),
      );
      await tester.pumpAndSettle();

      // Must display Unavailable because live query returned null
      expect(find.textContaining('Free space in /overlay: Unavailable'), findsOneWidget);

      // Must NOT render 15.0 MB from cached dashboardData
      expect(find.textContaining('15.0 MB'), findsNothing);
      expect(find.textContaining('15.00 MB'), findsNothing);

      // Still allows installation since filesystem was not affirmatively determined to be read-only
      final installBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Install Now'),
      );
      expect(installBtn.onPressed, isNotNull);
    });

    testWidgets('19. Displays Memory Exhaustion (OOM) diagnosis dialog on OOM install failure and leaves Install UI available', (tester) async {
      final mockController = _LifecycleTestController(
        'oom-fail-router',
        initialState: const SqmState(
          isInstalled: false,
          operatingState: SqmOperatingState.notInstalled,
        ),
      );
      mockController.installResultOverride = RpcResult.failed('Killed', code: 137);

      appState.setFreeDiskSpaceForTesting(1024 * 1024 * 10);
      appState.setCapabilitiesForTesting(RouterCapabilities.conservative('oom-fail-router'));

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider('oom-fail-router').overrideWith((ref) => mockController),
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const SqmScreen(routerId: 'oom-fail-router'),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Install SQM on SqmInstallCard
      await tester.tap(find.widgetWithText(FilledButton, 'Install SQM'));
      await tester.pumpAndSettle();

      // Tap Install Now in the dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Install Now'));
      await tester.pumpAndSettle();

      // Verify OOM diagnosis dialog appears
      expect(find.text('Memory Exhaustion (OOM)'), findsOneWidget);
      expect(find.textContaining('The router ran out of RAM while resolving package dependencies'), findsOneWidget);
      expect(find.textContaining('Insufficient Storage Space'), findsNothing);

      // Dismiss dialog
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Verify SqmInstallCard remains visible and available for retry
      expect(find.byType(SqmInstallCard), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Install SQM'), findsOneWidget);
      expect(mockController.state.isInstalled, isFalse);
    });
  });
}
