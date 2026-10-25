// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/diagnostics/controllers/speed_test_controller.dart';
import 'package:yala/modules/diagnostics/models/speed_test_models.dart';
import 'package:yala/modules/diagnostics/services/speed_test_service.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';

class _FakeSpeedTestService implements ISpeedTestService {
  final StreamController<SpeedTestProgress> _controller =
      StreamController<SpeedTestProgress>.broadcast();
  bool isCancelled = false;
  bool shouldFail = false;
  bool failUploadOnly = false;
  int runCount = 0;

  @override
  Stream<SpeedTestProgress> get progressStream => _controller.stream;

  @override
  void cancel() {
    isCancelled = true;
    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.cancelled,
        statusMessage: 'Cancelled',
      ),
    );
  }

  @override
  Future<String> detectTransportType() async => 'Wi-Fi';

  @override
  Future<SpeedTestResult> runRouterSpeedTest({
    required IApiService api,
    required String routerIp,
    required String sysauth,
    bool useHttps = false,
    String? wanInterface,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return runTest();
  }

  @override
  Future<SpeedTestResult> runTest({
    int downloadByteTarget = 15000000,
    int uploadByteTarget = 4000000,
    int latencyProbes = 5,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    runCount++;
    isCancelled = false;

    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.measuringLatency,
        currentLatencyMs: 12.5,
        currentJitterMs: 1.2,
      ),
    );

    if (shouldFail) {
      _controller.add(
        const SpeedTestProgress(
          stage: SpeedTestStage.failed,
          statusMessage: 'Server unreachable (500)',
        ),
      );
      return SpeedTestResult(
        stage: SpeedTestStage.failed,
        timestamp: DateTime.now(),
        errorMessage: 'Server unreachable (500)',
      );
    }

    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.measuringDownload,
        currentSpeedMbps: 85.4,
        progressPercent: 0.5,
      ),
    );

    if (failUploadOnly) {
      return SpeedTestResult(
        downloadSpeedMbps: 85.4,
        idleLatencyMs: 12.5,
        jitterMs: 1.2,
        stage: SpeedTestStage.failed,
        timestamp: DateTime.now(),
        errorMessage: 'Upload failed: timeout',
      );
    }

    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.measuringUpload,
        currentSpeedMbps: 42.1,
        progressPercent: 0.8,
      ),
    );

    final res = SpeedTestResult(
      downloadSpeedMbps: 85.4,
      uploadSpeedMbps: 42.1,
      idleLatencyMs: 12.5,
      jitterMs: 1.2,
      loadedLatencyMs: 18.3,
      connectionType: 'Wi-Fi',
      vantagePoint: 'Device Internet Speed Test',
      serverName: 'Cloudflare Anycast (speed.cloudflare.com)',
      timestamp: DateTime.now(),
      downloadBytes: downloadByteTarget,
      uploadBytes: uploadByteTarget,
      downloadDurationMs: 1400,
      uploadDurationMs: 760,
      latencySamples: const [12.0, 13.0, 12.5],
      stage: SpeedTestStage.completed,
    );

    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.completed,
        progressPercent: 1.0,
      ),
    );

    return res;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpeedTestService Math & Formula Tests', () {
    test(
      'calculateThroughputMbps converts bytes to decimal Mbps accurately',
      () {
        // 12,500,000 bytes = 100,000,000 bits.
        // In 1 second: 100,000,000 / 1,000,000 = 100.0 Mbps
        final mbps = SpeedTestService.calculateThroughputMbps(12500000, 1.0);
        expect(mbps, equals(100.0));

        // In 2 seconds: 50.0 Mbps
        final mbps2 = SpeedTestService.calculateThroughputMbps(12500000, 2.0);
        expect(mbps2, equals(50.0));

        // 0 or negative duration returns 0.0
        expect(
          SpeedTestService.calculateThroughputMbps(12500000, 0.0),
          equals(0.0),
        );
        expect(
          SpeedTestService.calculateThroughputMbps(12500000, -1.0),
          equals(0.0),
        );
      },
    );

    test(
      'calculateMedian computes correct median for odd and even length samples',
      () {
        expect(SpeedTestService.calculateMedian([]), equals(0.0));

        // Single item
        expect(SpeedTestService.calculateMedian([15.0]), equals(15.0));

        // Odd length sorted
        expect(
          SpeedTestService.calculateMedian([10.0, 15.0, 20.0]),
          equals(15.0),
        );

        // Even length sorted: average of middle two
        expect(
          SpeedTestService.calculateMedian([10.0, 14.0, 16.0, 20.0]),
          equals(15.0),
        );
      },
    );

    test(
      'calculateJitter computes RFC mean absolute difference between consecutive samples',
      () {
        // Less than 2 samples: jitter 0.0
        expect(SpeedTestService.calculateJitter([]), equals(0.0));
        expect(SpeedTestService.calculateJitter([10.0]), equals(0.0));

        // Samples: [10.0, 12.0, 11.0, 14.0]
        // Diffs: |12 - 10| = 2.0, |11 - 12| = 1.0, |14 - 11| = 3.0
        // Sum = 6.0, Count = 3 -> Jitter = 2.0 ms
        final jitter = SpeedTestService.calculateJitter([
          10.0,
          12.0,
          11.0,
          14.0,
        ]);
        expect(jitter, equals(2.0));
      },
    );

    test(
      'calculatePercentile computes accurate percentile with linear interpolation',
      () {
        expect(SpeedTestService.calculatePercentile([], 0.90), equals(0.0));
        expect(
          SpeedTestService.calculatePercentile([100.0], 0.90),
          equals(100.0),
        );

        // [100.0, 200.0, 250.0, 280.0]
        // 90th percentile rank = (4 - 1) * 0.9 = 2.7 -> 250*0.3 + 280*0.7 = 75 + 196 = 271.0
        final p90 = SpeedTestService.calculatePercentile([
          100.0,
          200.0,
          250.0,
          280.0,
        ], 0.90);
        expect(p90, closeTo(271.0, 0.001));

        // 50th percentile matches median
        final p50 = SpeedTestService.calculatePercentile([
          10.0,
          20.0,
          30.0,
        ], 0.50);
        expect(p50, equals(20.0));
      },
    );
  });

  group('SpeedTestResult Model Tests', () {
    test('JSON serialization roundtrip preserves all metrics', () {
      final now = DateTime.now();
      final original = SpeedTestResult(
        downloadSpeedMbps: 124.5,
        uploadSpeedMbps: 58.2,
        idleLatencyMs: 14.3,
        jitterMs: 1.8,
        loadedLatencyMs: 22.1,
        packetLossPercent: null, // Validly omitted
        connectionType: 'Wi-Fi',
        vantagePoint: 'Device Internet Speed Test',
        serverName: 'Cloudflare Anycast (speed.cloudflare.com)',
        timestamp: now,
        downloadBytes: 15000000,
        uploadBytes: 4000000,
        downloadDurationMs: 963,
        uploadDurationMs: 550,
        latencySamples: const [13.5, 14.3, 15.1],
        stage: SpeedTestStage.completed,
      );

      final json = original.toJson();
      final parsed = SpeedTestResult.fromJson(json);

      expect(parsed.downloadSpeedMbps, equals(124.5));
      expect(parsed.uploadSpeedMbps, equals(58.2));
      expect(parsed.idleLatencyMs, equals(14.3));
      expect(parsed.jitterMs, equals(1.8));
      expect(parsed.loadedLatencyMs, equals(22.1));
      expect(parsed.packetLossPercent, isNull);
      expect(parsed.connectionType, equals('Wi-Fi'));
      expect(parsed.vantagePoint, equals('Device Internet Speed Test'));
      expect(parsed.isSuccess, isTrue);
    });

    test('Failed result preserves partial measurements and reports error', () {
      final failed = SpeedTestResult(
        downloadSpeedMbps: 85.0,
        uploadSpeedMbps: null, // Upload failed
        idleLatencyMs: 12.0,
        stage: SpeedTestStage.failed,
        errorMessage: 'Upload failed: server 503',
        timestamp: DateTime.now(),
      );

      expect(failed.isSuccess, isFalse);
      expect(failed.downloadSpeedMbps, equals(85.0));
      expect(failed.uploadSpeedMbps, isNull);
      expect(failed.errorMessage, contains('server 503'));
    });
  });

  group('SpeedTestController Tests', () {
    test('startTest executes test and emits progress events', () async {
      final fake = _FakeSpeedTestService();
      final controller = SpeedTestController(fake);

      expect(controller.state.isRunning, isFalse);
      expect(controller.state.result, isNull);

      final future = controller.startTest();
      expect(controller.state.isRunning, isTrue);

      await future;

      expect(controller.state.isRunning, isFalse);
      expect(controller.state.result, isNotNull);
      expect(controller.state.result!.downloadSpeedMbps, equals(85.4));
      expect(controller.state.result!.uploadSpeedMbps, equals(42.1));
      expect(
        controller.state.result!.vantagePoint,
        equals('Device Internet Speed Test'),
      );
      expect(controller.state.result!.isSuccess, isTrue);
      expect(fake.runCount, equals(1));
    });

    test(
      'Single-flight lock prevents duplicate concurrent test runs',
      () async {
        final fake = _FakeSpeedTestService();
        final controller = SpeedTestController(fake);

        final f1 = controller.startTest();
        // Concurrent second invocation
        final f2 = controller.startTest();

        await Future.wait([f1, f2]);
        // Only 1 execution should have taken place
        expect(fake.runCount, equals(1));
      },
    );

    test('Cancellation stops test and marks state correctly', () async {
      final fake = _FakeSpeedTestService();
      final controller = SpeedTestController(fake);

      final future = controller.startTest();
      controller.cancelTest();

      await future;
      expect(fake.isCancelled, isTrue);
      expect(controller.state.isRunning, isFalse);
    });

    test(
      'Handles upload failure while preserving completed download',
      () async {
        final fake = _FakeSpeedTestService()..failUploadOnly = true;
        final controller = SpeedTestController(fake);

        await controller.startTest();

        expect(controller.state.isRunning, isFalse);
        expect(controller.state.result?.downloadSpeedMbps, equals(85.4));
        expect(controller.state.result?.uploadSpeedMbps, isNull);
        expect(
          controller.state.result?.errorMessage,
          contains('Upload failed'),
        );
      },
    );
  });
}
