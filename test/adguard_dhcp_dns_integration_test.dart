// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/modules/adguard_home/controllers/adguard_controller.dart';
import 'package:yala/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/screens/adguard_home_screen.dart';
import 'package:yala/modules/dhcp_dns/screens/dhcp_dns_screen.dart';
import 'package:yala/modules/dhcp_dns/widgets/adguard_dns_status_card.dart';
import 'package:yala/state/app_state.dart';

/// Configurable test controller for deterministic [AdGuardDnsStatusCard] widget testing.
class TestAdGuardController extends AdGuardController {
  TestAdGuardController(
    super.ref,
    super.routerId, {
    required AdGuardState initialState,
  }) {
    state = initialState;
  }

  @override
  Future<void> refresh({
    bool forceProbe = false,
    bool forceTopologyProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  }) async {
    // Keep test state unchanged during widget lifecycle callbacks
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });
  });

  Widget buildCardTestWidget({
    required String routerId,
    required AdGuardState adguardState,
    Locale locale = const Locale('en'),
  }) {
    return ProviderScope(
      overrides: [
        adguardControllerProvider(routerId).overrideWith(
          (ref) => TestAdGuardController(ref, routerId, initialState: adguardState),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdGuardDnsStatusCard(routerId: routerId),
          ),
        ),
      ),
    );
  }

  group('AdGuardDnsStatusCard — State Precedence & Visibility Tests', () {
    testWidgets('State 1: AdGuard not installed renders SizedBox.shrink() with zero footprint', (tester) async {
      const state = AdGuardState(
        routerId: 'router-1',
        capabilities: AdGuardCapabilities(
          isInstalled: false,
          isServiceManageable: false,
          isApiReachable: false,
          isApiAuthenticated: false,
          isDnsOperational: false,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.unknown,
            adguardDnsPort: 53,
            dnsmasqPort: 53,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Unknown',
          ),
        ),
      );

      await tester.pumpWidget(buildCardTestWidget(routerId: 'router-1', adguardState: state));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_dns_status_card_operational')), findsNothing);
      expect(find.byKey(const Key('agh_dns_status_card_degraded')), findsNothing);
      expect(find.byKey(const Key('agh_dns_status_card_dns_not_operational')), findsNothing);
      expect(find.text('AdGuard Home DNS'), findsNothing);
    });

    testWidgets('State 2: API unreachable renders degraded card and does NOT claim stopped', (tester) async {
      const state = AdGuardState(
        routerId: 'router-1',
        connectionStatus: AdGuardConnectionStatus.apiUnreachable,
        capabilities: AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: false,
          isApiAuthenticated: false,
          isDnsOperational: false,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.unknown,
            adguardDnsPort: 53,
            dnsmasqPort: 53,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Unknown',
          ),
        ),
      );

      await tester.pumpWidget(buildCardTestWidget(routerId: 'router-1', adguardState: state));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_dns_status_card_degraded')), findsOneWidget);
      expect(find.byKey(const Key('agh_dns_card_status_badge')), findsOneWidget);
      expect(find.text('API Unreachable'), findsOneWidget);
      expect(find.text('Stopped / Inactive'), findsNothing);
      expect(find.text('AdGuard Home DNS engine is stopped. Standard router DNS is active.'), findsNothing);
      expect(find.byKey(const Key('agh_dns_card_description')), findsOneWidget);
      expect(find.text('AdGuard Home detected, but management API is unauthenticated or unreachable.'), findsOneWidget);
      expect(find.byKey(const Key('agh_dns_card_manage_button')), findsOneWidget);
    });

    testWidgets('State 2: Authentication required renders degraded card with auth badge and does NOT claim stopped', (tester) async {
      const state = AdGuardState(
        routerId: 'router-1',
        connectionStatus: AdGuardConnectionStatus.authRequired,
        capabilities: AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: true,
          isApiAuthenticated: false,
          isDnsOperational: false,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.unknown,
            adguardDnsPort: 53,
            dnsmasqPort: 53,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Unknown',
          ),
        ),
      );

      await tester.pumpWidget(buildCardTestWidget(routerId: 'router-1', adguardState: state));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_dns_status_card_degraded')), findsOneWidget);
      expect(find.text('Authentication Required'), findsOneWidget);
      expect(find.text('Stopped / Inactive'), findsNothing);
      expect(find.byKey(const Key('agh_dns_card_description')), findsOneWidget);
    });

    testWidgets('State 3: Authenticated but DNS not operational renders DNS Not Operational when service is running', (tester) async {
      const state = AdGuardState(
        routerId: 'router-1',
        connectionStatus: AdGuardConnectionStatus.authenticated,
        status: AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        ),
        capabilities: AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: true,
          isApiAuthenticated: true,
          isDnsOperational: false, // DNS not operational
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.standalone,
            adguardDnsPort: 5353,
            dnsmasqPort: 53,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Standalone',
          ),
        ),
      );

      await tester.pumpWidget(buildCardTestWidget(routerId: 'router-1', adguardState: state));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_dns_status_card_dns_not_operational')), findsOneWidget);
      expect(find.text('DNS Not Operational'), findsOneWidget);
      expect(find.text('Stopped / Inactive'), findsNothing);
      expect(find.text('AdGuard Home API is connected, but DNS engine is not operational.'), findsOneWidget);
      expect(find.byKey(const Key('agh_dns_card_manage_button')), findsOneWidget);
    });

    testWidgets('State 3: Explicit running == false renders Stopped / Inactive', (tester) async {
      const state = AdGuardState(
        routerId: 'router-1',
        connectionStatus: AdGuardConnectionStatus.authenticated,
        status: AdGuardStatus(
          version: 'v0.107.52',
          running: false, // EXPLICITLY STOPPED
          protectionState: AdGuardProtectionState.disabled,
          dnsAddresses: [],
          dnsPort: 53,
          httpPort: 3000,
        ),
        capabilities: AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: true,
          isApiAuthenticated: true,
          isDnsOperational: false,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.stopped,
            adguardDnsPort: 53,
            dnsmasqPort: 53,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Stopped',
          ),
        ),
      );

      await tester.pumpWidget(buildCardTestWidget(routerId: 'router-1', adguardState: state));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_dns_status_card_dns_not_operational')), findsOneWidget);
      expect(find.text('Stopped / Inactive'), findsOneWidget);
      expect(find.text('AdGuard Home DNS engine is stopped. Standard router DNS is active.'), findsOneWidget);
    });

    testWidgets('State 4: Fully operational renders active card with protection, metrics, and topology', (tester) async {
      const state = AdGuardState(
        routerId: 'router-1',
        connectionStatus: AdGuardConnectionStatus.authenticated,
        status: AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        ),
        stats: AdGuardStats(
          numDnsQueries: 14250,
          numBlockedFiltering: 3120,
          numReplacedSafebrowsing: 0,
          numReplacedSafesearch: 0,
          numReplacedParental: 0,
          avgProcessingTime: 0.0125, // 12.5 ms
          topQueriedDomains: [],
          topBlockedDomains: [],
          topClients: [],
          dnsQueriesTrend: [],
          blockedFilteringTrend: [],
          blockRatePercentage: 21.9,
        ),
        capabilities: AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: true,
          isApiAuthenticated: true,
          isDnsOperational: true,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.adguardPrimary,
            adguardDnsPort: 53,
            dnsmasqPort: 5353,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'AdGuard Home is primary DNS on port 53 (dnsmasq relocated to port 5353).',
          ),
        ),
        topology: AdGuardDnsTopology(
          mode: AdGuardTopologyMode.adguardPrimary,
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          forwarders: [],
          hasFirewallRedirect: false,
          isIpv6Supported: false,
          description: 'AdGuard Home is primary DNS on port 53 (dnsmasq relocated to port 5353).',
        ),
      );

      await tester.pumpWidget(buildCardTestWidget(routerId: 'router-1', adguardState: state));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_dns_status_card_operational')), findsOneWidget);
      expect(find.text('AdGuard Home DNS'), findsOneWidget);
      expect(find.text('Protection Enabled'), findsOneWidget);

      // Verify metrics
      expect(find.byKey(const Key('agh_dns_card_total_queries')), findsOneWidget);
      expect(find.text('14250'), findsOneWidget);
      expect(find.byKey(const Key('agh_dns_card_blocked_queries')), findsOneWidget);
      expect(find.text('3120'), findsOneWidget);
      expect(find.byKey(const Key('agh_dns_card_block_rate')), findsOneWidget);
      expect(find.text('21.9%'), findsOneWidget);
      expect(find.byKey(const Key('agh_dns_card_avg_latency')), findsOneWidget);
      expect(find.text('12.5 ms'), findsOneWidget);

      // Verify topology description and mandatory inference disclaimer
      expect(find.byKey(const Key('agh_dns_card_topology_description')), findsOneWidget);
      expect(find.text('AdGuard Home is primary DNS on port 53 (dnsmasq relocated to port 5353).'), findsOneWidget);
      expect(find.byKey(const Key('agh_dns_card_topology_disclaimer')), findsOneWidget);
      expect(find.text('Inferred from router configuration'), findsOneWidget);

      // Verify action button
      expect(find.byKey(const Key('agh_dns_card_manage_button')), findsOneWidget);
      expect(find.text('Manage AdGuard Home'), findsOneWidget);
    });

    testWidgets('Precedence check: When both API unreachable and DNS non-operational, State 2 takes precedence', (tester) async {
      // Both isApiReachable: false and isDnsOperational: false
      const state = AdGuardState(
        routerId: 'router-1',
        connectionStatus: AdGuardConnectionStatus.apiUnreachable,
        capabilities: AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: false, // Condition for State 2
          isApiAuthenticated: false,
          isDnsOperational: false, // Condition for State 3
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.unknown,
            adguardDnsPort: 53,
            dnsmasqPort: 53,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Unknown',
          ),
        ),
      );

      await tester.pumpWidget(buildCardTestWidget(routerId: 'router-1', adguardState: state));
      await tester.pumpAndSettle();

      // State 2 MUST win due to higher precedence
      expect(find.byKey(const Key('agh_dns_status_card_degraded')), findsOneWidget);
      expect(find.byKey(const Key('agh_dns_status_card_dns_not_operational')), findsNothing);
      expect(find.text('API Unreachable'), findsOneWidget);
      expect(find.text('DNS Not Operational'), findsNothing);
    });

    testWidgets('Precedence check: When isInstalled is false, State 1 overrides all other conditions', (tester) async {
      const state = AdGuardState(
        routerId: 'router-1',
        connectionStatus: AdGuardConnectionStatus.apiUnreachable,
        status: AdGuardStatus(
          version: 'v0.107.52',
          running: false,
          protectionState: AdGuardProtectionState.disabled,
          dnsAddresses: [],
          dnsPort: 53,
          httpPort: 3000,
        ),
        capabilities: AdGuardCapabilities(
          isInstalled: false, // State 1 condition
          isServiceManageable: false,
          isApiReachable: false,
          isApiAuthenticated: false,
          isDnsOperational: false,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.stopped,
            adguardDnsPort: 53,
            dnsmasqPort: 53,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Stopped',
          ),
        ),
      );

      await tester.pumpWidget(buildCardTestWidget(routerId: 'router-1', adguardState: state));
      await tester.pumpAndSettle();

      // Nothing rendered
      expect(find.byKey(const Key('agh_dns_status_card_degraded')), findsNothing);
      expect(find.byKey(const Key('agh_dns_status_card_dns_not_operational')), findsNothing);
      expect(find.byKey(const Key('agh_dns_status_card_operational')), findsNothing);
    });
  });

  group('AdGuardDnsStatusCard — Navigation & Interaction Tests', () {
    testWidgets('Tapping Manage AdGuard Home navigates to AdGuardHomeScreen', (tester) async {
      const state = AdGuardState(
        routerId: 'router-test',
        connectionStatus: AdGuardConnectionStatus.authenticated,
        status: AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['192.168.1.1'],
          dnsPort: 53,
          httpPort: 3000,
        ),
        capabilities: AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: true,
          isApiAuthenticated: true,
          isDnsOperational: true,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.adguardPrimary,
            adguardDnsPort: 53,
            dnsmasqPort: 5353,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Primary',
          ),
        ),
      );

      await tester.pumpWidget(buildCardTestWidget(routerId: 'router-test', adguardState: state));
      await tester.pumpAndSettle();

      final manageBtn = find.byKey(const Key('agh_dns_card_manage_button'));
      expect(manageBtn, findsOneWidget);

      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(find.byType(AdGuardHomeScreen), findsOneWidget);
    });
  });

  group('AdGuardDnsStatusCard — Router Isolation & Switching', () {
    testWidgets('Independent router IDs maintain strictly isolated status card states', (tester) async {
      const stateA = AdGuardState(
        routerId: 'router-A',
        connectionStatus: AdGuardConnectionStatus.authenticated,
        capabilities: AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: true,
          isApiAuthenticated: true,
          isDnsOperational: true,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.adguardPrimary,
            adguardDnsPort: 53,
            dnsmasqPort: 5353,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Primary',
          ),
        ),
      );

      const stateB = AdGuardState(
        routerId: 'router-B',
        capabilities: AdGuardCapabilities(
          isInstalled: false, // Not installed on Router B
          isServiceManageable: false,
          isApiReachable: false,
          isApiAuthenticated: false,
          isDnsOperational: false,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.unknown,
            adguardDnsPort: 53,
            dnsmasqPort: 53,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Unknown',
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adguardControllerProvider('router-A').overrideWith(
              (ref) => TestAdGuardController(ref, 'router-A', initialState: stateA),
            ),
            adguardControllerProvider('router-B').overrideWith(
              (ref) => TestAdGuardController(ref, 'router-B', initialState: stateB),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  AdGuardDnsStatusCard(key: Key('card_A'), routerId: 'router-A'),
                  AdGuardDnsStatusCard(key: Key('card_B'), routerId: 'router-B'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card A renders operational status
      expect(find.descendant(of: find.byKey(const Key('card_A')), matching: find.byKey(const Key('agh_dns_status_card_operational'))), findsOneWidget);
      // Card B renders SizedBox.shrink()
      expect(find.descendant(of: find.byKey(const Key('card_B')), matching: find.byKey(const Key('agh_dns_status_card_operational'))), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('card_B')), matching: find.byKey(const Key('agh_dns_status_card_degraded'))), findsNothing);
    });
  });

  group('AdGuardDnsStatusCard — Localization Parity', () {
    testWidgets('All new localization strings resolve without key fallback in all 9 supported locales', (tester) async {
      final supportedCodes = ['en', 'de', 'es', 'fr', 'id', 'pt', 'ru', 'zh'];

      for (final code in supportedCodes) {
        final locale = Locale(code);
        final l10n = await AppLocalizations.delegate.load(locale);

        expect(l10n.aghManageAdGuardHome.isNotEmpty, isTrue, reason: 'Failed for $code');
        expect(l10n.aghDnsCardApiUnreachableDesc.isNotEmpty, isTrue, reason: 'Failed for $code');
        expect(l10n.aghAuthRequiredBadge.isNotEmpty, isTrue, reason: 'Failed for $code');
        expect(l10n.aghApiUnreachableBadge.isNotEmpty, isTrue, reason: 'Failed for $code');
        expect(l10n.aghDnsCardStoppedBadge.isNotEmpty, isTrue, reason: 'Failed for $code');
        expect(l10n.aghDnsCardStoppedDesc.isNotEmpty, isTrue, reason: 'Failed for $code');
        expect(l10n.aghDnsEngineNotOperationalBadge.isNotEmpty, isTrue, reason: 'Failed for $code');
        expect(l10n.aghDnsEngineNotOperationalDesc.isNotEmpty, isTrue, reason: 'Failed for $code');
        expect(l10n.aghDnsCardTitle.isNotEmpty, isTrue, reason: 'Failed for $code');
        expect(l10n.aghDnsCardInferredDisclaimer.isNotEmpty, isTrue, reason: 'Failed for $code');
      }

      // pt_BR
      final l10nPtBr = await AppLocalizations.delegate.load(const Locale('pt', 'BR'));
      expect(l10nPtBr.aghManageAdGuardHome.isNotEmpty, isTrue);
      expect(l10nPtBr.aghDnsCardTitle.isNotEmpty, isTrue);
    });
  });

  group('DhcpDnsScreen Integration Tests', () {
    testWidgets('DhcpDnsScreen embeds AdGuardDnsStatusCard cleanly above DNS forwarders section', (tester) async {
      final appState = AppState.instance;
      final testRouter = model.Router(
        id: 'router-integration',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      );
      await appState.routerService?.addRouter(testRouter);
      await appState.routerService?.selectRouter(testRouter.id);

      const state = AdGuardState(
        routerId: 'router-integration',
        connectionStatus: AdGuardConnectionStatus.authenticated,
        capabilities: AdGuardCapabilities(
          isInstalled: true,
          isServiceManageable: true,
          isApiReachable: true,
          isApiAuthenticated: true,
          isDnsOperational: true,
          topology: AdGuardDnsTopology(
            mode: AdGuardTopologyMode.adguardPrimary,
            adguardDnsPort: 53,
            dnsmasqPort: 5353,
            forwarders: [],
            hasFirewallRedirect: false,
            isIpv6Supported: false,
            description: 'Primary',
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adguardControllerProvider('router-integration').overrideWith(
              (ref) => TestAdGuardController(ref, 'router-integration', initialState: state),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DhcpDnsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both AdGuard card and existing DNS forwarders section are present
      expect(find.byType(AdGuardDnsStatusCard), findsOneWidget);
      expect(find.byKey(const Key('agh_dns_status_card_operational')), findsOneWidget);
      expect(find.text('DNS Forwarders & Dnsmasq Config'), findsOneWidget);

      // Verify vertical ordering: AdGuardDnsStatusCard must appear BEFORE DNS Forwarders header
      final adguardTop = tester.getTopLeft(find.byType(AdGuardDnsStatusCard)).dy;
      final forwardersTop = tester.getTopLeft(find.text('DNS Forwarders & Dnsmasq Config')).dy;
      expect(adguardTop, lessThan(forwardersTop));
    });
  });
}
