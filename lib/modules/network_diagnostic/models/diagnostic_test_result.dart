// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'diagnostic_confidence.dart';
import 'diagnostic_evidence.dart';
import 'diagnostic_scope.dart';
import 'diagnostic_status.dart';

/// The evaluated outcome of an individual diagnostic check.
class DiagnosticTestResult {
  /// Unique stable identifier (e.g. 'router_management_api', 'wan_interface_state').
  final String id;

  /// User-friendly title.
  final String title;

  /// Architectural network scope.
  final DiagnosticScope scope;

  /// Explicit typed outcome.
  final DiagnosticStatus status;

  /// Degree of certainty supported by evidence.
  final DiagnosticConfidence confidence;

  /// Plain-language explanation of what was observed.
  final String explanation;

  /// Clear explanation of why this test matters to network performance/reachability.
  final String whyItMatters;

  /// Actionable suggestion if degraded or failed.
  final String? recommendedStep;

  /// Structured facts, metrics, and technical outputs.
  final DiagnosticEvidence evidence;

  /// Optional deep technical detail for the advanced disclosure card.
  final String? technicalDetails;

  /// Reason why a test was skipped, inconclusive, or unsupported.
  final String? skipOrFailureReason;

  /// Time when this test execution began.
  final DateTime startedAt;

  /// Time when this test execution concluded.
  final DateTime? completedAt;

  /// Duration taken by this test.
  final Duration? duration;

  const DiagnosticTestResult({
    required this.id,
    required this.title,
    required this.scope,
    required this.status,
    required this.confidence,
    required this.explanation,
    required this.whyItMatters,
    this.recommendedStep,
    this.evidence = const DiagnosticEvidence(),
    this.technicalDetails,
    this.skipOrFailureReason,
    required this.startedAt,
    this.completedAt,
    this.duration,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'scope': scope.name,
    'status': status.name,
    'confidence': confidence.name,
    'explanation': explanation,
    'whyItMatters': whyItMatters,
    if (recommendedStep != null) 'recommendedStep': recommendedStep,
    'evidence': evidence.toJson(),
    if (technicalDetails != null) 'technicalDetails': technicalDetails,
    if (skipOrFailureReason != null) 'skipOrFailureReason': skipOrFailureReason,
    'startedAt': startedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (duration != null) 'durationMs': duration!.inMilliseconds,
  };
}
