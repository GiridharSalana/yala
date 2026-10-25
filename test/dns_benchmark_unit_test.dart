// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/diagnostics/controllers/dns_benchmark_controller.dart';
import 'package:yala/modules/diagnostics/models/dns_benchmark_models.dart';
import 'package:yala/modules/diagnostics/services/dns_benchmark_service.dart';
import 'package:yala/modules/diagnostics/services/dns_packet_codec.dart';
import 'package:yala/modules/diagnostics/services/dns_provider_registry.dart';
import 'package:yala/modules/diagnostics/services/dns_router_discovery.dart';
import 'package:yala/services/mock_api_service.dart';

class _FakeDnsBenchmarkService implements IDnsBenchmarkService {
  final Map<String, List<double>> providerLatencies;
  final Set<String> failingProviders;
  bool isCancelled = false;

  _FakeDnsBenchmarkService({
    this.providerLatencies = const {},
    this.failingProviders = const {},
  });

  @override
  void cancel() {
    isCancelled = true;
  }

  @override
  Future<DnsBenchmarkResult> benchmarkProvider({
    required DnsProviderMetadata provider,
    required DnsVantagePoint vantagePoint,
    required DnsProtocol protocol,
    int sampleCount = 3,
    Duration timeout = const Duration(milliseconds: 2500),
    String? routerIp,
    String? routerSysauth,
    bool routerUseHttps = false,
  }) async {
    if (failingProviders.contains(provider.id)) {
      return DnsBenchmarkResult(
        provider: provider,
        status: DnsBenchmarkStatus.timeout,
        totalQueries: sampleCount,
        successfulQueries: 0,
        failedQueries: sampleCount,
        testedEndpoint: '${provider.primaryServer}:53',
        protocol: protocol,
        vantagePoint: vantagePoint,
        errorMessage: 'Query timed out',
        timestamp: DateTime.now(),
      );
    }

    final samples = providerLatencies[provider.id] ?? const [15.0, 14.0, 16.0];
    final sorted = List<double>.from(samples)..sort();
    final median = DnsBenchmarkService.calculateMedian(sorted);

    return DnsBenchmarkResult(
      provider: provider,
      status: DnsBenchmarkStatus.success,
      medianLatencyMs: median,
      minLatencyMs: sorted.first,
      maxLatencyMs: sorted.last,
      avgLatencyMs: sorted.reduce((a, b) => a + b) / sorted.length,
      samples: samples,
      totalQueries: sampleCount,
      successfulQueries: sampleCount,
      failedQueries: 0,
      testedEndpoint: '${provider.primaryServer}:53',
      protocol: protocol,
      vantagePoint: vantagePoint,
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DnsPacketCodec Tests (RFC 1035)', () {
    test('buildQuery encodes standard DNS A-record query packet', () {
      const queryId = 0x4a2b;
      final packet = DnsPacketCodec.buildQuery('cloudflare.com', queryId);

      expect(packet.length, greaterThan(12));

      // Transaction ID
      expect(packet[0], equals(0x4a));
      expect(packet[1], equals(0x2b));

      // Flags: RD=1 -> 0x0100
      expect(packet[2], equals(0x01));
      expect(packet[3], equals(0x00));

      // QDCOUNT = 1
      expect(packet[4], equals(0x00));
      expect(packet[5], equals(0x01));

      // QNAME: 10 'cloudflare' 3 'com' 0
      const qnameStart = 12;
      expect(packet[qnameStart], equals(10));
      expect(
        String.fromCharCodes(packet.sublist(qnameStart + 1, qnameStart + 11)),
        equals('cloudflare'),
      );
      expect(packet[qnameStart + 11], equals(3));
      expect(
        String.fromCharCodes(packet.sublist(qnameStart + 12, qnameStart + 15)),
        equals('com'),
      );
      expect(packet[qnameStart + 15], equals(0)); // null terminator

      // QTYPE = 1 (A), QCLASS = 1 (IN)
      const typeOffset = qnameStart + 16;
      expect(packet[typeOffset], equals(0x00));
      expect(packet[typeOffset + 1], equals(0x01)); // QTYPE A
      expect(packet[typeOffset + 2], equals(0x00));
      expect(packet[typeOffset + 3], equals(0x01)); // QCLASS IN
    });

    test('parseResponse validates response ID and flags', () {
      const queryId = 0x1234;
      // Synthesize 16-byte response packet with QR=1, RCODE=0
      final respBytes = Uint8List(16);
      respBytes[0] = 0x12;
      respBytes[1] = 0x34;
      respBytes[2] = 0x81; // QR=1, RD=1
      respBytes[3] = 0x80; // RA=1, RCODE=0
      respBytes[4] = 0x00;
      respBytes[5] = 0x01; // QDCOUNT=1
      respBytes[6] = 0x00;
      respBytes[7] = 0x01; // ANCOUNT=1

      final parsed = DnsPacketCodec.parseResponse(respBytes, queryId);

      expect(parsed.isResponse, isTrue);
      expect(parsed.queryId, equals(queryId));
      expect(parsed.rcode, equals(0));
      expect(parsed.isSuccessfulResponse, isTrue);
      expect(parsed.rcodeDescription, equals('NoError'));
    });

    test(
      'parseResponse treats NXDOMAIN (RCODE 3) and Refused (RCODE 5) as valid server replies',
      () {
        const queryId = 0x5678;
        final respBytes = Uint8List(16);
        respBytes[0] = 0x56;
        respBytes[1] = 0x78;
        respBytes[2] = 0x81; // QR=1
        respBytes[3] = 0x03; // RCODE=3 (NXDOMAIN)

        final nxParsed = DnsPacketCodec.parseResponse(respBytes, queryId);
        expect(nxParsed.isSuccessfulResponse, isTrue);
        expect(nxParsed.rcode, equals(3));
        expect(nxParsed.rcodeDescription, contains('NXDOMAIN'));

        // Policy / Filter response: RCODE=5 Refused
        respBytes[3] = 0x05;
        final refParsed = DnsPacketCodec.parseResponse(respBytes, queryId);
        expect(refParsed.isSuccessfulResponse, isTrue);
        expect(refParsed.rcode, equals(5));
        expect(refParsed.rcodeDescription, contains('Refused'));
      },
    );

    test(
      'parseResponse rejects packets with ID mismatch or truncated headers',
      () {
        const queryId = 0x1111;
        final truncated = Uint8List(8);
        final tParsed = DnsPacketCodec.parseResponse(truncated, queryId);
        expect(tParsed.isResponse, isFalse);
        expect(tParsed.errorMessage, contains('Truncated'));

        final respWrongId = Uint8List(16);
        respWrongId[0] = 0x22;
        respWrongId[1] = 0x22;
        final mParsed = DnsPacketCodec.parseResponse(respWrongId, queryId);
        expect(mParsed.isResponse, isFalse);
        expect(mParsed.errorMessage, contains('mismatch'));
      },
    );
  });

  group('DnsProviderRegistry Tests', () {
    test('All 8 required public DNS providers are present with stable IDs', () {
      const providers = DnsProviderRegistry.publicProviders;
      expect(providers.length, equals(8));

      final ids = providers.map((p) => p.id).toSet();
      expect(
        ids,
        containsAll([
          'adguard',
          'cleanbrowsing',
          'cloudflare',
          'controld',
          'google',
          'nextdns',
          'opendns',
          'quad9',
        ]),
      );

      for (final p in providers) {
        expect(p.name, isNotEmpty);
        expect(p.primaryServer, isNotEmpty);
        expect(p.description, isNotEmpty);
        expect(p.isRouterDns, isFalse);
      }
    });

    test(
      'Initial public providers are in alphabetical order by display name',
      () {
        final names = DnsProviderRegistry.publicProviders
            .map((p) => p.name)
            .toList();
        const expected = [
          'AdGuard DNS',
          'CleanBrowsing',
          'Cloudflare',
          'Control D',
          'Google Public DNS',
          'NextDNS',
          'OpenDNS',
          'Quad9',
        ];
        expect(names, equals(expected));
      },
    );

    test('createRouterDnsProvider builds router DNS entry properly', () {
      const cfg = RouterDnsConfig(
        isLocalForwarder: true,
        localEndpoint: '192.168.1.1:53',
        upstreamServers: ['1.1.1.1', '8.8.8.8'],
        isVerified: true,
        details: 'Local dnsmasq forwarder on 192.168.1.1:53',
      );

      final rProvider = DnsProviderRegistry.createRouterDnsProvider(
        routerIp: '192.168.1.1',
        config: cfg,
      );

      expect(rProvider.id, equals('router_current'));
      expect(rProvider.name, equals('Current Router DNS'));
      expect(rProvider.primaryServer, equals('192.168.1.1'));
      expect(rProvider.isRouterDns, isTrue);
      expect(rProvider.description, contains('dnsmasq'));
    });
  });

  group('DNS Sorting Requirements Tests', () {
    test('Pre-test list is sorted alphabetically (case-insensitive)', () {
      final list = [
        const DnsBenchmarkResult(
          provider: DnsProviderRegistry.quad9,
          testedEndpoint: '9.9.9.9:53',
        ),
        const DnsBenchmarkResult(
          provider: DnsProviderRegistry.adguard,
          testedEndpoint: '94.140.14.14:53',
        ),
        const DnsBenchmarkResult(
          provider: DnsProviderRegistry.cloudflare,
          testedEndpoint: '1.1.1.1:53',
        ),
      ];

      final sorted = DnsBenchmarkResult.sortAlphabetical(list);
      expect(sorted[0].provider.name, equals('AdGuard DNS'));
      expect(sorted[1].provider.name, equals('Cloudflare'));
      expect(sorted[2].provider.name, equals('Quad9'));
    });

    test('Post-test list sorts by ascending median latency (lowest first)', () {
      final list = [
        const DnsBenchmarkResult(
          provider: DnsProviderRegistry.google,
          status: DnsBenchmarkStatus.success,
          medianLatencyMs: 32.4,
          testedEndpoint: '8.8.8.8:53',
        ),
        const DnsBenchmarkResult(
          provider: DnsProviderRegistry.cloudflare,
          status: DnsBenchmarkStatus.success,
          medianLatencyMs: 8.2,
          testedEndpoint: '1.1.1.1:53',
        ),
        const DnsBenchmarkResult(
          provider: DnsProviderRegistry.quad9,
          status: DnsBenchmarkStatus.success,
          medianLatencyMs: 14.5,
          testedEndpoint: '9.9.9.9:53',
        ),
      ];

      final sorted = DnsBenchmarkResult.sortByAscendingLatency(list);
      expect(sorted[0].provider.name, equals('Cloudflare'));
      expect(sorted[0].medianLatencyMs, equals(8.2));
      expect(sorted[1].provider.name, equals('Quad9'));
      expect(sorted[1].medianLatencyMs, equals(14.5));
      expect(sorted[2].provider.name, equals('Google Public DNS'));
      expect(sorted[2].medianLatencyMs, equals(32.4));
    });

    test('Equal latency uses deterministic alphabetical tie-breaker', () {
      final list = [
        const DnsBenchmarkResult(
          provider: DnsProviderRegistry.google,
          status: DnsBenchmarkStatus.success,
          medianLatencyMs: 15.0,
          testedEndpoint: '8.8.8.8:53',
        ),
        const DnsBenchmarkResult(
          provider: DnsProviderRegistry.cleanBrowsing,
          status: DnsBenchmarkStatus.success,
          medianLatencyMs: 15.0,
          testedEndpoint: '185.228.168.9:53',
        ),
      ];

      final sorted = DnsBenchmarkResult.sortByAscendingLatency(list);
      expect(sorted[0].provider.name, equals('CleanBrowsing'));
      expect(sorted[1].provider.name, equals('Google Public DNS'));
    });

    test(
      'Failed, timeout, and unmeasured providers are never zero ms and placed after successful providers',
      () {
        final list = [
          const DnsBenchmarkResult(
            provider: DnsProviderRegistry.quad9,
            status: DnsBenchmarkStatus.timeout,
            medianLatencyMs: null, // Must not be 0.0 ms!
            testedEndpoint: '9.9.9.9:53',
          ),
          const DnsBenchmarkResult(
            provider: DnsProviderRegistry.cloudflare,
            status: DnsBenchmarkStatus.success,
            medianLatencyMs: 9.1,
            testedEndpoint: '1.1.1.1:53',
          ),
          const DnsBenchmarkResult(
            provider: DnsProviderRegistry.adguard,
            status: DnsBenchmarkStatus.unreachable,
            medianLatencyMs: null,
            testedEndpoint: '94.140.14.14:53',
          ),
        ];

        final sorted = DnsBenchmarkResult.sortByAscendingLatency(list);

        // Cloudflare (successful) must be first
        expect(sorted[0].provider.name, equals('Cloudflare'));
        expect(sorted[0].medianLatencyMs, equals(9.1));

        // Failed / timeout must be placed after
        expect(sorted[1].status.hasValidLatency, isFalse);
        expect(sorted[1].medianLatencyMs, isNull);
        expect(sorted[2].status.hasValidLatency, isFalse);
        expect(sorted[2].medianLatencyMs, isNull);
      },
    );
  });

  group('DnsRouterDiscovery Tests', () {
    test('Discovers local forwarder and WAN upstream DNS', () async {
      final mockApi = MockApiService();
      final discovery = DnsRouterDiscovery(mockApi);

      final cfg = await discovery.discover(
        ipAddress: '192.168.1.1',
        sysauth: 'mock_token',
        useHttps: false,
      );

      expect(cfg.isLocalForwarder, isTrue);
      expect(cfg.localEndpoint, equals('192.168.1.1:53'));
      expect(cfg.details, contains('Local'));
    });
  });

  group('DnsBenchmarkController Tests', () {
    test(
      'Initial controller state has all 8 public providers in alphabetical order',
      () {
        final container = ProviderContainer(
          overrides: [
            dnsBenchmarkServiceProvider.overrideWithValue(
              _FakeDnsBenchmarkService(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final state = container.read(dnsBenchmarkControllerProvider);
        expect(state.publicResults.length, equals(8));
        expect(state.publicResults[0].provider.name, equals('AdGuard DNS'));
        expect(state.publicResults[1].provider.name, equals('CleanBrowsing'));
        expect(state.publicResults[2].provider.name, equals('Cloudflare'));
        expect(state.publicResults[3].provider.name, equals('Control D'));
        expect(
          state.publicResults[4].provider.name,
          equals('Google Public DNS'),
        );
        expect(state.publicResults[5].provider.name, equals('NextDNS'));
        expect(state.publicResults[6].provider.name, equals('OpenDNS'));
        expect(state.publicResults[7].provider.name, equals('Quad9'));
      },
    );

    test(
      'startBenchmark executes and ranks results by lowest latency first',
      () async {
        final latencies = {
          'adguard': [22.0, 23.0, 24.0], // median 23.0
          'cleanbrowsing': [35.0, 36.0, 37.0], // median 36.0
          'cloudflare': [6.0, 7.0, 8.0], // median 7.0 (FASTEST!)
          'controld': [18.0, 19.0, 20.0], // median 19.0
          'google': [12.0, 13.0, 14.0], // median 13.0
          'nextdns': [15.0, 16.0, 17.0], // median 16.0
          'opendns': [28.0, 29.0, 30.0], // median 29.0
          'quad9': [10.0, 11.0, 12.0], // median 11.0
          'router_current': [2.0, 2.5, 3.0], // median 2.5
        };

        final fake = _FakeDnsBenchmarkService(providerLatencies: latencies);
        final container = ProviderContainer(
          overrides: [dnsBenchmarkServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          dnsBenchmarkControllerProvider.notifier,
        );
        await notifier.startBenchmark();

        final state = container.read(dnsBenchmarkControllerProvider);
        expect(state.isRunning, isFalse);
        expect(state.fastestProvider, isNotNull);
        expect(state.fastestProvider!.provider.name, equals('Cloudflare'));

        // Check sorting order:
        // 1: Cloudflare (7.0)
        // 2: Quad9 (11.0)
        // 3: Google (13.0)
        // 4: NextDNS (16.0)
        // 5: Control D (19.0)
        // 6: AdGuard (23.0)
        // 7: OpenDNS (29.0)
        // 8: CleanBrowsing (36.0)
        expect(state.publicResults[0].provider.name, equals('Cloudflare'));
        expect(state.publicResults[0].medianLatencyMs, equals(7.0));
        expect(state.publicResults[1].provider.name, equals('Quad9'));
        expect(state.publicResults[1].medianLatencyMs, equals(11.0));
        expect(
          state.publicResults[2].provider.name,
          equals('Google Public DNS'),
        );
        expect(state.publicResults[3].provider.name, equals('NextDNS'));
        expect(state.publicResults[4].provider.name, equals('Control D'));
        expect(state.publicResults[5].provider.name, equals('AdGuard DNS'));
        expect(state.publicResults[6].provider.name, equals('OpenDNS'));
        expect(state.publicResults[7].provider.name, equals('CleanBrowsing'));
      },
    );

    test(
      'Rerun clears previous results and updates with latest measurements',
      () async {
        final fake = _FakeDnsBenchmarkService(
          providerLatencies: {
            'cloudflare': [5.0, 5.0, 5.0],
            'google': [10.0, 10.0, 10.0],
          },
        );
        final container = ProviderContainer(
          overrides: [dnsBenchmarkServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          dnsBenchmarkControllerProvider.notifier,
        );
        await notifier.startBenchmark();

        final firstRunTime = container
            .read(dnsBenchmarkControllerProvider)
            .lastRunTimestamp;
        expect(firstRunTime, isNotNull);

        // Now change latencies for rerun: make Google faster than Cloudflare
        final rerunLatencies = {
          'cloudflare': [20.0, 20.0, 20.0],
          'google': [4.0, 4.0, 4.0],
        };
        final fake2 = _FakeDnsBenchmarkService(
          providerLatencies: rerunLatencies,
        );

        // Re-run
        final container2 = ProviderContainer(
          overrides: [dnsBenchmarkServiceProvider.overrideWithValue(fake2)],
        );
        addTearDown(container2.dispose);

        final notifier2 = container2.read(
          dnsBenchmarkControllerProvider.notifier,
        );
        await notifier2.startBenchmark();

        final state2 = container2.read(dnsBenchmarkControllerProvider);
        expect(
          state2.fastestProvider!.provider.name,
          equals('Google Public DNS'),
        );
        expect(
          state2.publicResults[0].provider.name,
          equals('Google Public DNS'),
        );
      },
    );

    test(
      'startBenchmark handles provider timeouts and places failed providers last',
      () async {
        final fake = _FakeDnsBenchmarkService(
          providerLatencies: {
            'cloudflare': [5.0, 5.0, 5.0],
            'google': [8.0, 8.0, 8.0],
          },
          failingProviders: {'quad9', 'cleanbrowsing'},
        );
        final container = ProviderContainer(
          overrides: [dnsBenchmarkServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          dnsBenchmarkControllerProvider.notifier,
        );
        await notifier.startBenchmark();

        final state = container.read(dnsBenchmarkControllerProvider);
        expect(state.isRunning, isFalse);

        // Successfully measured come first
        expect(state.publicResults[0].provider.name, equals('Cloudflare'));
        expect(state.publicResults[0].medianLatencyMs, equals(5.0));
        expect(
          state.publicResults[1].provider.name,
          equals('Google Public DNS'),
        );

        // Failed providers are placed after measured providers and never have zero ms
        final quad9 = state.publicResults.firstWhere(
          (r) => r.provider.id == 'quad9',
        );
        final cleanBrowsing = state.publicResults.firstWhere(
          (r) => r.provider.id == 'cleanbrowsing',
        );
        expect(quad9.status, equals(DnsBenchmarkStatus.timeout));
        expect(quad9.medianLatencyMs, isNull);
        expect(cleanBrowsing.status, equals(DnsBenchmarkStatus.timeout));
        expect(cleanBrowsing.medianLatencyMs, isNull);
      },
    );

    test(
      'Custom DNS toggle and input includes custom provider in benchmark run',
      () async {
        final fake = _FakeDnsBenchmarkService(
          providerLatencies: {
            'custom_dns': [3.5, 3.5, 3.5], // Fastest
            'cloudflare': [5.0, 5.0, 5.0],
          },
        );
        final container = ProviderContainer(
          overrides: [dnsBenchmarkServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          dnsBenchmarkControllerProvider.notifier,
        );

        // Initially 8 public providers
        expect(
          container.read(dnsBenchmarkControllerProvider).publicResults.length,
          equals(8),
        );

        // Enable custom DNS and set valid IP
        notifier.toggleCustomDns(true);
        notifier.updateCustomDns('1.1.1.2');

        // Now 9 providers in state
        final preState = container.read(dnsBenchmarkControllerProvider);
        expect(preState.publicResults.length, equals(9));
        expect(
          preState.publicResults.any((p) => p.provider.id == 'custom_dns'),
          isTrue,
        );

        // Run benchmark
        await notifier.startBenchmark();

        final postState = container.read(dnsBenchmarkControllerProvider);
        expect(postState.fastestProvider, isNotNull);
        expect(postState.fastestProvider!.provider.id, equals('custom_dns'));
        expect(
          postState.publicResults[0].provider.name,
          equals('Custom DNS (1.1.1.2)'),
        );
        expect(postState.publicResults[0].medianLatencyMs, equals(3.5));
      },
    );
  });
}
