// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

/// Represents a single SQM queue configuration instance in OpenWrt (/etc/config/sqm).
class SqmQueue {
  final String name;
  final bool enabled;
  final String interface;
  final int
  download; // Ingress bandwidth in kbit/s (0 to disable ingress shaping)
  final int upload; // Egress bandwidth in kbit/s (0 to disable egress shaping)
  final String qdisc; // 'cake', 'fq_codel'
  final String
  script; // 'piece_of_cake.qos', 'layer_cake.qos', 'simple.qos', 'simplest.qos', etc.
  final String linklayer; // 'none', 'ethernet', 'atm'
  final int overhead; // Per-packet framing overhead in bytes (-1500 to 1500)
  final bool qdiscAdvanced;
  final bool squashDscp;
  final bool squashIngress;
  final String ingressEcn; // 'ECN' or 'NOECN'
  final String egressEcn; // 'NOECN' or 'ECN'
  final bool debugLogging;
  final int verbosity; // 0 to 10 (default 5)

  const SqmQueue({
    required this.name,
    this.enabled = true,
    required this.interface,
    this.download = 0,
    this.upload = 0,
    this.qdisc = 'cake',
    this.script = 'piece_of_cake.qos',
    this.linklayer = 'none',
    this.overhead = 0,
    this.qdiscAdvanced = false,
    this.squashDscp = true,
    this.squashIngress = true,
    this.ingressEcn = 'ECN',
    this.egressEcn = 'NOECN',
    this.debugLogging = false,
    this.verbosity = 5,
  });

  /// Ingress download bandwidth in Mbps (rounded to 2 decimal places)
  double get downloadMbps => download / 1000.0;

  /// Egress upload bandwidth in Mbps (rounded to 2 decimal places)
  double get uploadMbps => upload / 1000.0;

  /// Whether ingress shaping is active (rate > 0)
  bool get hasIngressShaping => download > 0;

  /// Whether egress shaping is active (rate > 0)
  bool get hasEgressShaping => upload > 0;

  /// Whether this queue has non-zero shaping bandwidth configured
  bool get isConfigured => download > 0 || upload > 0;

  /// Whether this queue represents an OpenWrt default template or anonymous section
  bool get isDefaultTemplate =>
      name.startsWith('cfg') || name.startsWith('@') || name == 'eth0';

  /// Human-friendly display title for the queue, masking raw internal hashes like cfg01b68a
  String displayName({String? primaryWanInterface}) {
    if (isDefaultTemplate) {
      if (primaryWanInterface != null && interface == primaryWanInterface) {
        return 'Primary WAN Queue ($interface)';
      }
      return 'Default Queue ($interface)';
    }
    return name;
  }

  SqmQueue copyWith({
    String? name,
    bool? enabled,
    String? interface,
    int? download,
    int? upload,
    String? qdisc,
    String? script,
    String? linklayer,
    int? overhead,
    bool? qdiscAdvanced,
    bool? squashDscp,
    bool? squashIngress,
    String? ingressEcn,
    String? egressEcn,
    bool? debugLogging,
    int? verbosity,
  }) {
    return SqmQueue(
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      interface: interface ?? this.interface,
      download: download ?? this.download,
      upload: upload ?? this.upload,
      qdisc: qdisc ?? this.qdisc,
      script: script ?? this.script,
      linklayer: linklayer ?? this.linklayer,
      overhead: overhead ?? this.overhead,
      qdiscAdvanced: qdiscAdvanced ?? this.qdiscAdvanced,
      squashDscp: squashDscp ?? this.squashDscp,
      squashIngress: squashIngress ?? this.squashIngress,
      ingressEcn: ingressEcn ?? this.ingressEcn,
      egressEcn: egressEcn ?? this.egressEcn,
      debugLogging: debugLogging ?? this.debugLogging,
      verbosity: verbosity ?? this.verbosity,
    );
  }

  factory SqmQueue.fromUci(String sectionName, Map<String, dynamic> json) {
    bool parseBool(dynamic val, {bool defaultValue = false}) {
      if (val == null) return defaultValue;
      if (val is bool) return val;
      final str = val.toString().trim().toLowerCase();
      return str == '1' || str == 'true' || str == 'yes' || str == 'on';
    }

    int parseInt(dynamic val, {int defaultValue = 0}) {
      if (val == null) return defaultValue;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString().trim()) ?? defaultValue;
    }

    return SqmQueue(
      name: sectionName,
      enabled: parseBool(json['enabled'], defaultValue: false),
      interface: json['interface']?.toString().trim() ?? 'wan',
      download: parseInt(json['download'], defaultValue: 0),
      upload: parseInt(json['upload'], defaultValue: 0),
      qdisc: json['qdisc']?.toString().trim().isNotEmpty == true
          ? json['qdisc']!.toString().trim()
          : 'cake',
      script: json['script']?.toString().trim().isNotEmpty == true
          ? json['script']!.toString().trim()
          : 'piece_of_cake.qos',
      linklayer: json['linklayer']?.toString().trim().isNotEmpty == true
          ? json['linklayer']!.toString().trim()
          : 'none',
      overhead: parseInt(json['overhead'], defaultValue: 0),
      qdiscAdvanced: parseBool(json['qdisc_advanced'], defaultValue: false),
      squashDscp: parseBool(json['squash_dscp'], defaultValue: true),
      squashIngress: parseBool(json['squash_ingress'], defaultValue: true),
      ingressEcn: json['ingress_ecn']?.toString().trim() ?? 'ECN',
      egressEcn: json['egress_ecn']?.toString().trim() ?? 'NOECN',
      debugLogging: parseBool(json['debug_logging'], defaultValue: false),
      verbosity: parseInt(json['verbosity'], defaultValue: 5),
    );
  }

  Map<String, dynamic> toUciParams() {
    final params = <String, dynamic>{
      'enabled': enabled ? '1' : '0',
      'interface': interface,
      'download': download.toString(),
      'upload': upload.toString(),
      'qdisc': qdisc,
      'script': script,
      'linklayer': linklayer,
      'overhead': overhead.toString(),
      'debug_logging': debugLogging ? '1' : '0',
      'verbosity': verbosity.toString(),
    };

    if (qdiscAdvanced) {
      params['qdisc_advanced'] = '1';
      params['squash_dscp'] = squashDscp ? '1' : '0';
      params['squash_ingress'] = squashIngress ? '1' : '0';
      params['ingress_ecn'] = ingressEcn;
      params['egress_ecn'] = egressEcn;
    } else {
      params['qdisc_advanced'] = '0';
    }

    return params;
  }
}
