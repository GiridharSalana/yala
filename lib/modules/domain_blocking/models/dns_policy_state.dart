// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'domain_block_rule.dart';

/// Aggregated runtime state of DNS blocking policies across AdGuard Home and native dnsmasq.
@immutable
class DnsPolicyState {
  /// The engine currently designated to enforce DNS domain blocking.
  final DnsBlockingEngine activeEngine;

  /// Whether DNS filtering is currently active and intercepting network traffic.
  final bool isFilteringActive;

  /// The active AdGuard Home DNS topology, if AdGuard Home is installed.
  final AdGuardDnsTopology? topology;

  /// Network-wide global domain blocking rules.
  final List<DomainBlockRule> globalRules;

  /// Set of filtering scopes supported under the current router capabilities and topology.
  final Set<DomainBlockScope> supportedScopes;

  /// Informative or security warning concerning topology limitations or bypass vectors.
  final String? warning;

  /// Operational error message, if policy evaluation or rule retrieval failed.
  final String? error;

  const DnsPolicyState({
    required this.activeEngine,
    this.isFilteringActive = false,
    this.topology,
    this.globalRules = const [],
    this.supportedScopes = const {DomainBlockScope.global},
    this.warning,
    this.error,
  });

  /// Factory creating an unconfigured / disabled policy state.
  factory DnsPolicyState.disabled({
    DnsBlockingEngine engine = DnsBlockingEngine.none,
    String? warning,
    String? error,
  }) {
    return DnsPolicyState(
      activeEngine: engine,
      isFilteringActive: false,
      globalRules: const [],
      supportedScopes: const {},
      warning: warning,
      error: error,
    );
  }

  DnsPolicyState copyWith({
    DnsBlockingEngine? activeEngine,
    bool? isFilteringActive,
    AdGuardDnsTopology? topology,
    List<DomainBlockRule>? globalRules,
    Set<DomainBlockScope>? supportedScopes,
    String? warning,
    String? error,
  }) {
    return DnsPolicyState(
      activeEngine: activeEngine ?? this.activeEngine,
      isFilteringActive: isFilteringActive ?? this.isFilteringActive,
      topology: topology ?? this.topology,
      globalRules: globalRules ?? this.globalRules,
      supportedScopes: supportedScopes ?? this.supportedScopes,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DnsPolicyState &&
          runtimeType == other.runtimeType &&
          activeEngine == other.activeEngine &&
          isFilteringActive == other.isFilteringActive &&
          listEquals(globalRules, other.globalRules) &&
          setEquals(supportedScopes, other.supportedScopes) &&
          warning == other.warning &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
    activeEngine,
    isFilteringActive,
    Object.hashAll(globalRules),
    Object.hashAll(supportedScopes),
    warning,
    error,
  );

  @override
  String toString() =>
      'DnsPolicyState(engine: ${activeEngine.name}, active: $isFilteringActive, rules: ${globalRules.length})';
}

/// Generic outcome wrapper for domain blocking mutations (add/remove/toggle).
@immutable
class DomainBlockActionResult {
  final bool success;
  final String message;
  final DomainBlockRule? rule;
  final DnsBlockingEngine? engine;
  final String? error;

  const DomainBlockActionResult({
    required this.success,
    required this.message,
    this.rule,
    this.engine,
    this.error,
  });

  factory DomainBlockActionResult.ok({
    required String message,
    DomainBlockRule? rule,
    DnsBlockingEngine? engine,
  }) {
    return DomainBlockActionResult(
      success: true,
      message: message,
      rule: rule,
      engine: engine,
    );
  }

  factory DomainBlockActionResult.failed({
    required String message,
    String? error,
    DnsBlockingEngine? engine,
  }) {
    return DomainBlockActionResult(
      success: false,
      message: message,
      error: error,
      engine: engine,
    );
  }
}
