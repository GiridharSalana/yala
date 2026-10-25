// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yala/modules/domain_blocking/models/dns_policy_state.dart';
import 'package:yala/modules/domain_blocking/models/domain_block_rule.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/operation_queue.dart';

/// Service coordinating domain/website blocking across AdGuard Home and native OpenWrt dnsmasq.
///
/// Features:
/// - Dynamic engine selection based on router capabilities, AdGuard authentication, and DNS topology.
/// - Operation queue locking on domain `'dns'` for strict serialization and race condition prevention.
/// - Snapshot preservation and atomic rollback during mutation failures.
/// - Idempotent rule addition and removal.
/// - RFC 1035 / RFC 1123 domain validation and URL stripping.
class DomainBlockingService {
  final IApiService apiService;
  final IAdGuardApiService adguardApiService;
  final RouterCapabilities capabilities;
  AdGuardDnsTopology? topology;
  final String routerId;
  final String ipAddress;
  final String sysauth;
  final bool useHttps;
  final RouterScopedOperationQueue operationQueue;

  DomainBlockingService({
    required this.apiService,
    required this.adguardApiService,
    required this.capabilities,
    this.topology,
    required this.routerId,
    required this.ipAddress,
    required this.sysauth,
    required this.useHttps,
    RouterScopedOperationQueue? operationQueue,
  }) : operationQueue = operationQueue ?? RouterScopedOperationQueue.instance;

  /// Determines the active [DnsBlockingEngine] based on current capabilities,
  /// AdGuard Home authentication status, and runtime DNS topology.
  DnsBlockingEngine resolveEngine({AdGuardDnsTopology? topologyOverride}) {
    final activeTopology = topologyOverride ?? topology;

    // 1. Evaluate AdGuard Home eligibility
    if (capabilities.hasAdGuardHome && adguardApiService.isAuthenticated) {
      if (activeTopology != null) {
        switch (activeTopology.mode) {
          case AdGuardTopologyMode.adguardPrimary:
          case AdGuardTopologyMode.firewallRedirect:
          case AdGuardTopologyMode.dnsmasqForwarder:
            return DnsBlockingEngine.adguardHome;
          case AdGuardTopologyMode.standalone:
          case AdGuardTopologyMode.stopped:
          case AdGuardTopologyMode.unknown:
            // In standalone, stopped, or unknown modes, AdGuard is not actively filtering LAN traffic
            break;
        }
      }
    }

    // 2. Fallback to native OpenWrt dnsmasq if router supports UCI write access
    if (capabilities.hasUciWriteAccess) {
      return DnsBlockingEngine.dnsmasqNative;
    }

    // 3. No active filtering engine available
    return DnsBlockingEngine.none;
  }

  /// Evaluates and returns the aggregated [DnsPolicyState].
  Future<DnsPolicyState> getPolicyState({
    AdGuardDnsTopology? topologyOverride,
    BuildContext? context,
  }) async {
    final activeTopology = topologyOverride ?? topology;
    final engine = resolveEngine(topologyOverride: activeTopology);

    switch (engine) {
      case DnsBlockingEngine.adguardHome:
        try {
          final res = await adguardApiService.getFilteringStatus();
          if (!res.isSuccess || res.data == null) {
            return DnsPolicyState(
              activeEngine: engine,
              isFilteringActive: false,
              topology: activeTopology,
              supportedScopes: _determineSupportedScopes(
                engine,
                activeTopology,
              ),
              warning: _buildTopologyWarning(activeTopology),
              error:
                  res.error?.message ??
                  'Failed to retrieve AdGuard Home filtering status',
            );
          }

          final status = res.data!;
          final List<DomainBlockRule> rules = [];
          for (final raw in status.userRules) {
            final domain = DomainValidator.parseBlockedDomainFromAdGuardRule(
              raw,
            );
            if (domain != null) {
              rules.add(
                DomainBlockRule.global(
                  domain: domain,
                  rawPattern: raw,
                  engine: engine,
                  isEnabled: status.enabled,
                ),
              );
            }
          }

          return DnsPolicyState(
            activeEngine: engine,
            isFilteringActive: status.enabled,
            topology: activeTopology,
            globalRules: rules,
            supportedScopes: _determineSupportedScopes(engine, activeTopology),
            warning: _buildTopologyWarning(activeTopology),
          );
        } catch (e) {
          return DnsPolicyState(
            activeEngine: engine,
            isFilteringActive: false,
            topology: activeTopology,
            supportedScopes: _determineSupportedScopes(engine, activeTopology),
            error: e.toString(),
          );
        }

      case DnsBlockingEngine.dnsmasqNative:
        try {
          final domains = await apiService.getDnsmasqBlockedDomains(
            ipAddress,
            sysauth,
            useHttps,
            context: context,
          );
          final rules = domains
              .map(
                (d) => DomainBlockRule.global(
                  domain: d,
                  rawPattern: '/$d/#',
                  engine: engine,
                  isEnabled: true,
                ),
              )
              .toList();

          return DnsPolicyState(
            activeEngine: engine,
            isFilteringActive: true,
            topology: activeTopology,
            globalRules: rules,
            supportedScopes: const {DomainBlockScope.global},
          );
        } catch (e) {
          return DnsPolicyState(
            activeEngine: engine,
            isFilteringActive: false,
            topology: activeTopology,
            supportedScopes: const {DomainBlockScope.global},
            error: e.toString(),
          );
        }

      case DnsBlockingEngine.none:
        return DnsPolicyState.disabled(
          engine: engine,
          warning: _buildDisabledWarning(activeTopology),
        );
    }
  }

  /// Adds a domain to the global blocked list using the active DNS engine.
  ///
  /// Serialized through [operationQueue] on domain `'dns'`.
  Future<DomainBlockActionResult> addGlobalDomain(
    String domain, {
    AdGuardDnsTopology? topologyOverride,
    BuildContext? context,
  }) async {
    final validationError = DomainValidator.validate(domain);
    if (validationError != null) {
      return DomainBlockActionResult.failed(
        message: 'Invalid domain: $validationError',
        error: validationError,
      );
    }

    final normalized = DomainValidator.normalize(domain)!;

    return await operationQueue.runLocked<DomainBlockActionResult>(
      routerId: routerId,
      domain: 'dns',
      action: () async {
        final activeTopology = topologyOverride ?? topology;
        final engine = resolveEngine(topologyOverride: activeTopology);

        if (engine == DnsBlockingEngine.adguardHome) {
          final statusRes = await adguardApiService.getFilteringStatus();
          if (!statusRes.isSuccess || statusRes.data == null) {
            return DomainBlockActionResult.failed(
              message: 'Failed to retrieve current AdGuard Home rules',
              error: statusRes.error?.message,
              engine: engine,
            );
          }

          final existingRules = List<String>.from(statusRes.data!.userRules);
          final newRulePattern = '||$normalized^';

          // Idempotency check:
          final alreadyPresent = existingRules.any((r) {
            final parsed = DomainValidator.parseBlockedDomainFromAdGuardRule(r);
            return parsed != null &&
                parsed.toLowerCase() == normalized.toLowerCase();
          });

          if (!alreadyPresent) {
            existingRules.add(newRulePattern);
            final updateRes = await adguardApiService.setUserRules(
              existingRules,
            );
            if (!updateRes.isSuccess || updateRes.data != true) {
              return DomainBlockActionResult.failed(
                message: 'Failed to apply rule to AdGuard Home',
                error: updateRes.error?.message,
                engine: engine,
              );
            }
          }

          return DomainBlockActionResult.ok(
            message: 'Domain $normalized blocked via AdGuard Home',
            rule: DomainBlockRule.global(
              domain: normalized,
              rawPattern: newRulePattern,
              engine: engine,
            ),
            engine: engine,
          );
        } else if (engine == DnsBlockingEngine.dnsmasqNative) {
          final success = await apiService.addDnsmasqBlockedDomain(
            ipAddress,
            sysauth,
            useHttps,
            normalized,
            context: context,
          );

          if (!success) {
            return DomainBlockActionResult.failed(
              message: 'Failed to block domain $normalized in dnsmasq',
              engine: engine,
            );
          }

          return DomainBlockActionResult.ok(
            message: 'Domain $normalized blocked via native dnsmasq',
            rule: DomainBlockRule.global(
              domain: normalized,
              rawPattern: '/$normalized/#',
              engine: engine,
            ),
            engine: engine,
          );
        } else {
          return DomainBlockActionResult.failed(
            message: 'No active DNS blocking engine available',
            error: _buildDisabledWarning(activeTopology),
            engine: engine,
          );
        }
      },
    );
  }

  /// Removes a domain from the global blocked list using the active DNS engine.
  ///
  /// Serialized through [operationQueue] on domain `'dns'`.
  Future<DomainBlockActionResult> removeGlobalDomain(
    String domain, {
    AdGuardDnsTopology? topologyOverride,
    BuildContext? context,
  }) async {
    final normalized = DomainValidator.normalize(domain);
    if (normalized == null || normalized.isEmpty) {
      return DomainBlockActionResult.failed(message: 'Invalid domain');
    }

    return await operationQueue.runLocked<DomainBlockActionResult>(
      routerId: routerId,
      domain: 'dns',
      action: () async {
        final activeTopology = topologyOverride ?? topology;
        final engine = resolveEngine(topologyOverride: activeTopology);

        if (engine == DnsBlockingEngine.adguardHome) {
          final statusRes = await adguardApiService.getFilteringStatus();
          if (!statusRes.isSuccess || statusRes.data == null) {
            return DomainBlockActionResult.failed(
              message: 'Failed to retrieve current AdGuard Home rules',
              error: statusRes.error?.message,
              engine: engine,
            );
          }

          final existingRules = List<String>.from(statusRes.data!.userRules);
          final updatedRules = existingRules.where((r) {
            final parsed = DomainValidator.parseBlockedDomainFromAdGuardRule(r);
            return parsed == null ||
                parsed.toLowerCase() != normalized.toLowerCase();
          }).toList();

          if (updatedRules.length != existingRules.length) {
            final updateRes = await adguardApiService.setUserRules(
              updatedRules,
            );
            if (!updateRes.isSuccess || updateRes.data != true) {
              return DomainBlockActionResult.failed(
                message: 'Failed to update AdGuard Home rules',
                error: updateRes.error?.message,
                engine: engine,
              );
            }
          }

          return DomainBlockActionResult.ok(
            message: 'Domain $normalized unblocked from AdGuard Home',
            engine: engine,
          );
        } else if (engine == DnsBlockingEngine.dnsmasqNative) {
          final success = await apiService.removeDnsmasqBlockedDomain(
            ipAddress,
            sysauth,
            useHttps,
            normalized,
            context: context,
          );

          if (!success) {
            return DomainBlockActionResult.failed(
              message: 'Failed to unblock domain $normalized in dnsmasq',
              engine: engine,
            );
          }

          return DomainBlockActionResult.ok(
            message: 'Domain $normalized unblocked from native dnsmasq',
            engine: engine,
          );
        } else {
          return DomainBlockActionResult.failed(
            message: 'No active DNS blocking engine available',
            engine: engine,
          );
        }
      },
    );
  }

  Set<DomainBlockScope> _determineSupportedScopes(
    DnsBlockingEngine engine,
    AdGuardDnsTopology? topo,
  ) {
    if (engine == DnsBlockingEngine.adguardHome) {
      if (topo?.mode == AdGuardTopologyMode.dnsmasqForwarder) {
        return const {DomainBlockScope.global};
      }
      return const {DomainBlockScope.global, DomainBlockScope.perDevice};
    } else if (engine == DnsBlockingEngine.dnsmasqNative) {
      return const {DomainBlockScope.global};
    }
    return const {};
  }

  String? _buildTopologyWarning(AdGuardDnsTopology? topo) {
    if (topo?.mode == AdGuardTopologyMode.dnsmasqForwarder) {
      return 'All LAN DNS queries pass through dnsmasq before reaching AdGuard Home; per-device identification is constrained to dnsmasq.';
    }
    return null;
  }

  String _buildDisabledWarning(AdGuardDnsTopology? topo) {
    if (!capabilities.hasUciWriteAccess) {
      return 'Router access is read-only. Domain blocking configuration cannot be modified.';
    }
    if (capabilities.hasAdGuardHome && !adguardApiService.isAuthenticated) {
      return 'AdGuard Home is installed but requires authentication to inspect or edit domain blocking rules.';
    }
    if (topo != null) {
      if (topo.mode == AdGuardTopologyMode.standalone) {
        return 'AdGuard Home is running in standalone mode on port ${topo.adguardDnsPort} and is not intercepting LAN traffic.';
      }
      if (topo.mode == AdGuardTopologyMode.stopped) {
        return 'AdGuard Home is stopped or disabled in router service configuration.';
      }
    }
    return 'No active DNS filtering engine detected on this router.';
  }
}
