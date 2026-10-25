// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Supported backend DNS engines for domain nullification and filtering.
enum DnsBlockingEngine {
  /// AdGuard Home running as a local or upstream daemon.
  adguardHome,

  /// Native OpenWrt dnsmasq resolver using UCI configuration.
  dnsmasqNative,

  /// No active blocking engine available (e.g. missing capabilities or read-only).
  none,
}

/// Target scope of a domain blocking rule.
enum DomainBlockScope {
  /// Applies network-wide to all clients resolving through the router.
  global,

  /// Targets a specific device via IP, MAC, or client attribution.
  perDevice,
}

/// Robust RFC 1035 / RFC 1123 domain validation and normalization helper.
class DomainValidator {
  static final RegExp _ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  static final RegExp _labelValidPattern = RegExp(
    r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
  );

  /// Validates a raw user domain input string.
  ///
  /// Returns `null` if the domain is valid, or an error message explaining the failure.
  static String? validate(String? input) {
    if (input == null || input.trim().isEmpty) {
      return 'Domain cannot be empty';
    }

    final normalized = normalize(input);
    if (normalized == null || normalized.isEmpty) {
      return 'Invalid domain format';
    }

    if (normalized.length > 253) {
      return 'Domain exceeds maximum length of 253 characters';
    }

    if (_ipv4Pattern.hasMatch(normalized) || normalized.contains(':')) {
      return 'Domain blocking does not accept IP addresses';
    }

    if (!normalized.contains('.')) {
      return 'Domain must contain at least one dot (e.g. example.com)';
    }

    if (normalized.contains('..')) {
      return 'Domain contains consecutive dots';
    }

    final labels = normalized.split('.');
    for (int i = 0; i < labels.length; i++) {
      final label = labels[i];
      if (label.isEmpty) {
        return 'Domain labels cannot be empty';
      }
      if (label.length > 63) {
        return 'Domain label "$label" exceeds maximum length of 63 characters';
      }
      if (label.startsWith('-') || label.endsWith('-')) {
        return 'Domain label cannot start or end with a hyphen';
      }

      // Check ASCII or punycode label syntax
      if (!_labelValidPattern.hasMatch(label)) {
        return 'Domain contains invalid characters in label "$label"';
      }
    }

    // Top-level domain must not be purely numeric
    final tld = labels.last;
    if (RegExp(r'^\d+$').hasMatch(tld)) {
      return 'Top-level domain cannot be purely numeric';
    }

    return null;
  }

  /// Returns `true` if the input is a valid domain name.
  static bool isValid(String? input) => validate(input) == null;

  /// Extracts the blocked domain from an AdGuard user rule (e.g., '||example.com^').
  ///
  /// Returns null if the rule is an allowlist rule ('@@||...'), a comment, or doesn't match standard domain blocking syntax.
  static String? parseBlockedDomainFromAdGuardRule(String rawRule) {
    final trimmed = rawRule.trim();
    if (trimmed.isEmpty || trimmed.startsWith('!') || trimmed.startsWith('#')) {
      return null;
    }
    // Allowlist rules start with @@
    if (trimmed.startsWith('@@')) return null;
    // Standard block rule: ||domain.com^
    if (trimmed.startsWith('||')) {
      var rest = trimmed.substring(2);
      final caretIndex = rest.indexOf('^');
      if (caretIndex != -1) {
        rest = rest.substring(0, caretIndex);
      }
      final dollarIndex = rest.indexOf(r'$');
      if (dollarIndex != -1) {
        rest = rest.substring(0, dollarIndex);
      }
      final norm = normalize(rest);
      return (norm != null && isValid(norm)) ? norm : null;
    }
    return null;
  }

  /// Extracts the blocked domain from a dnsmasq address entry (e.g., '/example.com/#').
  ///
  /// Matches null-routed address patterns like `/domain.com/#`, `/domain.com/0.0.0.0`, `/domain.com/::`, or `/domain.com/`.
  static String? parseBlockedDomainFromAddress(String rawEntry) {
    final trimmed = rawEntry.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    if (trimmed.startsWith('/')) {
      final parts = trimmed.substring(1).split('/');
      if (parts.isNotEmpty && parts[0].isNotEmpty) {
        final candidate = parts[0].trim();
        final suffix = parts.length > 1 ? parts[1].trim() : '';
        if (suffix == '#' ||
            suffix == '0.0.0.0' ||
            suffix == '::' ||
            suffix == '127.0.0.1' ||
            suffix.isEmpty) {
          final norm = normalize(candidate);
          return (norm != null && isValid(norm)) ? norm : null;
        }
      }
    }
    return null;
  }

  /// Normalizes a raw domain or URL string into a canonical, lowercase domain name.
  ///
  /// Features:
  /// - Strips `http://`, `https://`, and other protocol schemes.
  /// - Strips port numbers, query strings, fragments, and URL paths.
  /// - Strips leading wildcard prefixes (e.g., `*.example.com` -> `example.com`).
  /// - Strips leading/trailing dots and whitespace.
  /// - Converts internationalized domain names (IDN) to punycode ASCII via [Uri].
  static String? normalize(String? input) {
    if (input == null) return null;
    String raw = input.trim();
    if (raw.isEmpty) return null;

    // 1. Strip protocol scheme if provided (e.g. http://, https://, ftp://)
    final schemeIndex = raw.indexOf('://');
    if (schemeIndex != -1) {
      raw = raw.substring(schemeIndex + 3);
    }

    // 2. Strip credentials if present (e.g. user:pass@domain.com)
    final atIndex = raw.indexOf('@');
    if (atIndex != -1) {
      raw = raw.substring(atIndex + 1);
    }

    // 3. Strip path, query, and fragment (e.g. domain.com/path?arg=1#frag)
    final pathSeparatorIndex = raw.indexOf(RegExp(r'[/?#]'));
    if (pathSeparatorIndex != -1) {
      raw = raw.substring(0, pathSeparatorIndex);
    }

    // 4. Strip port number (e.g. domain.com:8080)
    final colonIndex = raw.indexOf(':');
    if (colonIndex != -1 && !raw.contains(']')) {
      // Avoid stripping IPv6 address bracketed colons prematurely
      raw = raw.substring(0, colonIndex);
    }

    // 5. Strip leading wildcard (e.g. *.example.com -> example.com)
    if (raw.startsWith('*.')) {
      raw = raw.substring(2);
    } else if (raw.startsWith('.')) {
      raw = raw.substring(1);
    }

    // 6. Strip trailing dots (e.g. example.com. -> example.com)
    while (raw.endsWith('.')) {
      raw = raw.substring(0, raw.length - 1);
    }

    raw = raw.trim().toLowerCase();
    if (raw.isEmpty) return null;

    // 7. Convert IDN non-ASCII labels to ASCII Punycode (RFC 3492)
    return toPunycode(raw);
  }

  /// Converts an IDN domain name to ASCII Punycode (e.g. 'bücher.de' -> 'xn--bcher-kva.de').
  static String toPunycode(String domain) {
    return domain.split('.').map(_encodePunycodeLabel).join('.');
  }

  static String _encodePunycodeLabel(String label) {
    if (label.isEmpty) return label;
    final runes = label.runes.toList();
    if (!runes.any((r) => r >= 128)) {
      return label;
    }

    const base = 36;
    const tMin = 1;
    const tMax = 26;
    const skew = 38;
    const damp = 700;
    const initialBias = 72;
    const initialN = 128;

    int adapt(int delta, int numPoints, bool firstTime) {
      var d = firstTime ? delta ~/ damp : delta ~/ 2;
      d += d ~/ numPoints;
      var k = 0;
      while (d > ((base - tMin) * tMax) ~/ 2) {
        d ~/= (base - tMin);
        k += base;
      }
      return k + (((base - tMin + 1) * d) ~/ (d + skew));
    }

    int encodeDigit(int d) {
      if (d < 26) return 97 + d; // 'a' - 'z'
      return 48 + (d - 26); // '0' - '9'
    }

    final output = StringBuffer();
    for (final r in runes) {
      if (r < 128) {
        output.writeCharCode(r);
      }
    }

    final basicCount = output.length;
    var h = basicCount;
    if (basicCount > 0) {
      output.write('-');
    }

    var n = initialN;
    var delta = 0;
    var bias = initialBias;

    while (h < runes.length) {
      var m = 0x7FFFFFFF;
      for (final r in runes) {
        if (r >= n && r < m) {
          m = r;
        }
      }

      delta += (m - n) * (h + 1);
      n = m;

      for (final r in runes) {
        if (r < n) {
          delta++;
        } else if (r == n) {
          var q = delta;
          for (var k = base; ; k += base) {
            final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
            if (q < t) break;
            final digit = t + ((q - t) % (base - t));
            output.writeCharCode(encodeDigit(digit));
            q = (q - t) ~/ (base - t);
          }
          output.writeCharCode(encodeDigit(q));
          bias = adapt(delta, h + 1, h == basicCount);
          delta = 0;
          h++;
        }
      }
      delta++;
      n++;
    }

    return 'xn--$output';
  }
}

/// Representation of a single domain-blocking rule.
@immutable
class DomainBlockRule {
  /// Canonical domain name (e.g., 'tiktok.com', 'ads.google.com').
  final String domain;

  /// Underlying raw pattern string (e.g. '||example.com^' or '/example.com/#').
  final String? rawPattern;

  /// The engine responsible for enforcing this rule.
  final DnsBlockingEngine engine;

  /// Scope of enforcement (global network-wide or specific device).
  final DomainBlockScope scope;

  /// Target device MAC address (if [scope] is [DomainBlockScope.perDevice]).
  final String? targetMac;

  /// Target device IP address (if [scope] is [DomainBlockScope.perDevice]).
  final String? targetIp;

  /// Whether this blocking rule is currently enabled.
  final bool isEnabled;

  /// Timestamp when this rule was added.
  final DateTime? createdAt;

  /// Optional comment or description.
  final String? comment;

  const DomainBlockRule({
    required this.domain,
    this.rawPattern,
    required this.engine,
    this.scope = DomainBlockScope.global,
    this.targetMac,
    this.targetIp,
    this.isEnabled = true,
    this.createdAt,
    this.comment,
  });

  /// Factory creating a global rule from a domain string and engine.
  factory DomainBlockRule.global({
    required String domain,
    required DnsBlockingEngine engine,
    String? rawPattern,
    bool isEnabled = true,
    DateTime? createdAt,
    String? comment,
  }) {
    final norm =
        DomainValidator.normalize(domain) ?? domain.trim().toLowerCase();
    return DomainBlockRule(
      domain: norm,
      rawPattern: rawPattern,
      engine: engine,
      scope: DomainBlockScope.global,
      isEnabled: isEnabled,
      createdAt: createdAt ?? DateTime.now(),
      comment: comment,
    );
  }

  /// Converts this rule to an AdGuard Home user rule string (e.g. '||example.com^').
  String toAdGuardRule() {
    return '||$domain^';
  }

  /// Converts this rule to a native dnsmasq address option string (e.g. '/example.com/#').
  String toDnsmasqAddress() {
    return '/$domain/#';
  }

  DomainBlockRule copyWith({
    String? domain,
    String? rawPattern,
    DnsBlockingEngine? engine,
    DomainBlockScope? scope,
    String? targetMac,
    String? targetIp,
    bool? isEnabled,
    DateTime? createdAt,
    String? comment,
  }) {
    return DomainBlockRule(
      domain: domain ?? this.domain,
      rawPattern: rawPattern ?? this.rawPattern,
      engine: engine ?? this.engine,
      scope: scope ?? this.scope,
      targetMac: targetMac ?? this.targetMac,
      targetIp: targetIp ?? this.targetIp,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      comment: comment ?? this.comment,
    );
  }

  Map<String, dynamic> toJson() => {
    'domain': domain,
    'rawPattern': rawPattern,
    'engine': engine.name,
    'scope': scope.name,
    'targetMac': targetMac,
    'targetIp': targetIp,
    'isEnabled': isEnabled,
    'createdAt': createdAt?.toIso8601String(),
    'comment': comment,
  };

  factory DomainBlockRule.fromJson(Map<String, dynamic> json) =>
      DomainBlockRule(
        domain: json['domain']?.toString() ?? '',
        rawPattern: json['rawPattern']?.toString(),
        engine: DnsBlockingEngine.values.firstWhere(
          (e) => e.name == json['engine'],
          orElse: () => DnsBlockingEngine.none,
        ),
        scope: DomainBlockScope.values.firstWhere(
          (s) => s.name == json['scope'],
          orElse: () => DomainBlockScope.global,
        ),
        targetMac: json['targetMac']?.toString(),
        targetIp: json['targetIp']?.toString(),
        isEnabled: json['isEnabled'] == true,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString())
            : null,
        comment: json['comment']?.toString(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainBlockRule &&
          runtimeType == other.runtimeType &&
          domain == other.domain &&
          engine == other.engine &&
          scope == other.scope &&
          targetMac == other.targetMac;

  @override
  int get hashCode => Object.hash(domain, engine, scope, targetMac);

  @override
  String toString() =>
      'DomainBlockRule(domain: $domain, engine: ${engine.name}, scope: ${scope.name})';
}
