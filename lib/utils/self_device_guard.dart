// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yala/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yala/utils/client_naming_helper.dart';
import 'package:yala/widgets/luci_toast.dart';
import 'package:yala/widgets/luci_guardrail.dart';

class SelfDeviceGuard {
  static Set<String>? _cachedLocalIpsAndMacs;
  static DateTime? _lastCacheTime;
  static bool _hasMockAddresses = false;
  static final Map<String, Set<int>> _routerManagementPortsCache = {};

  @visibleForTesting
  static void setMockLocalAddresses(Set<String>? addresses) {
    if (addresses == null) {
      _cachedLocalIpsAndMacs = null;
      _lastCacheTime = null;
      _hasMockAddresses = false;
    } else {
      _cachedLocalIpsAndMacs = Set<String>.from(addresses);
      _lastCacheTime = DateTime.now();
      _hasMockAddresses = true;
    }
  }

  @visibleForTesting
  static void setMockRouterManagementPorts(String routerId, Set<int>? ports) {
    if (ports == null) {
      _routerManagementPortsCache.remove(routerId);
    } else {
      _routerManagementPortsCache[routerId] = ports;
    }
  }

  /// Caches discovered management ports for a given router.
  static void setDiscoveredManagementPorts(String routerId, Set<int> ports) {
    _routerManagementPortsCache[routerId] = ports;
  }

  /// Returns known management ports for [routerId], always including well-known {22, 80, 443}.
  static Set<int> getDiscoveredManagementPorts([String? routerId]) {
    final standard = <int>{22, 80, 443};
    if (routerId != null && _routerManagementPortsCache.containsKey(routerId)) {
      return {...standard, ..._routerManagementPortsCache[routerId]!};
    }
    if (_routerManagementPortsCache.isNotEmpty) {
      final allCached = <int>{};
      for (final p in _routerManagementPortsCache.values) {
        allCached.addAll(p);
      }
      return {...standard, ...allCached};
    }
    return standard;
  }

  /// Clears discovered management ports cache. If [routerId] is provided, clears only that router.
  static void clearDiscoveredManagementPorts([String? routerId]) {
    if (routerId != null) {
      _routerManagementPortsCache.remove(routerId);
    } else {
      _routerManagementPortsCache.clear();
    }
  }

  /// Fetches all active local network IP addresses and MAC addresses of this device.
  static Future<Set<String>> getLocalDeviceAddresses() async {
    if (_hasMockAddresses && _cachedLocalIpsAndMacs != null) {
      return _cachedLocalIpsAndMacs!;
    }
    final now = DateTime.now();
    if (_cachedLocalIpsAndMacs != null &&
        _lastCacheTime != null &&
        now.difference(_lastCacheTime!) < const Duration(seconds: 10)) {
      return _cachedLocalIpsAndMacs!;
    }

    final addresses = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      ).timeout(const Duration(seconds: 2), onTimeout: () => []);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final clean = addr.address.toLowerCase().trim();
          if (clean.isNotEmpty) {
            addresses.add(clean);
          }
        }
      }
    } catch (_) {}

    _cachedLocalIpsAndMacs = addresses;
    _lastCacheTime = now;
    return addresses;
  }

  /// Normalizes MAC address string for comparison (e.g., 'AA:BB:CC:DD:EE:FF')
  static String normalizeMac(String mac) {
    return ClientNamingHelper.normalizeMac(mac);
  }

  /// Checks if target MAC or target IP belongs to the current device running this app.
  static Future<bool> isSelfDevice(
    String? targetMac, [
    String? targetIp,
  ]) async {
    final addresses = await getLocalDeviceAddresses();

    if (targetIp != null && targetIp.isNotEmpty && targetIp != 'N/A') {
      final cleanIp = targetIp.toLowerCase().trim();
      if (addresses.contains(cleanIp)) return true;

      if (cleanIp.contains('/')) {
        for (final addr in addresses) {
          if (Ipv4CidrUtil.containsCidr(cleanIp, addr)) return true;
        }

        final parsedCidr = cleanIp.split('/');
        if (parsedCidr.length == 2) {
          final prefix = int.tryParse(parsedCidr[1]);
          final netBytes = Ipv6AddressUtil.tryParse(parsedCidr[0]);
          if (prefix != null && netBytes != null) {
            for (final addr in addresses) {
              final candBytes = Ipv6AddressUtil.tryParse(addr);
              if (candBytes != null &&
                  Ipv6AddressUtil.containsIp(netBytes, candBytes, prefix)) {
                return true;
              }
            }
          }
        }
      } else {
        final targetBytes = Ipv6AddressUtil.tryParse(cleanIp);
        if (targetBytes != null) {
          for (final addr in addresses) {
            final candBytes = Ipv6AddressUtil.tryParse(addr);
            if (candBytes != null && listEquals(candBytes, targetBytes)) {
              return true;
            }
          }
        }
      }
    }

    if (targetMac != null && targetMac.isNotEmpty && targetMac != 'N/A') {
      final normTargetMac = normalizeMac(targetMac);
      for (final addr in addresses) {
        if (normalizeMac(addr) == normTargetMac) return true;
      }
    }

    return false;
  }

  /// Evaluates whether a proposed firewall custom rule presents an indirect or direct
  /// lockout risk to the managing device's management path.
  static Future<bool> isManagementLockoutRisk({
    required String target,
    required String srcZone,
    String? destZone,
    List<String> srcMac = const [],
    String? srcIp,
    String? destPort,
    String? proto,
    Set<int>? managementPorts,
    String? routerId,
  }) async {
    final cleanTarget = target.trim().toUpperCase();
    if (cleanTarget != 'DROP' && cleanTarget != 'REJECT') {
      return false;
    }

    // Direct MAC check
    for (final mac in srcMac) {
      if (await isSelfDevice(mac)) return true;
    }

    // Direct IP or CIDR check
    if (srcIp != null &&
        srcIp.trim().isNotEmpty &&
        srcIp.trim() != '*' &&
        srcIp.trim().toLowerCase() != 'any') {
      if (await isSelfDevice(null, srcIp)) return true;
    }

    // Indirect broad lockout check:
    // If neither srcMac nor srcIp restricts the source host, rule matches ALL hosts in srcZone.
    final isUnrestrictedSource =
        srcMac.isEmpty &&
        (srcIp == null ||
            srcIp.trim().isEmpty ||
            srcIp.trim() == '*' ||
            srcIp.trim().toLowerCase() == 'any');

    if (isUnrestrictedSource) {
      final cleanSrcZone = srcZone.trim().toLowerCase();
      // Managing device connects from LAN or inter-zone bridge
      if (cleanSrcZone == 'lan' || cleanSrcZone == '*') {
        final cleanDestZone = destZone?.trim().toLowerCase() ?? '';
        // Router input traffic has destZone empty or matching input, or inter-zone wildcard
        final isInputOrWildcard =
            cleanDestZone.isEmpty ||
            cleanDestZone == '*' ||
            cleanDestZone == 'lan';

        if (isInputOrWildcard) {
          final isTcp = FirewallValidator.protocolsOverlap(proto, 'tcp');
          if (isTcp) {
            final effectiveMgmtPorts =
                managementPorts ?? getDiscoveredManagementPorts(routerId);
            final isDestPortManagement =
                destPort == null ||
                destPort.trim().isEmpty ||
                destPort.trim() == '*' ||
                destPort.trim().toLowerCase() == 'any' ||
                effectiveMgmtPorts.any(
                  (p) => FirewallValidator.portsOverlap(destPort, p.toString()),
                );
            if (isDestPortManagement) {
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  /// Prompts a guardrail confirmation dialog if the target MAC or IP belongs to this device.
  /// Returns `true` if it's safe to proceed (either not self-device, or user explicitly confirmed).
  static Future<bool> checkSelfActionGuardrail(
    BuildContext context, {
    required String actionName,
    String? targetMac,
    String? targetIp,
    String? targetHostname,
  }) async {
    final isSelf = await isSelfDevice(targetMac, targetIp);
    if (!isSelf || !context.mounted) return true;

    final displayName =
        targetHostname ?? targetIp ?? targetMac ?? 'Current Device';

    final confirmed = await LuciGuardrail.showConfirmation(
      context,
      title: 'Managing Device Warning',
      subtitle:
          'Target ($displayName) is the phone/device currently running this app.\n\nPerforming "$actionName" on your own managing device will sever your router connection and disconnect this app session.',
      confirmLabel: 'Proceed Anyway',
      cancelLabel: 'Cancel (Recommended)',
      icon: Icons.phonelink_setup_rounded,
      iconColor: Colors.amber.shade900,
      isDestructive: true,
      barrierDismissible: false,
    );

    if (context.mounted) {
      if (confirmed != true) {
        LuciToastManager.showGuardrail(
          context,
          'Action Aborted by Guardrail',
          subtitle:
              'Modification on active managing device cancelled for safety.',
        );
      } else {
        LuciToastManager.showWarning(
          context,
          'Self-Device Guardrail Bypassed',
          subtitle: 'Proceeding with "$actionName" on managing device.',
        );
      }
    }

    return confirmed == true;
  }
}
