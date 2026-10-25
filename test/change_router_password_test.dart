// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/services/auth_service.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/api_service.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/services/secure_storage_service.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/state/controllers/session_controller.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/widgets/change_router_password_dialog.dart';
import 'package:yala/widgets/password_strength_meter.dart';

class ControllableMockApiService extends MockApiService {
  SetPasswordRpcResponse setPasswordResponse =
      const SetPasswordRpcResponse.success();
  AuthResult? nextAuthResult;
  Map<String, AuthResult> authResultsByPassword = {};
  bool boardInfoSucceeds = true;
  int destroySessionCallCount = 0;

  @override
  Future<SetPasswordRpcResponse> setRouterPassword(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String username = 'root',
    required String newPassword,
  }) async {
    return setPasswordResponse;
  }

  @override
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    if (authResultsByPassword.containsKey(password)) {
      return authResultsByPassword[password]!;
    }
    if (nextAuthResult != null) {
      return nextAuthResult!;
    }
    return AuthResult.success('token_for_$password');
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
    if (object == 'session' && method == 'destroy') {
      destroySessionCallCount++;
      return [0, 'success'];
    }
    if (object == 'system' && method == 'board') {
      if (!boardInfoSucceeds) return [6, 'Access denied'];
      return [
        0,
        {'hostname': 'TestRouter', 'model': 'OpenWrt'},
      ];
    }
    return super.call(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }
}

class ControllableRealApiService extends RealApiService {
  Completer<AuthResult>? authCompleter;

  @override
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    if (authCompleter != null) {
      return authCompleter!.future;
    }
    return const AuthResult(status: AuthStatus.success, token: 'renewed_token');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Capability Detection Tests', () {
    test(
      'hasSetPasswordRpc returns true only when ubusMethods[luci] contains setPassword',
      () {
        final capsWithMethod = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: {'luci', 'system'},
          ubusMethods: {
            'luci': ['setPassword', 'getLEDs'],
          },
          probedAt: DateTime.now(),
        );
        expect(capsWithMethod.hasSetPasswordRpc, isTrue);

        // luci object present, but setPassword absent
        final capsWithoutMethod = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: {'luci', 'system'},
          ubusMethods: {
            'luci': ['getLEDs'],
          },
          probedAt: DateTime.now(),
        );
        expect(capsWithoutMethod.hasSetPasswordRpc, isFalse);

        // luci object missing entirely
        final capsNoLuci = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: {'system'},
          ubusMethods: {},
          probedAt: DateTime.now(),
        );
        expect(capsNoLuci.hasSetPasswordRpc, isFalse);
      },
    );

    test('RouterCapabilities.mock exposes hasSetPasswordRpc', () {
      final mockCaps = RouterCapabilities.mock();
      expect(mockCaps.hasSetPasswordRpc, isTrue);
    });
  });

  group('Auth Epoch & Stale Renewal Barrier Tests', () {
    test(
      'Auth epoch barrier suppresses in-flight renewals with old credentials',
      () async {
        final apiService = ControllableRealApiService();
        final authService = RealAuthService(apiService);

        // Prepopulate credentials in secure storage so renewal proceeds to authenticate()
        final secureStorage = SecureStorageService();
        await secureStorage.saveCredentials(
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'old_password',
          useHttps: false,
        );

        expect(authService.authEpoch, equals(0));

        // 1. Hold authenticate() in-flight with Completer
        final authCompleter = Completer<AuthResult>();
        apiService.authCompleter = authCompleter;

        // 2. Start renewal BEFORE transition (epoch = 0)
        final renewalFuture = apiService.onSessionRenew?.call(
          '192.168.1.1',
          false,
        );

        // Allow microtask to yield so renewal enters authenticate() and awaits future
        await Future<void>.delayed(Duration.zero);

        // 3. Advance epoch via password transition while renewal is suspended in-flight
        final epoch = authService.startPasswordTransition();
        expect(epoch, equals(1));
        expect(authService.authEpoch, equals(1));

        // 4. Resolve authenticate() with stale token after epoch has advanced
        authCompleter.complete(
          const AuthResult(status: AuthStatus.success, token: 'stale_token'),
        );

        final renewalToken = await renewalFuture;

        // 5. Verify stale renewal was detected, discarded, and returned null
        expect(renewalToken, isNull);
        expect(authService.sysauth, isNot(equals('stale_token')));

        // 6. Complete password transition advances epoch and publishes verified token
        authService.completePasswordTransition(
          newToken: 'new_verified_token',
          newPassword: 'new_secure_password',
          ipAddress: '192.168.1.1',
          useHttps: false,
        );
        expect(authService.authEpoch, equals(2));
        expect(authService.sysauth, equals('new_verified_token'));
      },
    );

    test(
      'Cancelling password transition advances epoch and disengages barrier',
      () {
        final apiService = ControllableRealApiService();
        final authService = RealAuthService(apiService);

        authService.startPasswordTransition();
        expect(authService.authEpoch, equals(1));

        authService.cancelPasswordTransition();
        expect(authService.authEpoch, equals(2));
      },
    );
  });

  group('10-State Password Transition State Machine Tests', () {
    late AppState appState;
    late ControllableMockApiService mockApi;

    setUp(() async {
      mockApi = ControllableMockApiService();
      appState = AppState.instance;
      await appState.setReviewerMode(true);
      appState.setApiServiceForTesting(mockApi);
    });

    test('Validation prechecks reject invalid input before RPC', () async {
      // 1. Current password mismatch
      final resultMismatch = await appState.changeRouterPassword(
        currentPassword: 'wrong_current_password',
        newPassword: 'new_password_123',
      );
      expect(resultMismatch.isSuccess, isFalse);
      expect(resultMismatch.status, equals(ChangePasswordStatus.failed));
      expect(resultMismatch.errorMessage, contains('does not match'));

      // 2. New password identical to current password
      final routerWithPass = appState.selectedRouter!.copyWith(
        password: 'CurrentPass123',
      );
      appState.routerService?.updateRouterInMemory(routerWithPass);

      final resultSame = await appState.changeRouterPassword(
        currentPassword: 'CurrentPass123',
        newPassword: 'CurrentPass123',
      );
      expect(resultSame.isSuccess, isFalse);
      expect(resultSame.status, equals(ChangePasswordStatus.failed));
      expect(resultSame.errorMessage, contains('must be different'));

      // 3. Empty new password
      final resultEmpty = await appState.changeRouterPassword(
        currentPassword: 'CurrentPass123',
        newPassword: '',
      );
      expect(resultEmpty.isSuccess, isFalse);
      expect(resultEmpty.status, equals(ChangePasswordStatus.failed));
      expect(resultEmpty.errorMessage, contains('cannot be empty'));
    });

    test('Happy Path: Complete 10-state transition succeeds', () async {
      final currentPass = appState.selectedRouter?.password ?? '';
      const newPass = 'ValidNewPass123!';

      final progressStates = <ChangePasswordStatus>[];

      final result = await appState.changeRouterPassword(
        currentPassword: currentPass,
        newPassword: newPass,
        onProgress: (status) => progressStates.add(status),
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, equals(ChangePasswordStatus.success));

      // Verify all transactional states were visited
      expect(
        progressStates,
        containsAllInOrder([
          ChangePasswordStatus.requesting,
          ChangePasswordStatus.reauthenticating,
          ChangePasswordStatus.verifying,
          ChangePasswordStatus.savingStorage,
        ]),
      );

      // Verify old session destroyed
      expect(mockApi.destroySessionCallCount, greaterThanOrEqualTo(1));

      // Verify router in memory updated with new password
      expect(appState.selectedRouter?.password, equals(newPass));
    });

    test(
      'Router RPC Rejection: Preserves credentials and aborts cleanly',
      () async {
        final currentPass = appState.selectedRouter?.password ?? '';
        const newPass = 'NewPasswordRejected123';

        mockApi.setPasswordResponse = const SetPasswordRpcResponse.rejected(
          'Access denied',
        );

        final result = await appState.changeRouterPassword(
          currentPassword: currentPass,
          newPassword: newPass,
        );

        expect(result.isSuccess, isFalse);
        expect(result.status, equals(ChangePasswordStatus.failed));
        expect(result.errorMessage, contains('Access denied'));

        // Original password preserved in memory
        expect(appState.selectedRouter?.password, equals(currentPass));
        // Old session was NOT destroyed because transition aborted at step 5
        expect(mockApi.destroySessionCallCount, equals(0));
      },
    );

    test(
      'Rejection Router-Side: New auth fails, old auth succeeds restores old session',
      () async {
        final currentPass = appState.selectedRouter?.password ?? '';
        const newPass = 'FailedRouterApply123';

        // setPassword RPC says success, but router didn't actually change passwd:
        mockApi.setPasswordResponse = const SetPasswordRpcResponse.success();
        mockApi.authResultsByPassword[newPass] = AuthResult.invalidCredentials(
          'Wrong password',
        );
        mockApi.authResultsByPassword[currentPass] = const AuthResult(
          status: AuthStatus.success,
          token: 'restored_old_token',
        );

        final result = await appState.changeRouterPassword(
          currentPassword: currentPass,
          newPassword: newPass,
        );

        expect(result.isSuccess, isFalse);
        expect(result.status, equals(ChangePasswordStatus.failed));
        expect(
          result.errorMessage,
          contains('Password change was not applied by router'),
        );

        // Original credentials preserved
        expect(appState.selectedRouter?.password, equals(currentPass));
      },
    );

    test(
      'Ambiguous Failure: Both auth attempts fail enters ambiguous state with zero credential leakage',
      () async {
        const currentPass = 'SecretCurrentPass123';
        const newPass = 'AmbiguousNetworkDrop123';

        final initialRouter = appState.selectedRouter!.copyWith(
          password: currentPass,
        );
        appState.routerService?.updateRouterInMemory(initialRouter);

        mockApi.setPasswordResponse = const SetPasswordRpcResponse.networkError(
          'Socket closed',
        );
        mockApi.authResultsByPassword[newPass] = AuthResult.unreachable(
          'Connection timeout',
        );
        mockApi.authResultsByPassword[currentPass] = AuthResult.unreachable(
          'Connection timeout',
        );

        final result = await appState.changeRouterPassword(
          currentPassword: currentPass,
          newPassword: newPass,
        );

        expect(result.isSuccess, isFalse);
        expect(result.status, equals(ChangePasswordStatus.ambiguous));
        expect(result.errorMessage, isNotNull);

        // Zero password leakage: neither old nor new password in error message
        expect(result.errorMessage, isNot(contains(newPass)));
        expect(result.errorMessage, isNot(contains(currentPass)));

        // Stored credentials strictly unchanged
        expect(appState.selectedRouter?.password, equals(currentPass));
      },
    );

    test(
      'retrySaveRouterPassword updates credentials and returns true',
      () async {
        final router = appState.selectedRouter!.copyWith(
          password: 'RetriedNewPassword123',
        );
        final ok = await appState.retrySaveRouterPassword(router);
        expect(ok, isTrue);
        expect(
          appState.selectedRouter?.password,
          equals('RetriedNewPassword123'),
        );
      },
    );
  });

  group('PasswordStrengthMeter Unit Tests', () {
    testWidgets('PasswordStrengthMeter calculates strength and renders bars', (
      tester,
    ) async {
      // 1. Password under 8 characters: renders SizedBox.shrink
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PasswordStrengthMeter(password: 'short')),
        ),
      );
      expect(find.byType(PasswordStrengthMeter), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // 2. Strong password: renders bars
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordStrengthMeter(password: 'MyStr0ng!P@ssword'),
          ),
        ),
      );
      expect(find.textContaining('Security Strength'), findsOneWidget);
    });
  });

  group('ChangeRouterPasswordDialog Widget Tests', () {
    testWidgets('Dialog renders form fields, toggles visibility, and submits', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ChangeRouterPasswordDialog()),
        ),
      );
      await tester.pumpAndSettle();

      // Verify elements
      expect(find.text('Change Router Password'), findsOneWidget);
      expect(find.text('Current Password'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm New Password'), findsOneWidget);

      // Submit button initially disabled (fields empty)
      final submitButtonFinder = find.widgetWithText(
        FilledButton,
        'Change Password',
      );
      expect(submitButtonFinder, findsOneWidget);
      final FilledButton initialButton = tester.widget(submitButtonFinder);
      expect(initialButton.onPressed, isNull);

      // Fill in mismatched passwords
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current Password'),
        'OldPass123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Password'),
        'NewPassword123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm New Password'),
        'DifferentPassword123!',
      );
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);
      final FilledButton mismatchButton = tester.widget(submitButtonFinder);
      expect(mismatchButton.onPressed, isNull);

      // Fill in weak password (< 8 chars): requires acknowledgement checkbox
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Password'),
        'abc',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm New Password'),
        'abc',
      );
      await tester.pumpAndSettle();

      expect(find.text('Proceed with weak password anyway'), findsOneWidget);
      final FilledButton weakButton = tester.widget(submitButtonFinder);
      expect(weakButton.onPressed, isNull);

      // Check acknowledgement
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final FilledButton weakAcknowledgedButton = tester.widget(
        submitButtonFinder,
      );
      expect(weakAcknowledgedButton.onPressed, isNotNull);
    });
  });
}
