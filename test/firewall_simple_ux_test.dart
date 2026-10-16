// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/models/client.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/modules/firewall_security/models/firewall_info.dart';
import 'package:yala/modules/firewall_security/screens/firewall_security_screen.dart';
import 'package:yala/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yala/modules/firewall_security/widgets/add_port_forward_dialog.dart';
import 'package:yala/modules/firewall_security/widgets/block_incoming_traffic_dialog.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/state/app_state.dart';

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

Map<String, dynamic> _buildSampleUciFirewall({
  List<Map<String, dynamic>>? redirects,
  List<Map<String, dynamic>>? rules,
}) {
  return {
    'defaults': {
      '.type': 'defaults',
      'syn_flood': '1',
      'input': 'ACCEPT',
      'output': 'ACCEPT',
      'forward': 'REJECT',
    },
    'zone_lan': {
      '.type': 'zone',
      'name': 'lan',
      'input': 'ACCEPT',
      'output': 'ACCEPT',
      'forward': 'ACCEPT',
      'network': ['lan'],
      'masq': '0',
    },
    'zone_wan': {
      '.type': 'zone',
      'name': 'wan',
      'input': 'REJECT',
      'output': 'ACCEPT',
      'forward': 'REJECT',
      'masq': '1',
      'mtu_fix': '1',
      'network': ['wan', 'wan6'],
    },
    'fwd_lan_wan': {
      '.type': 'forwarding',
      'src': 'lan',
      'dest': 'wan',
    },
    if (redirects != null)
      for (int i = 0; i < redirects.length; i++)
        'redirect_$i': {
          '.type': 'redirect',
          ...redirects[i],
        },
    if (rules != null)
      for (int i = 0; i < rules.length; i++)
        'rule_$i': {
          '.type': 'rule',
          ...rules[i],
        },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (MethodCall methodCall) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          if (methodCall.method == 'write') {
            return null;
          }
          return null;
        });
  });

  late AppState appState;

  setUp(() async {
    appState = AppState.instance;
    await appState.setReviewerMode(true);
    appState.setApiServiceForTesting(MockApiService());
  });

  tearDown(() {
    appState.clearFreeDiskSpaceForTesting();
  });

  group('FirewallSecurityScreen Simple UX Tests', () {
    testWidgets('1. Displays Protection Status card, Quick Actions, and empty states when no rules', (tester) async {
      final uci = _buildSampleUciFirewall();
      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const FirewallSecurityScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Protection status
      expect(find.text('Firewall Shield'), findsOneWidget);
      expect(find.textContaining('Defending your home network'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);

      // 2. Quick Actions
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Open a Port'), findsOneWidget);
      expect(find.text('Block an Incoming Connection'), findsOneWidget);

      // 3. Confirm redundant separate sections are removed
      expect(find.text('Active Port Forwards'), findsNothing);
      expect(find.text('Active Security Rules'), findsNothing);

      // 4. Advanced Settings and collapsible cards are present
      await tester.scrollUntilVisible(
        find.text('Advanced Settings'),
        100.0,
      );
      expect(find.text('Advanced Settings'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Port Forwards'),
        100.0,
      );
      expect(find.textContaining('Port Forwards'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Custom Firewall Rules'),
        100.0,
      );
      expect(find.textContaining('Custom Firewall Rules'), findsOneWidget);
    });

    testWidgets('2. Displays Port Forwards with resolved client device name inside collapsible card', (tester) async {
      final uci = _buildSampleUciFirewall(
        redirects: [
          {
            '.name': 'redirect_plex',
            'name': 'Plex Server',
            'src': 'wan',
            'src_dport': '32400',
            'dest': 'lan',
            'dest_ip': '192.168.1.150',
            'dest_port': '32400',
            'proto': 'tcp',
            'target': 'DNAT',
            'enabled': '1',
          },
        ],
      );

      final client = Client(
        ipAddress: '192.168.1.150',
        macAddress: 'AA:BB:CC:DD:EE:01',
        hostname: 'Living Room PC',
      );

      appState.clients = [client];
      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const FirewallSecurityScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Expand Port Forwards collapsible card
      await tester.scrollUntilVisible(
        find.textContaining('Port Forwards'),
        100.0,
      );
      await tester.ensureVisible(find.textContaining('Port Forwards'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Port Forwards'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Plex Server'),
        100.0,
      );
      expect(find.text('Plex Server'), findsOneWidget);
      // Resolved device name in subtitle
      expect(
        find.textContaining('Living Room PC (192.168.1.150:32400)'),
        findsOneWidget,
      );
    });

    testWidgets('3. Displays Custom Firewall Rules list with details inside collapsible card', (tester) async {
      final uci = _buildSampleUciFirewall(
        rules: [
          {
            '.name': 'rule_block_telnet',
            'name': 'Block Telnet',
            'src': 'wan',
            'dest': 'lan',
            'dest_port': '23',
            'proto': 'tcp',
            'target': 'DROP',
            'enabled': '1',
          },
        ],
      );

      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const FirewallSecurityScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Expand Custom Firewall Rules collapsible card
      await tester.scrollUntilVisible(
        find.textContaining('Custom Firewall Rules'),
        100.0,
      );
      await tester.ensureVisible(find.textContaining('Custom Firewall Rules'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Custom Firewall Rules'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Block Telnet'),
        100.0,
      );
      expect(find.text('Block Telnet'), findsOneWidget);
      expect(find.text('DROP'), findsOneWidget);
      expect(find.textContaining('WAN ➔ LAN'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
    });
  });

  group('AddPortForwardDialog Tests', () {
    testWidgets('4. Preset selector includes Plex, Minecraft, Web Server, Custom, and excludes SSH', (tester) async {
      final uci = _buildSampleUciFirewall();
      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const AddPortForwardDialog(),
        ),
      );
      await tester.pumpAndSettle();

      // Open presets dropdown
      await tester.tap(find.text('Plex Media Server'));
      await tester.pumpAndSettle();

      expect(find.text('Minecraft Server'), findsOneWidget);
      expect(find.text('Web Server (HTTP/HTTPS)'), findsOneWidget);
      expect(find.text('Custom Service'), findsOneWidget);

      // Invariant: SSH (Port 22) is NOT in presets
      expect(find.textContaining('SSH'), findsNothing);
      expect(find.textContaining('Dropbear'), findsNothing);
    });

    testWidgets('5. Selecting Web Server preset displays warning banner and opens 80 and 443', (tester) async {
      final uci = _buildSampleUciFirewall();
      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const AddPortForwardDialog(),
        ),
      );
      await tester.pumpAndSettle();

      // Select Web Server preset
      await tester.tap(find.text('Plex Media Server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Web Server (HTTP/HTTPS)'));
      await tester.pumpAndSettle();

      // Verify security warning banner
      expect(
        find.text('This will make your web server accessible to anyone on the Internet.'),
        findsOneWidget,
      );
      expect(
        find.text('Opens TCP ports 80 and 443'),
        findsOneWidget,
      );
    });

    testWidgets('6. Preflight conflict detects already in-use external port', (tester) async {
      // Existing rule using port 32400
      final uci = _buildSampleUciFirewall(
        redirects: [
          {
            '.name': 'redirect_plex',
            'name': 'Existing Plex',
            'src': 'wan',
            'src_dport': '32400',
            'dest': 'lan',
            'dest_ip': '192.168.1.150',
            'dest_port': '32400',
            'proto': 'tcp',
            'target': 'DNAT',
            'enabled': '1',
          },
        ],
      );

      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );
      appState.clients = [
        Client(
          ipAddress: '192.168.1.150',
          macAddress: 'AA:BB:CC:DD:EE:01',
          hostname: 'PC',
        ),
      ];

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const AddPortForwardDialog(),
        ),
      );
      await tester.pumpAndSettle();

      // Attempt to submit Plex preset (port 32400)
      final submitBtn = find.widgetWithText(ElevatedButton, 'Open a Port');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('This port is already being used by another rule.'),
        findsOneWidget,
      );
    });

    testWidgets('7. Safety guard blocks exposing router management ports externally', (tester) async {
      final uci = _buildSampleUciFirewall();
      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const AddPortForwardDialog(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to custom preset
      await tester.tap(find.text('Plex Media Server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom Service'));
      await tester.pumpAndSettle();

      // Fill custom inputs: target port 22 and router IP 192.168.1.1
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Service Name'),
        'SSH Expose',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'External Port'),
        '22',
      );
      await tester.tap(find.text('Enter IP address manually'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Internal Device IP'),
        '192.168.1.1',
      );
      await tester.pumpAndSettle();

      final submitBtn = find.widgetWithText(ElevatedButton, 'Open a Port');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This port is reserved for router administration. Exposing it externally is not permitted.',
        ),
        findsOneWidget,
      );
    });
  });

  group('BlockIncomingTrafficDialog Tests', () {
    testWidgets('8. Preflight detects already-blocked incoming traffic on default WAN reject policy', (tester) async {
      final uci = _buildSampleUciFirewall();
      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const BlockIncomingTrafficDialog(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter external IP
      await tester.enterText(find.byType(TextFormField).first, '198.51.100.55');
      await tester.pumpAndSettle();

      expect(find.text('Already Blocked'), findsOneWidget);
      expect(
        find.text('This connection is already blocked by your router\'s default firewall protection.'),
        findsOneWidget,
      );
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Create Explicit Rule Anyway'), findsOneWidget);
    });

    testWidgets('9. Preflight detects currently-allowed incoming traffic when port forward exists', (tester) async {
      // WAN forward active for port 8080
      final uci = _buildSampleUciFirewall(
        redirects: [
          {
            '.name': 'redirect_camera',
            'name': 'Camera Stream',
            'src': 'wan',
            'src_dport': '8080',
            'dest': 'lan',
            'dest_ip': '192.168.1.80',
            'dest_port': '8080',
            'proto': 'tcp',
            'target': 'DNAT',
            'enabled': '1',
          },
        ],
      );

      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const BlockIncomingTrafficDialog(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Port
      await tester.tap(find.byIcon(Icons.numbers_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Port or Service'),
        '8080',
      );
      await tester.pumpAndSettle();

      expect(find.text('Currently Allowed'), findsOneWidget);
      expect(
        find.text(
          'This connection is currently permitted through your router by an active rule or port forward. Blocking it will override existing access.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'Block Connection'), findsOneWidget);
    });

    testWidgets('10. Preflight returns unableToDetermine when internal destination zone cannot be identified', (tester) async {
      // Zone topology with NO lan and NO forwardings
      final uci = {
        'defaults': {
          '.type': 'defaults',
          'syn_flood': '1',
          'input': 'ACCEPT',
          'output': 'ACCEPT',
          'forward': 'REJECT',
        },
        'zone_wan': {
          '.type': 'zone',
          'name': 'wan',
          'input': 'REJECT',
          'output': 'ACCEPT',
          'forward': 'REJECT',
          'masq': '1',
          'network': ['wan'],
        },
      };

      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const BlockIncomingTrafficDialog(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Port
      await tester.tap(find.byIcon(Icons.numbers_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Port or Service'),
        '9000',
      );
      await tester.pumpAndSettle();

      expect(find.text('Unable to Determine'), findsOneWidget);
      // Button must be disabled in unableToDetermine state
      final blockBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Block Connection'),
      );
      expect(blockBtn.onPressed, isNull);
    });
  });

  group('Topology & Semantics Unit Tests for Milestone 2', () {
    test('11. FirewallOverview primaryLanZoneName extracts internal zone correctly', () {
      final uci = _buildSampleUciFirewall();
      final overview = FirewallOverview.fromUciData(
        uci,
        backend: FirewallBackend.fw4,
      );

      expect(overview.primaryLanZoneName, equals('lan'));
    });

    test('12. Incoming destination port semantics: compared against destPort and redirect srcPort', () {
      final uci = _buildSampleUciFirewall(
        redirects: [
          {
            '.name': 'redirect_http',
            'name': 'HTTP',
            'src': 'wan',
            'src_dport': '80',
            'dest': 'lan',
            'dest_ip': '192.168.1.10',
            'dest_port': '80',
            'proto': 'tcp',
            'target': 'DNAT',
            'enabled': '1',
          },
        ],
      );
      final overview = FirewallOverview.fromUciData(
        uci,
        backend: FirewallBackend.fw4,
      );

      // Preflight for incoming destination port 80 matches the redirect srcPort (80)
      final resAllowed = FirewallValidator.evaluateIncomingTrafficPreflight(
        overview: overview,
        incomingPort: '80',
        proto: 'tcp',
      );
      expect(resAllowed.isCurrentlyAllowed, isTrue);

      // Preflight for incoming destination port 8080 does not match redirect and is alreadyBlocked by default policy
      final resBlocked = FirewallValidator.evaluateIncomingTrafficPreflight(
        overview: overview,
        incomingPort: '8080',
        proto: 'tcp',
      );
      expect(resBlocked.isAlreadyBlocked, isTrue);
    });
  });

  group('Responsive Custom Firewall Rules Card Tests', () {
    testWidgets('13. Narrow screen (320dp width): Zero overflow, single line ellipsis, structured secondary row', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final uci = _buildSampleUciFirewall(
        rules: [
          {
            '.name': 'rule_long_name',
            'name': 'Extremely Long Rule Name That Would Previously Wrap Character By Character',
            'src': 'wan',
            'dest': 'lan',
            'dest_port': '8080',
            'proto': 'tcp',
            'target': 'ACCEPT',
            'enabled': '1',
          },
          {
            '.name': 'rule_block_udp',
            'name': 'Block Malicious UDP Scans',
            'src': 'wan',
            'dest': 'lan',
            'dest_port': '5060',
            'proto': 'udp',
            'target': 'DROP',
            'enabled': '0',
          },
        ],
      );

      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const FirewallSecurityScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Expand Custom Firewall Rules collapsible card
      await tester.scrollUntilVisible(
        find.textContaining('Custom Firewall Rules'),
        100.0,
      );
      await tester.ensureVisible(find.textContaining('Custom Firewall Rules'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Custom Firewall Rules'));
      await tester.pumpAndSettle();

      // Verify long rule name is present
      await tester.scrollUntilVisible(
        find.textContaining('Extremely Long Rule Name'),
        100.0,
      );
      expect(find.textContaining('Extremely Long Rule Name'), findsOneWidget);

      // Verify single line with ellipsis
      final nameFinder = find.byWidgetPredicate(
        (w) => w is Text &&
            w.data != null &&
            w.data!.contains('Extremely Long Rule Name') &&
            w.maxLines == 1 &&
            w.overflow == TextOverflow.ellipsis,
      );
      expect(nameFinder, findsOneWidget);

      // Target badges are rendered
      expect(find.text('ACCEPT'), findsWidgets);

      // Reorder buttons, edit, delete buttons are rendered on secondary row
      expect(find.byTooltip('Move up'), findsWidgets);
      expect(find.byTooltip('Move down'), findsWidgets);
      expect(find.byTooltip('Edit rule'), findsWidgets);
      expect(find.byTooltip('Delete rule'), findsWidgets);

      // Verify reorder up is disabled for the first rule (index 0)
      final firstUpBtn = tester.widget<IconButton>(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Move up').first,
      );
      expect(firstUpBtn.onPressed, isNull);

      // Verify reorder down is disabled for the second/last rule (index 1)
      final lastDownBtn = tester.widget<IconButton>(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Move down').last,
      );
      expect(lastDownBtn.onPressed, isNull);
    });

    testWidgets('14. Wide screen (800dp width): Zero overflow, inline layout with status labels', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final uci = _buildSampleUciFirewall(
        rules: [
          {
            '.name': 'rule_long_name',
            'name': 'Extremely Long Rule Name That Would Previously Wrap Character By Character',
            'src': 'wan',
            'dest': 'lan',
            'dest_port': '8080',
            'proto': 'tcp',
            'target': 'ACCEPT',
            'enabled': '1',
          },
          {
            '.name': 'rule_block_udp',
            'name': 'Block Malicious UDP Scans',
            'src': 'wan',
            'dest': 'lan',
            'dest_port': '5060',
            'proto': 'udp',
            'target': 'DROP',
            'enabled': '0',
          },
        ],
      );

      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const FirewallSecurityScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Expand Custom Firewall Rules
      await tester.scrollUntilVisible(
        find.textContaining('Custom Firewall Rules'),
        100.0,
      );
      await tester.ensureVisible(find.textContaining('Custom Firewall Rules'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Custom Firewall Rules'));
      await tester.pumpAndSettle();

      // Both rules are visible
      expect(find.textContaining('Extremely Long Rule Name'), findsOneWidget);
      expect(find.text('Block Malicious UDP Scans'), findsOneWidget);
      expect(find.text('ACCEPT'), findsWidgets);
      expect(find.text('DROP'), findsOneWidget);

      // Status labels 'Enabled' and 'Disabled' are rendered
      expect(find.text('Enabled'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('15. Switch toggle updates staged state and displays STAGED badge', (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final uci = _buildSampleUciFirewall(
        rules: [
          {
            '.name': 'rule_long_name',
            'name': 'Long Rule Name',
            'src': 'wan',
            'dest': 'lan',
            'dest_port': '8080',
            'proto': 'tcp',
            'target': 'ACCEPT',
            'enabled': '1',
          },
        ],
      );

      appState.setDashboardDataForTesting({
        'uciFirewallConfig': uci,
      });
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [
            appStateProvider.overrideWith((ref) => appState),
          ],
          child: const FirewallSecurityScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Expand Custom Firewall Rules
      await tester.scrollUntilVisible(
        find.textContaining('Custom Firewall Rules'),
        100.0,
      );
      await tester.ensureVisible(find.textContaining('Custom Firewall Rules'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Custom Firewall Rules'));
      await tester.pumpAndSettle();

      // Initially no STAGED badge
      expect(find.text('STAGED'), findsNothing);

      // Toggle custom rule switch (last switch on page)
      final switches = find.byType(Switch);
      expect(switches, findsWidgets);
      await tester.tap(switches.last);
      await tester.pumpAndSettle();

      // STAGED badge appears
      expect(find.text('STAGED'), findsOneWidget);
      expect(find.textContaining('Original: ENABLED'), findsOneWidget);
    });
  });
}
