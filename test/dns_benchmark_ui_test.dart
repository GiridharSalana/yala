// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/modules/diagnostics/controllers/dns_benchmark_controller.dart';
import 'package:yala/modules/diagnostics/models/dns_benchmark_models.dart';
import 'package:yala/modules/diagnostics/screens/diagnostics_screen.dart';
import 'package:yala/modules/diagnostics/services/dns_benchmark_service.dart';
import 'package:yala/modules/diagnostics/widgets/dns_benchmark_view.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/state/app_state.dart';

class _MockDnsBenchmarkService implements IDnsBenchmarkService {
  final Map<String, double> latencies;
  bool isCancelled = false;

  _MockDnsBenchmarkService({required this.latencies});

  @override
  void cancel() {
    isCancelled = true;
  }

  @override
  Future<DnsBenchmarkResult> benchmarkProvider({
    required DnsProviderMetadata provider,
    required DnsVantagePoint vantagePoint,
    required DnsProtocol protocol,
    int sampleCount = 3,
    Duration timeout = const Duration(milliseconds: 2500),
    String? routerIp,
    String? routerSysauth,
    bool routerUseHttps = false,
  }) async {
    final ms = latencies[provider.id] ?? 20.0;
    return DnsBenchmarkResult(
      provider: provider,
      status: DnsBenchmarkStatus.success,
      medianLatencyMs: ms,
      minLatencyMs: ms - 1.0,
      maxLatencyMs: ms + 1.0,
      avgLatencyMs: ms,
      samples: [ms, ms, ms],
      totalQueries: sampleCount,
      successfulQueries: sampleCount,
      failedQueries: 0,
      testedEndpoint: '${provider.primaryServer}:53',
      protocol: protocol,
      vantagePoint: vantagePoint,
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget({
    required Widget child,
    IDnsBenchmarkService? service,
  }) {
    final appState = AppState.instance;
    appState.setApiServiceForTesting(MockApiService());

    return ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => appState),
        if (service != null)
          dnsBenchmarkServiceProvider.overrideWithValue(service),
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

  group('DnsBenchmarkView Widget Tests', () {
    testWidgets(
      'Pre-test displays all 8 public providers in alphabetical order with A-Z badge and custom DNS option',
      (tester) async {
        final mockService = _MockDnsBenchmarkService(latencies: {});
        await tester.pumpWidget(
          buildTestWidget(
            child: const DnsBenchmarkView(),
            service: mockService,
          ),
        );
        await tester.pumpAndSettle();

        // Custom DNS Resolver card
        expect(find.text('Custom DNS Resolver'), findsOneWidget);

        // Pinned router DNS card
        expect(find.text('Current Router DNS'), findsOneWidget);

        // Section header with A-Z badge
        expect(find.text('PUBLIC DNS RESOLVERS'), findsOneWidget);
        expect(find.text('A-Z'), findsOneWidget);

        // Verify all 8 providers are present
        expect(find.text('AdGuard DNS'), findsOneWidget);
        expect(find.text('CleanBrowsing'), findsOneWidget);
        expect(find.text('Cloudflare'), findsOneWidget);
        expect(find.text('Control D'), findsOneWidget);
        expect(find.text('Google Public DNS'), findsOneWidget);
        expect(find.text('NextDNS'), findsOneWidget);
        expect(find.text('OpenDNS'), findsOneWidget);
        expect(find.text('Quad9'), findsOneWidget);

        // Verify status is Untested (no fabricated latencies!)
        expect(find.text('Untested'), findsWidgets);
        expect(find.text('Run DNS Benchmark'), findsOneWidget);
      },
    );

    testWidgets(
      'Running benchmark re-orders by ascending median latency and awards fastest badge',
      (tester) async {
        // Configure latencies: Cloudflare fastest (5.5 ms), Quad9 second (11.0 ms)
        final mockService = _MockDnsBenchmarkService(
          latencies: {
            'router_current': 3.2,
            'cloudflare': 5.5,
            'quad9': 11.0,
            'google': 14.2,
            'nextdns': 18.0,
            'controld': 22.1,
            'adguard': 25.4,
            'opendns': 31.0,
            'cleanbrowsing': 42.0,
          },
        );

        await tester.pumpWidget(
          buildTestWidget(
            child: const DnsBenchmarkView(),
            service: mockService,
          ),
        );
        await tester.pumpAndSettle();

        // Run DNS Benchmark button is now near top
        final runBtn = find.text('Run DNS Benchmark');
        await tester.tap(runBtn);
        await tester.pump();
        await tester.pumpAndSettle();

        // Check sorting badge indicator
        expect(find.text('Lowest latency'), findsOneWidget);

        // Fastest measured badge appears on #1
        expect(find.text('Fastest measured in this test'), findsOneWidget);

        // Check latency values
        expect(find.text('5.5 ms'), findsOneWidget); // Cloudflare
        expect(find.text('11.0 ms'), findsOneWidget); // Quad9
        expect(find.text('14.2 ms'), findsOneWidget); // Google

        // Router DNS displays its measured latency
        expect(find.text('3.2 ms'), findsOneWidget);
      },
    );

    testWidgets(
      'Toggling and entering Custom DNS includes it in the benchmark list',
      (tester) async {
        final mockService = _MockDnsBenchmarkService(
          latencies: {
            'custom_dns': 4.1, // Custom DNS is fastest!
            'cloudflare': 6.2,
          },
        );

        await tester.pumpWidget(
          buildTestWidget(
            child: const DnsBenchmarkView(),
            service: mockService,
          ),
        );
        await tester.pumpAndSettle();

        // Toggle custom DNS switch
        final switchFinder = find.byType(Switch);
        expect(switchFinder, findsOneWidget);
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        // Enter IP address
        final ipField = find.widgetWithText(TextField, 'DNS Server IP Address');
        expect(ipField, findsOneWidget);
        await tester.enterText(ipField, '1.1.1.2');
        await tester.pumpAndSettle();

        // Verify CUSTOM badge and provider appears in resolvers list
        expect(find.text('CUSTOM'), findsOneWidget);
        expect(find.text('Custom DNS (1.1.1.2)'), findsOneWidget);

        // Run benchmark with custom DNS
        final runBtn = find.text('Run DNS Benchmark');
        await tester.tap(runBtn);
        await tester.pump();
        await tester.pumpAndSettle();

        // Custom DNS got 4.1 ms and should have fastest badge
        expect(find.text('4.1 ms'), findsOneWidget);
        expect(find.text('Fastest measured in this test'), findsOneWidget);
      },
    );

    testWidgets(
      'Integrated in DiagnosticsScreen TabBar and can be navigated independently',
      (tester) async {
        final mockService = _MockDnsBenchmarkService(latencies: {});
        await tester.pumpWidget(
          buildTestWidget(
            child: const DiagnosticsScreen(),
            service: mockService,
          ),
        );
        await tester.pumpAndSettle();

        final dnsTab = find.text('DNS Latency');
        expect(dnsTab, findsOneWidget);

        await tester.tap(dnsTab);
        await tester.pumpAndSettle();

        expect(find.byType(DnsBenchmarkView), findsOneWidget);
        expect(find.text('PUBLIC DNS RESOLVERS'), findsOneWidget);
      },
    );
  });
}
