// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'diagnostic_confidence.dart';
import 'diagnostic_scope.dart';
import 'diagnostic_status.dart';

/// Distinguishes purely informative diagnoses from those requiring user action.
enum FindingActionType { informational, userIntervention }

/// A structured, evidence-backed conclusion synthesized by the rules engine.
class RootCauseFinding {
  final String id;
  final String title;
  final String description;
  final DiagnosticStatus status;
  final DiagnosticConfidence confidence;
  final List<String> supportingEvidence;
  final List<String> contradictoryEvidence;
  final List<String> recommendedSteps;
  final FindingActionType actionType;
  final DiagnosticScope primaryScope;

  const RootCauseFinding({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.confidence,
    this.supportingEvidence = const [],
    this.contradictoryEvidence = const [],
    this.recommendedSteps = const [],
    this.actionType = FindingActionType.informational,
    required this.primaryScope,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'status': status.name,
    'confidence': confidence.name,
    'supportingEvidence': supportingEvidence,
    'contradictoryEvidence': contradictoryEvidence,
    'recommendedSteps': recommendedSteps,
    'actionType': actionType.name,
    'primaryScope': primaryScope.name,
  };
}
