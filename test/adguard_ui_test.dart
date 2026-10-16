// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/modules/adguard_home/controllers/adguard_controller.dart';
import 'package:yala/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/screens/adguard_home_screen.dart';
import 'package:yala/modules/adguard_home/utils/adguard_web_url_helper.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_credentials_dialog.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_custom_rules_dialog.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_dashboard_card.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_filtering_card.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_pause_dialog.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_process_card.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_profile_dialog.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_protection_card.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_service_card.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_stats_card.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_status_card.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_top_lists_card.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_topology_card.dart';
import 'package:yala/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/widgets/luci_loading_view.dart';

// ── Mock Services ─────────────────────────────────────────────────────────────

class UiTestMockAdGuardApiService implements IAdGuardApiService {
  @override
  final String routerId;

  @override
  String get instanceId => 'local_$routerId';

  AdGuardConnectionStatus testConnectionResult =
      AdGuardConnectionStatus.authenticated;

  @override
  Future<AdGuardConnectionStatus> testConnection({
    AdGuardCredentials? credentials,
  }) async =>
      testConnectionResult;

  AdGuardCredentials? activeCreds;
  AdGuardStatus? mockStatus;
  AdGuardStats? mockStats;
  AdGuardFilteringStatus? mockFiltering;
  bool isAuthRequiredState = false;
  Completer<void>? delayStatusCompleter;
  AdGuardApiResult<AdGuardStatus>? customStatusResult;

  int statusCallCount = 0;
  int setCredentialsCallCount = 0;

  UiTestMockAdGuardApiService({
    required this.routerId,
    this.mockStatus,
    this.mockStats,
    this.mockFiltering,
  }) {
    mockStatus ??= const AdGuardStatus(
      version: 'v0.107.52',
      running: true,
      protectionState: AdGuardProtectionState.enabled,
      dnsAddresses: ['192.168.1.1'],
      dnsPort: 53,
      httpPort: 3000,
    );

    mockStats ??= const AdGuardStats(
      numDnsQueries: 10000,
      numBlockedFiltering: 2000,
      numReplacedSafebrowsing: 5,
      numReplacedSafesearch: 0,
      numReplacedParental: 0,
      avgProcessingTime: 0.015,
      topQueriedDomains: [
        AdGuardTopItem(identifier: 'google.com', count: 500),
      ],
      topBlockedDomains: [
        AdGuardTopItem(identifier: 'adservice.google.com', count: 300),
      ],
      topClients: [
        AdGuardTopItem(identifier: '192.168.1.100', count: 800),
      ],
      dnsQueriesTrend: [100, 200],
      blockedFilteringTrend: [20, 40],
      blockRatePercentage: 20.0,
    );

    mockFiltering ??= const AdGuardFilteringStatus(
      enabled: true,
      filterLists: [],
      userRules: [],
      totalRulesCount: 50000,
    );
  }

  @override
  AdGuardCredentials? get activeCredentials => activeCreds;

  @override
  bool get isAuthenticated => !isAuthRequiredState;

  @override
  bool get isAuthRequired => isAuthRequiredState;

  @override
  void setCredentials(AdGuardCredentials? credentials) {
    setCredentialsCallCount++;
    activeCreds = credentials;
  }

  @override
  Future<AdGuardApiResult<AdGuardStatus>> getStatus({
    bool forceProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  }) async {
    statusCallCount++;
    if (delayStatusCompleter != null) {
      await delayStatusCompleter!.future;
    }
    if (customStatusResult != null) {
      return customStatusResult!;
    }
    if (isAuthRequiredState) {
      return AdGuardApiResult.authRequired();
    }
    return AdGuardApiResult.success(mockStatus!);
  }

  @override
  Future<AdGuardApiResult<AdGuardStats>> getStats({Duration? recent}) async {
    return AdGuardApiResult.success(mockStats!);
  }

  @override
  Future<AdGuardApiResult<AdGuardFilteringStatus>> getFilteringStatus() async {
    return AdGuardApiResult.success(mockFiltering!);
  }

  @override
  Future<AdGuardApiResult<bool>> setProtection({
    required bool enabled,
    Duration? duration,
  }) async {
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> setProtectionState(
    AdGuardProtectionState state, {
    Duration? pauseDuration,
  }) async {
    return AdGuardApiResult.success(true);
  }

  List<String>? lastSetUserRules;
  AdGuardApiResult<bool>? setUserRulesResult;

  @override
  Future<AdGuardApiResult<bool>> setUserRules(List<String> rules) async {
    lastSetUserRules = rules;
    return setUserRulesResult ?? AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<List<AdGuardClient>>> getClients() async {
    return AdGuardApiResult.success(const []);
  }

  @override
  Future<AdGuardApiResult<bool>> addClient(AdGuardClient client) async {
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> updateClient(String oldName, AdGuardClient client) async {
    return AdGuardApiResult.success(true);
  }

  List<String> mockUpstreamDns = const ['1.1.1.1', '8.8.8.8'];

  @override
  Future<AdGuardApiResult<List<String>>> getUpstreamDns() async {
    return AdGuardApiResult.success(mockUpstreamDns);
  }

  @override
  Future<AdGuardApiResult<bool>> addFilterList({
    required String name,
    required String url,
    required bool whitelist,
  }) async =>
      AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> setFilterList({
    required String url,
    required String name,
    required String newUrl,
    required bool enabled,
    required bool whitelist,
  }) async =>
      AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> removeFilterList({
    required String url,
    required bool whitelist,
  }) async =>
      AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> refreshFilterLists({bool? whitelist}) async =>
      AdGuardApiResult.success(true);
}

class UiTestFakeLuciApiService implements IApiService {
  final List<String> executedServiceActions = [];

  @override
  Future<bool> manageServiceAction(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String serviceName,
    required String action,
    BuildContext? context,
  }) async {
    executedServiceActions.add('$serviceName:$action');
    return true;
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
    if (object == 'luci' && method == 'getProcessList') {
      return {
        'result': [
          {
            'PID': '1660',
            'COMMAND': '/usr/bin/AdGuardHome -c /etc/adguardhome.yaml',
            '%CPU': '1.5',
            '%MEM': '3.2',
            'VSZ': '45056',
          }
        ]
      };
    }
    if (object == 'luci' && method == 'getInitList') {
      return {
        'result': {
          'adguardhome': {'enabled': true, 'running': true}
        }
      };
    }
    return {'result': []};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Widget Test App Helper ───────────────────────────────────────────────────

Widget buildTestApp({
  Key? key,
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    key: key,
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdGuard Home UI Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      AdGuardController.invalidateSessionCache();
    });

    // ── 15. IPv4/IPv6 Web UI URL Construction ──────────────────────────────
    test('15. IPv4/IPv6 Web UI URL construction handles formats and custom ports', () {
      // IPv4 HTTP
      expect(
        AdGuardWebUrlHelper.buildWebUrl(host: '192.168.1.1', port: 3000),
        equals('http://192.168.1.1:3000'),
      );
      // IPv4 HTTPS
      expect(
        AdGuardWebUrlHelper.buildWebUrl(
            host: '192.168.1.1', port: 3000, useHttps: true),
        equals('https://192.168.1.1:3000'),
      );
      // IPv6 standard (adds bracket notation)
      expect(
        AdGuardWebUrlHelper.buildWebUrl(host: '2001:db8::1', port: 3000),
        equals('http://[2001:db8::1]:3000'),
      );
      // IPv6 already bracketed (does not duplicate brackets)
      expect(
        AdGuardWebUrlHelper.buildWebUrl(host: '[2001:db8::1]', port: 3000),
        equals('http://[2001:db8::1]:3000'),
      );
      // Custom port
      expect(
        AdGuardWebUrlHelper.buildWebUrl(host: '10.0.0.1', port: 8080),
        equals('http://10.0.0.1:8080'),
      );
    });

    // ── 11. Reviewer Mode Browser Suppression ──────────────────────────────
    testWidgets(
      '11. Reviewer Mode suppresses browser launch and shows info notification',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('launch_button'),
                  onPressed: () async {
                    await AdGuardWebUrlHelper.launchWebInterface(
                      context: context,
                      isReviewerMode: true,
                      host: '192.168.1.1',
                      port: 3000,
                    );
                  },
                  child: const Text('Launch'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the launch button
        await tester.tap(find.byKey(const Key('launch_button')));
        await tester.pump();

        // Browser launch suppressed; localized notification shown
        expect(
          find.text('Web interface launch disabled in Reviewer Mode'),
          findsOneWidget,
        );
      },
    );

    // ── 2. Version / Status / DNS Listener / HTTP Port ─────────────────────
    testWidgets(
      '2. AdGuardStatusCard renders version, status, DNS listener, and HTTP port',
      (tester) async {
        const mockStatus = AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardStatusCard(
              status: mockStatus,
              routerHost: '192.168.1.1',
              isReviewerMode: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_status_version')), findsOneWidget);
        expect(find.text('v0.107.52'), findsOneWidget);
        expect(find.text('Running'), findsOneWidget);
        expect(find.text('192.168.1.1 : 53'), findsOneWidget);
        expect(find.text('3000'), findsOneWidget);
        expect(find.byKey(const Key('agh_open_web_ui_button')), findsOneWidget);
      },
    );

    // ── 3. Protection Card States (Enabled / Paused / Disabled) ─────────────
    testWidgets(
      '3. AdGuardProtectionCard renders enabled, paused, and disabled states',
      (tester) async {
        // State A: Enabled
        const enabledStatus = AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardProtectionCard(
              status: enabledStatus,
              isMutating: false,
              onSetProtection: ({required bool enabled, Duration? duration}) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Protection Enabled'), findsNothing);
        final Switch toggleSwitch =
            tester.widget(find.byKey(const Key('agh_protection_toggle_switch')));
        expect(toggleSwitch.value, isTrue);

        // State B: Paused with duration
        const pausedStatus = AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.paused,
          pauseDurationMs: 900000, // 15 mins
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardProtectionCard(
              status: pausedStatus,
              isMutating: false,
              onSetProtection: ({required bool enabled, Duration? duration}) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Protection Paused'), findsOneWidget);
        expect(find.byKey(const Key('agh_protection_pause_time')), findsOneWidget);
        expect(find.textContaining('15m 0s'), findsOneWidget);

        // State C: Disabled
        const disabledStatus = AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.disabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardProtectionCard(
              status: disabledStatus,
              isMutating: false,
              onSetProtection: ({required bool enabled, Duration? duration}) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Protection Disabled'), findsOneWidget);
        final Switch disabledSwitch =
            tester.widget(find.byKey(const Key('agh_protection_toggle_switch')));
        expect(disabledSwitch.value, isFalse);
      },
    );

    // ── 4. Pause Duration Presets & Custom Date/Time Option ────────────────
    testWidgets(
      '4. AdGuardPauseDialog presents preset durations and custom date/time option',
      (tester) async {
        Duration? selectedDuration;

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('open_pause_dialog'),
                  onPressed: () async {
                    selectedDuration = await AdGuardPauseDialog.show(context);
                  },
                  child: const Text('Pause'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_pause_dialog')));
        await tester.pumpAndSettle();

        // Verify presets exist
        expect(find.byKey(const Key('agh_pause_15m_option')), findsOneWidget);
        expect(find.byKey(const Key('agh_pause_30m_option')), findsOneWidget);
        expect(find.byKey(const Key('agh_pause_1h_option')), findsOneWidget);
        expect(find.byKey(const Key('agh_pause_24h_option')), findsOneWidget);
        expect(find.byKey(const Key('agh_pause_custom_option')), findsOneWidget);

        // Tap 30m preset
        await tester.tap(find.byKey(const Key('agh_pause_30m_option')));
        await tester.pumpAndSettle();

        expect(selectedDuration, equals(const Duration(minutes: 30)));
      },
    );

    // ── 5. Service Confirmation Dialogs and Actions ────────────────────────
    testWidgets(
      '5. AdGuardServiceCard requires confirmation before stopping or restarting',
      (tester) async {
        bool stopCalled = false;
        bool restartCalled = false;

        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardServiceCard(
              isRunning: true,
              isManageable: true,
              isManaging: false,
              onStart: () async => true,
              onStop: () async => stopCalled = true,
              onRestart: () async => restartCalled = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Stop -> shows confirmation dialog
        await tester.tap(find.byKey(const Key('agh_service_stop_button')));
        await tester.pumpAndSettle();

        expect(find.text('Stop AdGuard Home Service?'), findsOneWidget);
        // Cancel first
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(stopCalled, isFalse);

        // Tap Stop again -> Confirm
        await tester.tap(find.byKey(const Key('agh_service_stop_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(stopCalled, isTrue);

        // Tap Restart -> shows confirmation dialog
        await tester.tap(find.byKey(const Key('agh_service_restart_button')));
        await tester.pumpAndSettle();

        expect(find.text('Restart AdGuard Home Service?'), findsOneWidget);
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(restartCalled, isTrue);
      },
    );

    // ── 6. Estimated RAM Labeling (Zero Raw RSS Claims) ─────────────────────
    testWidgets(
      '6. AdGuardProcessCard labels memory strictly as Estimated RAM with tooltip',
      (tester) async {
        const mockTelemetry = AdGuardProcessTelemetry(
          pid: '1660',
          cpuPercent: 1.5,
          vszKb: 45056,
          vszMb: 44.0,
          memPercent: 3.2,
          estimatedRamMb: 8.5,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardProcessCard(
              telemetry: mockTelemetry,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Estimated RAM'), findsOneWidget);
        expect(find.byTooltip('Calculated from process memory percentage; not kernel RSS'),
            findsOneWidget);
        expect(find.text('1660'), findsOneWidget);
        expect(find.text('1.5%'), findsOneWidget);
        expect(find.text('44.0 MB'), findsOneWidget);
        expect(find.textContaining('8.5 MB (3.2%)'), findsOneWidget);
      },
    );

    // ── 7. Topology Disclaimer ──────────────────────────────────────────────
    testWidgets(
      '7. AdGuardTopologyCard displays mode and mandatory inference disclaimer',
      (tester) async {
        const topology = AdGuardDnsTopology(
          mode: AdGuardTopologyMode.adguardPrimary,
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          forwarders: ['127.0.0.1#53'],
          hasFirewallRedirect: false,
          isIpv6Supported: true,
          description: 'Primary DNS on port 53',
        );

        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardTopologyCard(
              topology: topology,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_topology_mode_badge')), findsOneWidget);
        expect(find.text('Direct Port 53'), findsOneWidget);
        expect(
          find.byKey(const Key('agh_topology_disclaimer_text')),
          findsOneWidget,
        );
        expect(
          find.text('Inferred from configuration and ports; not live traffic inspection'),
          findsOneWidget,
        );
      },
    );

    // ── 8. Authentication-Required UI ──────────────────────────────────────
    testWidgets(
      '8. Auth-required banner displays when credentials are required',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
          ..isAuthRequiredState = true;
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_auth_required_banner')), findsOneWidget);
        expect(find.text('AdGuard Home Authentication Required'), findsOneWidget);
        expect(find.byKey(const Key('agh_enter_credentials_button')), findsOneWidget);
      },
    );

    // ── 9. Credentials Submission Through Controller ────────────────────────
    testWidgets(
      '9. AdGuardCredentialsDialog collects and submits credentials to controller',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
          ..isAuthRequiredState = true;
        final mockLuci = UiTestFakeLuciApiService();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('open_creds_dialog'),
                  onPressed: () {
                    AdGuardCredentialsDialog.show(context, controller: controller);
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_creds_dialog')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_credentials_username_field')), findsOneWidget);
        expect(find.byKey(const Key('agh_credentials_password_field')), findsOneWidget);

        // Enter credentials
        await tester.enterText(
          find.byKey(const Key('agh_credentials_username_field')),
          'adguard_admin',
        );
        await tester.enterText(
          find.byKey(const Key('agh_credentials_password_field')),
          'super_secret_pass',
        );
        await tester.pump();

        // Submit
        mockApi.isAuthRequiredState = false;
        await tester.tap(find.byKey(const Key('agh_credentials_submit_button')));
        await tester.pumpAndSettle();

        expect(mockApi.setCredentialsCallCount, equals(1));
        expect(mockApi.activeCreds?.username, equals('adguard_admin'));
        expect(mockApi.activeCreds?.password, equals('super_secret_pass'));

        controller.dispose();
      },
    );

    // ── 9b. Credentials Failure Feedback ────────────────────────────────────
    testWidgets(
      '9b. AdGuardCredentialsDialog displays authentication failed error and remains open when submitted credentials fail',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
          ..isAuthRequiredState = true;
        final mockLuci = UiTestFakeLuciApiService();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('open_creds_dialog_9b'),
                  onPressed: () {
                    AdGuardCredentialsDialog.show(context, controller: controller);
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_creds_dialog_9b')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('agh_credentials_username_field')),
          'bad_user',
        );
        await tester.enterText(
          find.byKey(const Key('agh_credentials_password_field')),
          'wrong_password',
        );
        await tester.pump();

        // Submit while API still returns authRequired
        await tester.tap(find.byKey(const Key('agh_credentials_submit_button')));
        await tester.pumpAndSettle();

        // Dialog remains open and displays error
        expect(find.byType(AdGuardCredentialsDialog), findsOneWidget);
        expect(
          find.text('Authentication failed. Invalid username or password.'),
          findsOneWidget,
        );

        controller.dispose();
      },
    );

    // ── 10. Polling Options (Strictly No 60s Option) ────────────────────────
    testWidgets(
      '10. Polling interval menu presents exactly Off, 5s, 10s, 30s, Manual with no 60s option',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        // Open polling popup menu
        await tester.tap(find.byKey(const Key('agh_polling_interval_button')));
        await tester.pumpAndSettle();

        // Check required 5 options exist
        expect(find.byKey(const Key('agh_polling_off')), findsOneWidget);
        expect(find.byKey(const Key('agh_polling_s5')), findsOneWidget);
        expect(find.byKey(const Key('agh_polling_s10')), findsOneWidget);
        expect(find.byKey(const Key('agh_polling_s30')), findsOneWidget);
        expect(find.byKey(const Key('agh_polling_manual')), findsOneWidget);

        // Strictly verify that 60 seconds is NOT present
        expect(find.byKey(const Key('agh_polling_s60')), findsNothing);
        expect(find.text('60 seconds'), findsNothing);
      },
    );

    // ── 12. Dashboard Card Visibility Gating ────────────────────────────────
    testWidgets(
      '12. AdGuardDashboardCard renders only when all capability conditions are met',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        // 1. Initial unauthenticated state -> hides (SizedBox.shrink)
        mockApi.isAuthRequiredState = true;
        await tester.pumpWidget(
          buildTestApp(
            key: const Key('scope_unauth'),
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardDashboardCard(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('agh_dashboard_card')), findsNothing);

        // 2. Fully authenticated & operational -> displays card
        mockApi.isAuthRequiredState = false;
        await tester.pumpWidget(
          buildTestApp(
            key: const Key('scope_auth'),
            overrides: [
              adguardControllerProvider('test-router-auth').overrideWith(
                (ref) {
                  final c = AdGuardController(
                    ref,
                    'test-router-auth',
                    apiServiceOverride: mockApi,
                    luciApiServiceOverride: mockLuci,
                  );
                  c.refresh();
                  return c;
                },
              ),
            ],
            child: const AdGuardDashboardCard(routerId: 'test-router-auth'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('agh_dashboard_card')), findsOneWidget);
        expect(find.byKey(const Key('agh_dashboard_queries')), findsOneWidget);
        expect(find.byKey(const Key('agh_dashboard_blocked')), findsOneWidget);
        expect(find.byKey(const Key('agh_dashboard_block_rate')), findsOneWidget);
      },
    );

    // ── 13. Dashboard Navigation ───────────────────────────────────────────
    testWidgets(
      '13. AdGuardDashboardCard triggers navigation on tap',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();
        bool tapped = false;

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) {
                  final c = AdGuardController(
                    ref,
                    'test-router',
                    apiServiceOverride: mockApi,
                    luciApiServiceOverride: mockLuci,
                  );
                  c.refresh();
                  return c;
                },
              ),
            ],
            child: AdGuardDashboardCard(
              routerId: 'test-router',
              onTap: () => tapped = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('agh_dashboard_card')));
        await tester.pump();
        expect(tapped, isTrue);
      },
    );

    // ── 14. Router-State Isolation ─────────────────────────────────────────
    testWidgets(
      '14. Independent router IDs isolate AdGuard controller and screen states',
      (tester) async {
        final mockApiA = UiTestMockAdGuardApiService(
          routerId: 'router-A',
          mockStatus: const AdGuardStatus(
            version: 'v0.107.50',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['192.168.1.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );
        final mockApiB = UiTestMockAdGuardApiService(
          routerId: 'router-B',
          mockStatus: const AdGuardStatus(
            version: 'v0.107.99',
            running: false,
            protectionState: AdGuardProtectionState.disabled,
            dnsAddresses: ['10.0.0.1'],
            dnsPort: 5353,
            httpPort: 8080,
          ),
        );

        final mockLuci = UiTestFakeLuciApiService();

        // Pump Router A screen
        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('router-A').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'router-A',
                  apiServiceOverride: mockApiA,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
              adguardControllerProvider('router-B').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'router-B',
                  apiServiceOverride: mockApiB,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'router-A'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('v0.107.50'), findsOneWidget);
        expect(find.text('v0.107.99'), findsNothing);

        // Switch to Router B screen
        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('router-A').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'router-A',
                  apiServiceOverride: mockApiA,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
              adguardControllerProvider('router-B').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'router-B',
                  apiServiceOverride: mockApiB,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'router-B'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('v0.107.99'), findsOneWidget);
        expect(find.text('v0.107.50'), findsNothing);
      },
    );

    // ── 1. Main Screen Rendering ───────────────────────────────────────────
    testWidgets(
      '1. AdGuardHomeScreen renders all cards when healthy',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AdGuardStatusCard), findsOneWidget);
        expect(find.byType(AdGuardProtectionCard), findsOneWidget);
        expect(find.byType(AdGuardFilteringCard), findsOneWidget);
        expect(find.byType(AdGuardStatsCard), findsOneWidget);
        expect(find.byType(AdGuardTopListsCard), findsOneWidget);
        expect(find.byType(AdGuardTopologyCard), findsOneWidget);
        expect(find.byType(AdGuardProcessCard), findsOneWidget);
        expect(find.byType(AdGuardServiceCard), findsOneWidget);
      },
    );

    // ── 16. Milestone C: LuciLoadingView During Initial Discovery (No Red Flash) ──
    testWidgets(
      '16. AdGuardHomeScreen renders LuciLoadingView during initial loading without frame-0 red flash cards',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final delayCompleter = Completer<void>();
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
          ..delayStatusCompleter = delayCompleter;
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );

        // Frame-0: controller initialization initiated, getStatus is awaiting delayCompleter
        await tester.pump();

        // LuciLoadingView must be visible
        expect(find.byKey(const Key('agh_initial_loading_view')), findsOneWidget);
        expect(find.byType(LuciLoadingView), findsOneWidget);

        // Invariant: No premature red flash / Stopped / Disabled cards
        expect(find.byType(AdGuardStatusCard), findsNothing);
        expect(find.byType(AdGuardProtectionCard), findsNothing);
        expect(find.text('Protection Disabled'), findsNothing);
        expect(find.text('Stopped'), findsNothing);

        // Now complete discovery
        delayCompleter.complete();
        await tester.pumpAndSettle();

        // LuciLoadingView replaced by actual cards
        expect(find.byKey(const Key('agh_initial_loading_view')), findsNothing);
        expect(find.byType(AdGuardStatusCard), findsOneWidget);
        expect(find.byType(AdGuardProtectionCard), findsOneWidget);
      },
    );

    // ── 17. Milestone C: Discovery Failure View with Retry ─────────────────
    testWidgets(
      '17. AdGuardHomeScreen renders dedicated error view on discovery failure with retry button',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
          ..customStatusResult = AdGuardApiResult.failure(
            const AdGuardApiException(
              message: 'Connection timed out',
              type: AdGuardApiErrorType.networkFailure,
            ),
          );
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        // Error view rendered with retry button
        expect(find.byKey(const Key('agh_discovery_error_view')), findsOneWidget);
        expect(find.byKey(const Key('agh_error_retry_button')), findsOneWidget);
        expect(find.text('AdGuard Home Unreachable'), findsOneWidget);

        // Switch to succeeding response and tap retry
        mockApi.customStatusResult = null;
        await tester.tap(find.byKey(const Key('agh_error_retry_button')));
        await tester.pumpAndSettle();

        // Error view dismissed and cards shown
        expect(find.byKey(const Key('agh_discovery_error_view')), findsNothing);
        expect(find.byType(AdGuardStatusCard), findsOneWidget);
      },
    );

    // ── 18. Milestone C: AdGuardProfileDialog Validation, Test Connection & Save ─
    testWidgets(
      '18. AdGuardProfileDialog validates inputs, tests connection, and saves profile',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('open_dialog_button'),
                onPressed: () => AdGuardProfileDialog.show(
                  context,
                  controller: controller,
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open Dialog
        await tester.tap(find.byKey(const Key('open_dialog_button')));
        await tester.pumpAndSettle();

        // 1. Validation test: tap save with empty inputs
        await tester.tap(find.byKey(const Key('agh_save_profile_button')));
        await tester.pumpAndSettle();
        expect(find.text('Please enter a name'), findsOneWidget);
        expect(find.text('Host is required'), findsOneWidget);

        // 2. Fill valid form data
        await tester.enterText(
          find.byKey(const Key('agh_profile_name_field')),
          'Raspberry Pi AGH',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_host_field')),
          '192.168.1.129',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_port_field')),
          '3000',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_username_field')),
          'nightcode',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_password_field')),
          'secret123',
        );
        await tester.pumpAndSettle();

        // 3. Test pre-save connection probing
        await tester.tap(find.byKey(const Key('agh_test_connection_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_test_status_indicator')), findsOneWidget);
        expect(find.text('Connection successful!'), findsOneWidget);

        // 4. Save profile
        await tester.tap(find.byKey(const Key('agh_save_profile_button')));
        await tester.pumpAndSettle();

        // Verify profile added to controller and dialog closed
        expect(find.byType(AdGuardProfileDialog), findsNothing);
        expect(
          controller.state.profiles.any((p) => p.name == 'Raspberry Pi AGH'),
          isTrue,
        );
        expect(controller.state.activeProfile?.name, equals('Raspberry Pi AGH'));

        controller.dispose();
      },
    );

    // ── 18b. Profile Dialog: Auth-Required vs Auth-Failed Distinction ────────
    testWidgets(
      '18b. AdGuardProfileDialog distinguishes authentication failed from authentication required',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
          ..testConnectionResult = AdGuardConnectionStatus.authRequired;
        final mockLuci = UiTestFakeLuciApiService();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('open_dialog_button_18b'),
                  onPressed: () {
                    AdGuardProfileDialog.show(context, controller: controller);
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog_button_18b')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('agh_profile_name_field')),
          'Pi Auth Test',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_host_field')),
          '192.168.1.129',
        );

        // Case 1: No credentials entered -> Authentication required
        await tester.tap(find.byKey(const Key('agh_test_connection_button')));
        await tester.pumpAndSettle();
        expect(
          find.text('Authentication required. Enter username & password.'),
          findsOneWidget,
        );

        // Case 2: Credentials entered -> Authentication failed
        await tester.enterText(
          find.byKey(const Key('agh_profile_username_field')),
          'nightcode',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_password_field')),
          'wrongpass',
        );
        await tester.tap(find.byKey(const Key('agh_test_connection_button')));
        await tester.pumpAndSettle();
        expect(
          find.text('Authentication failed. Invalid username or password.'),
          findsOneWidget,
        );

        controller.dispose();
      },
    );

    // ── 19. Milestone C: External Profile Hides Procd Cards & Renders Disclaimer ──
    testWidgets(
      '19. AdGuardHomeScreen with external profile hides procd cards and displays topology disclaimer',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_pi_test',
          name: 'Raspberry Pi External',
          host: '192.168.1.129',
          port: 3000,
        );

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  initialProfile: extProfile,
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        // Active profile subtitle in AppBar
        expect(find.byKey(const Key('agh_active_profile_subtitle')), findsOneWidget);
        expect(find.text('Raspberry Pi External'), findsWidgets);

        // External topology disclaimer rendered
        expect(find.byKey(const Key('agh_external_topology_disclaimer')), findsOneWidget);

        // Procd OpenWrt cards must NOT be rendered
        expect(find.byType(AdGuardProcessCard), findsNothing);
        expect(find.byType(AdGuardServiceCard), findsNothing);

        // Standard AdGuard Home cards ARE rendered
        expect(find.byType(AdGuardStatusCard), findsOneWidget);
        expect(find.byType(AdGuardProtectionCard), findsOneWidget);
        expect(find.byType(AdGuardStatsCard), findsOneWidget);
        expect(find.byType(AdGuardTopListsCard), findsOneWidget);
        expect(find.byType(AdGuardTopologyCard), findsOneWidget);
      },
    );

    // ── 20. Host Sanitization & Validation in AdGuardProfileDialog ──────────
    testWidgets(
      '20. AdGuardProfileDialog sanitizes host input and validates IP/hostname format',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('open_dialog_button'),
                onPressed: () => AdGuardProfileDialog.show(
                  context,
                  controller: controller,
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog_button')));
        await tester.pumpAndSettle();

        // 1. Enter invalid host format
        await tester.enterText(
          find.byKey(const Key('agh_profile_name_field')),
          'Test AGH',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_host_field')),
          'invalid host with spaces!!!',
        );
        await tester.tap(find.byKey(const Key('agh_save_profile_button')));
        await tester.pumpAndSettle();

        expect(find.text('Enter a valid IP address or hostname'), findsOneWidget);

        // 2. Enter URL with http:// and port and trailing slash
        await tester.enterText(
          find.byKey(const Key('agh_profile_host_field')),
          'http://192.168.1.129:3000/',
        );
        await tester.ensureVisible(find.byKey(const Key('agh_test_connection_button')));
        await tester.tap(find.byKey(const Key('agh_test_connection_button')));
        await tester.pumpAndSettle();

        // Verifies host field was sanitized to IP only and port was parsed
        final hostField = tester.widget<TextFormField>(find.byKey(const Key('agh_profile_host_field')));
        expect(hostField.controller?.text, equals('192.168.1.129'));
        final portField = tester.widget<TextFormField>(find.byKey(const Key('agh_profile_port_field')));
        expect(portField.controller?.text, equals('3000'));
        expect(find.text('Connection successful!'), findsOneWidget);

        controller.dispose();
      },
    );

    // ── 21. Edit Active External Profile via AppBar Menu ───────────────────
    testWidgets(
      '21. AdGuardHomeScreen allows editing active external profile via AppBar menu',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_pi_edit',
          name: 'Raspberry Pi External',
          host: '192.168.1.129',
          port: 3000,
        );

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  initialProfile: extProfile,
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Profile Selector Menu Button
        await tester.tap(find.byKey(const Key('agh_profile_selector_button')));
        await tester.pumpAndSettle();

        // Expect Edit Current Profile button to be visible
        expect(find.byKey(const Key('agh_edit_active_profile_button')), findsOneWidget);
        expect(find.text('Edit Current Profile'), findsOneWidget);

        // Tap Edit Current Profile
        await tester.tap(find.byKey(const Key('agh_edit_active_profile_button')));
        await tester.pumpAndSettle();

        // Dialog opens in Edit mode
        expect(find.byType(AdGuardProfileDialog), findsOneWidget);
        expect(find.text('Edit AdGuard Profile'), findsOneWidget);
        expect(find.text('Raspberry Pi External'), findsWidgets);
      },
    );

    // ── 22. Profile Deletion Cancellation ──────────────────────────────────
    testWidgets(
      '22. Profile deletion cancellation keeps profile intact',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_cancel_del',
          name: 'Cancel Me Not',
          host: '192.168.1.130',
          port: 3000,
        );

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  initialProfile: extProfile,
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Profile Selector Menu Button
        await tester.tap(find.byKey(const Key('agh_profile_selector_button')));
        await tester.pumpAndSettle();

        // Tap Delete Current Profile
        await tester.tap(find.byKey(const Key('agh_delete_active_profile_button')));
        await tester.pumpAndSettle();

        // Verify confirmation dialog is displayed
        expect(find.text('Delete Instance Profile?'), findsOneWidget);
        expect(find.byKey(const Key('agh_delete_profile_cancel_button')), findsOneWidget);
        expect(find.byKey(const Key('agh_delete_profile_confirm_button')), findsOneWidget);

        // Tap Cancel
        await tester.tap(find.byKey(const Key('agh_delete_profile_cancel_button')));
        await tester.pumpAndSettle();

        // Verify dialog dismissed and profile remains active
        expect(find.text('Delete Instance Profile?'), findsNothing);
        expect(find.text('Cancel Me Not'), findsWidgets);
      },
    );

    // ── 23. Profile Deletion Confirmation ──────────────────────────────────
    testWidgets(
      '23. Profile deletion confirmation invokes deletion and switches to fallback profile',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_confirm_del',
          name: 'Delete Me Now',
          host: '192.168.1.131',
          port: 3000,
        );

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  initialProfile: extProfile,
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Profile Selector Menu Button
        await tester.tap(find.byKey(const Key('agh_profile_selector_button')));
        await tester.pumpAndSettle();

        // Tap Delete Current Profile
        await tester.tap(find.byKey(const Key('agh_delete_active_profile_button')));
        await tester.pumpAndSettle();

        // Tap Delete Confirm
        await tester.tap(find.byKey(const Key('agh_delete_profile_confirm_button')));
        await tester.pumpAndSettle();

        // Dialog dismissed
        expect(find.text('Delete Instance Profile?'), findsNothing);
      },
    );

    // ── 24. AdGuardDashboardCard with External Subtitle ────────────────────
    testWidgets(
      '24. AdGuardDashboardCard displays external standalone subtitle for external profile',
      (tester) async {
        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_dash_1',
          name: 'HomeLab Pi',
          host: '10.0.0.55',
          port: 3000,
        );

        final mockApi = UiTestMockAdGuardApiService(routerId: 'dash-ext-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('dash-ext-router').overrideWith(
                (ref) {
                  final c = AdGuardController(
                    ref,
                    'dash-ext-router',
                    initialProfile: extProfile,
                    apiServiceOverride: mockApi,
                    luciApiServiceOverride: mockLuci,
                  );
                  c.refresh();
                  return c;
                },
              ),
            ],
            child: const AdGuardDashboardCard(routerId: 'dash-ext-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_dashboard_card')), findsOneWidget);
        expect(find.byKey(const Key('agh_dashboard_card_external_subtitle')), findsOneWidget);
        expect(find.text('HomeLab Pi (External Standalone)'), findsOneWidget);
      },
    );

    // ── 25. AdGuardDashboardCard Auto-Hydration ────────────────────────────
    testWidgets(
      '25. AdGuardDashboardCard triggers auto-hydration on mount when router has capability',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'dash-hydrate-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              routerCapabilitiesProvider.overrideWithValue(
                RouterCapabilities.mock(),
              ),
              adguardControllerProvider('dash-hydrate-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'dash-hydrate-router',
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardDashboardCard(routerId: 'dash-hydrate-router'),
          ),
        );
        await tester.pumpAndSettle();

        // Should have hydrated and rendered card
        expect(find.byKey(const Key('agh_dashboard_card')), findsOneWidget);
        expect(mockApi.statusCallCount, greaterThan(0));
      },
    );

    // ── 26. Protection Action Error Feedback ─────────────────────────────────
    testWidgets(
      '26. AdGuardProtectionCard renders actionError banner and clears when null',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardProtectionCard(
              status: const AdGuardStatus(
                version: 'v0.107.52',
                running: true,
                protectionState: AdGuardProtectionState.enabled,
                dnsAddresses: ['192.168.1.1'],
                dnsPort: 53,
                httpPort: 3000,
              ),
              isMutating: false,
              actionError: 'Failed to update protection status',
              onSetProtection: ({required bool enabled, Duration? duration}) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_protection_error_banner')), findsOneWidget);
        expect(find.byKey(const Key('agh_protection_error_text')), findsOneWidget);
        expect(find.text('Failed to update protection status'), findsOneWidget);

        // Re-pump without error
        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardProtectionCard(
              status: const AdGuardStatus(
                version: 'v0.107.52',
                running: true,
                protectionState: AdGuardProtectionState.enabled,
                dnsAddresses: ['192.168.1.1'],
                dnsPort: 53,
                httpPort: 3000,
              ),
              isMutating: false,
              actionError: null,
              onSetProtection: ({required bool enabled, Duration? duration}) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_protection_error_banner')), findsNothing);
      },
    );

    // ── 27. Service Action Error Feedback ────────────────────────────────────
    testWidgets(
      '27. AdGuardServiceCard renders actionError banner and clears when null',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardServiceCard(
              isRunning: true,
              isManageable: true,
              isManaging: false,
              actionError: 'Service stop failed: RPC error',
              onStart: () async {},
              onStop: () async {},
              onRestart: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_service_error_banner')), findsOneWidget);
        expect(find.byKey(const Key('agh_service_error_text')), findsOneWidget);
        expect(find.text('Service stop failed: RPC error'), findsOneWidget);

        // Re-pump without error
        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardServiceCard(
              isRunning: true,
              isManageable: true,
              isManaging: false,
              actionError: null,
              onStart: () async {},
              onStop: () async {},
              onRestart: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_service_error_banner')), findsNothing);
      },
    );

    // ── 28. General Error Banner Without Duplication ─────────────────────────
    testWidgets(
      '28. AdGuardHomeScreen surfaces generalError banner without duplicating existing banners',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'gen-err-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('gen-err-router').overrideWith(
                (ref) {
                  final c = AdGuardController(
                    ref,
                    'gen-err-router',
                    apiServiceOverride: mockApi,
                    luciApiServiceOverride: mockLuci,
                  );
                  // Simulate an unexpected error while having valid cached status
                  c.refresh().then((_) {
                    c.state = c.state.copyWith(
                      generalError: 'Unexpected system fault during background sync',
                    );
                  });
                  return c;
                },
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'gen-err-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_general_error_banner')), findsOneWidget);
        expect(find.text('Unexpected system fault during background sync'), findsOneWidget);
        expect(find.byKey(const Key('agh_api_unreachable_banner')), findsNothing);
        expect(find.byKey(const Key('agh_invalid_endpoint_banner')), findsNothing);
      },
    );

    // ── 29. Filtering Card - Active State & Rules Overview ───────────────────
    testWidgets(
      '29. AdGuardFilteringCard renders active state, filter counts, and user rules',
      (tester) async {
        const filtering = AdGuardFilteringStatus(
          enabled: true,
          filterLists: [
            AdGuardFilterList(id: 1, name: 'AdGuard Base', rulesCount: 40000, enabled: true),
            AdGuardFilterList(id: 2, name: 'Tracking Protection', rulesCount: 15000, enabled: true),
            AdGuardFilterList(id: 3, name: 'Experimental', rulesCount: 5000, enabled: false),
          ],
          userRules: ['||example.com^', '@@||allowme.org^'],
          totalRulesCount: 55002,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardFilteringCard(
              filtering: filtering,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_filtering_card')), findsOneWidget);
        expect(find.byKey(const Key('agh_filtering_status_chip')), findsOneWidget);
        expect(find.text('Filtering Active'), findsOneWidget);
        // Enabled / Total filter lists (2 / 3)
        expect(find.byKey(const Key('agh_filter_lists_count')), findsOneWidget);
        expect(find.text('2 / 3'), findsOneWidget);
        // Custom user rules (2)
        expect(find.byKey(const Key('agh_user_rules_count')), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        // Total rules count
        expect(find.byKey(const Key('agh_total_rules_count')), findsOneWidget);
        expect(find.text('55,002'), findsOneWidget);
      },
    );

    // ── 30. Filtering Card - Inactive State ──────────────────────────────────
    testWidgets(
      '30. AdGuardFilteringCard renders inactive state when filtering is disabled',
      (tester) async {
        const filtering = AdGuardFilteringStatus(
          enabled: false,
          filterLists: [
            AdGuardFilterList(id: 1, name: 'AdGuard Base', rulesCount: 40000, enabled: false),
          ],
          userRules: [],
          totalRulesCount: 0,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardFilteringCard(
              filtering: filtering,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Filtering Disabled'), findsOneWidget);
        expect(find.text('0 / 1'), findsOneWidget);
      },
    );

    // ── 31. Filtering Card - Degraded Banner ─────────────────────────────────
    testWidgets(
      '31. AdGuardFilteringCard renders degraded banner when filteringError is set',
      (tester) async {
        const filtering = AdGuardFilteringStatus(
          enabled: true,
          filterLists: [],
          userRules: [],
          totalRulesCount: 0,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardFilteringCard(
              filtering: filtering,
              filteringError: 'Filtering API response delayed',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_filtering_degraded_banner')), findsOneWidget);
        expect(find.text('Filtering API response delayed'), findsOneWidget);
      },
    );

    // ── 32. Filtering Card - Empty State ─────────────────────────────────────
    testWidgets(
      '32. AdGuardFilteringCard renders empty state when lists and rules are empty',
      (tester) async {
        const filtering = AdGuardFilteringStatus(
          enabled: true,
          filterLists: [],
          userRules: [],
          totalRulesCount: 0,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardFilteringCard(
              filtering: filtering,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_filtering_empty_message')), findsOneWidget);
        expect(find.text('No filter lists configured'), findsOneWidget);
      },
    );

    // ── 33. Filtering Card - Loading and Error States ────────────────────────
    testWidgets(
      '33. AdGuardFilteringCard renders loading and error states appropriately',
      (tester) async {
        // Loading
        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardFilteringCard(
              filtering: null,
              isLoading: true,
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('agh_filtering_card_loading')), findsOneWidget);

        // Error when null
        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardFilteringCard(
              filtering: null,
              filteringError: 'Failed to connect to filtering endpoint',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('agh_filtering_card_error')), findsOneWidget);
        expect(find.text('Failed to connect to filtering endpoint'), findsOneWidget);

        // Sized box shrink when both null
        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardFilteringCard(
              filtering: null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('agh_filtering_card')), findsNothing);
      },
    );

    // ── 34. Topology Card - Localized Routing Status ─────────────────────────
    testWidgets(
      '34. AdGuardTopologyCard displays localized Routing Status label',
      (tester) async {
        const topology = AdGuardDnsTopology(
          mode: AdGuardTopologyMode.dnsmasqForwarder,
          adguardDnsPort: 5353,
          dnsmasqPort: 53,
          forwarders: ['127.0.0.1#5353'],
          hasFirewallRedirect: false,
          isIpv6Supported: false,
          description: 'Forwarding to AdGuard',
          routingStatus: AdGuardDnsRoutingStatus.routerForwardingVerified,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: const AdGuardTopologyCard(
              topology: topology,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Routing Status'), findsOneWidget);
        expect(find.byKey(const Key('agh_topology_routing_status_badge')), findsOneWidget);
        expect(find.text('Router Forwarding Verified'), findsOneWidget);
      },
    );

    // ── 35. Topology Card - Remove Forwarding Button Visibility ──────────────
    testWidgets(
      '35. AdGuardTopologyCard displays Remove Forwarding button when forwarding is active',
      (tester) async {
        final container = ProviderContainer();
        final mockApiService = UiTestMockAdGuardApiService(
          routerId: 'test_router_ui_revert',
        );
        final controller = AdGuardController(
          container.read(adguardControllerProvider('test_router_ui_revert').notifier).ref,
          'test_router_ui_revert',
          apiServiceOverride: mockApiService,
        );

        const forwardedTopology = AdGuardDnsTopology(
          mode: AdGuardTopologyMode.dnsmasqForwarder,
          adguardDnsPort: 5353,
          dnsmasqPort: 53,
          forwarders: ['127.0.0.1#5353'],
          hasFirewallRedirect: false,
          isIpv6Supported: false,
          description: 'Forwarding to AdGuard',
          routingStatus: AdGuardDnsRoutingStatus.routerForwardingVerified,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardTopologyCard(
              topology: forwardedTopology,
              controller: controller,
              routerId: 'test_router_ui_revert',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_configure_router_dns_btn')), findsOneWidget);
        expect(find.byKey(const Key('agh_revert_router_dns_btn')), findsOneWidget);
        expect(find.text('Remove Forwarding'), findsOneWidget);
      },
    );

    // ── 36. Stats Card - Period Selection Popup Menu ─────────────────────────
    testWidgets(
      '36. AdGuardStatsCard renders period popup menu and triggers onPeriodChanged',
      (tester) async {
        AdGuardStatsPeriod? selected;
        const stats = AdGuardStats(
          numDnsQueries: 500,
          numBlockedFiltering: 50,
          numReplacedSafebrowsing: 0,
          numReplacedSafesearch: 0,
          numReplacedParental: 0,
          avgProcessingTime: 0.02,
          topQueriedDomains: [],
          topBlockedDomains: [],
          topClients: [],
          dnsQueriesTrend: [],
          blockedFilteringTrend: [],
          blockRatePercentage: 10.0,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardStatsCard(
              stats: stats,
              selectedPeriod: AdGuardStatsPeriod.all,
              onPeriodChanged: (period) => selected = period,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_stats_period_button')), findsOneWidget);
        expect(find.text('All Time'), findsOneWidget);

        // Tap the period popup button
        await tester.tap(find.byKey(const Key('agh_stats_period_button')));
        await tester.pumpAndSettle();

        // Verify choices are shown
        expect(find.text('24 Hours'), findsOneWidget);
        expect(find.text('7 Days'), findsOneWidget);
        expect(find.text('30 Days'), findsOneWidget);

        // Select 24 Hours
        await tester.tap(find.text('24 Hours'));
        await tester.pumpAndSettle();

        expect(selected, equals(AdGuardStatsPeriod.hours24));
      },
    );

    // ── 37. Service Card - Autostart Toggle Switch ───────────────────────────
    testWidgets(
      '37. AdGuardServiceCard renders agh_service_autostart_switch and triggers onToggleAutostart',
      (tester) async {
        bool? toggledValue;

        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardServiceCard(
              isRunning: true,
              isManageable: true,
              isManaging: false,
              isAutostartEnabled: true,
              onToggleAutostart: (val) async => toggledValue = val,
              onStart: () async {},
              onStop: () async {},
              onRestart: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final switchFinder = find.byKey(const Key('agh_service_autostart_switch'));
        expect(switchFinder, findsOneWidget);
        expect(find.text('Autostart on boot'), findsOneWidget);

        // Verify initial state is true
        final switchWidget = tester.widget<SwitchListTile>(switchFinder);
        expect(switchWidget.value, isTrue);

        // Tap the switch
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(toggledValue, isFalse);
      },
    );

    // ── 38. Filtering Card - Manage Custom Rules Metric Tile ─────────────────
    testWidgets(
      '38. AdGuardFilteringCard triggers onManageUserRules via metric tile and removes redundant bottom button',
      (tester) async {
        bool rulesTapped = false;
        const filtering = AdGuardFilteringStatus(
          enabled: true,
          filterLists: [],
          userRules: ['||example.com^'],
          totalRulesCount: 1,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: AdGuardFilteringCard(
              filtering: filtering,
              onManageUserRules: () => rulesTapped = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_manage_user_rules_button')), findsNothing);

        final rulesTile = find.byKey(const Key('agh_user_rules_count'));
        expect(rulesTile, findsOneWidget);

        await tester.tap(rulesTile);
        await tester.pumpAndSettle();

        expect(rulesTapped, isTrue);
      },
    );

    // ── 39. Custom Rules Dialog - Render, Count Badge, Edit, and Save ─────────
    testWidgets(
      '39. AdGuardCustomRulesDialog renders rules, counts lines, and submits edits',
      (tester) async {
        final container = ProviderContainer();
        final mockApiService = UiTestMockAdGuardApiService(
          routerId: 'test_router_custom_rules',
        );
        final controller = AdGuardController(
          container.read(adguardControllerProvider('test_router_custom_rules').notifier).ref,
          'test_router_custom_rules',
          apiServiceOverride: mockApiService,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AdGuardCustomRulesDialog.show(
                  context,
                  controller: controller,
                  initialRules: const [
                    '||adservice.com^',
                    '! A comment line',
                    '127.0.0.1 bad.org',
                  ],
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open the dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_custom_rules_dialog')), findsOneWidget);
        // Comments should not be counted as active rules: 2 active rules
        expect(find.text('2 rules'), findsOneWidget);

        // Enter new rules in the text field
        final textField = find.byKey(const Key('agh_custom_rules_text_field'));
        expect(textField, findsOneWidget);

        await tester.enterText(
          textField,
          '||domain1.com^\n||domain2.com^\n||domain3.com^\n! Just comment',
        );
        await tester.pump();

        // Now count badge should show 3 rules
        expect(find.text('3 rules'), findsOneWidget);

        // Tap Save button
        await tester.tap(find.byKey(const Key('agh_custom_rules_save_button')));
        await tester.pumpAndSettle();

        // Verify dialog dismissed and mock received parsed rules
        expect(find.byKey(const Key('agh_custom_rules_dialog')), findsNothing);
        expect(
          mockApiService.lastSetUserRules,
          equals([
            '||domain1.com^',
            '||domain2.com^',
            '||domain3.com^',
            '! Just comment',
          ]),
        );
      },
    );

    // ── 40. Custom Rules Dialog - Error Banner on Failure ────────────────────
    testWidgets(
      '40. AdGuardCustomRulesDialog displays error banner on save failure',
      (tester) async {
        final container = ProviderContainer();
        final mockApiService = UiTestMockAdGuardApiService(
          routerId: 'test_router_custom_rules_err',
        );
        mockApiService.setUserRulesResult = AdGuardApiResult.failure(
          const AdGuardApiException(
            type: AdGuardApiErrorType.httpError,
            statusCode: 400,
            message: 'Invalid filter rule syntax error',
          ),
        );
        final controller = AdGuardController(
          container.read(adguardControllerProvider('test_router_custom_rules_err').notifier).ref,
          'test_router_custom_rules_err',
          apiServiceOverride: mockApiService,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AdGuardCustomRulesDialog.show(
                  context,
                  controller: controller,
                  initialRules: const ['bad_syntax_rule'],
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_custom_rules_dialog')), findsOneWidget);

        // Tap Save
        await tester.tap(find.byKey(const Key('agh_custom_rules_save_button')));
        await tester.pumpAndSettle();

        // Dialog should remain open with error banner visible
        expect(find.byKey(const Key('agh_custom_rules_dialog')), findsOneWidget);
        expect(find.byKey(const Key('agh_custom_rules_error_banner')), findsOneWidget);
        expect(find.textContaining('Invalid filter rule syntax error'), findsOneWidget);
      },
    );
  });
}
