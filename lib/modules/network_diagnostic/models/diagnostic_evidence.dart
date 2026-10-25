// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

/// Structured, factual evidence backing a diagnostic test result or root-cause finding.
class DiagnosticEvidence {
  /// Discrete observable facts discovered during diagnostic probing.
  final List<String> facts;

  /// Structured diagnostic details (e.g. latency, packet loss, resolved IPs, exit codes).
  final Map<String, dynamic> metrics;

  /// Sanitized command or API outputs for technical drill-down.
  final String? technicalOutput;

  /// Timestamps for specific observation milestones.
  final Map<String, DateTime> timestamps;

  const DiagnosticEvidence({
    this.facts = const [],
    this.metrics = const {},
    this.technicalOutput,
    this.timestamps = const {},
  });

  DiagnosticEvidence copyWith({
    List<String>? facts,
    Map<String, dynamic>? metrics,
    String? technicalOutput,
    Map<String, DateTime>? timestamps,
  }) {
    return DiagnosticEvidence(
      facts: facts ?? this.facts,
      metrics: metrics ?? this.metrics,
      technicalOutput: technicalOutput ?? this.technicalOutput,
      timestamps: timestamps ?? this.timestamps,
    );
  }

  Map<String, dynamic> toJson() => {
    'facts': facts,
    'metrics': metrics,
    if (technicalOutput != null) 'technicalOutput': technicalOutput,
    'timestamps': timestamps.map((k, v) => MapEntry(k, v.toIso8601String())),
  };
}
