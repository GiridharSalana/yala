// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/sqm/models/sqm_telemetry.dart';
import 'package:yala/modules/sqm/services/sqm_telemetry_service.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';

class _FakeFailingApiService implements IApiService {
  final int errorCode;
  final String? errorMessage;

  _FakeFailingApiService({
    this.errorCode = 1,
    this.errorMessage,
  });

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async {
    if (errorMessage != null) {
      throw Exception(errorMessage);
    }
    return [
      0,
      {'code': errorCode, 'stdout': '', 'stderr': 'error'}
    ];
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SQM Telemetry Service - Linux tc Parser Fixture Tests', () {
    test('1. Standard CAKE single-tin output parses correctly', () {
      const cakeStdout = '''
qdisc cake 800e: dev eth0 root refcnt 2 bandwidth 100Mbit besteffort nonrec dual-srchost nat nowash ack-filter split-gso rtt 100ms raw overhead 0
 Sent 124859021 bytes 184021 pkt (dropped 142, overlimits 184021 requeues 0)
 backlog 0b 0p requeues 0
 memory used: 124512b of 4Mb
 capacity estimate: 100Mbit
 min net len 40, max net len 1514
''';

      final telemetry = SqmTelemetryService.parseTcOutput('eth0', cakeStdout);

      expect(telemetry.interfaceName, equals('eth0'));
      expect(telemetry.qdisc, equals('cake'));
      expect(telemetry.handle, equals('800e:'));
      expect(telemetry.root, isTrue);
      expect(telemetry.sentBytes, equals(124859021));
      expect(telemetry.sentPackets, equals(184021));
      expect(telemetry.droppedPackets, equals(142));
      expect(telemetry.overlimits, equals(184021));
      expect(telemetry.requeues, equals(0));
      expect(telemetry.backlogBytes, equals(0));
      expect(telemetry.backlogPackets, equals(0));
      expect(telemetry.memoryUsedBytes, equals(124512));
      expect(telemetry.memoryLimitBytes, equals(4 * 1024 * 1024));
      expect(telemetry.capacityEstimateBps, equals(100 * 1000 * 1000));
      expect(telemetry.tinStats, isEmpty);
      expect(telemetry.hasBacklog, isFalse);
      expect(telemetry.hasCumulativeDrops, isTrue);
      expect(telemetry.hasCumulativeOverlimits, isTrue);
      expect(telemetry.dropRatePercent, closeTo(0.077, 0.005));
    });

    test('2. CAKE Diffserv3 multi-tin output parses all tins and delay metrics', () {
      const diffserv3Stdout = '''
qdisc cake 800e: dev eth0 root refcnt 2 bandwidth 100Mbit diffserv3 nonrec dual-srchost nat nowash ack-filter split-gso rtt 100ms raw overhead 0
 Sent 50000000 bytes 40000 pkt (dropped 25, overlimits 500 requeues 0)
 backlog 1500b 1p requeues 0
 memory used: 65536b of 4Mb
 capacity estimate: 100Mbit
 Bulk:
  threshold 6250Kbit
  target 19.3ms
  interval 119.3ms
  pk_delay 1.2ms
  av_delay 400us
  sp_delay 100us
  backlog 0b 0p
  dropped 5
 Best Effort:
  threshold 100Mbit
  target 5.0ms
  interval 100ms
  pk_delay 300us
  av_delay 120us
  sp_delay 40us
  backlog 1500b 1p
  dropped 20
 Voice:
  threshold 25Mbit
  target 5ms
  interval 100ms
  pk_delay 100us
  av_delay 40us
  sp_delay 20us
  backlog 0b 0p
  dropped 0
''';

      final telemetry = SqmTelemetryService.parseTcOutput('eth0', diffserv3Stdout);

      expect(telemetry.qdisc, equals('cake'));
      expect(telemetry.sentBytes, equals(50000000));
      expect(telemetry.droppedPackets, equals(25));
      expect(telemetry.backlogBytes, equals(1500));
      expect(telemetry.backlogPackets, equals(1));
      expect(telemetry.hasBacklog, isTrue);
      expect(telemetry.tinStats.length, equals(3));

      // Bulk Tin
      final bulk = telemetry.tinStats[0];
      expect(bulk.name, equals('Bulk'));
      expect(bulk.thresholdBps, equals(6250 * 1000));
      expect(bulk.targetMs, closeTo(19.3, 0.01));
      expect(bulk.intervalMs, closeTo(119.3, 0.01));
      expect(bulk.pkDelayMs, closeTo(1.2, 0.01));
      expect(bulk.avDelayMs, closeTo(0.4, 0.01));
      expect(bulk.spDelayMs, closeTo(0.1, 0.01));
      expect(bulk.droppedPackets, equals(5));
      expect(bulk.backlogBytes, equals(0));

      // Best Effort Tin
      final bestEffort = telemetry.tinStats[1];
      expect(bestEffort.name, equals('Best Effort'));
      expect(bestEffort.thresholdBps, equals(100 * 1000 * 1000));
      expect(bestEffort.targetMs, closeTo(5.0, 0.01));
      expect(bestEffort.avDelayMs, closeTo(0.12, 0.01));
      expect(bestEffort.droppedPackets, equals(20));
      expect(bestEffort.backlogBytes, equals(1500));
      expect(bestEffort.backlogPackets, equals(1));

      // Voice Tin
      final voice = telemetry.tinStats[2];
      expect(voice.name, equals('Voice'));
      expect(voice.thresholdBps, equals(25 * 1000 * 1000));
      expect(voice.droppedPackets, equals(0));
    });

    test('3. CAKE Diffserv4 4-tin output parses all tins', () {
      const diffserv4Stdout = '''
qdisc cake 800e: dev pppoe-wan root refcnt 2 bandwidth 50Mbit diffserv4
 Sent 100000 bytes 100 pkt (dropped 0, overlimits 0)
 backlog 0b 0p
 Bulk:
  dropped 0
 Best Effort:
  dropped 0
 Video:
  dropped 0
 Voice:
  dropped 0
''';

      final telemetry = SqmTelemetryService.parseTcOutput('pppoe-wan', diffserv4Stdout);
      expect(telemetry.interfaceName, equals('pppoe-wan'));
      expect(telemetry.tinStats.length, equals(4));
      expect(telemetry.tinStats.map((t) => t.name).toList(),
          equals(['Bulk', 'Best Effort', 'Video', 'Voice']));
    });

    test('4. Standard FQ-CoDel output parses correctly with detailed stats', () {
      const fqCodelStdout = '''
qdisc fq_codel 800f: dev eth0 root refcnt 2 limit 1024p flows 1024 quantum 1514 target 5ms interval 100ms memory_limit 32Mb ecn drop_batch 64
 Sent 9548201 bytes 12040 pkt (dropped 4, overlimits 0 requeues 0)
 backlog 0b 0p requeues 0
  maxpacket 1514 drop_overlimit 0 new_flow_count 124 ecn_mark 2
  new_flows_len 0 old_flows_len 1
''';

      final telemetry = SqmTelemetryService.parseTcOutput('eth0', fqCodelStdout);

      expect(telemetry.interfaceName, equals('eth0'));
      expect(telemetry.qdisc, equals('fq_codel'));
      expect(telemetry.isFqCodel, isTrue);
      expect(telemetry.isCake, isFalse);
      expect(telemetry.sentBytes, equals(9548201));
      expect(telemetry.sentPackets, equals(12040));
      expect(telemetry.droppedPackets, equals(4));
      expect(telemetry.maxPacket, equals(1514));
      expect(telemetry.dropOverlimit, equals(0));
      expect(telemetry.newFlowCount, equals(124));
      expect(telemetry.ecnMarked, equals(2));
    });

    test('5. No qdisc (noqueue) reports clean unshaped status', () {
      const noqueueStdout = 'qdisc noqueue 0: dev eth0 root refcnt 2';
      final telemetry = SqmTelemetryService.parseTcOutput('eth0', noqueueStdout);

      expect(telemetry.qdisc, equals('noqueue'));
      expect(telemetry.hasBacklog, isFalse);
      expect(telemetry.hasCumulativeDrops, isFalse);
      expect(telemetry.hasCumulativeOverlimits, isFalse);
      expect(telemetry.sentBytes, equals(0));
      expect(telemetry.droppedPackets, equals(0));
    });

    test('6. Pfifo_fast reports non-SQM default Linux qdisc', () {
      const pfifoStdout = '''
qdisc pfifo_fast 0: dev eth0 root refcnt 2 bands 3 priomap 1 2 2 2 1 2 0 0 1 1 1 1 1 1 1 1
 Sent 45120 bytes 310 pkt (dropped 0, overlimits 0 requeues 0)
 backlog 0b 0p requeues 0
''';
      final telemetry = SqmTelemetryService.parseTcOutput('eth0', pfifoStdout);

      expect(telemetry.qdisc, equals('pfifo_fast'));
      expect(telemetry.sentBytes, equals(45120));
      expect(telemetry.sentPackets, equals(310));
      expect(telemetry.droppedPackets, equals(0));
    });

    test('7. Unknown / third-party qdisc parses without throwing', () {
      const tbfStdout = '''
qdisc tbf 10: dev eth0 root refcnt 2 rate 10Mbit burst 10Kb lat 50ms
 Sent 1000 bytes 10 pkt (dropped 1, overlimits 5 requeues 0)
 backlog 500b 1p requeues 0
''';
      final telemetry = SqmTelemetryService.parseTcOutput('eth0', tbfStdout);

      expect(telemetry.qdisc, equals('tbf'));
      expect(telemetry.sentBytes, equals(1000));
      expect(telemetry.droppedPackets, equals(1));
      expect(telemetry.overlimits, equals(5));
      expect(telemetry.hasBacklog, isTrue);
      expect(telemetry.hasCumulativeDrops, isTrue);
      expect(telemetry.hasCumulativeOverlimits, isTrue);
    });

    test('8. Malformed truncated output gracefully recovers', () {
      const malformedStdout = 'qdisc cake 800e: dev eth0 Sent 12345 (truncated garbage...';
      final telemetry = SqmTelemetryService.parseTcOutput('eth0', malformedStdout);

      expect(telemetry.interfaceName, equals('eth0'));
      expect(telemetry.rawOutput, equals(malformedStdout));
      expect(telemetry.droppedPackets, equals(0));
    });

    test('9. Empty string and whitespace return safe empty telemetry', () {
      final emptyTelem = SqmTelemetryService.parseTcOutput('eth0', '');
      expect(emptyTelem.qdisc, equals('none'));
      expect(emptyTelem.sentBytes, equals(0));

      final whitespaceTelem = SqmTelemetryService.parseTcOutput('eth0', '   \n  \t ');
      expect(whitespaceTelem.qdisc, equals('none'));
      expect(whitespaceTelem.sentBytes, equals(0));
    });

    test('10. Multiple qdiscs (root + IFB / ingress) prioritizes root qdisc', () {
      const multiQdiscStdout = '''
qdisc cake 800e: dev eth0 root refcnt 2 bandwidth 100Mbit besteffort
 Sent 200000 bytes 200 pkt (dropped 5, overlimits 10)
 backlog 0b 0p
qdisc ingress ffff: dev eth0 parent ffff:fff1 ----------------
 Sent 50000 bytes 50 pkt (dropped 0, overlimits 0)
 backlog 0b 0p
''';
      final telemetry = SqmTelemetryService.parseTcOutput('eth0', multiQdiscStdout);
      expect(telemetry.qdisc, equals('cake'));
      expect(telemetry.sentBytes, equals(200000));
      expect(telemetry.droppedPackets, equals(5));
    });

    test('11. Representative interface names parse properly', () {
      for (final iface in ['eth0', 'pppoe-wan', 'wan6', 'br-lan', 'lan1', 'vlan.100']) {
        final telem = SqmTelemetryService.parseTcOutput(
          iface,
          'qdisc cake 800e: dev $iface root Sent 100 bytes 1 pkt (dropped 0, overlimits 0)',
        );
        expect(telem.interfaceName, equals(iface));
        expect(telem.qdisc, equals('cake'));
      }
    });

    test('12. Interface name validator rejects shell metacharacters and invalid inputs', () {
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch('eth0'), isTrue);
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch('pppoe-wan'), isTrue);
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch('br-lan.10'), isTrue);

      // Malicious or illegal characters
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch('eth0; rm -rf /'), isFalse);
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch('eth0 && reboot'), isFalse);
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch('eth0 | cat'), isFalse);
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch('eth0`id`'), isFalse);
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch('eth0\$VAR'), isFalse);
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch('eth0/1'), isFalse);
      expect(SqmTelemetryService.validInterfaceRegex.hasMatch(''), isFalse);
    });

    test('13. Zero manufactured latency: delay is never inferred when absent', () {
      const noDelayStdout = '''
qdisc cake 800e: dev eth0 root refcnt 2 bandwidth 100Mbit besteffort
 Sent 10000 bytes 10 pkt (dropped 0, overlimits 0)
 backlog 0b 0p
''';
      final telemetry = SqmTelemetryService.parseTcOutput('eth0', noDelayStdout);
      expect(telemetry.tinStats, isEmpty);
      // Ensure zero hallucination: no artificial delay is injected
      expect(telemetry.hasBacklog, isFalse);
      expect(telemetry.hasCumulativeDrops, isFalse);
      expect(telemetry.hasCumulativeOverlimits, isFalse);
      expect(telemetry.dropRatePercent, equals(0.0));
    });

    test('14. Command failure handling returns null gracefully', () async {
      final service = SqmTelemetryService();
      final failingApi = _FakeFailingApiService(errorCode: 127);

      final result = await service.fetchQueueTelemetry(
        apiService: failingApi,
        ipAddress: '192.168.1.1',
        sysauth: 'test-token',
        useHttps: false,
        interfaceName: 'eth0',
      );

      expect(result, isNull);
    });

    test('15. Permission / ACL failure returns null gracefully without crashing', () async {
      final service = SqmTelemetryService();
      final aclDeniedApi = _FakeFailingApiService(
        errorMessage: 'Access denied: method not allowed by rpcd ACL',
      );

      final result = await service.fetchQueueTelemetry(
        apiService: aclDeniedApi,
        ipAddress: '192.168.1.1',
        sysauth: 'test-token',
        useHttps: false,
        interfaceName: 'eth0',
      );

      expect(result, isNull);
    });

    test('16. Invalid interface name is rejected before calling API', () async {
      final service = SqmTelemetryService();
      final failingApi = _FakeFailingApiService();

      final result = await service.fetchQueueTelemetry(
        apiService: failingApi,
        ipAddress: '192.168.1.1',
        sysauth: 'test-token',
        useHttps: false,
        interfaceName: 'eth0; reboot',
      );

      expect(result, isNull);
    });

    test('17. Reviewer Mode generates deterministic realistic mock telemetry', () async {
      final service = SqmTelemetryService();
      final failingApi = _FakeFailingApiService();

      final mockTelem = await service.fetchQueueTelemetry(
        apiService: failingApi,
        ipAddress: '192.168.1.1',
        sysauth: '',
        useHttps: false,
        interfaceName: 'eth0',
        isReviewerMode: true,
      );

      expect(mockTelem, isNotNull);
      expect(mockTelem!.interfaceName, equals('eth0'));
      expect(mockTelem.qdisc, equals('cake'));
      expect(mockTelem.sentPackets, greaterThan(180000));
      expect(mockTelem.droppedPackets, greaterThan(0));
      expect(mockTelem.tinStats.length, equals(3));
      expect(mockTelem.tinStats[0].name, equals('Bulk'));
      expect(mockTelem.tinStats[1].name, equals('Best Effort'));
      expect(mockTelem.tinStats[2].name, equals('Voice'));
    });

    test('18. hasRecentDropActivity derives activity strictly from sample deltas, not cumulative counters', () {
      final sample1 = SqmQueueTelemetry(
        interfaceName: 'eth0',
        qdisc: 'cake',
        sentPackets: 1000,
        droppedPackets: 10,
        overlimits: 5,
        backlogPackets: 0,
        timestamp: DateTime.now().subtract(const Duration(seconds: 3)),
      );

      // Historical cumulative counters exist
      expect(sample1.hasCumulativeDrops, isTrue);
      expect(sample1.hasCumulativeOverlimits, isTrue);
      expect(sample1.hasBacklog, isFalse);

      // Without previous sample, cannot claim recent activity
      expect(sample1.hasRecentDropActivity(null), isFalse);

      // Sample 2: Same cumulative drops and overlimits -> no recent activity
      final sample2 = sample1.copyWith(
        sentPackets: 1500,
        timestamp: DateTime.now(),
      );
      expect(sample2.hasCumulativeDrops, isTrue);
      expect(sample2.hasRecentDropActivity(sample1), isFalse);

      // Sample 3: Cumulative drops increased by 1 -> recent drop activity detected
      final sample3 = sample2.copyWith(
        droppedPackets: 11,
        timestamp: DateTime.now(),
      );
      expect(sample3.hasRecentDropActivity(sample2), isTrue);

      // Sample 4: Overlimits increased by 1 -> recent drop activity detected
      final sample4 = sample2.copyWith(
        overlimits: 6,
        timestamp: DateTime.now(),
      );
      expect(sample4.hasRecentDropActivity(sample2), isTrue);
    });
  });
}
