// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/main.dart';
import 'package:yala/modules/diagnostics/controllers/diagnostics_controller.dart';
import 'package:yala/modules/diagnostics/models/diagnostic_report.dart';
import 'package:yala/modules/diagnostics/models/dns_lookup_result.dart';
import 'package:yala/modules/diagnostics/models/flush_dns_result.dart';
import 'package:yala/modules/diagnostics/models/internet_reachability.dart';
import 'package:yala/modules/diagnostics/models/ping_result.dart';
import 'package:yala/modules/diagnostics/models/routing_neighbor_info.dart';
import 'package:yala/modules/diagnostics/models/traceroute_result.dart';
import 'package:yala/services/api_service.dart';
import 'package:yala/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          if (methodCall.method == 'write') {
            return null;
          }
          return null;
        });
  });
  group('PingResult Tests', () {
    test('Parses standard OpenWrt BusyBox ping output successfully', () {
      const output = '''
PING 1.1.1.1 (1.1.1.1): 56 data bytes
64 bytes from 1.1.1.1: seq=0 ttl=57 time=8.532 ms
64 bytes from 1.1.1.1: seq=1 ttl=57 time=9.124 ms
64 bytes from 1.1.1.1: seq=2 ttl=57 time=8.951 ms
64 bytes from 1.1.1.1: seq=3 ttl=57 time=9.810 ms

--- 1.1.1.1 ping statistics ---
4 packets transmitted, 4 packets received, 0% packet loss
round-trip min/avg/max = 8.532/9.104/9.810 ms
''';

      final res = PingResult.parse('1.1.1.1', output, exitCode: 0);

      expect(res.isSuccess, isTrue);
      expect(res.target, equals('1.1.1.1'));
      expect(res.packetsTransmitted, equals(4));
      expect(res.packetsReceived, equals(4));
      expect(res.packetLossPercent, equals(0.0));
      expect(res.minRttMs, equals(8.532));
      expect(res.avgRttMs, equals(9.104));
      expect(res.maxRttMs, equals(9.810));
      expect(res.replies.length, equals(4));
      expect(res.replies[0].seq, equals(0));
      expect(res.replies[0].ttl, equals(57));
      expect(res.replies[0].timeMs, equals(8.532));
      expect(res.replies[0].ip, equals('1.1.1.1'));
      expect(res.errorMessage, isNull);
    });

    test('Parses iputils ping output with mdev', () {
      const output = '''
PING google.com (142.250.183.142) 56(84) bytes of data.
64 bytes from maa05s22-in-f14.1e100.net (142.250.183.142): icmp_seq=1 ttl=118 time=14.2 ms
64 bytes from maa05s22-in-f14.1e100.net (142.250.183.142): icmp_seq=2 ttl=118 time=15.1 ms

--- google.com ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 14.200/14.650/15.100/0.450 ms
''';

      final res = PingResult.parse('google.com', output, exitCode: 0);

      expect(res.isSuccess, isTrue);
      expect(res.packetsTransmitted, equals(2));
      expect(res.packetsReceived, equals(2));
      expect(res.packetLossPercent, equals(0.0));
      expect(res.minRttMs, equals(14.200));
      expect(res.avgRttMs, equals(14.650));
      expect(res.maxRttMs, equals(15.100));
      expect(res.mdevRttMs, equals(0.450));
      expect(res.replies.length, equals(2));
      expect(res.replies[0].seq, equals(1));
      expect(res.replies[0].ttl, equals(118));
      expect(res.replies[0].timeMs, equals(14.2));
    });

    test('Parses partial packet loss correctly', () {
      const output = '''
PING 192.168.1.50 (192.168.1.50): 56 data bytes
64 bytes from 192.168.1.50: seq=0 ttl=64 time=1.200 ms

--- 192.168.1.50 ping statistics ---
4 packets transmitted, 1 packets received, 75% packet loss
round-trip min/avg/max = 1.200/1.200/1.200 ms
''';

      final res = PingResult.parse('192.168.1.50', output, exitCode: 0);

      expect(res.isSuccess, isTrue);
      expect(res.packetsTransmitted, equals(4));
      expect(res.packetsReceived, equals(1));
      expect(res.packetLossPercent, equals(75.0));
      expect(res.replies.length, equals(1));
    });

    test('Handles 100% packet loss / ping failure', () {
      const output = '''
PING 192.168.1.254 (192.168.1.254): 56 data bytes

--- 192.168.1.254 ping statistics ---
3 packets transmitted, 0 packets received, 100% packet loss
''';

      final res = PingResult.parse(
        '192.168.1.254',
        output,
        exitCode: 1,
        stderr: 'Request timed out',
      );

      expect(res.isSuccess, isFalse);
      expect(res.packetsTransmitted, equals(3));
      expect(res.packetsReceived, equals(0));
      expect(res.packetLossPercent, equals(100.0));
      expect(res.replies, isEmpty);
      expect(res.errorMessage, equals('Request timed out'));
    });

    test('Handles complete failure with stderr and empty stdout', () {
      final res = PingResult.parse(
        'invalid.host',
        '',
        exitCode: 1,
        stderr: 'ping: bad address invalid.host',
      );

      expect(res.isSuccess, isFalse);
      expect(res.errorMessage, equals('ping: bad address invalid.host'));
    });

    test('PingResult and PingPacketReply JSON serialization roundtrip', () {
      final orig = PingResult(
        target: '1.1.1.1',
        isSuccess: true,
        packetsTransmitted: 3,
        packetsReceived: 3,
        packetLossPercent: 0.0,
        minRttMs: 5.1,
        avgRttMs: 5.5,
        maxRttMs: 6.0,
        mdevRttMs: 0.4,
        replies: const [
          PingPacketReply(seq: 0, ttl: 64, timeMs: 5.1, ip: '1.1.1.1'),
          PingPacketReply(seq: 1, ttl: 64, timeMs: 5.5, ip: '1.1.1.1'),
        ],
        rawOutput: 'raw ping output',
        timestamp: DateTime(2026, 3, 15, 12, 0, 0),
      );

      final json = orig.toJson();
      final restored = PingResult.fromJson(json);

      expect(restored.target, equals(orig.target));
      expect(restored.isSuccess, equals(orig.isSuccess));
      expect(restored.packetsTransmitted, equals(orig.packetsTransmitted));
      expect(restored.packetsReceived, equals(orig.packetsReceived));
      expect(restored.packetLossPercent, equals(orig.packetLossPercent));
      expect(restored.minRttMs, equals(orig.minRttMs));
      expect(restored.avgRttMs, equals(orig.avgRttMs));
      expect(restored.replies.length, equals(2));
      expect(restored.replies[0].seq, equals(0));
      expect(restored.replies[0].timeMs, equals(5.1));
    });
  });

  group('TracerouteResult Tests', () {
    test('Parses multi-hop OpenWrt BusyBox traceroute output', () {
      const output = '''
traceroute to 1.1.1.1 (1.1.1.1), 30 hops max, 38 byte packets
 1  10.0.0.1 (10.0.0.1)  0.612 ms  0.589 ms  0.554 ms
 2  172.16.0.1 (172.16.0.1)  1.234 ms  1.100 ms  1.150 ms
 3  *  *  *
 4  one.one.one.one (1.1.1.1)  8.921 ms  8.750 ms  8.810 ms
''';

      final res = TracerouteResult.parse('1.1.1.1', output, exitCode: 0);

      expect(res.isSuccess, isTrue);
      expect(res.hops.length, equals(4));

      // Hop 1
      expect(res.hops[0].hopNumber, equals(1));
      expect(res.hops[0].host, equals('10.0.0.1'));
      expect(res.hops[0].ip, equals('10.0.0.1'));
      expect(res.hops[0].isTimeout, isFalse);
      expect(res.hops[0].rttMs.length, equals(3));
      expect(res.hops[0].avgRttMs, closeTo(0.585, 0.01));

      // Hop 2
      expect(res.hops[1].hopNumber, equals(2));
      expect(res.hops[1].ip, equals('172.16.0.1'));
      expect(res.hops[1].isTimeout, isFalse);

      // Hop 3: Timeout
      expect(res.hops[2].hopNumber, equals(3));
      expect(res.hops[2].isTimeout, isTrue);
      expect(res.hops[2].displayAddress, equals('*'));

      // Hop 4: Hostname + IP
      expect(res.hops[3].hopNumber, equals(4));
      expect(res.hops[3].host, equals('one.one.one.one'));
      expect(res.hops[3].ip, equals('1.1.1.1'));
      expect(res.hops[3].displayAddress, equals('1.1.1.1'));
      expect(res.hops[3].isTimeout, isFalse);
    });

    test('Parses traceroute lines without hostname parens', () {
      const output = '''
 1  192.168.1.1  0.8 ms
 2  203.0.113.1  4.2 ms
''';

      final res = TracerouteResult.parse('203.0.113.1', output);

      expect(res.hops.length, equals(2));
      expect(res.hops[0].ip, equals('192.168.1.1'));
      expect(res.hops[0].rttMs, equals([0.8]));
      expect(res.hops[1].ip, equals('203.0.113.1'));
      expect(res.hops[1].rttMs, equals([4.2]));
    });

    test('Handles traceroute failure with stderr', () {
      final res = TracerouteResult.parse(
        'invalid.host',
        '',
        exitCode: 1,
        stderr: 'traceroute: bad address invalid.host',
      );

      expect(res.isSuccess, isFalse);
      expect(res.errorMessage, equals('traceroute: bad address invalid.host'));
      expect(res.hops, isEmpty);
    });

    test('TracerouteResult and TracerouteHop JSON serialization roundtrip', () {
      final orig = TracerouteResult(
        target: '8.8.8.8',
        isSuccess: true,
        maxHops: 20,
        hops: const [
          TracerouteHop(
            hopNumber: 1,
            host: 'gw',
            ip: '192.168.1.1',
            rttMs: [0.5, 0.6],
          ),
          TracerouteHop(hopNumber: 2, isTimeout: true),
        ],
        rawOutput: 'raw traceroute',
        timestamp: DateTime(2026, 3, 15, 12, 0, 0),
      );

      final json = orig.toJson();
      final restored = TracerouteResult.fromJson(json);

      expect(restored.target, equals('8.8.8.8'));
      expect(restored.maxHops, equals(20));
      expect(restored.hops.length, equals(2));
      expect(restored.hops[0].ip, equals('192.168.1.1'));
      expect(restored.hops[0].avgRttMs, equals(0.55));
      expect(restored.hops[1].isTimeout, isTrue);
    });
  });

  group('DnsLookupResult Tests', () {
    test('Parses BusyBox nslookup output with IPv4 and IPv6 answers', () {
      const output = '''
Server:    127.0.0.1
Address 1: 127.0.0.1 localhost#53

Name:      openwrt.org
Address 1: 139.59.209.225
Address 2: 2a03:b0c0:3:d0::1a11:1
''';

      final res = DnsLookupResult.parse('openwrt.org', output, exitCode: 0);

      expect(res.isSuccess, isTrue);
      expect(res.query, equals('openwrt.org'));
      expect(res.server, contains('127.0.0.1'));
      expect(res.serverPort, equals(53));
      expect(res.ipv4Addresses, contains('139.59.209.225'));
      expect(res.ipv6Addresses, contains('2a03:b0c0:3:d0::1a11:1'));
      expect(res.allAddresses.length, equals(2));
    });

    test('Parses CNAME canonical names', () {
      const output = '''
Server:    192.168.1.1
Address 1: 192.168.1.1:53

google.com    canonical name = www.google.com
Name:      www.google.com
Address 1: 142.250.183.142
''';

      final res = DnsLookupResult.parse('google.com', output, exitCode: 0);

      expect(res.isSuccess, isTrue);
      expect(res.cnames, contains('www.google.com'));
      expect(res.ipv4Addresses, contains('142.250.183.142'));
    });

    test('Handles lookup failure / unresolvable domain', () {
      const output = '''
Server:    127.0.0.1
Address 1: 127.0.0.1 localhost#53

** server can't find invaliddomain.test: NXDOMAIN
''';

      final res = DnsLookupResult.parse(
        'invaliddomain.test',
        output,
        exitCode: 1,
        stderr: 'NXDOMAIN',
      );

      expect(res.isSuccess, isFalse);
      expect(res.ipv4Addresses, isEmpty);
      expect(res.ipv6Addresses, isEmpty);
    });

    test('DnsLookupResult JSON serialization roundtrip', () {
      final orig = DnsLookupResult(
        query: 'example.com',
        server: '1.1.1.1',
        serverPort: 53,
        ipv4Addresses: const ['93.184.216.34'],
        ipv6Addresses: const ['2606:2800:220:1:248:1893:25c8:1946'],
        cnames: const ['alias.example.com'],
        isSuccess: true,
        rawOutput: 'raw dns output',
        timestamp: DateTime(2026, 3, 15, 12, 0, 0),
      );

      final json = orig.toJson();
      final restored = DnsLookupResult.fromJson(json);

      expect(restored.query, equals('example.com'));
      expect(restored.server, equals('1.1.1.1'));
      expect(restored.serverPort, equals(53));
      expect(restored.ipv4Addresses, equals(['93.184.216.34']));
      expect(
        restored.ipv6Addresses,
        equals(['2606:2800:220:1:248:1893:25c8:1946']),
      );
      expect(restored.cnames, equals(['alias.example.com']));
      expect(restored.isSuccess, isTrue);
    });
  });

  group('FlushDnsResult Tests', () {
    test('FlushDnsResult.success constructor initializes fields correctly', () {
      final res = FlushDnsResult.success(
        flushedResolvers: const ['dnsmasq', 'smartdns'],
        message: 'Cache cleared',
        rawOutput: 'dnsmasq reload ok',
      );

      expect(res.isSuccess, isTrue);
      expect(res.flushedResolvers, equals(['dnsmasq', 'smartdns']));
      expect(res.message, equals('Cache cleared'));
      expect(res.rawOutput, equals('dnsmasq reload ok'));
      expect(res.timestamp, isNotNull);
    });

    test('FlushDnsResult.failure constructor initializes failure state', () {
      final res = FlushDnsResult.failure(
        'Permission denied',
        rawOutput: 'Access error',
      );

      expect(res.isSuccess, isFalse);
      expect(res.flushedResolvers, isEmpty);
      expect(res.message, equals('Permission denied'));
      expect(res.rawOutput, equals('Access error'));
    });

    test('FlushDnsResult JSON serialization roundtrip', () {
      final orig = FlushDnsResult(
        isSuccess: true,
        flushedResolvers: const ['dnsmasq', 'unbound'],
        message: 'Flushed successfully',
        rawOutput: 'raw output',
        timestamp: DateTime(2026, 3, 15, 12, 0, 0),
      );

      final json = orig.toJson();
      final restored = FlushDnsResult.fromJson(json);

      expect(restored.isSuccess, isTrue);
      expect(restored.flushedResolvers, equals(['dnsmasq', 'unbound']));
      expect(restored.message, equals('Flushed successfully'));
      expect(restored.rawOutput, equals('raw output'));
      expect(restored.timestamp, equals(orig.timestamp));
    });
  });

  group('RealApiService.sanitizeHost Tests', () {
    test('Strips protocol scheme (http/https)', () {
      expect(
        RealApiService.sanitizeHost('https://google.com'),
        equals('google.com'),
      );
      expect(
        RealApiService.sanitizeHost('http://192.168.1.1'),
        equals('192.168.1.1'),
      );
      expect(
        RealApiService.sanitizeHost('http://[2001:db8::1]'),
        equals('2001:db8::1'),
      );
    });

    test('Strips paths and query parameters', () {
      expect(
        RealApiService.sanitizeHost('google.com/search?q=test'),
        equals('google.com'),
      );
      expect(
        RealApiService.sanitizeHost('https://example.com/api/v1/test'),
        equals('example.com'),
      );
      expect(
        RealApiService.sanitizeHost('192.168.1.1/cgi-bin/luci'),
        equals('192.168.1.1'),
      );
    });

    test('Strips port from hostnames and IPv4', () {
      expect(
        RealApiService.sanitizeHost('google.com:443'),
        equals('google.com'),
      );
      expect(
        RealApiService.sanitizeHost('192.168.1.1:8080'),
        equals('192.168.1.1'),
      );
    });

    test('Handles IPv6 addresses with and without brackets', () {
      expect(
        RealApiService.sanitizeHost('[2606:4700:4700::1111]'),
        equals('2606:4700:4700::1111'),
      );
      expect(
        RealApiService.sanitizeHost('2606:4700:4700::1111'),
        equals('2606:4700:4700::1111'),
      );
      expect(RealApiService.sanitizeHost('::1'), equals('::1'));
    });

    test('Trims surrounding whitespace', () {
      expect(RealApiService.sanitizeHost('   1.1.1.1   '), equals('1.1.1.1'));
      expect(
        RealApiService.sanitizeHost('\tcloudflare.com\n'),
        equals('cloudflare.com'),
      );
    });
  });

  group('Routing and Neighbor Table Tests', () {
    test(
      'RouteEntry.parseList parses standard ip -4 route show table all output',
      () {
        const output = '''
default via 10.0.0.1 dev eth1 proto static src 10.0.0.125
10.0.0.0/24 dev eth1 proto kernel scope link src 10.0.0.125
192.168.1.0/24 dev br-lan proto kernel scope link src 192.168.1.1
local 127.0.0.1 dev lo table local proto kernel scope host src 127.0.0.1
''';

        final routes = RouteEntry.parseList(output);

        expect(routes.length, equals(4));

        // Route 0: Default
        expect(routes[0].destination, equals('default'));
        expect(routes[0].isDefault, isTrue);
        expect(routes[0].gateway, equals('10.0.0.1'));
        expect(routes[0].interface, equals('eth1'));
        expect(routes[0].source, equals('10.0.0.125'));

        // Route 1: WAN Subnet
        expect(routes[1].destination, equals('10.0.0.0/24'));
        expect(routes[1].isDefault, isFalse);
        expect(routes[1].interface, equals('eth1'));
        expect(routes[1].source, equals('10.0.0.125'));

        // Route 2: LAN Subnet
        expect(routes[2].destination, equals('192.168.1.0/24'));
        expect(routes[2].interface, equals('br-lan'));
        expect(routes[2].source, equals('192.168.1.1'));

        // Route 3: Local Table
        expect(routes[3].destination, equals('local'));
        expect(routes[3].table, equals('local'));
        expect(routes[3].interface, equals('lo'));
      },
    );

    test('RouteEntry JSON serialization roundtrip', () {
      const orig = RouteEntry(
        destination: 'default',
        gateway: '192.168.1.1',
        interface: 'eth0',
        source: '192.168.1.50',
        table: 'main',
        metric: '100',
        isDefault: true,
      );

      final json = orig.toJson();
      final restored = RouteEntry.fromJson(json);

      expect(restored.destination, equals('default'));
      expect(restored.gateway, equals('192.168.1.1'));
      expect(restored.interface, equals('eth0'));
      expect(restored.source, equals('192.168.1.50'));
      expect(restored.metric, equals('100'));
      expect(restored.isDefault, isTrue);
    });

    test(
      'NeighborEntry.parseList parses ip -4 neigh show output correctly',
      () {
        const output = '''
10.0.0.1 dev eth1 lladdr e8:9f:80:a5:7d:8c REACHABLE
192.168.1.150 dev br-lan lladdr b8:27:eb:12:34:56 STALE
192.168.1.200 dev br-lan FAILED
''';

        final neighbors = NeighborEntry.parseList(output);

        expect(neighbors.length, equals(3));

        expect(neighbors[0].ip, equals('10.0.0.1'));
        expect(neighbors[0].interface, equals('eth1'));
        expect(neighbors[0].mac, equals('e8:9f:80:a5:7d:8c'));
        expect(neighbors[0].state, equals('REACHABLE'));

        expect(neighbors[1].ip, equals('192.168.1.150'));
        expect(neighbors[1].interface, equals('br-lan'));
        expect(neighbors[1].mac, equals('b8:27:eb:12:34:56'));
        expect(neighbors[1].state, equals('STALE'));

        expect(neighbors[2].ip, equals('192.168.1.200'));
        expect(neighbors[2].mac, isNull);
        expect(neighbors[2].state, equals('FAILED'));
      },
    );

    test('NeighborEntry JSON serialization roundtrip', () {
      const orig = NeighborEntry(
        ip: '192.168.1.100',
        mac: 'aa:bb:cc:dd:ee:ff',
        interface: 'br-lan',
        state: 'REACHABLE',
      );

      final json = orig.toJson();
      final restored = NeighborEntry.fromJson(json);

      expect(restored.ip, equals('192.168.1.100'));
      expect(restored.mac, equals('aa:bb:cc:dd:ee:ff'));
      expect(restored.interface, equals('br-lan'));
      expect(restored.state, equals('REACHABLE'));
    });

    test('ConntrackInfo utilization calculation and JSON serialization', () {
      const conntrack = ConntrackInfo(count: 2048, max: 16384);

      expect(conntrack.utilizationPercent, closeTo(12.5, 0.01));

      final json = conntrack.toJson();
      final restored = ConntrackInfo.fromJson(json);
      expect(restored.count, equals(2048));
      expect(restored.max, equals(16384));

      // Max 0 safety check
      const zeroMax = ConntrackInfo(count: 10, max: 0);
      expect(zeroMax.utilizationPercent, equals(0.0));
    });
  });

  group('InternetReachability Tests', () {
    test('Factory constructors produce valid instances', () {
      final unknown = InternetReachability.unknown();
      expect(unknown.status, equals(ReachabilityStatus.unknown));
      expect(unknown.isReachable, isFalse);

      final testing = InternetReachability.testing();
      expect(testing.status, equals(ReachabilityStatus.testing));
      expect(testing.isReachable, isFalse);

      final offline = InternetReachability.offline(
        reason: 'Gateway unreachable',
        gatewayIp: '192.168.1.1',
      );
      expect(offline.status, equals(ReachabilityStatus.offline));
      expect(offline.gatewayIp, equals('192.168.1.1'));
      expect(offline.statusMessage, equals('Gateway unreachable'));
    });

    test('JSON serialization roundtrip', () {
      final orig = InternetReachability(
        status: ReachabilityStatus.online,
        isReachable: true,
        wanInterface: 'eth0',
        wanIp: '100.64.1.20',
        gatewayIp: '10.0.0.1',
        gatewayReachable: true,
        gatewayLatencyMs: 0.8,
        publicDnsReachable: true,
        publicDnsLatencyMs: 12.4,
        dnsResolving: true,
        statusMessage: 'Connected',
        testedAt: DateTime(2026, 3, 15, 12, 0, 0),
      );

      final json = orig.toJson();
      final restored = InternetReachability.fromJson(json);

      expect(restored.status, equals(ReachabilityStatus.online));
      expect(restored.isReachable, isTrue);
      expect(restored.wanInterface, equals('eth0'));
      expect(restored.wanIp, equals('100.64.1.20'));
      expect(restored.gatewayLatencyMs, equals(0.8));
      expect(restored.publicDnsLatencyMs, equals(12.4));
      expect(restored.dnsResolving, isTrue);
    });
  });

  group('DiagnosticReport and Privacy Redaction Tests', () {
    test(
      'isPrivateIp distinguishes private, CGNAT, loopback, and public IPs',
      () {
        // RFC1918 Private IPv4
        expect(DiagnosticReport.isPrivateIp('10.0.0.1'), isTrue);
        expect(DiagnosticReport.isPrivateIp('10.255.0.1'), isTrue);
        expect(DiagnosticReport.isPrivateIp('192.168.1.1'), isTrue);
        expect(DiagnosticReport.isPrivateIp('192.168.100.254'), isTrue);
        expect(DiagnosticReport.isPrivateIp('172.16.0.1'), isTrue);
        expect(DiagnosticReport.isPrivateIp('172.31.255.255'), isTrue);
        expect(
          DiagnosticReport.isPrivateIp('172.32.0.1'),
          isFalse,
        ); // Outside RFC1918
        expect(
          DiagnosticReport.isPrivateIp('172.15.0.1'),
          isFalse,
        ); // Outside RFC1918

        // Loopback
        expect(DiagnosticReport.isPrivateIp('127.0.0.1'), isTrue);
        expect(DiagnosticReport.isPrivateIp('localhost'), isTrue);
        expect(DiagnosticReport.isPrivateIp('::1'), isTrue);

        // Carrier-Grade NAT (100.64.0.0/10: 100.64.x.x - 100.127.x.x)
        expect(DiagnosticReport.isPrivateIp('100.64.0.1'), isTrue);
        expect(DiagnosticReport.isPrivateIp('100.100.5.1'), isTrue);
        expect(DiagnosticReport.isPrivateIp('100.127.255.254'), isTrue);
        expect(
          DiagnosticReport.isPrivateIp('100.63.1.1'),
          isFalse,
        ); // Outside CGNAT
        expect(
          DiagnosticReport.isPrivateIp('100.128.1.1'),
          isFalse,
        ); // Outside CGNAT

        // Link-local
        expect(DiagnosticReport.isPrivateIp('169.254.1.1'), isTrue);

        // Wildcards & default routes
        expect(DiagnosticReport.isPrivateIp('default'), isTrue);
        expect(DiagnosticReport.isPrivateIp('0.0.0.0'), isTrue);
        expect(DiagnosticReport.isPrivateIp('0.0.0.0/0'), isTrue);
        expect(DiagnosticReport.isPrivateIp('*'), isTrue);
        expect(DiagnosticReport.isPrivateIp('-'), isTrue);

        // CIDR notation on private subnets
        expect(DiagnosticReport.isPrivateIp('192.168.1.0/24'), isTrue);
        expect(DiagnosticReport.isPrivateIp('10.0.0.0/8'), isTrue);

        // Well-known public DNS (preserved for diagnostic clarity)
        expect(DiagnosticReport.isPrivateIp('1.1.1.1'), isTrue);
        expect(DiagnosticReport.isPrivateIp('8.8.8.8'), isTrue);
        expect(DiagnosticReport.isPrivateIp('9.9.9.9'), isTrue);

        // Real public IPs (MUST return false so they get redacted)
        expect(DiagnosticReport.isPrivateIp('203.0.113.195'), isFalse);
        expect(DiagnosticReport.isPrivateIp('142.250.183.142'), isFalse);
        expect(DiagnosticReport.isPrivateIp('45.33.32.156'), isFalse);
      },
    );

    test(
      'maskIp redacts public IPv4 and IPv6 while preserving private IPs',
      () {
        // Private IPs preserved
        expect(DiagnosticReport.maskIp('192.168.1.1'), equals('192.168.1.1'));
        expect(DiagnosticReport.maskIp('10.0.0.1'), equals('10.0.0.1'));
        expect(DiagnosticReport.maskIp('127.0.0.1'), equals('127.0.0.1'));
        expect(DiagnosticReport.maskIp('default'), equals('default'));
        expect(
          DiagnosticReport.maskIp('192.168.1.0/24'),
          equals('192.168.1.0/24'),
        );

        // Public IPv4 masked
        expect(
          DiagnosticReport.maskIp('203.0.113.195'),
          equals('203.0.xxx.xxx'),
        );
        expect(
          DiagnosticReport.maskIp('142.250.183.142'),
          equals('142.250.xxx.xxx'),
        );
        expect(
          DiagnosticReport.maskIp('203.0.113.0/24'),
          equals('203.0.xxx.xxx/24'),
        );

        // Public IPv6 masked
        expect(
          DiagnosticReport.maskIp('2606:2800:220:1:248:1893:25c8:1946'),
          equals('2606:2800:xxxx:xxxx::xxxx'),
        );
      },
    );

    test('maskMac redacts MAC address suffix for privacy', () {
      expect(
        DiagnosticReport.maskMac('e4:a8:df:ca:41:8c'),
        equals('e4:a8:df:xx:xx:xx'),
      );
      expect(
        DiagnosticReport.maskMac('AA:BB:CC:11:22:33'),
        equals('AA:BB:CC:xx:xx:xx'),
      );
      expect(DiagnosticReport.maskMac('invalid_mac'), equals('[REDACTED_MAC]'));
    });

    test('redactText replaces embedded public IPs and MACs in raw logs', () {
      const rawLog = '''
daemon.info hostapd: phy0-ap0: STA e4:a8:df:ca:41:8c IEEE 802.11: associated
daemon.info dnsmasq-dhcp[1]: DHCPACK(br-lan) 192.168.1.150 e4:a8:df:ca:41:8c Pixel-7
netfilter: NAT translation: 192.168.1.150:49152 -> 203.0.113.195:49152 -> 142.250.183.142:443
''';

      final redacted = DiagnosticReport.redactText(rawLog);

      // Private IP 192.168.1.150 is preserved
      expect(redacted, contains('192.168.1.150'));

      // MAC addresses are masked
      expect(redacted, isNot(contains('e4:a8:df:ca:41:8c')));
      expect(redacted, contains('e4:a8:df:xx:xx:xx'));

      // Public IPs 203.0.113.195 and 142.250.183.142 are masked
      expect(redacted, isNot(contains('203.0.113.195')));
      expect(redacted, isNot(contains('142.250.183.142')));
      expect(redacted, contains('203.0.xxx.xxx'));
      expect(redacted, contains('142.250.xxx.xxx'));
    });

    test(
      'generateMarkdown generates full 6-section report with redaction enabled and disabled',
      () {
        final report = DiagnosticReport(
          hostname: 'OpenWrt-Test',
          model: 'TP-Link Archer C6 v3',
          architecture: 'MediaTek MT7621',
          target: 'ramips/mt7621',
          kernelVersion: '6.6.35',
          firmwareVersion: 'OpenWrt 23.05.3',
          uptime: '3d 14h 22m',
          loadAverage: '0.12, 0.08, 0.02',
          memorySummary: '48.2 MB / 128.0 MB used (38%)',
          temperatureSummary: 'CPU: 52.0°C',
          storageSummary: 'overlay 12.4 MB / 16.0 MB (78%)',
          internetStatus: InternetReachability(
            status: ReachabilityStatus.online,
            isReachable: true,
            wanInterface: 'eth1',
            wanIp: '203.0.113.195',
            gatewayIp: '203.0.113.1',
            gatewayReachable: true,
            gatewayLatencyMs: 2.1,
            publicDnsReachable: true,
            publicDnsLatencyMs: 8.9,
            dnsResolving: true,
            statusMessage: 'Connected to Internet',
            testedAt: DateTime(2026, 3, 15, 12, 0, 0),
          ),
          routes: const [
            RouteEntry(
              destination: 'default',
              gateway: '203.0.113.1',
              interface: 'eth1',
              isDefault: true,
            ),
            RouteEntry(
              destination: '192.168.1.0/24',
              interface: 'br-lan',
              source: '192.168.1.1',
            ),
          ],
          neighbors: const [
            NeighborEntry(
              ip: '192.168.1.150',
              mac: 'e4:a8:df:ca:41:8c',
              interface: 'br-lan',
              state: 'REACHABLE',
            ),
          ],
          conntrack: const ConntrackInfo(count: 142, max: 16384),
          wanInfo: 'eth1 (IP: 203.0.113.195)',
          lanInfo: 'br-lan (192.168.1.1/24)',
          recentSyslog: 'hostapd: STA e4:a8:df:ca:41:8c associated\n',
          recentDmesg: 'br-lan: port 1 entered forwarding state\n',
          generatedAt: DateTime(2026, 3, 15, 12, 0, 0),
        );

        // 1. Redacted Report
        final redactedMd = report.generateMarkdown(redact: true);

        expect(redactedMd, contains('# OpenWrt Router Diagnostic Report'));
        expect(redactedMd, contains('Privacy Redaction: Enabled'));
        expect(redactedMd, contains('## 1. System Information'));
        expect(redactedMd, contains('- **Hostname**: OpenWrt-Test'));
        expect(
          redactedMd,
          contains('- **Hardware Model**: TP-Link Archer C6 v3'),
        );
        expect(redactedMd, contains('- **Temperature**: CPU: 52.0°C'));
        expect(redactedMd, contains('## 2. Internet Reachability & WAN'));
        // Public WAN IP masked
        expect(redactedMd, contains('- **WAN IP**: 203.0.xxx.xxx'));
        expect(redactedMd, isNot(contains('203.0.113.195')));
        // Public Gateway masked
        expect(redactedMd, contains('- **Default Gateway**: 203.0.xxx.xxx'));
        expect(redactedMd, isNot(contains('203.0.113.1 (Reachable')));
        expect(redactedMd, contains('## 3. Kernel Routing Table'));
        expect(
          redactedMd,
          contains('## 4. ARP Neighbors & Active Connections'),
        );
        // Neighbor MAC masked
        expect(redactedMd, contains('e4:a8:df:xx:xx:xx'));
        expect(redactedMd, isNot(contains('e4:a8:df:ca:41:8c')));
        // Private LAN IP preserved
        expect(redactedMd, contains('192.168.1.150'));
        expect(redactedMd, contains('## 5. Recent System Log'));
        expect(redactedMd, contains('## 6. Recent Kernel Log (dmesg)'));

        // 2. Unredacted Report
        final plainMd = report.generateMarkdown(redact: false);
        expect(plainMd, contains('Privacy Redaction: Disabled'));
        expect(plainMd, contains('- **WAN IP**: 203.0.113.195'));
        expect(plainMd, contains('- **Default Gateway**: 203.0.113.1'));
        expect(plainMd, contains('e4:a8:df:ca:41:8c'));
      },
    );
  });

  group('DiagnosticsController Integration with MockApiService', () {
    test(
      'DiagnosticsController executes Ping, Reachability, Routes, and Report generation',
      () async {
        final appState = AppState.instance;
        await appState.setReviewerMode(true);

        final container = ProviderContainer(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
        );
        addTearDown(container.dispose);

        final controller = container.read(
          diagnosticsControllerProvider.notifier,
        );

        // Reachability test
        await controller.testReachability();
        final reachState = container.read(diagnosticsControllerProvider);
        expect(reachState.internetReachability, isNotNull);
        expect(reachState.internetReachability!.isReachable, isTrue);
        expect(
          reachState.internetReachability!.status,
          equals(ReachabilityStatus.online),
        );

        // Ping test
        await controller.ping('1.1.1.1', count: 3);
        final pingState = container.read(diagnosticsControllerProvider);
        expect(pingState.lastPingResult, isNotNull);
        expect(pingState.lastPingResult!.isSuccess, isTrue);
        expect(pingState.lastPingResult!.target, equals('1.1.1.1'));

        // Traceroute test
        await controller.traceroute('1.1.1.1', maxHops: 10);
        final traceState = container.read(diagnosticsControllerProvider);
        expect(traceState.lastTracerouteResult, isNotNull);
        expect(traceState.lastTracerouteResult!.isSuccess, isTrue);
        expect(traceState.lastTracerouteResult!.hops.isNotEmpty, isTrue);

        // DNS Lookup test
        await controller.dnsLookup('google.com');
        final dnsState = container.read(diagnosticsControllerProvider);
        expect(dnsState.lastDnsResult, isNotNull);
        expect(dnsState.lastDnsResult!.isSuccess, isTrue);
        expect(dnsState.lastDnsResult!.query, equals('google.com'));

        // Flush DNS Cache test
        await controller.flushDns();
        final flushState = container.read(diagnosticsControllerProvider);
        expect(flushState.lastFlushResult, isNotNull);
        expect(flushState.lastFlushResult!.isSuccess, isTrue);
        expect(
          flushState.lastFlushResult!.flushedResolvers,
          contains('dnsmasq'),
        );
        expect(flushState.isFlushingDns, isFalse);

        // Routing and Neighbor tables
        await controller.loadNetworkTables();
        final tableState = container.read(diagnosticsControllerProvider);
        expect(tableState.routes.isNotEmpty, isTrue);
        expect(tableState.neighbors.isNotEmpty, isTrue);
        expect(tableState.conntrack, isNotNull);

        // Full report generation
        await controller.generateReport();
        final reportState = container.read(diagnosticsControllerProvider);
        expect(reportState.lastReport, isNotNull);
        expect(reportState.lastReport!.hostname, equals('OpenWrt-Router'));
        expect(reportState.lastReport!.generateMarkdown().isNotEmpty, isTrue);

        // Toggle privacy redaction
        expect(reportState.redactSensitiveData, isTrue);
        controller.toggleRedaction(false);
        expect(
          container.read(diagnosticsControllerProvider).redactSensitiveData,
          isFalse,
        );
      },
    );
  });
}
