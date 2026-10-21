// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_capabilities.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_confidence.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_evidence.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_scope.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_status.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_test_result.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/network_diagnostic_report.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/root_cause_finding.dart';

void main() {
  group('DiagnosticStatus Semantics & Invariants', () {
    test(
      'Ensures explicit distinction between failures, problems, and non-failures',
      () {
        expect(DiagnosticStatus.failureConfirmed.isProblem, isTrue);
        expect(DiagnosticStatus.degraded.isProblem, isTrue);
        expect(DiagnosticStatus.suspected.isProblem, isTrue);

        expect(DiagnosticStatus.healthy.isProblem, isFalse);
        expect(DiagnosticStatus.healthy.isOperational, isTrue);

        // Invariant: unsupported, notTested, notApplicable, inconclusive are NOT treated as failureConfirmed
        expect(DiagnosticStatus.unsupported.isProblem, isFalse);
        expect(DiagnosticStatus.unsupported.isNonFailure, isTrue);
        expect(DiagnosticStatus.notTested.isProblem, isFalse);
        expect(DiagnosticStatus.notTested.isNonFailure, isTrue);
        expect(DiagnosticStatus.notApplicable.isProblem, isFalse);
        expect(DiagnosticStatus.notApplicable.isNonFailure, isTrue);
        expect(DiagnosticStatus.inconclusive.isProblem, isFalse);
        expect(DiagnosticStatus.inconclusive.isNonFailure, isTrue);
      },
    );

    test('All status variants have human-readable non-empty labels', () {
      for (final status in DiagnosticStatus.values) {
        expect(status.label, isNotEmpty);
      }
    });

    test('All confidence tiers have descriptions and labels', () {
      for (final conf in DiagnosticConfidence.values) {
        expect(conf.label, isNotEmpty);
        expect(conf.description, isNotEmpty);
      }
    });

    test('All diagnostic scopes have human-readable display names', () {
      for (final scope in DiagnosticScope.values) {
        expect(scope.displayName, isNotEmpty);
      }
    });
  });

  group('DiagnosticTestResult & Evidence Serialization', () {
    test(
      'Serializes and deserializes evidence and test results accurately',
      () {
        final now = DateTime.now();
        final evidence = DiagnosticEvidence(
          facts: ['Observation A', 'Observation B'],
          metrics: {'rttMs': 12.5, 'lossPercent': 0.0},
          technicalOutput: 'PING 1.1.1.1 (1.1.1.1): 56 data bytes',
          timestamps: {'started': now},
        );

        final result = DiagnosticTestResult(
          id: 'external_ipv4',
          title: 'IPv4 External Reachability',
          scope: DiagnosticScope.ipv4,
          status: DiagnosticStatus.healthy,
          confidence: DiagnosticConfidence.high,
          explanation: 'All 3 public DNS targets reachable.',
          whyItMatters: 'Validates outbound packet forwarding.',
          recommendedStep: 'No action needed.',
          evidence: evidence,
          technicalDetails: 'Min RTT 12.5ms',
          skipOrFailureReason: null,
          startedAt: now,
          completedAt: now.add(const Duration(milliseconds: 200)),
          duration: const Duration(milliseconds: 200),
        );

        final json = result.toJson();
        expect(json['id'], equals('external_ipv4'));
        expect(json['scope'], equals('ipv4'));
        expect(json['status'], equals('healthy'));
        expect(json['confidence'], equals('high'));
        expect(json['durationMs'], equals(200));

        final evJson = json['evidence'] as Map<String, dynamic>;
        expect(evJson['facts'], contains('Observation A'));
        expect(evJson['metrics']['rttMs'], equals(12.5));
        expect(evJson['technicalOutput'], contains('56 data bytes'));
      },
    );
  });

  group('NetworkDiagnosticReport Invariants', () {
    test(
      'Report preserves session identity and serializes without secret leakage',
      () {
        final now = DateTime.now();
        final report = NetworkDiagnosticReport(
          sessionId: 'session_12345',
          timestamp: now,
          routerScope: '192.168.1.1',
          overallStatus: DiagnosticStatus.healthy,
          overallSummary: 'Internet connection is operational.',
          testResults: [],
          findings: [
            const RootCauseFinding(
              id: 'finding_1',
              title: 'Router Reachability Verified',
              description: 'Direct IP and DNS resolved.',
              status: DiagnosticStatus.healthy,
              confidence: DiagnosticConfidence.high,
              primaryScope: DiagnosticScope.ipv4,
            ),
          ],
          capabilities: const DiagnosticCapabilities(
            hasManagementApi: true,
            activeWanInterface: 'wan',
            wanProtocol: 'dhcp',
          ),
          unverifiedAreas: ['Client Wi-Fi latency'],
        );

        final json = report.toJson();
        expect(json['sessionId'], equals('session_12345'));
        expect(json['routerScope'], equals('192.168.1.1'));
        expect(json['overallStatus'], equals('healthy'));
        expect(json.toString(), isNot(contains('password')));
        expect(json.toString(), isNot(contains('sysauth')));
        expect(json.toString(), isNot(contains('token')));
      },
    );
  });
}
