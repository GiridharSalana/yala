// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/modules/sqm/controllers/sqm_controller.dart';
import 'package:yala/modules/sqm/models/sqm_queue.dart';
import 'package:yala/modules/sqm/models/sqm_telemetry.dart';
import 'package:yala/modules/sqm/widgets/sqm_dashboard_card.dart';

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

class _TestSqmController extends SqmController {
  int startTelemetryCalls = 0;
  int stopTelemetryCalls = 0;
  int refreshCalls = 0;

  _TestSqmController(super.routerId, {SqmState? initialState}) {
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseQueue = SqmQueue(
    name: 'eth0',
    enabled: true,
    interface: 'eth0',
    download: 100000,
    upload: 20000,
    qdisc: 'cake',
    script: 'piece_of_cake.qos',
  );

  group('SqmDashboardCard Visibility Tests', () {
    testWidgets('1. Renders SizedBox.shrink when SQM is not installed', (
      tester,
    ) async {
      final mockController = _TestSqmController(
        'test-router',
        initialState: const SqmState(
          isInstalled: false,
          operatingState: SqmOperatingState.notInstalled,
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider(
              'test-router',
            ).overrideWith((ref) => mockController),
          ],
          child: const SqmDashboardCard(routerId: 'test-router'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sqm_dashboard_card')), findsNothing);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('2. Renders SizedBox.shrink when SQM is inactive / no queues', (
      tester,
    ) async {
      final mockController = _TestSqmController(
        'test-router',
        initialState: const SqmState(
          isInstalled: true,
          operatingState: SqmOperatingState.inactive,
          queues: [],
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider(
              'test-router',
            ).overrideWith((ref) => mockController),
          ],
          child: const SqmDashboardCard(routerId: 'test-router'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sqm_dashboard_card')), findsNothing);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets(
      '3. Renders SizedBox.shrink when SQM operatingState is inactive',
      (tester) async {
        final mockController = _TestSqmController(
          'test-router',
          initialState: const SqmState(
            isInstalled: true,
            operatingState: SqmOperatingState.inactive,
            queues: [baseQueue],
          ),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [
              sqmControllerProvider(
                'test-router',
              ).overrideWith((ref) => mockController),
            ],
            child: const SqmDashboardCard(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('sqm_dashboard_card')), findsNothing);
        expect(find.byType(Card), findsNothing);
      },
    );

    testWidgets('4. Renders Card when SQM is active with configured queue', (
      tester,
    ) async {
      final mockController = _TestSqmController(
        'test-router',
        initialState: const SqmState(
          isInstalled: true,
          operatingState: SqmOperatingState.active,
          queues: [baseQueue],
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider(
              'test-router',
            ).overrideWith((ref) => mockController),
          ],
          child: const SqmDashboardCard(routerId: 'test-router'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sqm_dashboard_card')), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });
  });

  group('SqmDashboardCard State Presentation Tests', () {
    testWidgets(
      '5. Displays Active SQM summary with interface, qdisc, bandwidth, and clean backlog',
      (tester) async {
        final telemetry = SqmQueueTelemetry(
          interfaceName: 'eth0',
          qdisc: 'cake',
          sentBytes: 1048576,
          sentPackets: 1000,
          droppedPackets: 0,
          backlogBytes: 0,
          backlogPackets: 0,
          timestamp: DateTime.now(),
        );

        final mockController = _TestSqmController(
          'test-router',
          initialState: SqmState(
            isInstalled: true,
            operatingState: SqmOperatingState.active,
            queues: const [baseQueue],
            telemetryByInterface: {'eth0': telemetry},
          ),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [
              sqmControllerProvider(
                'test-router',
              ).overrideWith((ref) => mockController),
            ],
            child: const SqmDashboardCard(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('sqm_dashboard_card_interface_qdisc')),
          findsOneWidget,
        );
        expect(find.text('eth0 • CAKE'), findsOneWidget);
        expect(find.text('Active'), findsOneWidget);
        expect(find.text('↓100 / ↑20 M'), findsOneWidget);
        expect(find.text('0 pkts (Clean)'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
      },
    );

    testWidgets('6. Displays Active Backlog and Cumulative Drops correctly', (
      tester,
    ) async {
      final telemetry = SqmQueueTelemetry(
        interfaceName: 'eth0',
        qdisc: 'cake',
        sentBytes: 5242880,
        sentPackets: 5000,
        droppedPackets: 25,
        backlogBytes: 4096,
        backlogPackets: 3,
        timestamp: DateTime.now(),
      );

      final mockController = _TestSqmController(
        'test-router',
        initialState: SqmState(
          isInstalled: true,
          operatingState: SqmOperatingState.active,
          queues: const [baseQueue],
          telemetryByInterface: {'eth0': telemetry},
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider(
              'test-router',
            ).overrideWith((ref) => mockController),
          ],
          child: const SqmDashboardCard(routerId: 'test-router'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 pkts (4.0 KB)'), findsOneWidget);
      expect(find.text('25 (0.5%)'), findsOneWidget);
    });

    testWidgets(
      '7. Displays Telemetry N/A gracefully when telemetry is unavailable',
      (tester) async {
        final mockController = _TestSqmController(
          'test-router',
          initialState: const SqmState(
            isInstalled: true,
            operatingState: SqmOperatingState.telemetryUnavailable,
            queues: [baseQueue],
            telemetryByInterface: {},
          ),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [
              sqmControllerProvider(
                'test-router',
              ).overrideWith((ref) => mockController),
            ],
            child: const SqmDashboardCard(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Telemetry N/A'), findsOneWidget);
        expect(find.text('↓100 / ↑20 M'), findsOneWidget);
        expect(
          find.text('—'),
          findsNWidgets(2),
        ); // Backlog and Drops both display '—'
      },
    );

    testWidgets(
      '8. Displays Offloading Conflict chip and Warning Banner when firewall offloading is active',
      (tester) async {
        final mockController = _TestSqmController(
          'test-router',
          initialState: const SqmState(
            isInstalled: true,
            operatingState: SqmOperatingState.flowOffloadingConflict,
            hasSoftwareFlowOffload: true,
            queues: [baseQueue],
          ),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [
              sqmControllerProvider(
                'test-router',
              ).overrideWith((ref) => mockController),
            ],
            child: const SqmDashboardCard(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Offloading Conflict'), findsOneWidget);
        expect(
          find.byKey(const Key('sqm_dashboard_card_conflict_banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Flow offloading is active in Firewall'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '9. Displays Recent Drop Activity badge when delta detection finds new drops',
      (tester) async {
        final prevTelemetry = SqmQueueTelemetry(
          interfaceName: 'eth0',
          qdisc: 'cake',
          sentBytes: 10000,
          sentPackets: 100,
          droppedPackets: 5,
          timestamp: DateTime.now().subtract(const Duration(seconds: 3)),
        );

        final currentTelemetry = SqmQueueTelemetry(
          interfaceName: 'eth0',
          qdisc: 'cake',
          sentBytes: 15000,
          sentPackets: 150,
          droppedPackets: 12, // 7 new drops
          timestamp: DateTime.now(),
        );

        final mockController = _TestSqmController(
          'test-router',
          initialState: SqmState(
            isInstalled: true,
            operatingState: SqmOperatingState.active,
            queues: const [baseQueue],
            telemetryByInterface: {'eth0': currentTelemetry},
            previousTelemetryByInterface: {'eth0': prevTelemetry},
          ),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [
              sqmControllerProvider(
                'test-router',
              ).overrideWith((ref) => mockController),
            ],
            child: const SqmDashboardCard(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('sqm_dashboard_card_recent_drops_badge')),
          findsOneWidget,
        );
        expect(find.text('Recent Drop Activity'), findsOneWidget);
      },
    );
  });

  group('Critical Polling Invariant Tests', () {
    testWidgets(
      '10. SqmDashboardCard NEVER calls startLiveTelemetry or creates a polling timer',
      (tester) async {
        final mockController = _TestSqmController(
          'polling-guard-router',
          initialState: const SqmState(
            isInstalled: true,
            operatingState: SqmOperatingState.active,
            queues: [baseQueue],
          ),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [
              sqmControllerProvider(
                'polling-guard-router',
              ).overrideWith((ref) => mockController),
            ],
            child: const SqmDashboardCard(routerId: 'polling-guard-router'),
          ),
        );
        await tester.pumpAndSettle();

        // Polling methods MUST NEVER be called by dashboard card
        expect(mockController.startTelemetryCalls, equals(0));
        expect(mockController.stopTelemetryCalls, equals(0));

        // Advance time to verify no internal timers were launched
        await tester.pump(const Duration(seconds: 5));
        expect(mockController.startTelemetryCalls, equals(0));
        expect(mockController.stopTelemetryCalls, equals(0));

        // Unmount card
        await tester.pumpWidget(
          _wrapWidget(
            overrides: [
              sqmControllerProvider(
                'polling-guard-router',
              ).overrideWith((ref) => mockController),
            ],
            child: const SizedBox(),
          ),
        );
        await tester.pumpAndSettle();

        expect(mockController.startTelemetryCalls, equals(0));
        expect(mockController.stopTelemetryCalls, equals(0));
      },
    );
  });

  group('Router Isolation Tests', () {
    testWidgets(
      '11. Different router IDs consume their own isolated controller state',
      (tester) async {
        const queueA = SqmQueue(
          name: 'eth0',
          enabled: true,
          interface: 'eth0',
          download: 100000,
          upload: 20000,
          qdisc: 'cake',
          script: 'piece_of_cake.qos',
        );

        const queueB = SqmQueue(
          name: 'wan',
          enabled: true,
          interface: 'wan',
          download: 50000,
          upload: 10000,
          qdisc: 'fq_codel',
          script: 'simple.qos',
        );

        final controllerA = _TestSqmController(
          'router-alpha',
          initialState: const SqmState(
            isInstalled: true,
            operatingState: SqmOperatingState.active,
            queues: [queueA],
          ),
        );

        final controllerB = _TestSqmController(
          'router-beta',
          initialState: const SqmState(
            isInstalled: true,
            operatingState: SqmOperatingState.active,
            queues: [queueB],
          ),
        );

        // Render Alpha
        await tester.pumpWidget(
          _wrapWidget(
            overrides: [
              sqmControllerProvider(
                'router-alpha',
              ).overrideWith((ref) => controllerA),
              sqmControllerProvider(
                'router-beta',
              ).overrideWith((ref) => controllerB),
            ],
            child: const SqmDashboardCard(routerId: 'router-alpha'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('eth0 • CAKE'), findsOneWidget);
        expect(find.text('↓100 / ↑20 M'), findsOneWidget);
        expect(find.text('wan • FQ_CODEL'), findsNothing);

        // Render Beta
        await tester.pumpWidget(
          _wrapWidget(
            overrides: [
              sqmControllerProvider(
                'router-alpha',
              ).overrideWith((ref) => controllerA),
              sqmControllerProvider(
                'router-beta',
              ).overrideWith((ref) => controllerB),
            ],
            child: const SqmDashboardCard(routerId: 'router-beta'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('wan • FQ_CODEL'), findsOneWidget);
        expect(find.text('↓50 / ↑10 M'), findsOneWidget);
        expect(find.text('eth0 • CAKE'), findsNothing);
      },
    );
  });

  group('Dashboard Interaction Tests', () {
    testWidgets('12. Tapping card triggers custom onTap callback', (
      tester,
    ) async {
      int tapCount = 0;
      final mockController = _TestSqmController(
        'test-router',
        initialState: const SqmState(
          isInstalled: true,
          operatingState: SqmOperatingState.active,
          queues: [baseQueue],
        ),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            sqmControllerProvider(
              'test-router',
            ).overrideWith((ref) => mockController),
          ],
          child: SqmDashboardCard(
            routerId: 'test-router',
            onTap: () => tapCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sqm_dashboard_card')));
      await tester.pumpAndSettle();

      expect(tapCount, equals(1));
    });
  });
}
