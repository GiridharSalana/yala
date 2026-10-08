// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/state/controllers/network_actions_controller.dart';
import 'package:yala/widgets/edit_hostname_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('RFC 1123 Hostname Validation Edge Cases', () {
    test('Valid hostnames pass RFC 1123 validator', () {
      expect(NetworkActionsController.validateHostname('OpenWrt'), isNull);
      expect(NetworkActionsController.validateHostname('my-router'), isNull);
      expect(NetworkActionsController.validateHostname('router-1'), isNull);
      expect(NetworkActionsController.validateHostname('router1'), isNull);
      expect(NetworkActionsController.validateHostname('a'), isNull);
      expect(NetworkActionsController.validateHostname('0'), isNull);
      expect(NetworkActionsController.validateHostname('wrt3200acm-01'), isNull);
      expect(NetworkActionsController.validateHostname('a' * 63), isNull);
      expect(NetworkActionsController.validateHostname('  OpenWrt  '), isNull); // trimmed
    });

    test('Empty or whitespace-only hostnames fail with empty reason', () {
      expect(NetworkActionsController.validateHostname(null), equals('empty'));
      expect(NetworkActionsController.validateHostname(''), equals('empty'));
      expect(NetworkActionsController.validateHostname('   '), equals('empty'));
      expect(NetworkActionsController.validateHostname('\t\n'), equals('empty'));
    });

    test('Hostnames longer than 63 characters fail with too_long reason', () {
      expect(NetworkActionsController.validateHostname('a' * 64), equals('too_long'));
      expect(NetworkActionsController.validateHostname('router-' * 15), equals('too_long'));
    });

    test('Hostnames with leading or trailing hyphens fail with hyphen_edge reason', () {
      expect(NetworkActionsController.validateHostname('-openwrt'), equals('hyphen_edge'));
      expect(NetworkActionsController.validateHostname('openwrt-'), equals('hyphen_edge'));
      expect(NetworkActionsController.validateHostname('-openwrt-'), equals('hyphen_edge'));
      expect(NetworkActionsController.validateHostname('-'), equals('hyphen_edge'));
    });

    test('Hostnames with invalid characters fail with invalid_characters reason', () {
      expect(NetworkActionsController.validateHostname('open_wrt'), equals('invalid_characters'));
      expect(NetworkActionsController.validateHostname('open.wrt'), equals('invalid_characters'));
      expect(NetworkActionsController.validateHostname('open wrt'), equals('invalid_characters'));
      expect(NetworkActionsController.validateHostname('router@home'), equals('invalid_characters'));
      expect(NetworkActionsController.validateHostname('router#1'), equals('invalid_characters'));
      expect(NetworkActionsController.validateHostname('router!'), equals('invalid_characters'));
      expect(NetworkActionsController.validateHostname('router:80'), equals('invalid_characters'));
      expect(NetworkActionsController.validateHostname('router/lan'), equals('invalid_characters'));
    });
  });

  group('MockApiService Hostname Updates', () {
    test('setRouterHostname updates mock system.board hostname', () async {
      final mockApi = MockApiService();

      // Check default board info
      final boardRes = await mockApi.callSimple('system', 'board', {});
      expect(boardRes[0], equals(0));
      expect(boardRes[1]['hostname'], equals('MockRouter'));

      // Update hostname
      final success = await mockApi.setRouterHostname(
        '192.168.1.1',
        'mock_token',
        false,
        'CustomRouterHost',
      );
      expect(success, isTrue);

      // Verify updated board info
      final updatedRes = await mockApi.callSimple('system', 'board', {});
      expect(updatedRes[0], equals(0));
      expect(updatedRes[1]['hostname'], equals('CustomRouterHost'));

      // Reset mock state
      MockApiService.resetMockState();
      final resetRes = await mockApi.callSimple('system', 'board', {});
      expect(resetRes[1]['hostname'], equals('MockRouter'));
    });
  });

  group('AppState updateRouterHostname in Reviewer Mode', () {
    test('Updates in-memory hostname state cleanly', () async {
      final appState = AppState.instance;
      await appState.setReviewerMode(true);

      // Verify initial reviewer router
      expect(appState.reviewerModeEnabled, isTrue);

      final ok = await appState.updateRouterHostname('Reviewer-Router-01');
      expect(ok, isTrue);

      // Last known hostname updated
      expect(appState.selectedRouter?.lastKnownHostname, equals('Reviewer-Router-01'));

      // Unchanged hostname returns true without error
      final unchangedOk = await appState.updateRouterHostname('Reviewer-Router-01');
      expect(unchangedOk, isTrue);

      // Cleanup
      await appState.setReviewerMode(false);
      await appState.logout();
    });
  });

  group('EditHostnameDialog Widget Tests', () {
    testWidgets('Renders dialog with current hostname and enforces live validation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const EditHostnameDialog(
                    currentHostname: 'Initial-Host',
                  ),
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog elements
      expect(find.text('Edit Router Hostname'), findsOneWidget);
      expect(find.text('Initial-Host'), findsNWidgets(2)); // in chip and in TextFormField

      // Enter empty hostname -> shows error
      final textFormField = find.byType(TextFormField);
      await tester.enterText(textFormField, '');
      await tester.pumpAndSettle();
      expect(find.text('Hostname cannot be empty'), findsOneWidget);

      // Save button should be disabled when invalid
      final saveButton = find.widgetWithText(ElevatedButton, 'Save');
      expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNull);

      // Enter hostname with invalid edge hyphen
      await tester.enterText(textFormField, 'bad-name-');
      await tester.pumpAndSettle();
      expect(find.text('Hostname cannot start or end with a hyphen'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNull);

      // Enter valid hostname
      await tester.enterText(textFormField, 'good-host-1');
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNotNull);
    });
  });
}
