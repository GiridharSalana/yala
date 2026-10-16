// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/domain_blocking/models/domain_block_rule.dart';

void main() {
  group('DomainValidator - Normalization', () {
    test('strips http and https schemes and paths', () {
      expect(
        DomainValidator.normalize('https://example.com/path?foo=bar#frag'),
        'example.com',
      );
      expect(
        DomainValidator.normalize('http://sub.domain.org/nested/path/'),
        'sub.domain.org',
      );
    });

    test('strips port numbers and user credentials', () {
      expect(
        DomainValidator.normalize('http://user:password@tracker.adservice.net:8443/ping'),
        'tracker.adservice.net',
      );
      expect(
        DomainValidator.normalize('adserver.com:8080'),
        'adserver.com',
      );
    });

    test('converts uppercase to lowercase', () {
      expect(DomainValidator.normalize('TIKTOK.COM'), 'tiktok.com');
      expect(DomainValidator.normalize('Ads.Google.COM'), 'ads.google.com');
    });

    test('strips leading wildcard prefixes and dots', () {
      expect(DomainValidator.normalize('*.doubleclick.net'), 'doubleclick.net');
      expect(DomainValidator.normalize('.analytics.yahoo.com'), 'analytics.yahoo.com');
      expect(DomainValidator.normalize('example.com.'), 'example.com');
    });

    test('converts IDN / non-ASCII domains to punycode', () {
      final normalized = DomainValidator.normalize('bücher.de');
      expect(normalized, isNotNull);
      expect(normalized, contains('xn--'));
    });

    test('returns null for empty or whitespace-only inputs', () {
      expect(DomainValidator.normalize(''), isNull);
      expect(DomainValidator.normalize('   '), isNull);
      expect(DomainValidator.normalize(null), isNull);
    });
  });

  group('DomainValidator - RFC 1035/1123 Validation', () {
    test('validates standard FQDNs', () {
      expect(DomainValidator.isValid('example.com'), isTrue);
      expect(DomainValidator.isValid('sub-domain.example.co.uk'), isTrue);
      expect(DomainValidator.isValid('a.b.c.d.org'), isTrue);
      expect(DomainValidator.validate('example.com'), isNull);
    });

    test('rejects empty or whitespace inputs', () {
      expect(DomainValidator.isValid(''), isFalse);
      expect(DomainValidator.validate(''), 'Domain cannot be empty');
      expect(DomainValidator.isValid('   '), isFalse);
    });

    test('rejects single label domains without dot', () {
      expect(DomainValidator.isValid('localhost'), isFalse);
      expect(
        DomainValidator.validate('localhost'),
        'Domain must contain at least one dot (e.g. example.com)',
      );
    });

    test('rejects consecutive dots', () {
      expect(DomainValidator.isValid('example..com'), isFalse);
      expect(
        DomainValidator.validate('example..com'),
        'Domain contains consecutive dots',
      );
    });

    test('rejects IPv4 and IPv6 addresses', () {
      expect(DomainValidator.isValid('192.168.1.1'), isFalse);
      expect(
        DomainValidator.validate('192.168.1.1'),
        'Domain blocking does not accept IP addresses',
      );
      expect(DomainValidator.isValid('10.0.0.1'), isFalse);
      expect(DomainValidator.isValid('fe80::1'), isFalse);
      expect(DomainValidator.isValid('::1'), isFalse);
    });

    test('rejects labels starting or ending with a hyphen', () {
      expect(DomainValidator.isValid('-example.com'), isFalse);
      expect(DomainValidator.isValid('example-.com'), isFalse);
    });

    test('rejects purely numeric top-level domains', () {
      expect(DomainValidator.isValid('example.123'), isFalse);
      expect(
        DomainValidator.validate('example.123'),
        'Top-level domain cannot be purely numeric',
      );
    });

    test('rejects labels exceeding 63 characters', () {
      final longLabel = 'a' * 64;
      expect(DomainValidator.isValid('$longLabel.com'), isFalse);
      expect(
        DomainValidator.validate('$longLabel.com'),
        contains('exceeds maximum length of 63 characters'),
      );
    });

    test('rejects domain exceeding 253 characters', () {
      final longDomain =
          '${'a' * 50}.${'b' * 50}.${'c' * 50}.${'d' * 50}.${'e' * 50}.com';
      expect(longDomain.length, greaterThan(253));
      expect(DomainValidator.isValid(longDomain), isFalse);
    });
  });

  group('DomainValidator - AdGuard Rule Parser', () {
    test('extracts domain from standard block rules', () {
      expect(
        DomainValidator.parseBlockedDomainFromAdGuardRule('||example.com^'),
        'example.com',
      );
      expect(
        DomainValidator.parseBlockedDomainFromAdGuardRule('||sub.ads.org^'),
        'sub.ads.org',
      );
      expect(
        DomainValidator.parseBlockedDomainFromAdGuardRule('||tracker.net^\$important'),
        'tracker.net',
      );
    });

    test('ignores allowlist rules starting with @@', () {
      expect(
        DomainValidator.parseBlockedDomainFromAdGuardRule('@@||allowed.workplace.com^'),
        isNull,
      );
    });

    test('ignores comments and empty lines', () {
      expect(DomainValidator.parseBlockedDomainFromAdGuardRule('! Comment line'), isNull);
      expect(DomainValidator.parseBlockedDomainFromAdGuardRule('# Another comment'), isNull);
      expect(DomainValidator.parseBlockedDomainFromAdGuardRule(''), isNull);
    });
  });

  group('DomainValidator - dnsmasq Address Parser', () {
    test('extracts domain from standard null-routed address entries', () {
      expect(
        DomainValidator.parseBlockedDomainFromAddress('/example.com/#'),
        'example.com',
      );
      expect(
        DomainValidator.parseBlockedDomainFromAddress('/ads.google.com/0.0.0.0'),
        'ads.google.com',
      );
      expect(
        DomainValidator.parseBlockedDomainFromAddress('/telemetry.ms.com/::'),
        'telemetry.ms.com',
      );
      expect(
        DomainValidator.parseBlockedDomainFromAddress('/badtracker.org/'),
        'badtracker.org',
      );
    });

    test('ignores comments and non-matching formats', () {
      expect(DomainValidator.parseBlockedDomainFromAddress('# /commented.com/#'), isNull);
      expect(DomainValidator.parseBlockedDomainFromAddress(''), isNull);
      expect(DomainValidator.parseBlockedDomainFromAddress('invalid_entry'), isNull);
    });
  });

  group('DomainBlockRule - Model & Serialization', () {
    test('creates global rule with canonical properties', () {
      final rule = DomainBlockRule.global(
        domain: 'TIKTOK.COM',
        engine: DnsBlockingEngine.adguardHome,
      );

      expect(rule.domain, 'tiktok.com');
      expect(rule.scope, DomainBlockScope.global);
      expect(rule.engine, DnsBlockingEngine.adguardHome);
      expect(rule.isEnabled, isTrue);
      expect(rule.toAdGuardRule(), '||tiktok.com^');
      expect(rule.toDnsmasqAddress(), '/tiktok.com/#');
    });

    test('serializes to and from JSON', () {
      final rule = DomainBlockRule.global(
        domain: 'youtube.com',
        engine: DnsBlockingEngine.dnsmasqNative,
        comment: 'Blocked for focus',
      );

      final json = rule.toJson();
      final revived = DomainBlockRule.fromJson(json);

      expect(revived.domain, 'youtube.com');
      expect(revived.engine, DnsBlockingEngine.dnsmasqNative);
      expect(revived.scope, DomainBlockScope.global);
      expect(revived.comment, 'Blocked for focus');
      expect(revived, equals(rule));
    });
  });
}
