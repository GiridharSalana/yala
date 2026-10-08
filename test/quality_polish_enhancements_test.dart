// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yala/screens/main_screen.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/widgets/luci_toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});

  group('Quality & Polish Enhancements Tests', () {
    setUp(() async {
      ActionRateLimiter.reset();
      final appState = AppState.instance;
      await appState.setReviewerMode(true);
      appState.markReviewerNoticeShown();
    });

    test('AppState routerBackOnline listener registration and dispatch', () {
      final appState = AppState.instance;
      bool callbackSuccess = false;
      int callbackCount = 0;

      void listener(bool success) {
        callbackSuccess = success;
        callbackCount++;
      }

      appState.addRouterBackOnlineListener(listener);
      // Adding duplicate should not register twice
      appState.addRouterBackOnlineListener(listener);

      // Trigger legacy callback and listeners via simulated internal dispatch
      bool legacyCalled = false;
      appState.onRouterBackOnline = () {
        legacyCalled = true;
      };

      // Dispatch test
      appState.notifyRouterBackOnlineForTesting(success: true);

      expect(callbackCount, equals(1));
      expect(callbackSuccess, isTrue);
      expect(legacyCalled, isTrue);

      // Unregister listener
      appState.removeRouterBackOnlineListener(listener);
      appState.notifyRouterBackOnlineForTesting(success: false);

      // Count should still be 1 (listener was removed)
      expect(callbackCount, equals(1));
    });

    test('ActionRateLimiter blocks rapid subsequent calls within cooldown', () {
      const key = 'test_action';
      ActionRateLimiter.reset(key);

      // First call should not be rate-limited
      expect(
        ActionRateLimiter.isRateLimited(
          key,
          cooldown: const Duration(milliseconds: 500),
        ),
        isFalse,
      );

      // Immediate second call should be rate-limited
      expect(
        ActionRateLimiter.isRateLimited(
          key,
          cooldown: const Duration(milliseconds: 500),
        ),
        isTrue,
      );
      expect(ActionRateLimiter.getSuppressionCount(key), equals(1));

      // Reset allows it again
      ActionRateLimiter.reset(key);
      expect(
        ActionRateLimiter.isRateLimited(
          key,
          cooldown: const Duration(milliseconds: 500),
        ),
        isFalse,
      );
    });

    testWidgets(
      'MainScreen displays connectivity banner when reconnecting or disconnected',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.setConnectionStatusForTesting(
          RouterConnectionStatus.reconnecting,
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MainScreen(initialTab: 0)),
          ),
        );
        await tester.pumpAndSettle();

        // Banner should be visible with reconnecting text
        expect(find.text('Reconnecting to router...'), findsOneWidget);

        // Switch to disconnected
        appState.setConnectionStatusForTesting(
          RouterConnectionStatus.disconnected,
        );
        await tester.pumpAndSettle();

        // Banner should be visible with disconnected text and retry button
        expect(find.text('Router disconnected'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        // Switch to connected
        appState.setConnectionStatusForTesting(
          RouterConnectionStatus.connected,
        );
        await tester.pumpAndSettle();

        // Banner should disappear
        expect(find.text('Router disconnected'), findsNothing);
        expect(find.text('Reconnecting to router...'), findsNothing);
      },
    );
  });
}
