// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

/// Rigorous confidence tiers for diagnostic findings.
///
/// Ensures arbitrary percentages are never displayed without mathematical calibration.
enum DiagnosticConfidence {
  /// Multiple independent observations support the conclusion with zero contradictory evidence.
  high,

  /// Several observations support a likely cause, but alternatives or unverified factors remain.
  moderate,

  /// A possible cause is suggested by limited or indirect evidence.
  low,

  /// Evidence is insufficient, incomplete, or mutually contradictory.
  inconclusive;

  String get label {
    switch (this) {
      case DiagnosticConfidence.high:
        return 'High Confidence';
      case DiagnosticConfidence.moderate:
        return 'Moderate Confidence';
      case DiagnosticConfidence.low:
        return 'Low Confidence';
      case DiagnosticConfidence.inconclusive:
        return 'Inconclusive Evidence';
    }
  }

  String get description {
    switch (this) {
      case DiagnosticConfidence.high:
        return 'Corroborated by multiple independent observations with no conflicting evidence.';
      case DiagnosticConfidence.moderate:
        return 'Supported by key observations, though secondary factors could contribute.';
      case DiagnosticConfidence.low:
        return 'Plausible hypothesis based on limited diagnostic data.';
      case DiagnosticConfidence.inconclusive:
        return 'Available evidence does not allow a definitive conclusion.';
    }
  }
}
