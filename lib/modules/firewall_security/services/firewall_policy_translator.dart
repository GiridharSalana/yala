// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yala/models/network_access_policy.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/modules/firewall_security/models/firewall_info.dart';
import 'package:yala/utils/client_naming_helper.dart';

/// Non-destructive recognition result for an existing client firewall policy.
class RecognizedDevicePolicy {
  final String targetMac;
  final bool hasActiveBlock;
  final bool isLegacy;
  final List<String> matchingSectionKeys;
  final Set<String> blockedFamilies;
  final NetworkAccessPolicy policy;

  const RecognizedDevicePolicy({
    required this.targetMac,
    required this.hasActiveBlock,
    required this.isLegacy,
    required this.matchingSectionKeys,
    required this.blockedFamilies,
    required this.policy,
  });
}

/// Description of a UCI mutation required to enforce a policy.
enum UciMutationType { add, set, delete, none }

class UciRuleMutation {
  final UciMutationType type;
  final String? sectionKey;
  final Map<String, dynamic> values;

  const UciRuleMutation({
    required this.type,
    this.sectionKey,
    this.values = const {},
  });
}

/// Translates [NetworkAccessPolicy] to UCI firewall representations and
/// recognizes legacy firewall blocking rules non-destructively.
class FirewallPolicyTranslator {
  /// Well-known legacy block rule names.
  static const String legacyNoInternetRuleName = 'nointernet_wireless_clients';
  static const String legacyPausePrefix = 'Pause_Internet_';
  static const String legacyBanPrefix = 'Ban_Client_';
  static const String legacyKickPrefix = 'Kick_Client_';
  static const String yalaRulePrefix = 'Yala_Block_';

  /// Generates a standardized rule name for YALA-managed blocks.
  static String formatYalaRuleName(String mac, {String family = 'any'}) {
    final cleanMac = mac.toUpperCase().replaceAll(':', '').replaceAll('-', '');
    if (family == 'ipv4') {
      return '${yalaRulePrefix}IPv4_$cleanMac';
    } else if (family == 'ipv6') {
      return '${yalaRulePrefix}IPv6_$cleanMac';
    }
    return '$yalaRulePrefix$cleanMac';
  }

  /// Evaluates whether a given rule represents a legacy device block.
  static bool isLegacyBlockRule(FirewallCustomRule rule) {
    final name = rule.name;
    return name == legacyNoInternetRuleName ||
        name.startsWith(legacyPausePrefix) ||
        name.startsWith(legacyBanPrefix) ||
        name.startsWith(legacyKickPrefix);
  }

  /// Non-destructively inspects existing firewall rules to identify any active blocks
  /// for the specified [targetMac].
  ///
  /// CRITICAL: This is a purely read-only recognition function. It NEVER renames,
  /// deletes, migrates, or normalizes existing rules.
  static RecognizedDevicePolicy recognizePolicy({
    required String targetMac,
    required List<FirewallCustomRule> rules,
  }) {
    final normMac = ClientNamingHelper.normalizeMac(targetMac);
    final rawMacNoDelim = normMac.replaceAll(':', '').toLowerCase();

    bool hasBlock = false;
    bool isLegacy = false;
    final matchingSectionKeys = <String>[];
    final blockedFamilies = <String>{};

    for (final rule in rules) {
      if (!rule.enabled) continue;

      final target = rule.target.toUpperCase();
      final isDropOrReject =
          target == 'DROP' || target == 'REJECT' || target == 'STOP';
      if (!isDropOrReject) continue;

      // Check if MAC is in src_mac list
      bool macMatches = false;
      for (final sm in rule.srcMac) {
        if (ClientNamingHelper.normalizeMac(sm) == normMac) {
          macMatches = true;
          break;
        }
      }

      // Check if rule name specifically targets this MAC
      final lowerName = rule.name.toLowerCase();
      if (!macMatches && lowerName.contains(rawMacNoDelim)) {
        macMatches = true;
      }

      if (macMatches) {
        hasBlock = true;
        matchingSectionKeys.add(rule.sectionKey);
        if (isLegacyBlockRule(rule)) {
          isLegacy = true;
        }
        final fam = rule.family.toLowerCase();
        if (fam.isEmpty || fam == 'any' || fam == 'all') {
          blockedFamilies.add('ipv4');
          blockedFamilies.add('ipv6');
        } else {
          blockedFamilies.add(fam);
        }
      }
    }

    if (!hasBlock) {
      return RecognizedDevicePolicy(
        targetMac: normMac,
        hasActiveBlock: false,
        isLegacy: false,
        matchingSectionKeys: const [],
        blockedFamilies: const {},
        policy: NetworkAccessPolicy.unrestricted(normMac),
      );
    }

    final blocksIpv4 = blockedFamilies.contains('ipv4');
    final blocksIpv6 = blockedFamilies.contains('ipv6');
    final blocksBoth = blocksIpv4 && blocksIpv6;

    final policy = NetworkAccessPolicy(
      targetMac: normMac,
      internetAccess: !blocksBoth,
      ipv4Access: !blocksIpv4,
      ipv6Access: !blocksIpv6,
    );

    return RecognizedDevicePolicy(
      targetMac: normMac,
      hasActiveBlock: true,
      isLegacy: isLegacy,
      matchingSectionKeys: matchingSectionKeys,
      blockedFamilies: blockedFamilies,
      policy: policy,
    );
  }

  /// Translates a desired [NetworkAccessPolicy] into deterministic UCI firewall mutations.
  ///
  /// Respects [RouterCapabilities]:
  /// - IPv6 blocks are only generated if the router supports IPv6.
  /// - If global internet is blocked, master override unconditionally blocks both IPv4 and IPv6.
  static List<UciRuleMutation> translatePolicyToUci({
    required NetworkAccessPolicy policy,
    required RouterCapabilities capabilities,
    required List<FirewallCustomRule> existingRules,
  }) {
    final normMac = ClientNamingHelper.normalizeMac(policy.targetMac);
    final mutations = <UciRuleMutation>[];

    // Find any existing YALA-created or legacy rules targeting this MAC
    final recognized = recognizePolicy(
      targetMac: normMac,
      rules: existingRules,
    );

    // Case 1: Unblocked / Allowed
    if (policy.effectiveInternetAccess &&
        policy.effectiveIpv4Access &&
        policy.effectiveIpv6Access) {
      // If there are existing rules matching this MAC, remove this MAC or delete the rule
      for (final secKey in recognized.matchingSectionKeys) {
        final existingRule = existingRules.firstWhere(
          (r) => r.sectionKey == secKey,
          orElse: () => FirewallCustomRule(
            sectionKey: secKey,
            name: '',
            srcZone: '',
            destZone: '',
            target: '',
            enabled: false,
          ),
        );

        if (existingRule.srcMac.length > 1) {
          final updatedMacs = existingRule.srcMac
              .where((m) => ClientNamingHelper.normalizeMac(m) != normMac)
              .toList();
          mutations.add(
            UciRuleMutation(
              type: UciMutationType.set,
              sectionKey: secKey,
              values: {'src_mac': updatedMacs},
            ),
          );
        } else {
          mutations.add(
            UciRuleMutation(type: UciMutationType.delete, sectionKey: secKey),
          );
        }
      }
      return mutations;
    }

    // Case 2: Blocked (Global, IPv4-only, or IPv6-only)
    String targetFamily = 'any';
    if (!policy.effectiveInternetAccess ||
        (!policy.effectiveIpv4Access && !policy.effectiveIpv6Access)) {
      targetFamily = 'any';
    } else if (!policy.effectiveIpv4Access && policy.effectiveIpv6Access) {
      targetFamily = 'ipv4';
    } else if (policy.effectiveIpv4Access && !policy.effectiveIpv6Access) {
      // IPv6 capability check: Requires operational IPv6 Internet firewall capability.
      // Notice: odhcpd presence alone is NOT sufficient proof of working IPv6 Internet.
      if (capabilities.supportsIpv6InternetFirewall) {
        targetFamily = 'ipv6';
      } else {
        // Router has no operational IPv6 Internet firewall capability; skip creating invalid rule
        return mutations;
      }
    }

    final ruleName = formatYalaRuleName(normMac, family: targetFamily);

    // Check if an existing YALA rule section can be updated in-place preserving its section key
    String? existingYalaSecKey;
    for (final rule in existingRules) {
      if (rule.name == ruleName ||
          (rule.name.startsWith(yalaRulePrefix) &&
              rule.srcMac.any(
                (m) => ClientNamingHelper.normalizeMac(m) == normMac,
              ))) {
        existingYalaSecKey = rule.sectionKey;
        break;
      }
    }

    final ruleValues = <String, dynamic>{
      'name': ruleName,
      'src': '*',
      'dest': 'wan',
      'src_mac': [normMac],
      'target': 'DROP',
      'enabled': '1',
    };
    if (targetFamily != 'any') {
      ruleValues['family'] = targetFamily;
    }

    if (existingYalaSecKey != null) {
      // In-place update preserving section key
      mutations.add(
        UciRuleMutation(
          type: UciMutationType.set,
          sectionKey: existingYalaSecKey,
          values: ruleValues,
        ),
      );
    } else {
      // Add new rule section
      mutations.add(
        UciRuleMutation(
          type: UciMutationType.add,
          values: ruleValues,
        ),
      );
    }

    return mutations;
  }
}
