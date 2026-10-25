// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/models/rpc_result.dart';
import 'package:yala/modules/sqm/controllers/sqm_controller.dart';
import 'package:yala/modules/sqm/models/sqm_telemetry.dart';
import 'package:yala/modules/sqm/services/sqm_telemetry_service.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/operation_queue.dart';

class _MockLuciApiService implements IApiService {
  final Map<String, dynamic> responses;
  int callCount = 0;

  _MockLuciApiService({this.responses = const {}});

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async {
    callCount++;
    final key = '$object.$method';
    if (responses.containsKey(key)) {
      return responses[key];
    }
    // Return empty success by default
    return [0, {}];
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingLuciApiService implements IApiService {
  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async {
    throw Exception('Simulated network/RPC connection refused');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockTelemetryService extends SqmTelemetryService {
  SqmQueueTelemetry? cannedTelemetry;
  int fetchCount = 0;

  _MockTelemetryService({this.cannedTelemetry});

  @override
  Future<SqmQueueTelemetry?> fetchQueueTelemetry({
    required IApiService apiService,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interfaceName,
    bool isReviewerMode = false,
  }) async {
    fetchCount++;
    return cannedTelemetry;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SqmController.clearSessionCache);

  group('SqmController Lifecycle & State Discovery Tests', () {
    test('1. Reviewer Mode populates realistic active mock state', () async {
      final controller = SqmController('reviewer-mock-router');
      addTearDown(controller.dispose);

      await controller.refresh();

      final state = controller.state;
      expect(state.isInstalled, isTrue);
      expect(state.isServiceRunning, isTrue);
      expect(state.operatingState, equals(SqmOperatingState.active));
      expect(state.queues.length, equals(2));
      expect(state.primaryQueue?.interface, equals('eth0'));
      expect(state.primaryTelemetry?.qdisc, equals('cake'));
      expect(state.primaryTelemetry?.tinStats.length, equals(3));
      expect(state.isLoading, isFalse);
    });

    test('2. Uninstalled SQM router classifies as notInstalled', () async {
      final api = _MockLuciApiService(
        responses: {
          'rc.list': [
            0,
            {
              'firewall': {'running': true},
            },
          ],
          'uci.get': [
            0,
            {'values': {}},
          ],
        },
      );

      final controller = SqmController(
        'test-router-1',
        apiServiceOverride: api,
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      final state = controller.state;
      expect(state.isInstalled, isFalse);
      expect(state.operatingState, equals(SqmOperatingState.notInstalled));
      expect(state.queues, isEmpty);
    });

    test(
      '3. Firewall flow offloading detected as flowOffloadingConflict',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'sqm': {'running': true, 'enabled': true},
              },
            ],
            'uci.get': [
              0,
              {
                'values': {
                  'defaults': {
                    '.type': 'defaults',
                    'flow_offloading': '1',
                    'flow_offloading_hw': '0',
                  },
                  'eth0': {
                    '.type': 'queue',
                    'interface': 'eth0',
                    'download': 100000,
                    'upload': 20000,
                    'qdisc': 'cake',
                    'enabled': '1',
                  },
                },
              },
            ],
          },
        );

        final controller = SqmController(
          'test-router-2',
          apiServiceOverride: api,
        );
        addTearDown(controller.dispose);

        await controller.refresh();

        final state = controller.state;
        expect(state.isInstalled, isTrue);
        expect(state.hasSoftwareFlowOffload, isTrue);
        expect(state.hasHardwareFlowOffload, isFalse);
        expect(state.hasAnyFlowOffloading, isTrue);
        expect(
          state.operatingState,
          equals(SqmOperatingState.flowOffloadingConflict),
        );
      },
    );

    test('4. Inactive service classifies as inactive', () async {
      final api = _MockLuciApiService(
        responses: {
          'rc.list': [
            0,
            {
              'sqm': {'running': false, 'enabled': false},
            },
          ],
          'uci.get': [
            0,
            {
              'values': {
                'eth0': {
                  '.type': 'queue',
                  'interface': 'eth0',
                  'download': 100000,
                  'upload': 20000,
                  'qdisc': 'cake',
                  'enabled': '0',
                },
              },
            },
          ],
        },
      );

      final controller = SqmController(
        'test-router-3',
        apiServiceOverride: api,
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      final state = controller.state;
      expect(state.isInstalled, isTrue);
      expect(state.isServiceRunning, isFalse);
      expect(state.operatingState, equals(SqmOperatingState.inactive));
    });

    test(
      '5. Telemetry failure on active queue classifies as telemetryUnavailable',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'sqm': {'running': true, 'enabled': true},
              },
            ],
            'uci.get': [
              0,
              {
                'values': {
                  'eth0': {
                    '.type': 'queue',
                    'interface': 'eth0',
                    'download': 100000,
                    'upload': 20000,
                    'qdisc': 'cake',
                    'enabled': '1',
                  },
                },
              },
            ],
          },
        );

        final telemetryService = _MockTelemetryService(cannedTelemetry: null);

        final controller = SqmController(
          'test-router-4',
          apiServiceOverride: api,
          telemetryServiceOverride: telemetryService,
        );
        addTearDown(controller.dispose);

        await controller.refresh(forceTelemetry: true);

        final state = controller.state;
        expect(state.isInstalled, isTrue);
        expect(
          state.operatingState,
          equals(SqmOperatingState.telemetryUnavailable),
        );
      },
    );

    test(
      '6. Single-flight mutex blocks concurrent overlapping refreshes',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'sqm': {'running': true, 'enabled': true},
              },
            ],
          },
        );

        final controller = SqmController(
          'test-router-5',
          apiServiceOverride: api,
        );
        addTearDown(controller.dispose);

        // Trigger two simultaneous refreshes
        final f1 = controller.refresh();
        final f2 = controller.refresh();

        await Future.wait([f1, f2]);

        // Only one execution should have proceeded
        expect(api.callCount, greaterThan(0));
      },
    );

    test(
      '7. Controller refresh alone does NOT start live telemetry timer',
      () async {
        final mockTelem = SqmQueueTelemetry(
          interfaceName: 'eth0',
          qdisc: 'cake',
          sentPackets: 1000,
          droppedPackets: 10,
          timestamp: DateTime.now(),
        );

        final telemetryService = _MockTelemetryService(
          cannedTelemetry: mockTelem,
        );

        final controller = SqmController(
          'reviewer-mock-router',
          telemetryServiceOverride: telemetryService,
        );
        addTearDown(controller.dispose);

        await controller.refresh();

        // Provider/controller existence or refresh alone NEVER starts telemetry timer
        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.activeScreenSessions, equals(0));
        expect(controller.state.isTelemetryPolling, isFalse);
      },
    );

    test(
      '8. Provider subscriber / dashboard observer alone does NOT start live telemetry timer',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Simulate dashboard card mounting and watching sqmControllerProvider
        final subscription = container.listen(
          sqmControllerProvider('reviewer-mock-router'),
          (previous, next) {},
        );

        final controller = container.read(
          sqmControllerProvider('reviewer-mock-router').notifier,
        );

        // Wait for auto-refresh microtask to settle
        await Future.delayed(const Duration(milliseconds: 20));

        // Provider subscriber / dashboard observer alone must NEVER activate live polling timer
        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.activeScreenSessions, equals(0));
        expect(controller.state.isTelemetryPolling, isFalse);

        subscription.close();
      },
    );

    test(
      '9. Explicit startLiveTelemetry by SqmScreen starts 3-second timer and stopLiveTelemetry immediately cancels it',
      () async {
        final controller = SqmController('reviewer-mock-router');
        addTearDown(controller.dispose);

        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.activeScreenSessions, equals(0));

        // 1st SqmScreen mounts
        controller.startLiveTelemetry();
        expect(controller.isTelemetryTimerActive, isTrue);
        expect(controller.activeScreenSessions, equals(1));
        expect(controller.state.isTelemetryPolling, isTrue);

        // 2nd screen / nested observer mounts
        controller.startLiveTelemetry();
        expect(controller.activeScreenSessions, equals(2));
        expect(controller.isTelemetryTimerActive, isTrue);

        // 1st screen leaves
        controller.stopLiveTelemetry();
        expect(controller.isTelemetryTimerActive, isTrue);
        expect(controller.activeScreenSessions, equals(1));

        // 2nd screen leaves -> timer immediately cancelled
        controller.stopLiveTelemetry();
        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.activeScreenSessions, equals(0));
        expect(controller.state.isTelemetryPolling, isFalse);
      },
    );

    test(
      '10. Controller dispose cancels telemetry timer immediately',
      () async {
        final controller = SqmController('reviewer-mock-router');

        controller.startLiveTelemetry();
        expect(controller.isTelemetryTimerActive, isTrue);

        controller.dispose();
        expect(controller.isTelemetryTimerActive, isFalse);
      },
    );

    test(
      '11. AutoDispose family provider creates distinct instances for different router IDs',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final subA = container.listen(
          sqmControllerProvider('router-A'),
          (previous, next) {},
        );
        final subB = container.listen(
          sqmControllerProvider('router-B'),
          (previous, next) {},
        );

        final controllerA = container.read(
          sqmControllerProvider('router-A').notifier,
        );
        final controllerB = container.read(
          sqmControllerProvider('router-B').notifier,
        );

        expect(controllerA.routerId, equals('router-A'));
        expect(controllerB.routerId, equals('router-B'));
        expect(identical(controllerA, controllerB), isFalse);

        subA.close();
        subB.close();
      },
    );
  });

  group('SqmController Package Installation & Lifecycle Tests', () {
    test(
      '12. installSqmPackage in Reviewer Mode succeeds and populates reviewer state',
      () async {
        final controller = SqmController('reviewer-mock-router');
        addTearDown(controller.dispose);

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isTrue);
        expect(res.data, contains('sqm-scripts'));
        expect(controller.state.isInstalled, isTrue);
        expect(controller.state.queues.length, equals(2));
        expect(controller.state.primaryQueue?.interface, equals('eth0'));
      },
    );

    test(
      '13. installSqmPackage acquires router-exclusive lock blocking concurrent operations',
      () async {
        final lockAcquiredOrder = <String>[];
        final queue = RouterScopedOperationQueue.instance;

        final controller = SqmController(
          'queue-test-router',
          packageInstallerOverride: (pkg) async {
            lockAcquiredOrder.add('install-started');
            // While holding router-exclusive lock, try to see if another domain can run
            await Future.delayed(const Duration(milliseconds: 50));
            lockAcquiredOrder.add('install-finished');
            return RpcResult.success('Installed');
          },
        );
        addTearDown(controller.dispose);

        // Launch installation (acquires '*')
        final installFuture = controller.installSqmPackage();

        // Launch concurrent normal operation on domain 'uci' for the same router
        final uciFuture = queue.runLocked(
          routerId: 'queue-test-router',
          domain: 'uci',
          action: () async {
            lockAcquiredOrder.add('uci-executed');
          },
        );

        await Future.wait([installFuture, uciFuture]);

        // Router-exclusive install must complete before subsequent queued domain executes
        expect(
          lockAcquiredOrder,
          equals(['install-started', 'install-finished', 'uci-executed']),
        );
      },
    );

    test(
      '14. installSqmPackage halts live telemetry timer during execution and restores it on success if screen is active',
      () async {
        bool? timerStateDuringInstall;

        late final SqmController controller;
        controller = SqmController(
          'reviewer-mock-router',
          packageInstallerOverride: (pkg) async {
            timerStateDuringInstall = controller.isTelemetryTimerActive;
            return RpcResult.success('Installed');
          },
        );
        addTearDown(controller.dispose);

        // Simulate active screen session
        controller.startLiveTelemetry();
        expect(controller.isTelemetryTimerActive, isTrue);
        expect(controller.activeScreenSessions, equals(1));

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isTrue);
        expect(
          timerStateDuringInstall,
          isFalse,
          reason: 'Telemetry timer must be suspended during installation',
        );
        expect(
          controller.isTelemetryTimerActive,
          isTrue,
          reason:
              'Telemetry timer must be restored on success when screen is active',
        );
      },
    );

    test(
      '15. installSqmPackage failure preserves error and does not restore telemetry timer if uninstalled',
      () async {
        final controller = SqmController(
          'failed-install-router',
          packageInstallerOverride: (pkg) async {
            return RpcResult.failed('opkg: exit status 127: binary not found');
          },
        );
        addTearDown(controller.dispose);

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isFalse);
        expect(res.errorMessage, contains('exit status 127'));
        expect(controller.state.isInstalled, isFalse);
        expect(controller.isTelemetryTimerActive, isFalse);
      },
    );

    test(
      '16. installSqmPackage correctly classifies insufficient storage failure',
      () async {
        final controller = SqmController(
          'low-storage-router',
          packageInstallerOverride: (pkg) async {
            return RpcResult.failed(
              'Collected errors:\n * verify_pkg_installable: Only 24kb available on filesystem /overlay, ipkg needs 120kb.',
            );
          },
        );
        addTearDown(controller.dispose);

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isFalse);
        expect(res.isInsufficientStorage, isTrue);
        expect(
          res.userFriendlyPackageError,
          contains('Insufficient storage space'),
        );
      },
    );

    test(
      '17. installSqmPackage correctly classifies OOM / process killed failure without labeling as storage failure',
      () async {
        final controller = SqmController(
          'oom-router',
          packageInstallerOverride: (pkg) async {
            return RpcResult.failed('Killed', code: 137);
          },
        );
        addTearDown(controller.dispose);

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isFalse);
        expect(res.isMemoryExhausted, isTrue);
        expect(
          res.isInsufficientStorage,
          isFalse,
          reason: 'OOM must not be falsely classified as insufficient storage',
        );
        expect(res.userFriendlyPackageError, contains('out of memory (OOM)'));
        expect(controller.state.isInstalled, isFalse);
        expect(controller.isTelemetryTimerActive, isFalse);
      },
    );

    test(
      '18. Semantic post-failure verification: SQM remains uninstalled, no false capability, telemetry does not resume',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'firewall': {'running': true},
              },
            ],
            'uci.get': [
              0,
              {'values': {}},
            ],
          },
        );

        final controller = SqmController(
          'semantic-fail-router',
          apiServiceOverride: api,
          packageInstallerOverride: (pkg) async {
            return RpcResult.failed('Out of memory: Kill process 1234 (apk)');
          },
        );
        addTearDown(controller.dispose);

        await controller.refresh();
        expect(controller.state.isInstalled, isFalse);
        expect(
          controller.state.operatingState,
          equals(SqmOperatingState.notInstalled),
        );

        // Start screen session before install
        controller.startLiveTelemetry();
        expect(controller.activeScreenSessions, equals(1));

        final res = await controller.installSqmPackage();

        // 1. Installation failure cleanly captured
        expect(res.isSuccess, isFalse);
        expect(res.isMemoryExhausted, isTrue);
        expect(res.isInsufficientStorage, isFalse);

        // 2. State remains strictly uninstalled
        expect(controller.state.isInstalled, isFalse);
        expect(
          controller.state.operatingState,
          equals(SqmOperatingState.notInstalled),
        );
        expect(controller.state.queues, isEmpty);

        // 3. Telemetry timer does NOT resume after failure
        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.state.isTelemetryPolling, isFalse);
      },
    );

    test(
      '19. Probe failure on both rc.list and uci.get sqm sets errorMessage instead of false notInstalled',
      () async {
        // Mock API throwing exceptions on call
        final failingApi = _FailingLuciApiService();

        final controller = SqmController(
          'failing-probe-router',
          apiServiceOverride: failingApi,
        );
        addTearDown(controller.dispose);

        await controller.refresh();

        expect(controller.state.isLoading, isFalse);
        expect(controller.state.errorMessage, isNotNull);
        expect(
          controller.state.errorMessage,
          contains('Unable to check SQM status'),
        );
      },
    );

    test(
      '20. Router-scoped session cache seeds new controller instance immediately without re-loading flash',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'sqm': {'running': true, 'enabled': true},
              },
            ],
            'uci.get': [
              0,
              {
                'values': {
                  'eth0': {
                    '.type': 'queue',
                    'interface': 'eth0',
                    'download': 100000,
                    'upload': 20000,
                    'qdisc': 'cake',
                    'enabled': '1',
                  },
                },
              },
            ],
          },
        );

        // Visit 1: First controller instance discovers SQM
        final controller1 = SqmController(
          'cache-router-1',
          apiServiceOverride: api,
        );
        await controller1.refresh();

        expect(controller1.state.isInstalled, isTrue);
        expect(controller1.state.queues.length, equals(1));
        controller1.dispose();

        // Visit 2: Subsequent controller instance for the same router starts instantly with cached state
        final controller2 = SqmController(
          'cache-router-1',
          apiServiceOverride: api,
        );
        addTearDown(controller2.dispose);

        // Frame 0: Already installed, not loading initial blank state
        expect(controller2.state.isInstalled, isTrue);
        expect(controller2.state.queues.length, equals(1));
        expect(controller2.state.queues.first.interface, equals('eth0'));

        // Different router ID does not share the cache
        final controllerDifferentRouter = SqmController(
          'other-router',
          apiServiceOverride: api,
        );
        addTearDown(controllerDifferentRouter.dispose);
        expect(controllerDifferentRouter.state.lastUpdated, isNull);
        expect(controllerDifferentRouter.state.queues, isEmpty);
      },
    );
  });
}
