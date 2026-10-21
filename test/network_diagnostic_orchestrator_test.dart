// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/dns_lookup_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/ping_result.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/engine/diagnostic_orchestrator.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_status.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

class OrchestratorMockApiService extends MockApiService {
  final bool failApi;
  final bool failPing;
  final bool failDns;
  final bool isIpv6Supported;

  OrchestratorMockApiService({
    this.failApi = false,
    this.failPing = false,
    this.failDns = false,
    this.isIpv6Supported = false,
  });

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async {
    if (failApi) {
      throw Exception('Connection refused');
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

  @override
  Future<PingResult> executePing(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String target,
    int count = 3,
    int timeoutSec = 2,
    bool isIpv6 = false,
    dynamic context,
  }) async {
    if (failPing) {
      return PingResult.failure(
        target: target,
        errorMessage: '100% packet loss',
      );
    }
    return super.executePing(
      ipAddress,
      sysauth,
      useHttps,
      target: target,
      count: count,
      timeoutSec: timeoutSec,
      isIpv6: isIpv6,
      context: context,
    );
  }

  @override
  Future<DnsLookupResult> executeDnsLookup(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String host,
    String? server,
    dynamic context,
  }) async {
    if (failDns) {
      return DnsLookupResult.failure(
        query: host,
        errorMessage: 'Server failure',
      );
    }
    return super.executeDnsLookup(
      ipAddress,
      sysauth,
      useHttps,
      host: host,
      server: server,
      context: context,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiagnosticOrchestrator Execution Lifecycle', () {
    test(
      'Runs full suite and emits progressive updates when network is healthy',
      () async {
        final api = OrchestratorMockApiService();
        final orchestrator = DiagnosticOrchestrator(api: api);

        final progressSteps = <double>[];
        final report = await orchestrator.runDiagnostics(
          ipAddress: '192.168.1.1',
          sysauth: 'valid_token',
          useHttps: false,
          onProgress: (current, percent) {
            progressSteps.add(percent);
          },
        );

        expect(progressSteps, isNotEmpty);
        expect(report.overallStatus, equals(DiagnosticStatus.healthy));
        expect(report.testResults.length, greaterThanOrEqualTo(7));
        expect(report.unverifiedAreas, isNotEmpty);
        expect(
          report.testResults.any((t) => t.id == 'router_management_api'),
          isTrue,
        );
        expect(
          report.testResults.any((t) => t.id == 'wan_interface_state'),
          isTrue,
        );
        expect(
          report.testResults.any((t) => t.id == 'ipv4_external_reachability'),
          isTrue,
        );
      },
    );

    test(
      'Cascades cleanly when Router Management API fails without falsely fabricating WAN failures',
      () async {
        final api = OrchestratorMockApiService(failApi: true);
        final orchestrator = DiagnosticOrchestrator(api: api);

        final report = await orchestrator.runDiagnostics(
          ipAddress: '192.168.1.1',
          sysauth: 'valid_token',
          useHttps: false,
        );

        expect(report.overallStatus, equals(DiagnosticStatus.failureConfirmed));

        final mgmt = report.testResults.firstWhere(
          (t) => t.id == 'router_management_api',
        );
        expect(mgmt.status, equals(DiagnosticStatus.failureConfirmed));

        // Downstream checks must be notTested, NOT failureConfirmed!
        final downstream = report.testResults.where(
          (t) => t.id != 'router_management_api',
        );
        for (final test in downstream) {
          expect(
            test.status,
            equals(DiagnosticStatus.notTested),
            reason:
                'Test ${test.id} should be notTested when management API failed',
          );
        }
      },
    );

    test('Handles cancellation gracefully', () async {
      final api = OrchestratorMockApiService();
      final orchestrator = DiagnosticOrchestrator(api: api);

      // Cancel immediately
      orchestrator.cancel();

      final report = await orchestrator.runDiagnostics(
        ipAddress: '192.168.1.1',
        sysauth: 'valid_token',
        useHttps: false,
      );

      expect(report.overallStatus, equals(DiagnosticStatus.inconclusive));
      expect(report.overallSummary, contains('cancelled'));
    });
  });
}
