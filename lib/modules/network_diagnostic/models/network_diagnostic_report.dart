// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'diagnostic_capabilities.dart';
import 'diagnostic_status.dart';
import 'diagnostic_test_result.dart';
import 'root_cause_finding.dart';

/// Comprehensive session diagnostic report synthesizing all observations.
class NetworkDiagnosticReport {
  /// Unique session execution identifier.
  final String sessionId;

  /// Time when diagnostics completed.
  final DateTime timestamp;

  /// Target router hostname or IP (never includes passwords or tokens).
  final String routerScope;

  /// Overall assessment synthesized from all independent tests.
  final DiagnosticStatus overallStatus;

  /// Plain-language high-level synthesis of connectivity state.
  final String overallSummary;

  /// Test-by-test results.
  final List<DiagnosticTestResult> testResults;

  /// Root-cause findings deduced from correlating evidence.
  final List<RootCauseFinding> findings;

  /// Detected capabilities and topological features.
  final DiagnosticCapabilities capabilities;

  /// Explicit statements of domains that could not be evaluated.
  final List<String> unverifiedAreas;

  const NetworkDiagnosticReport({
    required this.sessionId,
    required this.timestamp,
    required this.routerScope,
    required this.overallStatus,
    required this.overallSummary,
    required this.testResults,
    required this.findings,
    required this.capabilities,
    required this.unverifiedAreas,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'routerScope': routerScope,
    'overallStatus': overallStatus.name,
    'overallSummary': overallSummary,
    'testResults': testResults.map((e) => e.toJson()).toList(),
    'findings': findings.map((e) => e.toJson()).toList(),
    'capabilities': capabilities.toJson(),
    'unverifiedAreas': unverifiedAreas,
  };
}
