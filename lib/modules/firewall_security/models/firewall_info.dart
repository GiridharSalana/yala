// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:yala/models/router_capabilities.dart';

/// Default global firewall policy.
class FirewallDefaultPolicy {
  final String sectionKey;
  final String input;
  final String output;
  final String forward;
  final bool synFlood;
  final bool flowOffloading;
  final bool flowOffloadingHw;

  const FirewallDefaultPolicy({
    this.sectionKey = '@defaults[0]',
    required this.input,
    required this.output,
    required this.forward,
    required this.synFlood,
    this.flowOffloading = false,
    this.flowOffloadingHw = false,
  });

  /// Returns true if either software or hardware flow offloading is active.
  bool get hasAnyFlowOffloading => flowOffloading || flowOffloadingHw;

  FirewallDefaultPolicy copyWith({
    String? sectionKey,
    String? input,
    String? output,
    String? forward,
    bool? synFlood,
    bool? flowOffloading,
    bool? flowOffloadingHw,
  }) {
    return FirewallDefaultPolicy(
      sectionKey: sectionKey ?? this.sectionKey,
      input: input ?? this.input,
      output: output ?? this.output,
      forward: forward ?? this.forward,
      synFlood: synFlood ?? this.synFlood,
      flowOffloading: flowOffloading ?? this.flowOffloading,
      flowOffloadingHw: flowOffloadingHw ?? this.flowOffloadingHw,
    );
  }

  factory FirewallDefaultPolicy.fromJson(
    Map<String, dynamic>? json, {
    String sectionKey = '@defaults[0]',
  }) {
    if (json == null) {
      return FirewallDefaultPolicy(
        sectionKey: sectionKey,
        input: 'ACCEPT',
        output: 'ACCEPT',
        forward: 'REJECT',
        synFlood: true,
      );
    }

    final secKey = json['.name']?.toString() ?? sectionKey;

    return FirewallDefaultPolicy(
      sectionKey: secKey.isNotEmpty ? secKey : sectionKey,
      input: (json['input']?.toString() ?? 'ACCEPT').toUpperCase(),
      output: (json['output']?.toString() ?? 'ACCEPT').toUpperCase(),
      forward: (json['forward']?.toString() ?? 'REJECT').toUpperCase(),
      synFlood:
          json['syn_flood'] == '1' ||
          json['syn_flood'] == true ||
          json['synflood_protect'] == '1' ||
          json['synflood_protect'] == true,
      flowOffloading:
          json['flow_offloading'] == '1' ||
          json['flow_offloading'] == 1 ||
          json['flow_offloading'] == true ||
          json['flow_offloading'] == 'true',
      flowOffloadingHw:
          json['flow_offloading_hw'] == '1' ||
          json['flow_offloading_hw'] == 1 ||
          json['flow_offloading_hw'] == true ||
          json['flow_offloading_hw'] == 'true',
    );
  }
}

/// Firewall zone definition (e.g., LAN, WAN).
class FirewallZone {
  final String name;
  final String input;
  final String output;
  final String forward;
  final bool masquerade;
  final bool masquerade6;
  final List<String> networks;

  const FirewallZone({
    required this.name,
    required this.input,
    required this.output,
    required this.forward,
    required this.masquerade,
    this.masquerade6 = false,
    required this.networks,
  });

  factory FirewallZone.fromJson(String name, Map<String, dynamic> json) {
    final nets = <String>[];
    final netVal = json['network'];
    if (netVal is List) {
      nets.addAll(netVal.map((e) => e.toString()));
    } else if (netVal is String) {
      nets.add(netVal);
    }

    return FirewallZone(
      name: json['name']?.toString() ?? name,
      input: (json['input']?.toString() ?? 'ACCEPT').toUpperCase(),
      output: (json['output']?.toString() ?? 'ACCEPT').toUpperCase(),
      forward: (json['forward']?.toString() ?? 'REJECT').toUpperCase(),
      masquerade: json['masq'] == '1' || json['masq'] == true,
      masquerade6: json['masq6'] == '1' || json['masq6'] == true,
      networks: nets,
    );
  }
}

/// Firewall inter-zone forwarding rule (e.g. lan -> wan).
class FirewallForwarding {
  final String srcZone;
  final String destZone;

  const FirewallForwarding({required this.srcZone, required this.destZone});

  factory FirewallForwarding.fromJson(Map<String, dynamic> json) {
    return FirewallForwarding(
      srcZone: json['src']?.toString() ?? 'lan',
      destZone: json['dest']?.toString() ?? 'wan',
    );
  }
}

/// Port forwarding rule (redirect).
class FirewallPortForwarding {
  final String sectionKey;
  final String name;
  final String srcZone;
  final String srcPort;
  final String destZone;
  final String destIp;
  final String destPort;
  final String proto;
  final String? srcIp;
  final bool reflection;
  final bool enabled;
  final String family;
  final String target;
  final Map<String, dynamic> rawUciValues;

  const FirewallPortForwarding({
    this.sectionKey = '',
    required this.name,
    required this.srcZone,
    required this.srcPort,
    required this.destZone,
    required this.destIp,
    required this.destPort,
    required this.proto,
    this.srcIp,
    this.reflection = true,
    this.enabled = true,
    this.family = 'any',
    this.target = 'DNAT',
    this.rawUciValues = const {},
  });

  FirewallPortForwarding copyWith({
    String? sectionKey,
    String? name,
    String? srcZone,
    String? srcPort,
    String? destZone,
    String? destIp,
    String? destPort,
    String? proto,
    String? srcIp,
    bool? reflection,
    bool? enabled,
    String? family,
    String? target,
    Map<String, dynamic>? rawUciValues,
  }) {
    return FirewallPortForwarding(
      sectionKey: sectionKey ?? this.sectionKey,
      name: name ?? this.name,
      srcZone: srcZone ?? this.srcZone,
      srcPort: srcPort ?? this.srcPort,
      destZone: destZone ?? this.destZone,
      destIp: destIp ?? this.destIp,
      destPort: destPort ?? this.destPort,
      proto: proto ?? this.proto,
      srcIp: srcIp ?? this.srcIp,
      reflection: reflection ?? this.reflection,
      enabled: enabled ?? this.enabled,
      family: family ?? this.family,
      target: target ?? this.target,
      rawUciValues: rawUciValues ?? this.rawUciValues,
    );
  }

  factory FirewallPortForwarding.fromJson(
    Map<String, dynamic> json, [
    String? sectionKey,
  ]) {
    final sec = json['.name']?.toString() ?? sectionKey ?? '';
    final rawTarget = (json['target']?.toString() ?? 'DNAT').toUpperCase();
    final rawFamily = json['family']?.toString().toLowerCase() ?? 'any';
    final rawProto = json['proto']?.toString().toLowerCase() ?? 'tcp';
    final reflectionVal = json['reflection'];
    final bool isReflection = reflectionVal == null ||
        reflectionVal == '1' ||
        reflectionVal == 1 ||
        reflectionVal == true ||
        reflectionVal == 'true';
    final enabledVal = json['enabled'];
    final bool isEnabled = enabledVal == null ||
        (enabledVal != '0' &&
            enabledVal != 0 &&
            enabledVal != false &&
            enabledVal != 'false');

    return FirewallPortForwarding(
      sectionKey: sec,
      name: json['name']?.toString() ?? (sec.isNotEmpty ? sec : 'Redirect'),
      srcZone: json['src']?.toString() ?? 'wan',
      srcPort:
          json['src_dport']?.toString() ??
          json['src_port']?.toString() ??
          'Any',
      destZone: json['dest']?.toString() ?? 'lan',
      destIp: json['dest_ip']?.toString() ?? 'Any',
      destPort:
          json['dest_port']?.toString() ??
          json['src_dport']?.toString() ??
          'Any',
      proto: rawProto,
      srcIp: json['src_ip']?.toString(),
      reflection: isReflection,
      enabled: isEnabled,
      family: rawFamily,
      target: rawTarget,
      rawUciValues: Map<String, dynamic>.from(json),
    );
  }

  Map<String, String> toUciValues() {
    final values = <String, String>{
      'name': name,
      'src': srcZone,
      'dest': destZone,
      'proto': proto,
      'target': target,
      'enabled': enabled ? '1' : '0',
    };
    if (srcPort.isNotEmpty && srcPort != 'Any') {
      values['src_dport'] = srcPort;
    }
    if (destPort.isNotEmpty && destPort != 'Any') {
      values['dest_port'] = destPort;
    }
    if (destIp.isNotEmpty && destIp != 'Any') {
      values['dest_ip'] = destIp;
    }
    if (srcIp != null && srcIp!.trim().isNotEmpty && srcIp != 'Any') {
      values['src_ip'] = srcIp!.trim();
    }
    if (!reflection) {
      values['reflection'] = '0';
    }
    if (family != 'any' && family.isNotEmpty) {
      values['family'] = family;
    }
    return values;
  }

  Map<String, dynamic> toJson() => {
    'sectionKey': sectionKey,
    'name': name,
    'srcZone': srcZone,
    'srcPort': srcPort,
    'destZone': destZone,
    'destIp': destIp,
    'destPort': destPort,
    'proto': proto,
    if (srcIp != null) 'srcIp': srcIp,
    'reflection': reflection,
    'enabled': enabled,
    'family': family,
    'target': target,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FirewallPortForwarding &&
        other.sectionKey == sectionKey &&
        other.name == name &&
        other.srcZone == srcZone &&
        other.srcPort == srcPort &&
        other.destZone == destZone &&
        other.destIp == destIp &&
        other.destPort == destPort &&
        other.proto == proto &&
        other.srcIp == srcIp &&
        other.reflection == reflection &&
        other.enabled == enabled &&
        other.family == family &&
        other.target == target;
  }

  @override
  int get hashCode => Object.hash(
    sectionKey,
    name,
    srcZone,
    srcPort,
    destZone,
    destIp,
    destPort,
    proto,
    srcIp,
    reflection,
    enabled,
    family,
    target,
  );
}

/// Custom security rule.
class FirewallCustomRule {
  final String sectionKey;
  final String name;
  final String srcZone;
  final String destZone;
  final String target;
  final bool enabled;
  final bool isUnrecognizedTarget;
  final String proto;
  final List<String> srcMac;
  final String? srcIp;
  final String? destIp;
  final String? destPort;
  final String family;
  final int? position;
  final Map<String, dynamic> rawUciValues;

  static const List<String> knownTargets = [
    'ACCEPT',
    'REJECT',
    'DROP',
    'DNAT',
    'SNAT',
    'MASQUERADE',
    'NOTRACK',
    'HELPER',
    'MARK',
    'DSCP',
  ];

  const FirewallCustomRule({
    required this.sectionKey,
    required this.name,
    required this.srcZone,
    required this.destZone,
    required this.target,
    required this.enabled,
    this.isUnrecognizedTarget = false,
    this.proto = 'any',
    this.srcMac = const [],
    this.srcIp,
    this.destIp,
    this.destPort,
    this.family = 'any',
    this.position,
    this.rawUciValues = const {},
  });

  FirewallCustomRule copyWith({
    String? sectionKey,
    String? name,
    String? srcZone,
    String? destZone,
    String? target,
    bool? enabled,
    bool? isUnrecognizedTarget,
    String? proto,
    List<String>? srcMac,
    String? srcIp,
    String? destIp,
    String? destPort,
    String? family,
    int? position,
    Map<String, dynamic>? rawUciValues,
  }) {
    return FirewallCustomRule(
      sectionKey: sectionKey ?? this.sectionKey,
      name: name ?? this.name,
      srcZone: srcZone ?? this.srcZone,
      destZone: destZone ?? this.destZone,
      target: target ?? this.target,
      enabled: enabled ?? this.enabled,
      isUnrecognizedTarget: isUnrecognizedTarget ?? this.isUnrecognizedTarget,
      proto: proto ?? this.proto,
      srcMac: srcMac ?? this.srcMac,
      srcIp: srcIp ?? this.srcIp,
      destIp: destIp ?? this.destIp,
      destPort: destPort ?? this.destPort,
      family: family ?? this.family,
      position: position ?? this.position,
      rawUciValues: rawUciValues ?? this.rawUciValues,
    );
  }

  factory FirewallCustomRule.fromJson(String key, Map<String, dynamic> json) {
    final rawTarget = (json['target']?.toString() ?? 'ACCEPT').toUpperCase();
    final isUnknown = !knownTargets.contains(rawTarget);
    final secName = json['.name']?.toString() ?? key;

    final List<String> parsedSrcMac = [];
    final rawSrcMac = json['src_mac'];
    if (rawSrcMac is List) {
      parsedSrcMac.addAll(
        rawSrcMac.map((e) => e.toString().toUpperCase().replaceAll('-', ':')),
      );
    } else if (rawSrcMac != null && rawSrcMac.toString().trim().isNotEmpty) {
      parsedSrcMac.add(
        rawSrcMac.toString().toUpperCase().replaceAll('-', ':'),
      );
    }

    final rawProto = json['proto']?.toString().toLowerCase() ?? 'any';
    final rawFamily = json['family']?.toString().toLowerCase() ?? 'any';

    return FirewallCustomRule(
      sectionKey: secName.isNotEmpty ? secName : key,
      name: json['name']?.toString() ?? 'Custom Rule',
      srcZone: json['src']?.toString() ?? 'wan',
      destZone: json['dest']?.toString() ?? 'lan',
      target: rawTarget,
      enabled:
          json['enabled'] != '0' &&
          json['enabled'] != 0 &&
          json['enabled'] != false,
      isUnrecognizedTarget: isUnknown,
      proto: rawProto,
      srcMac: parsedSrcMac,
      srcIp: json['src_ip']?.toString(),
      destIp: json['dest_ip']?.toString(),
      destPort:
          json['dest_port']?.toString() ?? json['dest_dport']?.toString(),
      family: rawFamily,
      position: json['.index'] is int ? json['.index'] as int : null,
      rawUciValues: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toUciValues() {
    final values = <String, dynamic>{
      'name': name,
      'src': srcZone,
      'dest': destZone,
      'target': target,
      'enabled': enabled ? '1' : '0',
    };
    if (proto.isNotEmpty && proto != 'any') {
      values['proto'] = proto;
    }
    if (srcMac.isNotEmpty) {
      values['src_mac'] = srcMac.length == 1 ? srcMac.first : srcMac;
    }
    if (srcIp != null && srcIp!.trim().isNotEmpty && srcIp != 'Any') {
      values['src_ip'] = srcIp!.trim();
    }
    if (destIp != null && destIp!.trim().isNotEmpty && destIp != 'Any') {
      values['dest_ip'] = destIp!.trim();
    }
    if (destPort != null && destPort!.trim().isNotEmpty && destPort != 'Any') {
      values['dest_port'] = destPort!.trim();
    }
    if (family.isNotEmpty && family != 'any') {
      values['family'] = family;
    }
    return values;
  }

  Map<String, dynamic> toJson() => {
    'sectionKey': sectionKey,
    'name': name,
    'srcZone': srcZone,
    'destZone': destZone,
    'target': target,
    'enabled': enabled,
    'isUnrecognizedTarget': isUnrecognizedTarget,
    'proto': proto,
    'srcMac': srcMac,
    if (srcIp != null) 'srcIp': srcIp,
    if (destIp != null) 'destIp': destIp,
    if (destPort != null) 'destPort': destPort,
    'family': family,
    if (position != null) 'position': position,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FirewallCustomRule &&
        other.sectionKey == sectionKey &&
        other.name == name &&
        other.srcZone == srcZone &&
        other.destZone == destZone &&
        other.target == target &&
        other.enabled == enabled &&
        other.isUnrecognizedTarget == isUnrecognizedTarget &&
        other.proto == proto &&
        listEquals(other.srcMac, srcMac) &&
        other.srcIp == srcIp &&
        other.destIp == destIp &&
        other.destPort == destPort &&
        other.family == family &&
        other.position == position;
  }

  @override
  int get hashCode => Object.hash(
    sectionKey,
    name,
    srcZone,
    destZone,
    target,
    enabled,
    isUnrecognizedTarget,
    proto,
    Object.hashAll(srcMac),
    srcIp,
    destIp,
    destPort,
    family,
    position,
  );
}

/// Complete firewall & security overview container.
class FirewallOverview {
  final FirewallBackend backend;
  final FirewallDefaultPolicy defaultPolicy;
  final List<FirewallZone> zones;
  final List<FirewallForwarding> forwardings;
  final List<FirewallPortForwarding> portForwards;
  final List<FirewallCustomRule> customRules;
  final bool isAvailable;
  final bool isNoCustomRules;
  final String? errorMessage;

  const FirewallOverview({
    required this.backend,
    required this.defaultPolicy,
    required this.zones,
    required this.forwardings,
    required this.portForwards,
    required this.customRules,
    required this.isAvailable,
    required this.isNoCustomRules,
    this.errorMessage,
  });

  /// Resolves the primary internal destination zone from the active firewall topology.
  String? get primaryLanZoneName {
    // 1. Look for a forwarding from an internal zone to wan
    for (final fwd in forwardings) {
      if (fwd.destZone.toLowerCase() == 'wan' &&
          fwd.srcZone.toLowerCase() != 'wan') {
        return fwd.srcZone;
      }
    }
    // 2. Look for a zone named 'lan'
    for (final zone in zones) {
      if (zone.name.toLowerCase() == 'lan') {
        return zone.name;
      }
    }
    // 3. Fallback to non-masquerading zone that is not 'wan'
    for (final zone in zones) {
      if (!zone.masquerade && !zone.name.toLowerCase().contains('wan')) {
        return zone.name;
      }
    }
    return null;
  }

  factory FirewallOverview.unavailable(
    FirewallBackend backend, [
    String? reason,
  ]) {
    return FirewallOverview(
      backend: backend,
      defaultPolicy: const FirewallDefaultPolicy(
        input: 'ACCEPT',
        output: 'ACCEPT',
        forward: 'REJECT',
        synFlood: true,
      ),
      zones: const [],
      forwardings: const [],
      portForwards: const [],
      customRules: const [],
      isAvailable: false,
      isNoCustomRules: false,
      errorMessage: reason ?? 'Firewall configuration unavailable',
    );
  }

  factory FirewallOverview.fromUciData(
    Map<String, dynamic>? uciData, {
    FirewallBackend backend = FirewallBackend.fw4,
    bool isReviewerMode = false,
  }) {
    if (uciData == null) {
      if (isReviewerMode) {
        return Fw4FirewallParser.parse({
          'values': {
            'defaults': {
              '.type': 'defaults',
              'input': 'ACCEPT',
              'output': 'ACCEPT',
              'forward': 'REJECT',
            },
            'lan': {
              '.type': 'zone',
              'name': 'lan',
              'input': 'ACCEPT',
              'output': 'ACCEPT',
              'forward': 'ACCEPT',
              'network': ['lan'],
            },
            'wan': {
              '.type': 'zone',
              'name': 'wan',
              'input': 'REJECT',
              'output': 'ACCEPT',
              'forward': 'REJECT',
              'masq': '1',
              'network': ['wan', 'wan6'],
            },
            'fwd': {'.type': 'forwarding', 'src': 'lan', 'dest': 'wan'},
            'ssh': {
              '.type': 'redirect',
              'name': 'SSH Forward',
              'src': 'wan',
              'src_dport': '2222',
              'dest': 'lan',
              'dest_ip': '192.168.1.1',
              'dest_port': '22',
              'proto': 'tcp',
            },
            'r1': {
              '.type': 'rule',
              'name': 'Allow-DHCP-Renew',
              'src': 'wan',
              'dest': 'lan',
              'target': 'ACCEPT',
              'enabled': '1',
            },
          },
        });
      }
      return FirewallOverview.unavailable(
        backend,
        'No firewall configuration data received',
      );
    }

    if (backend == FirewallBackend.fw3) {
      return Fw3FirewallParser.parse(uciData);
    } else {
      return Fw4FirewallParser.parse(uciData);
    }
  }
}

/// Dedicated Firewall3 (iptables backend) parser
class Fw3FirewallParser {
  static FirewallOverview parse(Map<String, dynamic> uciFirewallConfig) {
    try {
      final rawValues = uciFirewallConfig['values'];
      final Map<String, dynamic> uciValues = (rawValues is Map)
          ? Map<String, dynamic>.from(rawValues)
          : Map<String, dynamic>.from(uciFirewallConfig);

      if (uciValues.isEmpty) {
        return FirewallOverview.unavailable(
          FirewallBackend.fw3,
          'UCI firewall configuration payload is empty or unpopulated',
        );
      }

      Map<String, dynamic>? defaultsMap;
      String defaultsSecKey = '@defaults[0]';
      final zoneList = <FirewallZone>[];
      final fwdList = <FirewallForwarding>[];
      final pfList = <FirewallPortForwarding>[];
      final ruleList = <FirewallCustomRule>[];
      bool hasDefaultsOrZone = false;

      uciValues.forEach((key, val) {
        if (val is Map) {
          final type = val['.type']?.toString();
          if (type == 'defaults') {
            defaultsMap = Map<String, dynamic>.from(val);
            defaultsSecKey = val['.name']?.toString() ?? key;
            hasDefaultsOrZone = true;
          } else if (type == 'zone') {
            zoneList.add(
              FirewallZone.fromJson(key, Map<String, dynamic>.from(val)),
            );
            hasDefaultsOrZone = true;
          } else if (type == 'forwarding') {
            fwdList.add(
              FirewallForwarding.fromJson(Map<String, dynamic>.from(val)),
            );
          } else if (type == 'redirect') {
            pfList.add(
              FirewallPortForwarding.fromJson(
                Map<String, dynamic>.from(val),
                key,
              ),
            );
          } else if (type == 'rule') {
            ruleList.add(
              FirewallCustomRule.fromJson(key, Map<String, dynamic>.from(val)),
            );
          }
        }
      });

      if (!hasDefaultsOrZone) {
        return FirewallOverview.unavailable(
          FirewallBackend.fw3,
          'No valid firewall defaults or zone sections found in payload',
        );
      }

      final isNoCustom = ruleList.isEmpty && pfList.isEmpty;

      return FirewallOverview(
        backend: FirewallBackend.fw3,
        defaultPolicy: FirewallDefaultPolicy.fromJson(
          defaultsMap,
          sectionKey: defaultsSecKey,
        ),
        zones: zoneList,
        forwardings: fwdList,
        portForwards: pfList,
        customRules: ruleList,
        isAvailable: true,
        isNoCustomRules: isNoCustom,
      );
    } catch (e) {
      return FirewallOverview.unavailable(
        FirewallBackend.fw3,
        'Failed to parse fw3 firewall config: $e',
      );
    }
  }
}

/// Dedicated Firewall4 (nftables backend) parser
class Fw4FirewallParser {
  static FirewallOverview parse(Map<String, dynamic> uciFirewallConfig) {
    try {
      final rawValues = uciFirewallConfig['values'];
      final Map<String, dynamic> uciValues = (rawValues is Map)
          ? Map<String, dynamic>.from(rawValues)
          : Map<String, dynamic>.from(uciFirewallConfig);

      if (uciValues.isEmpty) {
        return FirewallOverview.unavailable(
          FirewallBackend.fw4,
          'UCI firewall configuration payload is empty or unpopulated',
        );
      }

      Map<String, dynamic>? defaultsMap;
      String defaultsSecKey = '@defaults[0]';
      final zoneList = <FirewallZone>[];
      final fwdList = <FirewallForwarding>[];
      final pfList = <FirewallPortForwarding>[];
      final ruleList = <FirewallCustomRule>[];
      bool hasDefaultsOrZone = false;

      uciValues.forEach((key, val) {
        if (val is Map) {
          final type = val['.type']?.toString();
          if (type == 'defaults') {
            defaultsMap = Map<String, dynamic>.from(val);
            defaultsSecKey = val['.name']?.toString() ?? key;
            hasDefaultsOrZone = true;
          } else if (type == 'zone') {
            zoneList.add(
              FirewallZone.fromJson(key, Map<String, dynamic>.from(val)),
            );
            hasDefaultsOrZone = true;
          } else if (type == 'forwarding') {
            fwdList.add(
              FirewallForwarding.fromJson(Map<String, dynamic>.from(val)),
            );
          } else if (type == 'redirect') {
            pfList.add(
              FirewallPortForwarding.fromJson(
                Map<String, dynamic>.from(val),
                key,
              ),
            );
          } else if (type == 'rule') {
            ruleList.add(
              FirewallCustomRule.fromJson(key, Map<String, dynamic>.from(val)),
            );
          }
        }
      });

      if (!hasDefaultsOrZone) {
        return FirewallOverview.unavailable(
          FirewallBackend.fw4,
          'No valid firewall defaults or zone sections found in payload',
        );
      }

      final isNoCustom = ruleList.isEmpty && pfList.isEmpty;

      return FirewallOverview(
        backend: FirewallBackend.fw4,
        defaultPolicy: FirewallDefaultPolicy.fromJson(
          defaultsMap,
          sectionKey: defaultsSecKey,
        ),
        zones: zoneList,
        forwardings: fwdList,
        portForwards: pfList,
        customRules: ruleList,
        isAvailable: true,
        isNoCustomRules: isNoCustom,
      );
    } catch (e) {
      return FirewallOverview.unavailable(
        FirewallBackend.fw4,
        'Failed to parse fw4 firewall config: $e',
      );
    }
  }
}
