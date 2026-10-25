// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/modules/diagnostics/controllers/speed_test_controller.dart';
import 'package:yala/modules/diagnostics/models/speed_test_models.dart';
import 'package:yala/modules/diagnostics/screens/diagnostics_screen.dart';
import 'package:yala/modules/diagnostics/services/speed_test_service.dart';
import 'package:yala/modules/diagnostics/widgets/speed_test_view.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/state/app_state.dart';

class _MockSpeedTestService implements ISpeedTestService {
  final StreamController<SpeedTestProgress> _controller =
      StreamController<SpeedTestProgress>.broadcast();
  bool isCancelled = false;

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
  Future<String> detectTransportType() async => 'Router WAN';

  @override
  Future<SpeedTestResult> runTest({
    int downloadByteTarget = 15000000,
    int uploadByteTarget = 4000000,
    int latencyProbes = 5,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.measuringDownload,
        currentSpeedMbps: 92.4,
        progressPercent: 0.5,
        statusMessage: 'Downloading...',
      ),
    );

    return SpeedTestResult(
      downloadSpeedMbps: 92.4,
      uploadSpeedMbps: 45.1,
      idleLatencyMs: 14.2,
      jitterMs: 1.5,
      loadedLatencyMs: 20.8,
      connectionType: 'Router WAN (wan)',
      vantagePoint: 'Router Internet Speed Test (WAN)',
      serverName: 'Cloudflare Anycast (speed.cloudflare.com)',
      timestamp: DateTime.now(),
      downloadBytes: downloadByteTarget,
      uploadBytes: uploadByteTarget,
      downloadDurationMs: 1300,
      uploadDurationMs: 710,
      stage: SpeedTestStage.completed,
    );
  }

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget({required Widget child, ISpeedTestService? service}) {
    final appState = AppState.instance;
    appState.setApiServiceForTesting(MockApiService());

    return ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => appState),
        if (service != null)
          speedTestServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: child),
      ),
    );
  }

  group('SpeedTestView Widget Tests', () {
    testWidgets('Renders idle state without displaying false zero speed', (
      tester,
    ) async {
      final mockService = _MockSpeedTestService();
      await tester.pumpWidget(
        buildTestWidget(child: const SpeedTestView(), service: mockService),
      );
      await tester.pumpAndSettle();

      expect(find.text('Router Internet Speed Test (WAN)'), findsOneWidget);
      expect(
        find.textContaining(
          'Vantage Point: Direct OpenWrt router WAN interface',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Endpoint: Cloudflare Anycast edge'),
        findsOneWidget,
      );
      expect(find.text('DOWNLOAD'), findsOneWidget);
      expect(find.text('UPLOAD'), findsOneWidget);
      expect(find.text('Start Router Speed Test'), findsOneWidget);

      // Verify that idle state shows '--' instead of misleading 0.0 Mbps
      expect(
        find.text('--'),
        findsNWidgets(4),
      ); // Download, Upload, Idle Ping, Jitter
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets(
      'Tapping Start Router Speed Test executes and displays measured results',
      (tester) async {
        final mockService = _MockSpeedTestService();
        await tester.pumpWidget(
          buildTestWidget(child: const SpeedTestView(), service: mockService),
        );
        await tester.pumpAndSettle();

        // Tap Start Router Speed Test
        await tester.tap(find.text('Start Router Speed Test'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify results display
        expect(find.text('92.4'), findsOneWidget);
        expect(find.text('45.1'), findsOneWidget);
        expect(find.text('14.2 ms'), findsOneWidget);
        expect(find.text('1.5 ms'), findsOneWidget);
        expect(find.text('Run Router Speed Test Again'), findsOneWidget);
      },
    );

    testWidgets('Integrated in DiagnosticsScreen TabBar and can be selected', (
      tester,
    ) async {
      final mockService = _MockSpeedTestService();
      await tester.pumpWidget(
        buildTestWidget(child: const DiagnosticsScreen(), service: mockService),
      );
      await tester.pumpAndSettle();

      // Tab 'Speed Test' exists
      final speedTab = find.text('Speed Test');
      expect(speedTab, findsOneWidget);

      // Tap 'Speed Test' Tab
      await tester.tap(speedTab);
      await tester.pumpAndSettle();

      // Verify SpeedTestView is active
      expect(find.byType(SpeedTestView), findsOneWidget);
      expect(find.text('Router Internet Speed Test (WAN)'), findsOneWidget);
    });
  });
}
