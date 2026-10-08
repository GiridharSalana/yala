// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'sqm_queue.dart';

/// Predefined standard SQM configuration templates natively supported by OpenWrt's sqm-scripts.
/// These templates provide one-tap configuration for all typical router connection types.
class SqmPreset {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String qdisc;
  final String script;
  final String linklayer;
  final int overhead;
  final bool qdiscAdvanced;
  final IconData icon;
  final String? badge;

  const SqmPreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.qdisc,
    required this.script,
    this.linklayer = 'none',
    this.overhead = 0,
    this.qdiscAdvanced = false,
    required this.icon,
    this.badge,
  });

  /// Standard Fiber / Direct Ethernet / Cable (CAKE)
  /// Recommended for >90% of modern internet connections.
  static const cakeFiber = SqmPreset(
    id: 'cake_fiber',
    title: 'Standard Fiber / Cable',
    subtitle: 'CAKE • Zero-Config • Best Latency',
    description:
        'Recommended for fiber, direct ethernet, and standard broadband connections. Uses CAKE with automatic flow isolation to eliminate bufferbloat.',
    qdisc: 'cake',
    script: 'piece_of_cake.qos',
    linklayer: 'none',
    overhead: 0,
    qdiscAdvanced: false,
    icon: Icons.rocket_launch_rounded,
    badge: 'Recommended',
  );

  /// VDSL / FTTH with PPPoE encapsulation
  /// Compensates for 44 bytes of PPPoE and 802.1Q VLAN framing overhead.
  static const vdslPppoe = SqmPreset(
    id: 'vdsl_pppoe',
    title: 'VDSL / FTTH PPPoE',
    subtitle: 'CAKE • 44-Byte Overhead Compensation',
    description:
        'Compensates for per-packet framing overhead on VDSL2 and fiber connections that utilize PPPoE tunneling and VLAN tagging.',
    qdisc: 'cake',
    script: 'piece_of_cake.qos',
    linklayer: 'ethernet',
    overhead: 44,
    qdiscAdvanced: false,
    icon: Icons.electrical_services_rounded,
    badge: 'PPPoE',
  );

  /// Gaming & Low-Latency VoIP (Layer CAKE)
  /// Uses Diffserv tiers to prioritize real-time interactive traffic.
  static const layerCake = SqmPreset(
    id: 'layer_cake',
    title: 'Gaming & VoIP (Layer CAKE)',
    subtitle: 'CAKE • 3-Tier Diffserv Prioritization',
    description:
        'Applies multi-tier Diffserv traffic classification. Gives top priority to online gaming packets, Discord, Zoom, and VoIP calls over background downloads.',
    qdisc: 'cake',
    script: 'layer_cake.qos',
    linklayer: 'none',
    overhead: 0,
    qdiscAdvanced: true,
    icon: Icons.sports_esports_rounded,
    badge: 'Low Ping',
  );

  /// DOCSIS Coaxial Cable Modem
  /// Compensates for 34 bytes of DOCSIS Ethernet framing overhead.
  static const docsisCable = SqmPreset(
    id: 'docsis_cable',
    title: 'DOCSIS Cable (Coax)',
    subtitle: 'CAKE • 34-Byte Overhead',
    description:
        'Optimized for coaxial cable internet providers (Comcast, Spectrum, Virgin, etc.) with 34-byte packet overhead compensation.',
    qdisc: 'cake',
    script: 'piece_of_cake.qos',
    linklayer: 'ethernet',
    overhead: 34,
    qdiscAdvanced: false,
    icon: Icons.cable_rounded,
    badge: 'Cable',
  );

  /// Lightweight / Low-CPU (FQ-CoDel)
  /// Lowest CPU usage for low-power MIPS / single-core routers.
  static const lowCpu = SqmPreset(
    id: 'low_cpu',
    title: 'Lightweight (Low CPU)',
    subtitle: 'FQ-CoDel • Minimal CPU Usage',
    description:
        'Ideal for low-power MIPS (e.g. 400-600MHz) or single-core routers to prevent the router CPU from becoming a bottleneck during fast downloads.',
    qdisc: 'fq_codel',
    script: 'simplest.qos',
    linklayer: 'none',
    overhead: 0,
    qdiscAdvanced: false,
    icon: Icons.energy_savings_leaf_rounded,
    badge: 'Low CPU',
  );

  /// ADSL ATM
  /// Compensates for ATM 53-byte cell encapsulation on copper lines.
  static const adslAtm = SqmPreset(
    id: 'adsl_atm',
    title: 'ADSL / ATM',
    subtitle: 'CAKE • 40-Byte ATM Cell Tax',
    description:
        'Compensates for 53-byte ATM cell packaging and framing tax on legacy copper ADSL and ADSL2+ lines.',
    qdisc: 'cake',
    script: 'piece_of_cake.qos',
    linklayer: 'atm',
    overhead: 40,
    qdiscAdvanced: false,
    icon: Icons.phonelink_ring_rounded,
    badge: 'ADSL',
  );

  /// Ordered list of all available templates
  static const List<SqmPreset> presets = [
    cakeFiber,
    vdslPppoe,
    layerCake,
    docsisCable,
    lowCpu,
    adslAtm,
  ];

  /// Matches a queue against known standard presets.
  /// Returns the matching preset if found, or null for custom setups.
  static SqmPreset? match(SqmQueue queue) {
    // Exact match including linklayer and overhead
    for (final p in presets) {
      if (p.qdisc == queue.qdisc &&
          p.script == queue.script &&
          p.linklayer == queue.linklayer &&
          p.overhead == queue.overhead) {
        return p;
      }
    }

    // Relaxed match on qdisc and script if overhead is default
    for (final p in presets) {
      if (p.qdisc == queue.qdisc && p.script == queue.script) {
        return p;
      }
    }

    return null;
  }
}
