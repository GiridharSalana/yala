// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

/// Typed outcome model for diagnostic checks and root-cause analysis.
///
/// Semantics are strictly explicit and never collapsed into a generic failure:
/// - [healthy]: Sufficient tests passed for the specific scope being assessed.
/// - [degraded]: Partial functionality or a meaningful impairment was detected.
/// - [failureConfirmed]: A specific failure is supported by rigorous corroborating evidence.
/// - [suspected]: Evidence points toward a probable cause but is not conclusive.
/// - [inconclusive]: Available evidence cannot determine the outcome or is contradictory.
/// - [notTested]: The test was intentionally skipped (e.g. prerequisite failed or not run).
/// - [unsupported]: The required capability, tool, or permission is unavailable on the router.
/// - [notApplicable]: The test does not apply to the detected router configuration (e.g. IPv6 unconfigured).
enum DiagnosticStatus {
  healthy,
  degraded,
  failureConfirmed,
  suspected,
  inconclusive,
  notTested,
  unsupported,
  notApplicable;

  String get label {
    switch (this) {
      case DiagnosticStatus.healthy:
        return 'Healthy';
      case DiagnosticStatus.degraded:
        return 'Degraded';
      case DiagnosticStatus.failureConfirmed:
        return 'Failure Confirmed';
      case DiagnosticStatus.suspected:
        return 'Suspected Issue';
      case DiagnosticStatus.inconclusive:
        return 'Inconclusive';
      case DiagnosticStatus.notTested:
        return 'Not Tested';
      case DiagnosticStatus.unsupported:
        return 'Unsupported';
      case DiagnosticStatus.notApplicable:
        return 'Not Applicable';
    }
  }

  /// Whether this outcome represents an active problem requiring attention or investigation.
  bool get isProblem =>
      this == DiagnosticStatus.failureConfirmed ||
      this == DiagnosticStatus.degraded ||
      this == DiagnosticStatus.suspected;

  /// Whether this outcome indicates complete operational readiness for its scope.
  bool get isOperational => this == DiagnosticStatus.healthy;

  /// Whether this outcome represents missing data or capabilities rather than a failure.
  bool get isNonFailure =>
      this == DiagnosticStatus.notTested ||
      this == DiagnosticStatus.unsupported ||
      this == DiagnosticStatus.notApplicable ||
      this == DiagnosticStatus.inconclusive;
}
