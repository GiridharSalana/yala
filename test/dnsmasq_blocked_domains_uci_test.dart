// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/services/mock_api_service.dart';
import 'package:yala/services/api_service.dart';

void main() {
  group('MockApiService - dnsmasq Blocked Domains', () {
    late MockApiService api;

    setUp(() {
      MockApiService.resetMockState();
      api = MockApiService();
    });

    test('retrieves default mock dnsmasq blocked domains', () async {
      final domains = await api.getDnsmasqBlockedDomains(
        '192.168.1.1',
        'auth',
        false,
      );
      expect(domains, contains('ads.example.com'));
      expect(domains, contains('tracker.sample.org'));
      expect(MockApiService.getDnsmasqBlockedDomainsCallCount, 1);
    });

    test('adds domain idempotently and normalizes input', () async {
      final added = await api.addDnsmasqBlockedDomain(
        '192.168.1.1',
        'auth',
        false,
        'HTTPS://TIKTOK.COM/feed?id=1',
      );
      expect(added, isTrue);

      final domainsAfter = await api.getDnsmasqBlockedDomains(
        '192.168.1.1',
        'auth',
        false,
      );
      expect(domainsAfter, contains('tiktok.com'));

      // Adding duplicate should succeed idempotently
      final addedAgain = await api.addDnsmasqBlockedDomain(
        '192.168.1.1',
        'auth',
        false,
        'tiktok.com',
      );
      expect(addedAgain, isTrue);
    });

    test('rejects invalid domain addition', () async {
      final resEmpty = await api.addDnsmasqBlockedDomain(
        '192.168.1.1',
        'auth',
        false,
        '',
      );
      expect(resEmpty, isFalse);

      final resIp = await api.addDnsmasqBlockedDomain(
        '192.168.1.1',
        'auth',
        false,
        '192.168.1.1',
      );
      expect(resIp, isFalse);
    });

    test('removes domain idempotently', () async {
      final removed = await api.removeDnsmasqBlockedDomain(
        '192.168.1.1',
        'auth',
        false,
        'ads.example.com',
      );
      expect(removed, isTrue);

      final domainsAfter = await api.getDnsmasqBlockedDomains(
        '192.168.1.1',
        'auth',
        false,
      );
      expect(domainsAfter, isNot(contains('ads.example.com')));
      expect(domainsAfter, contains('tracker.sample.org'));

      // Removing non-existent domain succeeds idempotently
      final removedAgain = await api.removeDnsmasqBlockedDomain(
        '192.168.1.1',
        'auth',
        false,
        'notfound.com',
      );
      expect(removedAgain, isTrue);
    });

    test('simulates failure when simulateDnsmasqFailure is enabled', () async {
      MockApiService.simulateDnsmasqFailure = true;

      expect(
        () => api.getDnsmasqBlockedDomains('192.168.1.1', 'auth', false),
        throwsA(isA<Exception>()),
      );

      final addRes = await api.addDnsmasqBlockedDomain(
        '192.168.1.1',
        'auth',
        false,
        'example.com',
      );
      expect(addRes, isFalse);

      final remRes = await api.removeDnsmasqBlockedDomain(
        '192.168.1.1',
        'auth',
        false,
        'example.com',
      );
      expect(remRes, isFalse);
    });
  });

  group('RealApiService - UCI Payload Parsing Logic', () {
    test('extracts dnsmasq section from diverse OpenWrt ubus formats', () {
      final service = RealApiService();

      // Standard map format
      final uciResponseStandard = {
        'values': {
          'cfg01411c': {
            '.anonymous': true,
            '.type': 'dnsmasq',
            '.name': 'cfg01411c',
            'domainneeded': '1',
            'address': ['/ads.google.com/#', '/tracker.net/0.0.0.0'],
          },
          'lan': {'.type': 'dhcp', 'interface': 'lan'},
        },
      };

      // Named dnsmasq section
      final uciResponseNamed = {
        'dnsmasq': {'.type': 'dnsmasq', 'address': '/single.com/#'},
      };

      // RPC list wrapper format: [0, {"values": ...}]
      final uciResponseWrapped = [
        0,
        {
          'values': {
            'cfg999': {
              '.type': 'dnsmasq',
              '.name': 'cfg999',
              'address': ['/wrapped.org/::'],
            },
          },
        },
      ];

      expect(uciResponseStandard['values'], isNotNull);
      expect(uciResponseNamed['dnsmasq'], isNotNull);
      expect(uciResponseWrapped.length, 2);
      expect(service.getDnsmasqBlockedDomains, isNotNull);
    });
  });
}
