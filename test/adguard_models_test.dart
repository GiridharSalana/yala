// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';

void main() {
  group('AdGuardProtectionState', () {
    final fixedNow = DateTime.utc(2026, 10, 8, 12, 0, 0);

    test('resolves enabled when protection_enabled is true', () {
      expect(
        AdGuardProtectionState.resolve({
          'protection_enabled': true,
        }, now: fixedNow),
        equals(AdGuardProtectionState.enabled),
      );
      // Even if pause duration or future timestamp is present, enabled takes precedence
      expect(
        AdGuardProtectionState.resolve({
          'protection_enabled': true,
          'protection_disabled_duration': 5000,
          'protection_disabled_until': fixedNow
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }, now: fixedNow),
        equals(AdGuardProtectionState.enabled),
      );
    });

    test(
      'resolves paused when protection_enabled is false and modern duration > 0',
      () {
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_duration': 300000,
          }, now: fixedNow),
          equals(AdGuardProtectionState.paused),
        );
      },
    );

    test(
      'modern duration takes precedence over legacy timestamp when present',
      () {
        // Modern duration = 0 (disabled) overrides future legacy timestamp
        final futureTimestamp = fixedNow
            .add(const Duration(hours: 2))
            .millisecondsSinceEpoch;
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_duration': 0,
            'protection_disabled_until': futureTimestamp,
          }, now: fixedNow),
          equals(AdGuardProtectionState.disabled),
        );

        // Modern duration > 0 (paused) overrides even an expired legacy timestamp
        final pastTimestamp = fixedNow
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch;
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_duration': 60000,
            'protection_disabled_until': pastTimestamp,
          }, now: fixedNow),
          equals(AdGuardProtectionState.paused),
        );
      },
    );

    test(
      'resolves paused when legacy protection_disabled_until is in the future',
      () {
        // Future timestamp in milliseconds
        final futureMs = fixedNow
            .add(const Duration(minutes: 30))
            .millisecondsSinceEpoch;
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_until': futureMs,
          }, now: fixedNow),
          equals(AdGuardProtectionState.paused),
        );

        // Future timestamp in seconds
        final futureSec = futureMs ~/ 1000;
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_until': futureSec,
          }, now: fixedNow),
          equals(AdGuardProtectionState.paused),
        );

        // Future timestamp as ISO 8601 string
        final futureIso = fixedNow
            .add(const Duration(minutes: 15))
            .toIso8601String();
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_until': futureIso,
          }, now: fixedNow),
          equals(AdGuardProtectionState.paused),
        );
      },
    );

    test(
      'resolves disabled when legacy protection_disabled_until is expired',
      () {
        // Past timestamp in milliseconds
        final pastMs = fixedNow
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch;
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_until': pastMs,
          }, now: fixedNow),
          equals(AdGuardProtectionState.disabled),
        );

        // Past timestamp as ISO 8601 string
        final pastIso = fixedNow
            .subtract(const Duration(hours: 1))
            .toIso8601String();
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_until': pastIso,
          }, now: fixedNow),
          equals(AdGuardProtectionState.disabled),
        );
      },
    );

    test(
      'resolves disabled when legacy timestamp is absent, null, or invalid',
      () {
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
          }, now: fixedNow),
          equals(AdGuardProtectionState.disabled),
        );
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_until': null,
          }, now: fixedNow),
          equals(AdGuardProtectionState.disabled),
        );
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_until': 'invalid_date_format',
          }, now: fixedNow),
          equals(AdGuardProtectionState.disabled),
        );
        expect(
          AdGuardProtectionState.resolve({
            'protection_enabled': false,
            'protection_disabled_until': 0,
          }, now: fixedNow),
          equals(AdGuardProtectionState.disabled),
        );
        expect(
          AdGuardProtectionState.resolve({}, now: fixedNow),
          equals(AdGuardProtectionState.disabled),
        );
      },
    );
  });

  group('AdGuardStatus & Payload Validation', () {
    test('validates genuine AdGuard status payloads', () {
      final validPayload1 = {
        'version': 'v0.107.50',
        'running': true,
        'protection_enabled': true,
        'dns_port': 53,
        'http_port': 3000,
        'dns_addresses': ['192.168.1.1', '127.0.0.1'],
      };
      expect(AdGuardStatus.isValidStatusPayload(validPayload1), isTrue);

      final validPayload2 = {'protection_enabled': false, 'dns_port': 5353};
      expect(AdGuardStatus.isValidStatusPayload(validPayload2), isTrue);

      final validPayload3 = {'version': '0.107.43', 'running': false};
      expect(AdGuardStatus.isValidStatusPayload(validPayload3), isTrue);
    });

    test('rejects arbitrary non-AdGuard payloads', () {
      expect(AdGuardStatus.isValidStatusPayload(null), isFalse);
      expect(AdGuardStatus.isValidStatusPayload({}), isFalse);
      // Generic router status or HTML captive portal JSON
      expect(
        AdGuardStatus.isValidStatusPayload({'status': 'ok', 'code': 200}),
        isFalse,
      );
      // Single generic field is insufficient
      expect(AdGuardStatus.isValidStatusPayload({'running': true}), isFalse);
    });

    test('parses status correctly from JSON', () {
      final json = {
        'version': 'v0.107.52',
        'running': true,
        'protection_enabled': false,
        'protection_disabled_duration': 180000,
        'dns_addresses': ['192.168.1.1', 'fe80::1'],
        'dns_port': 53,
        'http_port': 8080,
        'start_time': 1696700000000,
      };

      final status = AdGuardStatus.fromJson(json);
      expect(status.version, equals('v0.107.52'));
      expect(status.running, isTrue);
      expect(status.protectionState, equals(AdGuardProtectionState.paused));
      expect(status.pauseDurationMs, equals(180000));
      expect(status.dnsAddresses, equals(['192.168.1.1', 'fe80::1']));
      expect(status.dnsPort, equals(53));
      expect(status.httpPort, equals(8080));
      expect(status.startTimeMs, equals(1696700000000));
    });

    test(
      'parses status with legacy protection_disabled_until calculating remaining duration',
      () {
        final fixedNow = DateTime.utc(2026, 10, 8, 12, 0, 0);
        final futureDate = fixedNow.add(
          const Duration(minutes: 5),
        ); // 300,000 ms

        final jsonFuture = {
          'version': 'v0.107.50',
          'running': true,
          'protection_enabled': false,
          'protection_disabled_until': futureDate.millisecondsSinceEpoch,
          'dns_addresses': ['127.0.0.1'],
          'dns_port': 53,
          'http_port': 3000,
        };

        final statusFuture = AdGuardStatus.fromJson(jsonFuture, now: fixedNow);
        expect(
          statusFuture.protectionState,
          equals(AdGuardProtectionState.paused),
        );
        expect(statusFuture.pauseDurationMs, equals(300000));

        final pastDate = fixedNow.subtract(const Duration(minutes: 5));
        final jsonPast = {
          'version': 'v0.107.50',
          'running': true,
          'protection_enabled': false,
          'protection_disabled_until': pastDate.millisecondsSinceEpoch,
          'dns_addresses': ['127.0.0.1'],
          'dns_port': 53,
          'http_port': 3000,
        };

        final statusPast = AdGuardStatus.fromJson(jsonPast, now: fixedNow);
        expect(
          statusPast.protectionState,
          equals(AdGuardProtectionState.disabled),
        );
        expect(statusPast.pauseDurationMs, equals(0));
      },
    );

    test('applies safe defaults on empty or partial status JSON', () {
      final status = AdGuardStatus.fromJson({});
      expect(status.version, equals('Unknown'));
      expect(status.running, isFalse);
      expect(status.protectionState, equals(AdGuardProtectionState.disabled));
      expect(status.dnsAddresses, isEmpty);
      expect(status.dnsPort, equals(53));
      expect(status.httpPort, equals(3000));
      expect(status.startTimeMs, isNull);
    });
  });

  group('AdGuardStats & Top Lists', () {
    test('calculates block rate percentage safely with edge cases', () {
      // Normal percentage calculation
      expect(AdGuardStats.calculateBlockRate(100, 25), equals(25.0));
      expect(AdGuardStats.calculateBlockRate(200, 30), equals(15.0));

      // Division by zero
      expect(AdGuardStats.calculateBlockRate(0, 0), equals(0.0));
      expect(AdGuardStats.calculateBlockRate(0, 50), equals(0.0));

      // Negative values
      expect(AdGuardStats.calculateBlockRate(-10, 5), equals(0.0));
      expect(AdGuardStats.calculateBlockRate(100, -5), equals(0.0));

      // Blocked exceeds total (server anomaly clamp)
      expect(AdGuardStats.calculateBlockRate(100, 150), equals(100.0));
      expect(AdGuardStats.calculateBlockRate(50, 50), equals(100.0));
    });

    test('parses modern object top lists (v0.107+)', () {
      final rawDomains = [
        {'domain': 'example.com', 'count': 150},
        {'host': 'google.com', 'count': 85},
        {'domain': 'cloudflare.com', 'count': 42},
      ];
      final parsed = AdGuardStats.parseTopList(rawDomains);
      expect(parsed.length, equals(3));
      expect(parsed[0].identifier, equals('example.com'));
      expect(parsed[0].count, equals(150));
      expect(parsed[1].identifier, equals('google.com'));
      expect(parsed[1].count, equals(85));
      expect(parsed[2].identifier, equals('cloudflare.com'));
      expect(parsed[2].count, equals(42));

      final rawClients = [
        {'ip': '192.168.1.100', 'count': 500},
        {'IP': '192.168.1.101', 'count': 320},
      ];
      final parsedClients = AdGuardStats.parseTopList(rawClients);
      expect(parsedClients.length, equals(2));
      expect(parsedClients[0].identifier, equals('192.168.1.100'));
      expect(parsedClients[0].count, equals(500));
      expect(parsedClients[1].identifier, equals('192.168.1.101'));
      expect(parsedClients[1].count, equals(320));
    });

    test('parses legacy single-entry map top lists (v0.100-v0.106)', () {
      final rawLegacy = [
        {'example.com': 150},
        {'blocked.ads': 85},
      ];
      final parsed = AdGuardStats.parseTopList(rawLegacy);
      expect(parsed.length, equals(2));
      expect(parsed[0].identifier, equals('example.com'));
      expect(parsed[0].count, equals(150));
      expect(parsed[1].identifier, equals('blocked.ads'));
      expect(parsed[1].count, equals(85));
    });

    test('handles malformed top lists defensively without throwing', () {
      expect(AdGuardStats.parseTopList(null), isEmpty);
      expect(AdGuardStats.parseTopList('invalid'), isEmpty);
      expect(AdGuardStats.parseTopList([null, 42, 'string', {}]), isEmpty);

      final mixed = [
        {'domain': 'valid.org', 'count': 10},
        {'domain': '', 'count': 5},
        {'empty': null},
      ];
      final parsed = AdGuardStats.parseTopList(mixed);
      expect(parsed.length, equals(1));
      expect(parsed.first.identifier, equals('valid.org'));
      expect(parsed.first.count, equals(10));
    });

    test(
      'parses complete stats payload and preserves historical trends separately',
      () {
        final json = {
          'num_dns_queries': 10000,
          'num_blocked_filtering': 1500,
          'num_replaced_safebrowsing': 12,
          'num_replaced_safesearch': 4,
          'num_replaced_parental': 0,
          'avg_processing_time': 0.015,
          'top_queried_domains': [
            {'domain': 'github.com', 'count': 400},
          ],
          'top_blocked_domains': [
            {'domain': 'telemetry.corp', 'count': 120},
          ],
          'top_clients': [
            {'ip': '192.168.1.50', 'count': 2500},
          ],
          'dns_queries': [100, 200, 300],
          'blocked_filtering': [10, 20, 30],
          'time_units': 'hours',
        };

        final stats = AdGuardStats.fromJson(json);
        expect(stats.numDnsQueries, equals(10000));
        expect(stats.numBlockedFiltering, equals(1500));
        expect(stats.numReplacedSafebrowsing, equals(12));
        expect(stats.numReplacedSafesearch, equals(4));
        expect(stats.numReplacedParental, equals(0));
        expect(stats.avgProcessingTime, equals(0.015));
        expect(stats.blockRatePercentage, equals(15.0));
        expect(stats.dnsQueriesTrend, equals([100, 200, 300]));
        expect(stats.blockedFilteringTrend, equals([10, 20, 30]));
        expect(stats.timeUnits, equals('hours'));
      },
    );
  });

  group('AdGuardFilteringStatus', () {
    test('parses filters and sums enabled rules count', () {
      final json = {
        'enabled': true,
        'filters': [
          {
            'id': 1,
            'name': 'AdGuard DNS filter',
            'rules_count': 60000,
            'enabled': true,
            'last_updated': '2026-10-01T00:00:00Z',
          },
          {
            'id': 2,
            'name': 'Optional Filter (Disabled)',
            'rules_count': 15000,
            'enabled': false,
            'last_updated': '2026-10-01T00:00:00Z',
          },
        ],
        'user_rules': ['||badsite.com^', '||tracking.org^'],
      };

      final filtering = AdGuardFilteringStatus.fromJson(json);
      expect(filtering.enabled, isTrue);
      expect(filtering.filterLists.length, equals(2));
      expect(filtering.userRules.length, equals(2));
      // Total rules count: 60000 (enabled filter) + 2 (user rules) = 60002
      // Disabled filter (15000) must NOT be counted
      expect(filtering.totalRulesCount, equals(60002));
    });
  });

  group('AdGuardProcessTelemetry', () {
    test('parses process metrics from OpenWrt luci.getProcessList format', () {
      final json = {
        'PID': '2415',
        '%CPU': '1.5%',
        '%MEM': '8%',
        'VSZ': '28672', // 28MB in KB
        'COMMAND': '/usr/bin/AdGuardHome -c /etc/adguardhome.yaml',
      };

      // Simulating a router with 128MB total RAM
      const totalRamBytes = 128 * 1024 * 1024;
      final telemetry = AdGuardProcessTelemetry.fromLuciProcess(
        json,
        totalSystemRamBytes: totalRamBytes,
      );

      expect(telemetry.pid, equals('2415'));
      expect(telemetry.cpuPercent, equals(1.5));
      expect(telemetry.vszKb, equals(28672));
      expect(telemetry.vszMb, equals(28.0));
      expect(telemetry.memPercent, equals(8.0));
      // 8% of 128MB = 10.24MB
      expect(telemetry.estimatedRamMb, closeTo(10.24, 0.01));
    });

    test('handles missing total RAM gracefully', () {
      final json = {'PID': '100', '%CPU': '0%', '%MEM': '5%', 'VSZ': '10240'};
      final telemetry = AdGuardProcessTelemetry.fromLuciProcess(json);
      expect(telemetry.pid, equals('100'));
      expect(telemetry.estimatedRamMb, isNull);
    });
  });

  group('AdGuardDnsTopology', () {
    test(
      'infers Mode A (AdGuard Primary) when AGH on 53 and dnsmasq moved',
      () {
        final topo = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          dnsmasqServers: [],
          hasDnatRedirect: false,
          adguardDnsAddresses: ['192.168.1.1', '127.0.0.1'],
          isDnsRunning: true,
        );
        expect(topo.mode, equals(AdGuardTopologyMode.adguardPrimary));
        expect(topo.isIpv6Supported, isFalse);
      },
    );

    test(
      'infers Mode B (dnsmasq Forwarder) when dnsmasq on 53 forwards to AGH',
      () {
        final topo = AdGuardDnsTopology.infer(
          adguardDnsPort: 5353,
          dnsmasqPort: 53,
          dnsmasqServers: ['127.0.0.1#5353'],
          hasDnatRedirect: false,
          adguardDnsAddresses: ['127.0.0.1', '::1'],
          isDnsRunning: true,
        );
        expect(topo.mode, equals(AdGuardTopologyMode.dnsmasqForwarder));
        expect(topo.isIpv6Supported, isTrue);
      },
    );

    test('infers Mode C (Firewall Redirect) when DNAT rule is active', () {
      final topo = AdGuardDnsTopology.infer(
        adguardDnsPort: 5353,
        dnsmasqPort: 53,
        dnsmasqServers: ['1.1.1.1'],
        hasDnatRedirect: true,
        adguardDnsAddresses: ['192.168.1.1'],
        isDnsRunning: true,
      );
      expect(topo.mode, equals(AdGuardTopologyMode.firewallRedirect));
    });

    test(
      'infers Mode D (Standalone) when AGH on custom port without routing',
      () {
        final topo = AdGuardDnsTopology.infer(
          adguardDnsPort: 5353,
          dnsmasqPort: 53,
          dnsmasqServers: ['8.8.8.8'],
          hasDnatRedirect: false,
          adguardDnsAddresses: ['192.168.1.1'],
          isDnsRunning: true,
        );
        expect(topo.mode, equals(AdGuardTopologyMode.standalone));
      },
    );

    test('infers stopped mode when DNS engine is not running', () {
      final topo = AdGuardDnsTopology.infer(
        adguardDnsPort: 53,
        dnsmasqPort: 5353,
        dnsmasqServers: [],
        hasDnatRedirect: false,
        adguardDnsAddresses: ['192.168.1.1'],
        isDnsRunning: false,
      );
      expect(topo.mode, equals(AdGuardTopologyMode.stopped));
    });
  });

  group('AdGuardCapabilities Evaluator', () {
    final defaultTopology = AdGuardDnsTopology.infer(
      adguardDnsPort: 53,
      dnsmasqPort: 5353,
      dnsmasqServers: [],
      hasDnatRedirect: false,
      adguardDnsAddresses: ['192.168.1.1'],
      isDnsRunning: true,
    );

    test('evaluates fully operational installation', () {
      final status = AdGuardStatus.fromJson({
        'version': 'v0.107.50',
        'running': true,
        'protection_enabled': true,
        'dns_port': 53,
        'http_port': 3000,
      });

      final caps = AdGuardCapabilities.evaluate(
        hasServiceInRcList: true,
        hasInitScript: true,
        resolvedServiceName: 'adguardhome',
        hasRunningProcess: true,
        isApiReachable: true,
        isApiAuthenticated: true,
        status: status,
        topology: defaultTopology,
        configuredHttpPort: 3000,
      );

      expect(caps.isInstalled, isTrue);
      expect(caps.isServiceManageable, isTrue);
      expect(caps.isApiReachable, isTrue);
      expect(caps.isApiAuthenticated, isTrue);
      expect(caps.isDnsOperational, isTrue);
      expect(caps.discoveredHttpPort, equals(3000));
      expect(caps.discoveredDnsPort, equals(53));
      expect(caps.serviceName, equals('adguardhome'));
    });

    test('distinguishes running manual binary without OpenWrt init script', () {
      final status = AdGuardStatus.fromJson({
        'version': 'v0.107.50',
        'running': true,
        'protection_enabled': true,
        'dns_port': 53,
        'http_port': 3000,
      });

      final caps = AdGuardCapabilities.evaluate(
        hasServiceInRcList: false,
        hasInitScript: false, // No init script!
        resolvedServiceName: null,
        hasRunningProcess: true, // Manual process running
        isApiReachable: true,
        isApiAuthenticated: true,
        status: status,
        topology: defaultTopology,
        configuredHttpPort: 3000,
      );

      expect(caps.isInstalled, isTrue);
      expect(
        caps.isServiceManageable,
        isFalse,
      ); // Installed, but NOT manageable!
      expect(caps.isApiReachable, isTrue);
      expect(caps.isApiAuthenticated, isTrue);
    });

    test('handles stopped service with registered init script', () {
      final caps = AdGuardCapabilities.evaluate(
        hasServiceInRcList: true,
        hasInitScript: true,
        resolvedServiceName: 'adguardhome',
        hasRunningProcess: false, // Process not running
        isApiReachable: false,
        isApiAuthenticated: false,
        status: null,
        topology: defaultTopology,
        configuredHttpPort: 3000,
      );

      expect(caps.isInstalled, isTrue);
      expect(caps.isServiceManageable, isTrue);
      expect(caps.isApiReachable, isFalse);
      expect(caps.isApiAuthenticated, isFalse);
      expect(caps.isDnsOperational, isFalse);
    });

    test('handles uninstalled router completely', () {
      final caps = AdGuardCapabilities.evaluate(
        hasServiceInRcList: false,
        hasInitScript: false,
        resolvedServiceName: null,
        hasRunningProcess: false,
        isApiReachable: false,
        isApiAuthenticated: false,
        status: null,
        topology: defaultTopology,
        configuredHttpPort: 3000,
      );

      expect(caps.isInstalled, isFalse);
      expect(caps.isServiceManageable, isFalse);
      expect(caps.isApiReachable, isFalse);
      expect(caps.isDnsOperational, isFalse);
    });
  });

  group('AdGuardInstanceProfile', () {
    test('local instance profile initializes with correct properties', () {
      final profile = AdGuardInstanceProfile.local(
        routerId: 'router-123',
        host: '192.168.1.1',
        port: 3000,
        useHttps: false,
      );

      expect(profile.id, equals('local_router-123'));
      expect(profile.type, equals(AdGuardInstanceType.localRouter));
      expect(profile.host, equals('192.168.1.1'));
      expect(profile.port, equals(3000));
      expect(profile.useHttps, isFalse);
      expect(profile.routerId, equals('router-123'));
    });

    test(
      'external instance profile serializes and deserializes accurately',
      () {
        final profile = AdGuardInstanceProfile.external(
          id: 'ext_1700000000',
          name: 'Raspberry Pi AGH',
          host: '192.168.1.129',
          port: 8080,
          useHttps: true,
        );

        final json = profile.toJson();
        expect(json['id'], equals('ext_1700000000'));
        expect(json['name'], equals('Raspberry Pi AGH'));
        expect(json['type'], equals('externalHost'));
        expect(json['host'], equals('192.168.1.129'));
        expect(json['port'], equals(8080));
        expect(json['use_https'], isTrue);
        expect(json.containsKey('router_id'), isFalse);

        final deserialized = AdGuardInstanceProfile.fromJson(json);
        expect(deserialized, equals(profile));
        expect(deserialized.hashCode, equals(profile.hashCode));
        expect(deserialized.type, equals(AdGuardInstanceType.externalHost));
      },
    );

    test(
      'copyWith modifies specified fields and preserves unmodified ones',
      () {
        final original = AdGuardInstanceProfile.external(
          id: 'ext_1',
          name: 'Server 1',
          host: '10.0.0.5',
          port: 3000,
        );

        final modified = original.copyWith(
          name: 'Server 1 Updated',
          port: 3001,
          useHttps: true,
        );

        expect(modified.id, equals('ext_1'));
        expect(modified.name, equals('Server 1 Updated'));
        expect(modified.host, equals('10.0.0.5'));
        expect(modified.port, equals(3001));
        expect(modified.useHttps, isTrue);
      },
    );
  });
}
