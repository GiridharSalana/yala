// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/flush_dns_result.dart';

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
          if (methodCall.method == 'write') {
            return null;
          }
          return null;
        });
  });

  group('Toast Accuracy & Resilience Tests', () {
    test(
      'isUciSuccessful correctly identifies success and failure results',
      () {
        final api = ApiService();

        // Null or empty
        expect(api.isUciSuccessful(null), isFalse);

        // JSON-RPC error field
        expect(
          api.isUciSuccessful({
            'error': {'code': -32000, 'message': 'Access denied'},
          }),
          isFalse,
        );
        expect(api.isUciSuccessful({'error': 'UCI parse error'}), isFalse);

        // Array return codes: [0] = success, [1] = failure
        expect(api.isUciSuccessful([0]), isTrue);
        expect(api.isUciSuccessful([0, 'OK']), isTrue);
        expect(api.isUciSuccessful([1]), isFalse);
        expect(api.isUciSuccessful([4, 'Entry not found']), isFalse);

        // Map return codes
        expect(api.isUciSuccessful({'code': 0}), isTrue);
        expect(api.isUciSuccessful({'rc': 0}), isTrue);
        expect(api.isUciSuccessful({'code': 1}), isFalse);
        expect(api.isUciSuccessful({'rc': 255}), isFalse);

        // Map with error key and no code
        expect(
          api.isUciSuccessful({
            'result': 'failed',
            'error': 'Ubus call timed out',
          }),
          isFalse,
        );
      },
    );

    test(
      'isExpectedServiceDisconnect distinguishes expected severed connections from real failures',
      () {
        final api = ApiService();

        // Network-critical service with socket connection reset / abort
        const socketResetErr = SocketException('Connection reset by peer');
        const brokenPipeErr = SocketException('Broken pipe');
        const httpClosedErr = HttpException(
          'Connection closed before full header was received',
        );
        final dioConnErr = DioException(
          requestOptions: RequestOptions(path: '/ubus'),
          type: DioExceptionType.connectionError,
          message: 'SocketException: OS Error: Connection reset by peer',
        );

        // Critical services
        expect(
          api.isExpectedServiceDisconnect('network', socketResetErr),
          isTrue,
        );
        expect(
          api.isExpectedServiceDisconnect('uhttpd', brokenPipeErr),
          isTrue,
        );
        expect(
          api.isExpectedServiceDisconnect('firewall', httpClosedErr),
          isTrue,
        );
        expect(api.isExpectedServiceDisconnect('dropbear', dioConnErr), isTrue);

        // Non-critical services: disconnecting unexpectedly should NOT be treated as success
        expect(
          api.isExpectedServiceDisconnect('samba', socketResetErr),
          isFalse,
        );
        expect(api.isExpectedServiceDisconnect('sqm', socketResetErr), isFalse);
        expect(api.isExpectedServiceDisconnect('ddns', brokenPipeErr), isFalse);

        // Unrelated error on critical service (e.g. 403 Forbidden or 404) should NOT be treated as expected disconnect
        final dio403Err = DioException(
          requestOptions: RequestOptions(path: '/ubus'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/ubus'),
            statusCode: 403,
          ),
        );
        expect(api.isExpectedServiceDisconnect('network', dio403Err), isFalse);
      },
    );

    test(
      'AppState.flushDns returns a valid simulated FlushDnsResult in reviewer mode',
      () async {
        final appState = AppState.instance;
        await appState.setReviewerMode(true);

        final res = await appState.flushDns();
        expect(res, isA<FlushDnsResult>());
        expect(res.isSuccess, isTrue);
        expect(res.flushedResolvers, contains('dnsmasq'));
        expect(res.message, contains('simulated'));
      },
    );

    test(
      'FlushDnsResult model serialization and factories preserve success state',
      () {
        final successResult = FlushDnsResult.success(
          flushedResolvers: ['dnsmasq', 'odhcpd'],
          message: 'Flushed 2 resolvers',
        );
        expect(successResult.isSuccess, isTrue);
        expect(successResult.flushedResolvers, equals(['dnsmasq', 'odhcpd']));
        expect(successResult.message, equals('Flushed 2 resolvers'));

        final json = successResult.toJson();
        final roundtrip = FlushDnsResult.fromJson(json);
        expect(roundtrip.isSuccess, isTrue);
        expect(roundtrip.flushedResolvers, equals(['dnsmasq', 'odhcpd']));

        final failureResult = FlushDnsResult.failure(
          'Command failed with code 127',
        );
        expect(failureResult.isSuccess, isFalse);
        expect(failureResult.message, contains('127'));
      },
    );
  });
}
