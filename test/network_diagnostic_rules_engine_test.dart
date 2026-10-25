// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/network_diagnostic/engine/diagnostic_rules_engine.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_capabilities.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_confidence.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_evidence.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_scope.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_status.dart';
import 'package:yala/modules/network_diagnostic/models/diagnostic_test_result.dart';

void main() {
  const engine = DiagnosticRulesEngine();
  final now = DateTime.now();

  DiagnosticTestResult makeTest({
    required String id,
    required String title,
    required DiagnosticScope scope,
    required DiagnosticStatus status,
    DiagnosticConfidence confidence = DiagnosticConfidence.high,
    List<String> facts = const [],
  }) {
    return DiagnosticTestResult(
      id: id,
      title: title,
      scope: scope,
      status: status,
      confidence: confidence,
      explanation: 'Test outcome for $id',
      whyItMatters: 'Importance of $id',
      evidence: DiagnosticEvidence(facts: facts),
      startedAt: now,
    );
  }

  group('DiagnosticRulesEngine — Pattern A: Router Reachable, WAN Down', () {
    test(
      'Identifies WAN down without falsely blaming ISP for general internet failure',
      () {
        final tests = [
          makeTest(
            id: 'router_management_api',
            title: 'Management API',
            scope: DiagnosticScope.managementApi,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'wan_interface_state',
            title: 'WAN Interface',
            scope: DiagnosticScope.routerUplink,
            status: DiagnosticStatus.failureConfirmed,
            facts: ['Interface wan reports up=false.'],
          ),
        ];

        final findings = engine.analyze(
          testResults: tests,
          capabilities: const DiagnosticCapabilities(
            hasManagementApi: true,
            activeWanInterface: 'wan',
            wanProtocol: 'static',
          ),
        );

        expect(findings.any((f) => f.id == 'uplink_interface_down'), isTrue);
        final finding = findings.firstWhere(
          (f) => f.id == 'uplink_interface_down',
        );
        expect(finding.status, equals(DiagnosticStatus.failureConfirmed));
        expect(finding.confidence, equals(DiagnosticConfidence.high));
        expect(finding.recommendedSteps, isNotEmpty);
      },
    );

    test('Specializes diagnosis for PPPoE session failure', () {
      final tests = [
        makeTest(
          id: 'router_management_api',
          title: 'Management API',
          scope: DiagnosticScope.managementApi,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'wan_interface_state',
          title: 'WAN Interface',
          scope: DiagnosticScope.routerUplink,
          status: DiagnosticStatus.failureConfirmed,
          facts: ['PPPoE session disconnected.'],
        ),
      ];

      final findings = engine.analyze(
        testResults: tests,
        capabilities: const DiagnosticCapabilities(
          hasManagementApi: true,
          activeWanInterface: 'pppoe-wan',
          wanProtocol: 'pppoe',
        ),
      );

      expect(findings.any((f) => f.id == 'uplink_pppoe_disconnected'), isTrue);
      final finding = findings.firstWhere(
        (f) => f.id == 'uplink_pppoe_disconnected',
      );
      expect(finding.recommendedSteps.any((s) => s.contains('PPPoE')), isTrue);
    });

    test('Specializes diagnosis for DHCP lease absence', () {
      final tests = [
        makeTest(
          id: 'router_management_api',
          title: 'Management API',
          scope: DiagnosticScope.managementApi,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'wan_interface_state',
          title: 'WAN Interface',
          scope: DiagnosticScope.routerUplink,
          status: DiagnosticStatus.failureConfirmed,
          facts: ['DHCP active but 0 IPv4 addresses.'],
        ),
      ];

      final findings = engine.analyze(
        testResults: tests,
        capabilities: const DiagnosticCapabilities(
          hasManagementApi: true,
          activeWanInterface: 'wan',
          wanProtocol: 'dhcp',
        ),
      );

      expect(findings.any((f) => f.id == 'uplink_dhcp_no_lease'), isTrue);
      final finding = findings.firstWhere(
        (f) => f.id == 'uplink_dhcp_no_lease',
      );
      expect(finding.recommendedSteps.any((s) => s.contains('modem')), isTrue);
    });
  });

  group(
    'DiagnosticRulesEngine — Pattern B: WAN Connected, Upstream Unreachable',
    () {
      test(
        'Deduces upstream ISP outage when WAN is UP but all external targets fail',
        () {
          final tests = [
            makeTest(
              id: 'router_management_api',
              title: 'Management API',
              scope: DiagnosticScope.managementApi,
              status: DiagnosticStatus.healthy,
            ),
            makeTest(
              id: 'wan_interface_state',
              title: 'WAN Interface',
              scope: DiagnosticScope.routerUplink,
              status: DiagnosticStatus.healthy,
            ),
            makeTest(
              id: 'gateway_reachability',
              title: 'Gateway',
              scope: DiagnosticScope.addressing,
              status: DiagnosticStatus.failureConfirmed,
              facts: ['Gateway 100.64.0.1 ping timed out.'],
            ),
            makeTest(
              id: 'dns_resolution',
              title: 'DNS',
              scope: DiagnosticScope.dns,
              status: DiagnosticStatus.failureConfirmed,
            ),
            makeTest(
              id: 'ipv4_external_reachability',
              title: 'IPv4 External',
              scope: DiagnosticScope.ipv4,
              status: DiagnosticStatus.failureConfirmed,
              facts: ['Ping to 1.1.1.1, 8.8.8.8, 9.9.9.9 failed.'],
            ),
          ];

          final findings = engine.analyze(
            testResults: tests,
            capabilities: const DiagnosticCapabilities(
              hasManagementApi: true,
              activeWanInterface: 'wan',
              wanProtocol: 'dhcp',
            ),
          );

          expect(findings.any((f) => f.id == 'upstream_isp_outage'), isTrue);
          final finding = findings.firstWhere(
            (f) => f.id == 'upstream_isp_outage',
          );
          expect(finding.status, equals(DiagnosticStatus.failureConfirmed));
          expect(finding.confidence, equals(DiagnosticConfidence.high));
        },
      );
    },
  );

  group(
    'DiagnosticRulesEngine — Pattern C: DNS Failure with Direct IP Working',
    () {
      test(
        'Pinpoints DNS failure while confirming direct IP reachability is intact',
        () {
          final tests = [
            makeTest(
              id: 'router_management_api',
              title: 'Management API',
              scope: DiagnosticScope.managementApi,
              status: DiagnosticStatus.healthy,
            ),
            makeTest(
              id: 'wan_interface_state',
              title: 'WAN Interface',
              scope: DiagnosticScope.routerUplink,
              status: DiagnosticStatus.healthy,
            ),
            makeTest(
              id: 'dns_resolution',
              title: 'DNS Resolution',
              scope: DiagnosticScope.dns,
              status: DiagnosticStatus.failureConfirmed,
              facts: ['Failed to resolve openwrt.org and google.com'],
            ),
            makeTest(
              id: 'ipv4_external_reachability',
              title: 'IPv4 External Reachability',
              scope: DiagnosticScope.ipv4,
              status: DiagnosticStatus.healthy,
              facts: ['Ping to 1.1.1.1 and 8.8.8.8 succeeded.'],
            ),
          ];

          final findings = engine.analyze(
            testResults: tests,
            capabilities: const DiagnosticCapabilities(hasManagementApi: true),
          );

          expect(
            findings.any(
              (f) => f.id == 'dns_resolution_failure_direct_ip_working',
            ),
            isTrue,
          );
          final finding = findings.firstWhere(
            (f) => f.id == 'dns_resolution_failure_direct_ip_working',
          );
          expect(finding.status, equals(DiagnosticStatus.failureConfirmed));
          expect(finding.primaryScope, equals(DiagnosticScope.dns));
          expect(
            finding.recommendedSteps.any((s) => s.contains('DNS')),
            isTrue,
          );
        },
      );
    },
  );

  group('DiagnosticRulesEngine — Pattern D: IPv4 Succeeds, IPv6 Fails', () {
    test('Distinguishes unconfigured IPv6 from an actual IPv6 outage', () {
      // Case 1: IPv6 NOT configured -> Must NOT be reported as an outage!
      final testsUnconf = [
        makeTest(
          id: 'router_management_api',
          title: 'Management API',
          scope: DiagnosticScope.managementApi,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'ipv4_external_reachability',
          title: 'IPv4 External Reachability',
          scope: DiagnosticScope.ipv4,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'dns_resolution',
          title: 'DNS Resolution',
          scope: DiagnosticScope.dns,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'ipv6_external_reachability',
          title: 'IPv6 External Reachability',
          scope: DiagnosticScope.ipv6,
          status: DiagnosticStatus.notApplicable,
        ),
      ];

      final findingsUnconf = engine.analyze(
        testResults: testsUnconf,
        capabilities: const DiagnosticCapabilities(
          hasManagementApi: true,
          isIpv6Configured: false,
        ),
      );

      expect(
        findingsUnconf.any((f) => f.id == 'ipv6_degraded_ipv4_healthy'),
        isFalse,
      );
      expect(findingsUnconf.any((f) => f.id == 'ipv6_not_configured'), isTrue);
      final (overallStatus, _) = engine.synthesizeOverall(
        testResults: testsUnconf,
        findings: findingsUnconf,
      );
      expect(overallStatus, equals(DiagnosticStatus.healthy));

      // Case 2: IPv6 IS configured, but failing -> Reported as degraded IPv6
      final testsConfFailing = [
        makeTest(
          id: 'router_management_api',
          title: 'Management API',
          scope: DiagnosticScope.managementApi,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'ipv4_external_reachability',
          title: 'IPv4 External Reachability',
          scope: DiagnosticScope.ipv4,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'dns_resolution',
          title: 'DNS Resolution',
          scope: DiagnosticScope.dns,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'ipv6_external_reachability',
          title: 'IPv6 External Reachability',
          scope: DiagnosticScope.ipv6,
          status: DiagnosticStatus.failureConfirmed,
          facts: ['IPv6 ping to 2606:4700:4700::1111 failed.'],
        ),
      ];

      final findingsConfFailing = engine.analyze(
        testResults: testsConfFailing,
        capabilities: const DiagnosticCapabilities(
          hasManagementApi: true,
          isIpv6Configured: true,
        ),
      );

      expect(
        findingsConfFailing.any((f) => f.id == 'ipv6_degraded_ipv4_healthy'),
        isTrue,
      );
      final finding = findingsConfFailing.firstWhere(
        (f) => f.id == 'ipv6_degraded_ipv4_healthy',
      );
      expect(finding.status, equals(DiagnosticStatus.degraded));
    });
  });

  group('DiagnosticRulesEngine — Anti-False-Positive Tests', () {
    test(
      'ICMP blocked by upstream network does NOT declare internet down when DNS works',
      () {
        final tests = [
          makeTest(
            id: 'router_management_api',
            title: 'Management API',
            scope: DiagnosticScope.managementApi,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'wan_interface_state',
            title: 'WAN Interface',
            scope: DiagnosticScope.routerUplink,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'dns_resolution',
            title: 'DNS Resolution',
            scope: DiagnosticScope.dns,
            status: DiagnosticStatus.healthy,
            facts: ['Resolved openwrt.org and google.com successfully.'],
          ),
          makeTest(
            id: 'ipv4_external_reachability',
            title: 'IPv4 Reachability',
            scope: DiagnosticScope.ipv4,
            status:
                DiagnosticStatus.healthy, // Corrected by collector based on DNS
            facts: ['ICMP ping blocked, but DNS verified.'],
          ),
        ];

        final findings = engine.analyze(
          testResults: tests,
          capabilities: const DiagnosticCapabilities(hasManagementApi: true),
        );

        // Must NOT report upstream outage!
        expect(findings.any((f) => f.id == 'upstream_isp_outage'), isFalse);
        expect(
          findings.any((f) => f.id == 'icmp_blocked_dns_operational'),
          isFalse,
        ); // Handled cleanly
        final (status, _) = engine.synthesizeOverall(
          testResults: tests,
          findings: findings,
        );
        expect(status, equals(DiagnosticStatus.healthy));
      },
    );

    test(
      'Gateway ICMP suppression does NOT declare failure when external internet works',
      () {
        final tests = [
          makeTest(
            id: 'router_management_api',
            title: 'Management API',
            scope: DiagnosticScope.managementApi,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'wan_interface_state',
            title: 'WAN Interface',
            scope: DiagnosticScope.routerUplink,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'gateway_reachability',
            title: 'Gateway',
            scope: DiagnosticScope.addressing,
            status: DiagnosticStatus.suspected,
            facts: ['Gateway 192.168.1.1 ping unanswered.'],
          ),
          makeTest(
            id: 'dns_resolution',
            title: 'DNS Resolution',
            scope: DiagnosticScope.dns,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'ipv4_external_reachability',
            title: 'IPv4 Reachability',
            scope: DiagnosticScope.ipv4,
            status: DiagnosticStatus.healthy,
          ),
        ];

        final findings = engine.analyze(
          testResults: tests,
          capabilities: const DiagnosticCapabilities(hasManagementApi: true),
        );

        expect(
          findings.any((f) => f.id == 'gateway_icmp_suppressed_external_ok'),
          isTrue,
        );
        final finding = findings.firstWhere(
          (f) => f.id == 'gateway_icmp_suppressed_external_ok',
        );
        expect(finding.status, equals(DiagnosticStatus.healthy));
        final (overallStatus, _) = engine.synthesizeOverall(
          testResults: tests,
          findings: findings,
        );
        expect(overallStatus, equals(DiagnosticStatus.healthy));
      },
    );

    test('Static WAN interface with no DHCP lease is treated as Healthy', () {
      final tests = [
        makeTest(
          id: 'router_management_api',
          title: 'Management API',
          scope: DiagnosticScope.managementApi,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'wan_interface_state',
          title: 'WAN Interface',
          scope: DiagnosticScope.routerUplink,
          status: DiagnosticStatus.healthy,
          facts: ['Static IP 192.168.10.5 assigned.'],
        ),
        makeTest(
          id: 'default_route_verification',
          title: 'Default Route',
          scope: DiagnosticScope.routing,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'dns_resolution',
          title: 'DNS',
          scope: DiagnosticScope.dns,
          status: DiagnosticStatus.healthy,
        ),
        makeTest(
          id: 'ipv4_external_reachability',
          title: 'IPv4',
          scope: DiagnosticScope.ipv4,
          status: DiagnosticStatus.healthy,
        ),
      ];

      final findings = engine.analyze(
        testResults: tests,
        capabilities: const DiagnosticCapabilities(
          hasManagementApi: true,
          wanProtocol: 'static',
          activeWanInterface: 'wan',
        ),
      );

      // Never looks for or complains about missing DHCP leases on static configurations
      expect(findings.any((f) => f.id == 'uplink_dhcp_no_lease'), isFalse);
      expect(findings.where((f) => f.status.isProblem), isEmpty);
    });
  });

  group('DiagnosticRulesEngine — False-Negative Tests', () {
    test(
      'Router API healthy but WAN down is NOT marked as overall healthy',
      () {
        final tests = [
          makeTest(
            id: 'router_management_api',
            title: 'Management API',
            scope: DiagnosticScope.managementApi,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'wan_interface_state',
            title: 'WAN Interface',
            scope: DiagnosticScope.routerUplink,
            status: DiagnosticStatus.failureConfirmed,
          ),
        ];

        final findings = engine.analyze(
          testResults: tests,
          capabilities: const DiagnosticCapabilities(
            hasManagementApi: true,
            activeWanInterface: 'wan',
          ),
        );

        final (overallStatus, _) = engine.synthesizeOverall(
          testResults: tests,
          findings: findings,
        );
        expect(overallStatus, equals(DiagnosticStatus.failureConfirmed));
      },
    );

    test(
      'Router internet healthy but LAN forwarding blocked is correctly flagged',
      () {
        final tests = [
          makeTest(
            id: 'router_management_api',
            title: 'Management API',
            scope: DiagnosticScope.managementApi,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'dns_resolution',
            title: 'DNS',
            scope: DiagnosticScope.dns,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'ipv4_external_reachability',
            title: 'IPv4',
            scope: DiagnosticScope.ipv4,
            status: DiagnosticStatus.healthy,
          ),
          makeTest(
            id: 'client_forwarding_policy',
            title: 'Client Forwarding',
            scope: DiagnosticScope.clientForwarding,
            status: DiagnosticStatus.failureConfirmed,
            facts: ['Firewall forwarding lan -> wan is REJECT'],
          ),
        ];

        final findings = engine.analyze(
          testResults: tests,
          capabilities: const DiagnosticCapabilities(
            hasManagementApi: true,
            isLanToWanForwardingAllowed: false,
          ),
        );

        expect(
          findings.any((f) => f.id == 'client_forwarding_firewall_blocked'),
          isTrue,
        );
        final finding = findings.firstWhere(
          (f) => f.id == 'client_forwarding_firewall_blocked',
        );
        expect(finding.status, equals(DiagnosticStatus.failureConfirmed));
      },
    );
  });
}
