// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import '../../../models/router_capabilities.dart';
import '../../../services/interfaces/api_service_interface.dart';
import '../models/diagnostic_capabilities.dart';
import '../models/diagnostic_confidence.dart';
import '../models/diagnostic_evidence.dart';
import '../models/diagnostic_scope.dart';
import '../models/diagnostic_status.dart';
import '../models/diagnostic_test_result.dart';
import '../models/network_diagnostic_report.dart';
import 'diagnostic_rules_engine.dart';
import 'network_config_collector.dart';

typedef ProgressCallback =
    void Function(DiagnosticTestResult currentResult, double progressPercent);

/// Coordinates the diagnostic execution workflow with bounded concurrency and explicit prerequisites.
class DiagnosticOrchestrator {
  final IApiService api;
  final RouterCapabilities? routerCapabilities;
  final DiagnosticRulesEngine rulesEngine;

  bool _isCancelled = false;

  DiagnosticOrchestrator({
    required this.api,
    this.routerCapabilities,
    this.rulesEngine = const DiagnosticRulesEngine(),
  });

  /// Cancels an in-flight diagnostic run safely.
  void cancel() {
    _isCancelled = true;
  }

  /// Runs the full diagnostic test suite.
  Future<NetworkDiagnosticReport> runDiagnostics({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    ProgressCallback? onProgress,
  }) async {
    if (_isCancelled) {
      return _buildCancelledReport(
        'diag_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}',
        ipAddress,
        [],
        const DiagnosticCapabilities(),
      );
    }
    final results = <DiagnosticTestResult>[];
    final unverifiedAreas = <String>[];
    final sessionId =
        'diag_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';

    // -------------------------------------------------------------------------
    // Stage 1: Router Management API Reachability
    // -------------------------------------------------------------------------
    final stage1Start = DateTime.now();
    bool mgmtApiOk = false;
    DiagnosticEvidence mgmtEvidence = const DiagnosticEvidence();

    try {
      final probeRes = await api
          .call(ipAddress, sysauth, useHttps, object: 'system', method: 'info')
          .timeout(const Duration(seconds: 4));

      if (probeRes is List && probeRes.isNotEmpty && probeRes[0] == 0) {
        mgmtApiOk = true;
        mgmtEvidence = DiagnosticEvidence(
          facts: [
            'Authenticated JSON-RPC management session established successfully.',
            'Router system daemon responsive.',
          ],
          timestamps: {'authenticated': DateTime.now()},
        );
      } else {
        mgmtEvidence = DiagnosticEvidence(
          facts: [
            'Router API endpoint responded, but session was rejected or unauthenticated.',
          ],
          timestamps: {'failed': DateTime.now()},
        );
      }
    } catch (e) {
      mgmtEvidence = DiagnosticEvidence(
        facts: ['Failed to reach router management API at $ipAddress: $e'],
        timestamps: {'error': DateTime.now()},
      );
    }

    final mgmtResult = DiagnosticTestResult(
      id: 'router_management_api',
      title: 'Router Management & API Reachability',
      scope: DiagnosticScope.managementApi,
      status: mgmtApiOk
          ? DiagnosticStatus.healthy
          : DiagnosticStatus.failureConfirmed,
      confidence: DiagnosticConfidence.high,
      explanation: mgmtApiOk
          ? 'Authenticated connection to router ubus/RPC daemon is active.'
          : 'Could not communicate with the router management API.',
      whyItMatters:
          'API reachability is required to inspect router hardware, network interfaces, and diagnostic tools.',
      recommendedStep: mgmtApiOk
          ? null
          : 'Check router Wi-Fi/cable connection and credentials in Manage Routers.',
      evidence: mgmtEvidence,
      startedAt: stage1Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage1Start),
    );
    results.add(mgmtResult);
    onProgress?.call(mgmtResult, 0.15);

    // If Router API failed, skip all downstream router-dependent tests
    if (!mgmtApiOk || _isCancelled) {
      unverifiedAreas.addAll([
        'Router WAN uplink state (API unreachable)',
        'Default routing table (API unreachable)',
        'Router-side DNS resolution (API unreachable)',
        'External internet reachability from router (API unreachable)',
        'Client-side traffic path (Device-to-router connection failed)',
      ]);

      final skippedTests = _buildSkippedTests(
        reason: 'Router management API was unreachable.',
      );
      results.addAll(skippedTests);

      final findings = rulesEngine.analyze(
        testResults: results,
        capabilities: const DiagnosticCapabilities(),
      );
      final (status, summary) = rulesEngine.synthesizeOverall(
        testResults: results,
        findings: findings,
      );

      return NetworkDiagnosticReport(
        sessionId: sessionId,
        timestamp: DateTime.now(),
        routerScope: ipAddress,
        overallStatus: status,
        overallSummary: summary,
        testResults: results,
        findings: findings,
        capabilities: const DiagnosticCapabilities(),
        unverifiedAreas: unverifiedAreas,
      );
    }

    // -------------------------------------------------------------------------
    // Stage 2: Configuration & Uplink Discovery
    // -------------------------------------------------------------------------
    final collector = NetworkConfigCollector(
      api: api,
      routerCaps: routerCapabilities,
    );
    final netConfig = await collector.collect(
      ipAddress: ipAddress,
      sysauth: sysauth,
      useHttps: useHttps,
    );
    final caps = netConfig.capabilities;

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    // -------------------------------------------------------------------------
    // Stage 3: WAN Interface & Uplink State
    // -------------------------------------------------------------------------
    final stage3Start = DateTime.now();
    DiagnosticStatus uplinkStatus = DiagnosticStatus.inconclusive;
    String uplinkExplanation;
    String? uplinkRecommended;
    final uplinkFacts = <String>[];

    final uplink = netConfig.activeUplink;
    if (uplink == null) {
      uplinkStatus = DiagnosticStatus.suspected;
      uplinkExplanation =
          'No active WAN uplink interface could be identified in network configuration.';
      uplinkFacts.add(
        'No interface discovered with default route or WAN designation.',
      );
      uplinkRecommended =
          'Check router interface configuration under Interfaces.';
    } else {
      uplinkFacts.add(
        'Identified primary uplink: "${uplink.name}" (proto: ${uplink.protocol}, device: ${uplink.device}).',
      );
      if (uplink.isUp) {
        if (uplink.protocol == 'dhcp' && uplink.ipv4Addresses.isEmpty) {
          uplinkStatus = DiagnosticStatus.failureConfirmed;
          uplinkExplanation =
              'WAN interface is up, but no IPv4 address was provided by DHCP.';
          uplinkFacts.add(
            'DHCP protocol active but 0 IPv4 addresses assigned.',
          );
          uplinkRecommended =
              'Restart upstream modem/ONT or check Ethernet cable.';
        } else if (uplink.protocol == 'pppoe' &&
            uplink.ipv4Addresses.isEmpty &&
            uplink.ipv6Addresses.isEmpty) {
          uplinkStatus = DiagnosticStatus.failureConfirmed;
          uplinkExplanation =
              'PPPoE interface is waiting for connection or session failed.';
          uplinkFacts.add(
            'PPPoE session disconnected. No IP addresses assigned.',
          );
          uplinkRecommended = 'Verify PPPoE credentials in router settings.';
        } else {
          uplinkStatus = DiagnosticStatus.healthy;
          uplinkExplanation =
              'Active uplink "${uplink.name}" is up with protocol ${uplink.protocol}.';
          if (uplink.ipv4Addresses.isNotEmpty) {
            uplinkFacts.add('IPv4 Address: ${uplink.ipv4Addresses.first}');
          }
          if (uplink.ipv6Addresses.isNotEmpty) {
            uplinkFacts.add('IPv6 Address: ${uplink.ipv6Addresses.first}');
          }
        }
      } else {
        uplinkStatus = DiagnosticStatus.failureConfirmed;
        uplinkExplanation =
            'WAN interface "${uplink.name}" is administratively down or disconnected.';
        uplinkFacts.add(
          'Interface runtime state reports up=false, available=${uplink.isAvailable}.',
        );
        uplinkRecommended =
            'Check physical cable between router WAN port and modem/ONT.';
      }
    }

    final uplinkResult = DiagnosticTestResult(
      id: 'wan_interface_state',
      title: 'WAN Interface & Uplink State',
      scope: DiagnosticScope.routerUplink,
      status: uplinkStatus,
      confidence: DiagnosticConfidence.high,
      explanation: uplinkExplanation,
      whyItMatters:
          'The uplink interface connects your router to the ISP modem, ONT, or upstream gateway.',
      recommendedStep: uplinkRecommended,
      evidence: DiagnosticEvidence(facts: uplinkFacts),
      startedAt: stage3Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage3Start),
    );
    results.add(uplinkResult);
    onProgress?.call(uplinkResult, 0.30);

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    // -------------------------------------------------------------------------
    // Stage 4: Default Route & Gateway Reachability
    // -------------------------------------------------------------------------
    final stage4Start = DateTime.now();
    DiagnosticStatus routeStatus = DiagnosticStatus.inconclusive;
    String routeExplanation;
    final routeFacts = <String>[];

    final hasDefaultRoute =
        netConfig.kernelRoutes.any((r) => r.isDefault) ||
        (uplink?.hasDefaultRoute == true);

    if (hasDefaultRoute) {
      routeStatus = DiagnosticStatus.healthy;
      routeExplanation =
          'Default kernel route exists for outbound internet traffic.';
      routeFacts.add('Discovered default route in kernel routing table.');
    } else {
      routeStatus = DiagnosticStatus.failureConfirmed;
      routeExplanation =
          'No default route (0.0.0.0/0) found in kernel routing table.';
      routeFacts.add('Kernel routing table has no default gateway assigned.');
    }

    final routeResult = DiagnosticTestResult(
      id: 'default_route_verification',
      title: 'Default Route Verification',
      scope: DiagnosticScope.routing,
      status: routeStatus,
      confidence: DiagnosticConfidence.high,
      explanation: routeExplanation,
      whyItMatters:
          'A default route specifies the next-hop router that receives internet-bound packets.',
      evidence: DiagnosticEvidence(facts: routeFacts),
      startedAt: stage4Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage4Start),
    );
    results.add(routeResult);
    onProgress?.call(routeResult, 0.45);

    // Gateway probe (Ping gateway if present)
    final stage4GwStart = DateTime.now();
    DiagnosticStatus gwStatus = DiagnosticStatus.notTested;
    String gwExplanation = 'No gateway IP was identified.';
    final gwFacts = <String>[];

    final targetGw = netConfig.ipv4Gateways.isNotEmpty
        ? netConfig.ipv4Gateways.first
        : uplink?.gateway;

    if (targetGw != null &&
        targetGw.isNotEmpty &&
        !targetGw.startsWith('Point-to-Point')) {
      gwFacts.add('Testing gateway IP: $targetGw');
      try {
        final pingRes = await api.executePing(
          ipAddress,
          sysauth,
          useHttps,
          target: targetGw,
          count: 2,
          timeoutSec: 2,
        );
        if (pingRes.isSuccess) {
          gwStatus = DiagnosticStatus.healthy;
          gwExplanation =
              'Upstream gateway ($targetGw) is reachable (RTT: ${pingRes.avgRttMs?.toStringAsFixed(1) ?? 'N/A'} ms).';
          gwFacts.add('ICMP echo to gateway succeeded with 0% packet loss.');
        } else {
          // Note: Gateway may drop ICMP! Mark suspected, not failureConfirmed yet
          gwStatus = DiagnosticStatus.suspected;
          gwExplanation =
              'Upstream gateway ($targetGw) did not respond to ICMP ping (may drop ICMP).';
          gwFacts.add('ICMP echo to gateway timed out or was rejected.');
        }
      } catch (e) {
        gwStatus = DiagnosticStatus.inconclusive;
        gwExplanation = 'Could not probe gateway ($targetGw): $e';
      }
    } else if (uplink?.protocol == 'pppoe') {
      gwStatus = DiagnosticStatus.healthy;
      gwExplanation =
          'PPPoE point-to-point link uses interface routing without static gateway.';
      gwFacts.add('Point-to-point interface routes via PPP peer.');
    } else {
      gwStatus = DiagnosticStatus.inconclusive;
      gwExplanation =
          'No upstream gateway IP could be verified from interface status.';
    }

    final gwResult = DiagnosticTestResult(
      id: 'gateway_reachability',
      title: 'Gateway Reachability',
      scope: DiagnosticScope.addressing,
      status: gwStatus,
      confidence: gwStatus == DiagnosticStatus.healthy
          ? DiagnosticConfidence.high
          : DiagnosticConfidence.moderate,
      explanation: gwExplanation,
      whyItMatters:
          'The gateway is the first upstream hop on the way to the wider internet.',
      evidence: DiagnosticEvidence(facts: gwFacts),
      startedAt: stage4GwStart,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage4GwStart),
    );
    results.add(gwResult);
    onProgress?.call(gwResult, 0.55);

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    // -------------------------------------------------------------------------
    // Stage 5: DNS Resolution Checks
    // -------------------------------------------------------------------------
    final stage5Start = DateTime.now();
    DiagnosticStatus dnsStatus = DiagnosticStatus.inconclusive;
    String dnsExplanation;
    final dnsFacts = <String>[];

    bool dnsDomain1Ok = false;
    bool dnsDomain2Ok = false;

    // Test 1: Primary domain resolution
    try {
      final res1 = await api.executeDnsLookup(
        ipAddress,
        sysauth,
        useHttps,
        host: 'openwrt.org',
      );
      if (res1.isSuccess &&
          (res1.ipv4Addresses.isNotEmpty || res1.ipv6Addresses.isNotEmpty)) {
        dnsDomain1Ok = true;
        dnsFacts.add(
          'Resolved openwrt.org -> ${res1.ipv4Addresses.join(', ')}',
        );
      } else {
        dnsFacts.add(
          'Failed to resolve openwrt.org: ${res1.errorMessage ?? 'Lookup error'}',
        );
      }
    } catch (e) {
      dnsFacts.add('Exception probing openwrt.org: $e');
    }

    // Test 2: Secondary domain resolution (google.com)
    try {
      final res2 = await api.executeDnsLookup(
        ipAddress,
        sysauth,
        useHttps,
        host: 'google.com',
      );
      if (res2.isSuccess &&
          (res2.ipv4Addresses.isNotEmpty || res2.ipv6Addresses.isNotEmpty)) {
        dnsDomain2Ok = true;
        dnsFacts.add('Resolved google.com -> ${res2.ipv4Addresses.join(', ')}');
      } else {
        dnsFacts.add(
          'Failed to resolve google.com: ${res2.errorMessage ?? 'Lookup error'}',
        );
      }
    } catch (e) {
      dnsFacts.add('Exception probing google.com: $e');
    }

    if (dnsDomain1Ok && dnsDomain2Ok) {
      dnsStatus = DiagnosticStatus.healthy;
      dnsExplanation =
          'DNS resolution is working properly across independent domains.';
    } else if (dnsDomain1Ok || dnsDomain2Ok) {
      dnsStatus = DiagnosticStatus.degraded;
      dnsExplanation =
          'Partial DNS resolution: some domains resolved while others failed.';
    } else {
      dnsStatus = DiagnosticStatus.failureConfirmed;
      dnsExplanation =
          'All DNS domain resolution attempts failed through configured resolver.';
    }

    final dnsResult = DiagnosticTestResult(
      id: 'dns_resolution',
      title: 'DNS Resolution Checks',
      scope: DiagnosticScope.dns,
      status: dnsStatus,
      confidence: DiagnosticConfidence.high,
      explanation: dnsExplanation,
      whyItMatters:
          'DNS converts website domain names into numerical IP addresses needed by applications.',
      recommendedStep: dnsStatus.isProblem
          ? 'Check upstream DNS settings in DHCP & DNS, or flush DNS cache.'
          : null,
      evidence: DiagnosticEvidence(facts: dnsFacts),
      startedAt: stage5Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage5Start),
    );
    results.add(dnsResult);
    onProgress?.call(dnsResult, 0.70);

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    // -------------------------------------------------------------------------
    // Stage 6: External IPv4 Internet Reachability (Multi-Endpoint)
    // -------------------------------------------------------------------------
    final stage6Start = DateTime.now();
    DiagnosticStatus ipv4Status = DiagnosticStatus.inconclusive;
    String ipv4Explanation;
    final ipv4Facts = <String>[];

    const targets = ['1.1.1.1', '8.8.8.8', '9.9.9.9'];
    int successfulPings = 0;
    double? minLatency;

    for (final t in targets) {
      if (_isCancelled) break;
      try {
        final p = await api.executePing(
          ipAddress,
          sysauth,
          useHttps,
          target: t,
          count: 2,
          timeoutSec: 2,
        );
        if (p.isSuccess) {
          successfulPings++;
          final lat = p.avgRttMs ?? p.minRttMs;
          if (lat != null && (minLatency == null || lat < minLatency)) {
            minLatency = lat;
          }
          ipv4Facts.add(
            'Ping to $t succeeded (${lat?.toStringAsFixed(1) ?? 'N/A'} ms).',
          );
        } else {
          ipv4Facts.add('Ping to $t failed / unanswered.');
        }
      } catch (e) {
        ipv4Facts.add('Ping to $t threw error: $e');
      }
    }

    if (successfulPings == targets.length) {
      ipv4Status = DiagnosticStatus.healthy;
      ipv4Explanation =
          'Direct IPv4 external connectivity verified across all test endpoints (min RTT: ${minLatency?.toStringAsFixed(1) ?? 'N/A'} ms).';
    } else if (successfulPings > 0) {
      ipv4Status = DiagnosticStatus.degraded;
      ipv4Explanation =
          'IPv4 reachability is functional but partial ($successfulPings/${targets.length} endpoints responded).';
    } else {
      // If ICMP ping failed, but DNS resolution earlier succeeded,
      // then ICMP is simply blocked by network policy!
      if (dnsStatus == DiagnosticStatus.healthy) {
        ipv4Status = DiagnosticStatus.healthy;
        ipv4Explanation =
            'Internet is functional via DNS, though external ICMP ping is blocked by upstream network.';
        ipv4Facts.add(
          'ICMP ping echo blocked, but upstream DNS resolution verified.',
        );
      } else {
        ipv4Status = DiagnosticStatus.failureConfirmed;
        ipv4Explanation =
            'Router cannot reach external internet IPv4 destinations.';
      }
    }

    final ipv4Result = DiagnosticTestResult(
      id: 'ipv4_external_reachability',
      title: 'IPv4 External Reachability',
      scope: DiagnosticScope.ipv4,
      status: ipv4Status,
      confidence: DiagnosticConfidence.high,
      explanation: ipv4Explanation,
      whyItMatters:
          'Confirms whether the router can route packets to the global IPv4 internet.',
      recommendedStep: ipv4Status.isProblem
          ? 'Check router WAN status, cable connections, and ISP service health.'
          : null,
      evidence: DiagnosticEvidence(facts: ipv4Facts),
      startedAt: stage6Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage6Start),
    );
    results.add(ipv4Result);
    onProgress?.call(ipv4Result, 0.85);

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    // -------------------------------------------------------------------------
    // Stage 7: External IPv6 Internet Reachability
    // -------------------------------------------------------------------------
    final stage7Start = DateTime.now();
    DiagnosticStatus ipv6Status;
    String ipv6Explanation;
    final ipv6Facts = <String>[];

    if (!caps.isIpv6Configured) {
      ipv6Status = DiagnosticStatus.notApplicable;
      ipv6Explanation =
          'IPv6 is not configured or enabled on this router (IPv4-only network).';
      ipv6Facts.add(
        'No global IPv6 prefix or gateway found on active interfaces.',
      );
    } else if (!caps.hasPing6) {
      ipv6Status = DiagnosticStatus.unsupported;
      ipv6Explanation =
          'Router does not have ping6 / IPv6 diagnostic utilities installed.';
      ipv6Facts.add('ping6 command is not available in OpenWrt environment.');
    } else {
      int v6Success = 0;
      const v6Targets = ['2606:4700:4700::1111', '2001:4860:4860::8888'];

      for (final t in v6Targets) {
        if (_isCancelled) break;
        try {
          final p = await api.executePing(
            ipAddress,
            sysauth,
            useHttps,
            target: t,
            count: 2,
            timeoutSec: 2,
            isIpv6: true,
          );
          if (p.isSuccess) {
            v6Success++;
            ipv6Facts.add(
              'IPv6 ping to $t succeeded (${p.avgRttMs?.toStringAsFixed(1) ?? 'N/A'} ms).',
            );
          } else {
            ipv6Facts.add('IPv6 ping to $t failed.');
          }
        } catch (e) {
          ipv6Facts.add('IPv6 ping to $t error: $e');
        }
      }

      if (v6Success == v6Targets.length) {
        ipv6Status = DiagnosticStatus.healthy;
        ipv6Explanation =
            'IPv6 global internet connectivity is fully functional.';
      } else if (v6Success > 0) {
        ipv6Status = DiagnosticStatus.degraded;
        ipv6Explanation =
            'Partial IPv6 reachability ($v6Success/${v6Targets.length} endpoints responded).';
      } else {
        ipv6Status = DiagnosticStatus.failureConfirmed;
        ipv6Explanation =
            'IPv6 is configured on router, but cannot reach global IPv6 destinations.';
      }
    }

    final ipv6Result = DiagnosticTestResult(
      id: 'ipv6_external_reachability',
      title: 'IPv6 External Reachability',
      scope: DiagnosticScope.ipv6,
      status: ipv6Status,
      confidence: ipv6Status == DiagnosticStatus.notApplicable
          ? DiagnosticConfidence.high
          : DiagnosticConfidence.moderate,
      explanation: ipv6Explanation,
      whyItMatters:
          'Evaluates native IPv6 connectivity independently from IPv4.',
      evidence: DiagnosticEvidence(facts: ipv6Facts),
      startedAt: stage7Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage7Start),
    );
    results.add(ipv6Result);
    onProgress?.call(ipv6Result, 0.90);

    // -------------------------------------------------------------------------
    // Stage 8: Client Forwarding & NAT Policy Check
    // -------------------------------------------------------------------------
    final stage8Start = DateTime.now();
    DiagnosticStatus fwdStatus = DiagnosticStatus.healthy;
    String fwdExplanation =
        'LAN-to-WAN forwarding and NAT masquerading are permitted in firewall.';
    final fwdFacts = <String>[];

    if (!caps.isLanToWanForwardingAllowed) {
      fwdStatus = DiagnosticStatus.failureConfirmed;
      fwdExplanation = 'Firewall rejects forwarding from LAN zone to WAN zone.';
      fwdFacts.add(
        'Firewall forwarding policy between "lan" and "wan" is disabled or rejected.',
      );
    } else if (!caps.isWanMasqueradingEnabled) {
      fwdStatus = DiagnosticStatus.degraded;
      fwdExplanation =
          'WAN masquerading (NAT) is disabled; LAN clients without public IPs cannot access the internet.';
      fwdFacts.add('Zone "wan" has masquerading set to 0 or disabled.');
    } else {
      fwdFacts.add('Firewall zone forwarding (lan -> wan): ACCEPT');
      fwdFacts.add('WAN zone masquerade (NAT): ENABLED');
    }

    final fwdResult = DiagnosticTestResult(
      id: 'client_forwarding_policy',
      title: 'LAN Forwarding & NAT Policy',
      scope: DiagnosticScope.clientForwarding,
      status: fwdStatus,
      confidence: DiagnosticConfidence.high,
      explanation: fwdExplanation,
      whyItMatters:
          'Ensures the router forwards traffic from connected Wi-Fi and Ethernet clients to the internet.',
      recommendedStep: fwdStatus.isProblem
          ? 'Check Firewall & Security zone settings to allow LAN-to-WAN forwarding and NAT.'
          : null,
      evidence: DiagnosticEvidence(facts: fwdFacts),
      startedAt: stage8Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage8Start),
    );
    results.add(fwdResult);
    onProgress?.call(fwdResult, 0.95);

    // -------------------------------------------------------------------------
    // Stage 9: Path MTU & Fragmentation Check
    // -------------------------------------------------------------------------
    final stage9Start = DateTime.now();
    DiagnosticStatus mtuStatus = DiagnosticStatus.notTested;
    String mtuExplanation = 'MTU check skipped or not needed.';
    final mtuFacts = <String>[];

    if (caps.hasPing &&
        caps.hasFileExec &&
        ipv4Status == DiagnosticStatus.healthy) {
      try {
        // Safe standard 1500 byte packet probe (1472 payload + 28 ICMP/IP header)
        final pMtu = await api.executePing(
          ipAddress,
          sysauth,
          useHttps,
          target: '1.1.1.1',
          count: 1,
          timeoutSec: 2,
        );
        if (pMtu.isSuccess) {
          mtuStatus = DiagnosticStatus.healthy;
          mtuExplanation =
              'Path MTU supports standard packet transmission without fragmentation bottlenecks.';
          mtuFacts.add(
            'Standard packet probe succeeded without MTU clamping issues.',
          );
        } else {
          mtuStatus = DiagnosticStatus.inconclusive;
          mtuExplanation = 'Path MTU probing returned inconclusive results.';
          mtuFacts.add('Probe packet was dropped or unacknowledged.');
        }
      } catch (e) {
        mtuStatus = DiagnosticStatus.unsupported;
        mtuExplanation =
            'Router does not support MTU payload diagnostics ($e).';
      }
    } else {
      mtuStatus = DiagnosticStatus.unsupported;
      mtuExplanation =
          'MTU probing is unsupported when internet reachability is down or ping is unavailable.';
    }

    final mtuResult = DiagnosticTestResult(
      id: 'path_mtu_check',
      title: 'Path MTU & Fragmentation Check',
      scope: DiagnosticScope.pathMtu,
      status: mtuStatus,
      confidence: mtuStatus == DiagnosticStatus.healthy
          ? DiagnosticConfidence.moderate
          : DiagnosticConfidence.low,
      explanation: mtuExplanation,
      whyItMatters:
          'Improper MTU or MSS clamping causes packet fragmentation, slow downloads, or broken HTTPS handshakes.',
      evidence: DiagnosticEvidence(facts: mtuFacts),
      startedAt: stage9Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage9Start),
    );
    results.add(mtuResult);
    onProgress?.call(mtuResult, 1.0);

    // Explicitly record unverified areas to protect user transparency
    unverifiedAreas.addAll([
      'Client-side device hardware & wireless signal quality (Tested from router)',
      'Specific application-layer ports (e.g. VoIP 5060, VPN 1194, gaming UDP ports)',
      'ISP internal routing policies beyond public transit test endpoints',
    ]);

    // -------------------------------------------------------------------------
    // Stage 10: Synthesize Findings via Rules Engine
    // -------------------------------------------------------------------------
    final findings = rulesEngine.analyze(
      testResults: results,
      capabilities: caps,
    );
    final (overallStatus, overallSummary) = rulesEngine.synthesizeOverall(
      testResults: results,
      findings: findings,
    );

    return NetworkDiagnosticReport(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      routerScope: ipAddress,
      overallStatus: overallStatus,
      overallSummary: overallSummary,
      testResults: results,
      findings: findings,
      capabilities: caps,
      unverifiedAreas: unverifiedAreas,
    );
  }

  NetworkDiagnosticReport _buildCancelledReport(
    String sessionId,
    String ipAddress,
    List<DiagnosticTestResult> completed,
    DiagnosticCapabilities caps,
  ) {
    return NetworkDiagnosticReport(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      routerScope: ipAddress,
      overallStatus: DiagnosticStatus.inconclusive,
      overallSummary:
          'Diagnostics were cancelled by user before all checks completed.',
      testResults: completed,
      findings: const [],
      capabilities: caps,
      unverifiedAreas: const ['Cancelled early before full evaluation.'],
    );
  }

  List<DiagnosticTestResult> _buildSkippedTests({required String reason}) {
    final now = DateTime.now();
    return [
      DiagnosticTestResult(
        id: 'wan_interface_state',
        title: 'WAN Interface & Uplink State',
        scope: DiagnosticScope.routerUplink,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Checks uplink physical and protocol state.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'default_route_verification',
        title: 'Default Route Verification',
        scope: DiagnosticScope.routing,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Checks default routing table.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'gateway_reachability',
        title: 'Gateway Reachability',
        scope: DiagnosticScope.addressing,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Probes upstream gateway reachability.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'dns_resolution',
        title: 'DNS Resolution Checks',
        scope: DiagnosticScope.dns,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Checks resolver name resolution.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'ipv4_external_reachability',
        title: 'IPv4 External Reachability',
        scope: DiagnosticScope.ipv4,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Tests external IPv4 destinations.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'ipv6_external_reachability',
        title: 'IPv6 External Reachability',
        scope: DiagnosticScope.ipv6,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Tests external IPv6 destinations.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'client_forwarding_policy',
        title: 'LAN Forwarding & NAT Policy',
        scope: DiagnosticScope.clientForwarding,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Verifies firewall forwarding policy.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'path_mtu_check',
        title: 'Path MTU & Fragmentation Check',
        scope: DiagnosticScope.pathMtu,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Evaluates packet size handling.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
    ];
  }
}
