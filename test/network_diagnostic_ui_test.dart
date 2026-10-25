// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/modules/core/luci_module_registry.dart';
import 'package:yala/modules/diagnostics/diagnostics_module.dart';
import 'package:yala/modules/diagnostics/screens/diagnostics_screen.dart';
import 'package:yala/modules/network_diagnostic/controllers/network_diagnostic_controller.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_capabilities.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_confidence.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_evidence.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_scope.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_status.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_test_result.dart';
import 'package:yala/modules/network_diagnostic/models/network_diagnostic_report.dart';
import 'package:yala/modules/network_diagnostic/models/root_cause_finding.dart';
import 'package:yala/modules/network_diagnostic/screens/network_diagnostic_screen.dart';
import 'package:yala/screens/more_screen.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          return null;
        });

    // Ensure built-in modules are registered
    LuciModuleRegistry.instance.registerModule(DiagnosticsModule());
  });

  setUp(() {
    final appState = AppState.instance;
    appState.setApiServiceForTesting(MockApiService());
    appState.setDashboardTabActive(false);
    appState.cancelThroughputTimer();
  });

  tearDown(() {
    AppState.instance.cancelThroughputTimer();
  });

  group('NetworkDiagnosticScreen UI & Widget Tests', () {
    testWidgets('Renders initial ready state with Run Diagnostics button', (
      tester,
    ) async {
      final appState = AppState.instance;
      appState.setApiServiceForTesting(MockApiService());
      appState.setDashboardTabActive(false);
      appState.cancelThroughputTimer();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(home: NetworkDiagnosticScreen()),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Network Diagnostic'), findsOneWidget);
      expect(find.text('Network Diagnostic Ready'), findsOneWidget);
      expect(find.text('Run Diagnostics'), findsOneWidget);
    });

    testWidgets('Renders localized ready state in German (de)', (tester) async {
      final appState = AppState.instance;
      appState.setApiServiceForTesting(MockApiService());
      appState.setDashboardTabActive(false);
      appState.cancelThroughputTimer();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('de'),
            home: NetworkDiagnosticScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Netzwerkdiagnose'), findsOneWidget);
      expect(find.text('Netzwerkdiagnose bereit'), findsOneWidget);
      expect(find.text('Diagnose starten'), findsOneWidget);
    });

    testWidgets('Renders localized ready state in Spanish (es)', (
      tester,
    ) async {
      final appState = AppState.instance;
      appState.setApiServiceForTesting(MockApiService());
      appState.setDashboardTabActive(false);
      appState.cancelThroughputTimer();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: NetworkDiagnosticScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Diagnóstico de red'), findsOneWidget);
      expect(find.text('Diagnóstico de red listo'), findsOneWidget);
      expect(find.text('Ejecutar diagnóstico'), findsOneWidget);
    });

    testWidgets(
      'Renders overall health and test breakdown when report is present',
      (tester) async {
        final mockTestResults = [
          DiagnosticTestResult(
            id: 'router_management_api',
            title: 'Router Management & API Reachability',
            scope: DiagnosticScope.managementApi,
            status: DiagnosticStatus.healthy,
            confidence: DiagnosticConfidence.high,
            explanation: 'Connection active',
            whyItMatters: 'API access required',
            startedAt: DateTime.now(),
          ),
          DiagnosticTestResult(
            id: 'dns_resolution',
            title: 'DNS Resolution Checks',
            scope: DiagnosticScope.dns,
            status: DiagnosticStatus.failureConfirmed,
            confidence: DiagnosticConfidence.high,
            explanation: 'DNS failed',
            whyItMatters: 'Resolves domains',
            recommendedStep: 'Check DNS upstream servers',
            evidence: const DiagnosticEvidence(facts: ['openwrt.org failed']),
            startedAt: DateTime.now(),
          ),
        ];

        final mockFindings = [
          const RootCauseFinding(
            id: 'dns_resolution_failure_direct_ip_working',
            title: 'DNS Resolution Failure (Direct Internet IP is Working)',
            description: 'Websites fail by name, but numerical IPs connect.',
            status: DiagnosticStatus.failureConfirmed,
            confidence: DiagnosticConfidence.high,
            supportingEvidence: ['openwrt.org failed'],
            recommendedSteps: ['Check DNS in DHCP & DNS settings'],
            actionType: FindingActionType.userIntervention,
            primaryScope: DiagnosticScope.dns,
          ),
        ];

        final mockReport = NetworkDiagnosticReport(
          sessionId: 'test_session',
          timestamp: DateTime.now(),
          routerScope: '192.168.1.1',
          overallStatus: DiagnosticStatus.failureConfirmed,
          overallSummary:
              'DNS resolution failed, but direct IPv4 connectivity succeeded.',
          testResults: mockTestResults,
          findings: mockFindings,
          capabilities: const DiagnosticCapabilities(hasManagementApi: true),
          unverifiedAreas: ['Client Wi-Fi latency'],
        );

        final appState = AppState.instance;
        appState.setApiServiceForTesting(MockApiService());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith((ref) => appState),
              networkDiagnosticControllerProvider.overrideWith(
                (ref) => _StubController(
                  NetworkDiagnosticState(
                    report: mockReport,
                    liveResults: mockTestResults,
                  ),
                ),
              ),
            ],
            child: const MaterialApp(home: NetworkDiagnosticScreen()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(find.text('Connectivity Issue Detected'), findsOneWidget);
        expect(
          find.text(
            'DNS resolution failed, but direct IPv4 connectivity succeeded.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('DNS Resolution Failure (Direct Internet IP is Working)'),
          findsOneWidget,
        );
        expect(
          find.text('Router Management & API Reachability'),
          findsOneWidget,
        );
        expect(find.text('DNS Resolution Checks'), findsOneWidget);
        expect(
          find.text('Diagnostic Scope & Unverified Domains'),
          findsOneWidget,
        );
      },
    );
  });

  group('More Tab Integration — Network Diagnostics', () {
    testWidgets(
      'More tab displays only "Network Diagnostics" (no separate duplicate "Network Diagnostic") and navigates to DiagnosticsScreen with integrated root cause diagnostics',
      (tester) async {
        final appState = AppState.instance;
        appState.setApiServiceForTesting(MockApiService());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const MaterialApp(home: MoreScreen()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Verify that "Network Diagnostics" tile is present in the More tab!
        expect(find.text('Network Diagnostics'), findsOneWidget);

        // Verify that there is NO duplicate "Network Diagnostic" entry!
        expect(
          find.widgetWithText(ListTile, 'Network Diagnostic'),
          findsNothing,
        );

        // Tap on "Network Diagnostics" tile
        await tester.tap(find.text('Network Diagnostics'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Verify that DiagnosticsScreen is pushed and visible!
        expect(find.byType(DiagnosticsScreen), findsOneWidget);

        // Verify that the Reachability Hero Card contains the integrated action button
        expect(
          find.text('“Why Is My Internet Broken?” Diagnostic'),
          findsOneWidget,
        );

        // Verify that the "Health & Diagnostic" tab is present and selected
        expect(find.text('Health & Diagnostic'), findsOneWidget);

        // Verify that NetworkDiagnosticView is active as Tab 0 child
        expect(find.byType(NetworkDiagnosticView), findsOneWidget);
        expect(find.text('Run Diagnostics'), findsOneWidget);
      },
    );

    testWidgets(
      'DiagnosticsScreen displays localized German tab and hero card button',
      (tester) async {
        final appState = AppState.instance;
        appState.setApiServiceForTesting(MockApiService());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const MaterialApp(
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('de'),
              home: DiagnosticsScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(find.text('Zustand & Diagnose'), findsOneWidget);
        expect(
          find.text('Diagnose „Warum ist mein Internet gestört?“'),
          findsOneWidget,
        );
      },
    );
  });
}

class _StubController extends NetworkDiagnosticController {
  _StubController(NetworkDiagnosticState initial) : super(_DummyRef()) {
    state = initial;
  }
}

class _DummyRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
