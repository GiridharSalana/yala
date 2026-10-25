// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/diagnostic_capabilities.dart';
import '../models/diagnostic_confidence.dart';
import '../models/diagnostic_scope.dart';
import '../models/diagnostic_status.dart';
import '../models/diagnostic_test_result.dart';
import '../models/root_cause_finding.dart';

/// Evaluates test results and synthesized evidence against explicit rules
/// to deduce root causes without jumping to unsupported assumptions.
class DiagnosticRulesEngine {
  const DiagnosticRulesEngine();

  List<RootCauseFinding> analyze({
    required List<DiagnosticTestResult> testResults,
    required DiagnosticCapabilities capabilities,
  }) {
    final findings = <RootCauseFinding>[];

    // Map test results by ID for rapid lookup
    final map = {for (final t in testResults) t.id: t};

    final mgmtApi = map['router_management_api'];
    final uplink = map['wan_interface_state'];
    final gateway = map['gateway_reachability'];
    final defaultRoute = map['default_route_verification'];
    final dns = map['dns_resolution'];
    final ipv4Ext = map['ipv4_external_reachability'];
    final ipv6Ext = map['ipv6_external_reachability'];
    final mtu = map['path_mtu_check'];
    final forwarding = map['client_forwarding_policy'];

    // -------------------------------------------------------------------------
    // Rule 1: Router Management API Unreachable
    // -------------------------------------------------------------------------
    if (mgmtApi != null &&
        mgmtApi.status == DiagnosticStatus.failureConfirmed) {
      findings.add(
        const RootCauseFinding(
          id: 'router_api_unreachable',
          title: 'Router Management API Unreachable',
          description:
              'YALA cannot communicate with the router management service. The router may be offline, rebooting, experiencing RPC daemon failure, or on a different network subnet. Router-side internet diagnostics could not run.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: [
            'RPC / Ubus management endpoint did not respond to authenticated connection attempts.',
          ],
          contradictoryEvidence: [],
          recommendedSteps: [
            'Verify your device is connected to the router\'s Wi-Fi network or Ethernet LAN port.',
            'Check that the router IP address and credentials are correct in Manage Routers.',
            'Verify router power and status indicator LEDs.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.managementApi,
        ),
      );
      return findings; // Downstream router tests cannot be evaluated
    }

    // -------------------------------------------------------------------------
    // Rule 2: Active WAN Uplink Down / Disconnected
    // -------------------------------------------------------------------------
    if (uplink != null && uplink.status == DiagnosticStatus.failureConfirmed) {
      final isPppoe = capabilities.wanProtocol == 'pppoe';
      final isDhcp = capabilities.wanProtocol == 'dhcp';

      if (isPppoe) {
        findings.add(
          RootCauseFinding(
            id: 'uplink_pppoe_disconnected',
            title: 'PPPoE Uplink Disconnected',
            description:
                'The active WAN interface (${capabilities.activeWanInterface ?? 'pppoe-wan'}) is configured for PPPoE, but the session is not established. This typically indicates incorrect PPPoE credentials, modem bridge issues, or ISP service authentication downtime.',
            status: DiagnosticStatus.failureConfirmed,
            confidence: DiagnosticConfidence.high,
            supportingEvidence: uplink.evidence.facts,
            contradictoryEvidence: [],
            recommendedSteps: [
              'Verify PPPoE username and password configured on the router.',
              'Ensure your upstream ONT / fiber modem is in bridge mode and synced.',
              'Contact your ISP to verify line status and authentication health.',
            ],
            actionType: FindingActionType.userIntervention,
            primaryScope: DiagnosticScope.routerUplink,
          ),
        );
      } else if (isDhcp) {
        findings.add(
          RootCauseFinding(
            id: 'uplink_dhcp_no_lease',
            title: 'No WAN DHCP Lease Acquired',
            description:
                'The active WAN interface (${capabilities.activeWanInterface ?? 'wan'}) is set to DHCP, but no IP address was provided by the upstream modem or ISP gateway. The physical link may be down or the upstream DHCP server is unresponsive.',
            status: DiagnosticStatus.failureConfirmed,
            confidence: DiagnosticConfidence.high,
            supportingEvidence: uplink.evidence.facts,
            contradictoryEvidence: [],
            recommendedSteps: [
              'Check the Ethernet cable between the router\'s WAN port and the upstream modem/ONT.',
              'Power-cycle the upstream ISP modem or ONT and wait 2 minutes for DHCP renewal.',
              'Verify if MAC cloning or specific VLAN tagging is required by your ISP.',
            ],
            actionType: FindingActionType.userIntervention,
            primaryScope: DiagnosticScope.routerUplink,
          ),
        );
      } else {
        findings.add(
          RootCauseFinding(
            id: 'uplink_interface_down',
            title: 'WAN Uplink Interface Down',
            description:
                'The router\'s primary WAN uplink interface (${capabilities.activeWanInterface ?? 'wan'}) reports down or disconnected. No alternate active uplink was detected.',
            status: DiagnosticStatus.failureConfirmed,
            confidence: DiagnosticConfidence.high,
            supportingEvidence: uplink.evidence.facts,
            contradictoryEvidence: [],
            recommendedSteps: [
              'Check the physical network cable connected to the WAN port.',
              'Verify that the upstream modem, fiber ONT, or gateway is powered on.',
              'Review interface configuration under Interfaces.',
            ],
            actionType: FindingActionType.userIntervention,
            primaryScope: DiagnosticScope.routerUplink,
          ),
        );
      }
    }

    // -------------------------------------------------------------------------
    // Rule 3: Missing Default Route
    // -------------------------------------------------------------------------
    if (defaultRoute != null &&
        defaultRoute.status == DiagnosticStatus.failureConfirmed) {
      findings.add(
        RootCauseFinding(
          id: 'missing_default_route',
          title: 'Missing Default Kernel Route',
          description:
              'No active default gateway route (0.0.0.0/0) was discovered in the router\'s kernel routing table. The router cannot determine where to forward outbound internet packets.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: defaultRoute.evidence.facts,
          contradictoryEvidence: [],
          recommendedSteps: [
            'Inspect network configuration to ensure a valid gateway is assigned to the WAN interface.',
            'If using multiple WANs or policy routing, verify routing table metrics and rules.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.routing,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Rule 4: DNS Resolution Failure with Direct IP Connectivity Intact
    // -------------------------------------------------------------------------
    final isIpv4Online =
        ipv4Ext != null && ipv4Ext.status == DiagnosticStatus.healthy;
    final isDnsFailing =
        dns != null &&
        (dns.status == DiagnosticStatus.failureConfirmed ||
            dns.status == DiagnosticStatus.degraded);

    if (isIpv4Online && isDnsFailing) {
      findings.add(
        RootCauseFinding(
          id: 'dns_resolution_failure_direct_ip_working',
          title: 'DNS Resolution Failure (Direct Internet IP is Working)',
          description:
              'The router can reach external internet IP addresses directly (e.g. 1.1.1.1, 8.8.8.8), but domain name resolution is failing or degraded. Websites will fail to load by name, but numerical IP connections succeed.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: [
            ...dns.evidence.facts,
            'Direct ICMP echo to external public IPs succeeded.',
          ],
          contradictoryEvidence: [],
          recommendedSteps: [
            'Check configured DNS upstream resolvers in DHCP & DNS settings.',
            'If using custom upstream DNS servers, verify they are reachable and not blocked.',
            'If using AdGuard Home, NextDNS, or domain blocking filters, ensure the local resolver service is active.',
            'Flush local DNS cache and test resolution again.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.dns,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Rule 5: Upstream ICMP Dropped but DNS / Internet Works (Anti-False-Positive)
    // -------------------------------------------------------------------------
    final isIpv4IcmpDown =
        ipv4Ext != null &&
        (ipv4Ext.status == DiagnosticStatus.degraded ||
            ipv4Ext.status == DiagnosticStatus.failureConfirmed);
    final isDnsWorking = dns != null && dns.status == DiagnosticStatus.healthy;

    if (isIpv4IcmpDown && isDnsWorking) {
      findings.add(
        RootCauseFinding(
          id: 'icmp_blocked_dns_operational',
          title: 'Internet Operational (ICMP Ping Blocked by Upstream Network)',
          description:
              'DNS resolution is functioning cleanly, but direct ICMP ping probes were unanswered. Many ISPs and corporate uplinks intentionally drop ICMP echo requests for security or policy reasons. Your internet connection is operational.',
          status: DiagnosticStatus.healthy,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: [
            ...dns.evidence.facts,
            'DNS queries resolved external domains successfully.',
          ],
          contradictoryEvidence: [...ipv4Ext.evidence.facts],
          recommendedSteps: [
            'No action required. ICMP suppression by ISPs is common practice and does not impair standard web or app traffic.',
          ],
          actionType: FindingActionType.informational,
          primaryScope: DiagnosticScope.ipv4,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Rule 6: Gateway ICMP Unresponsive but External Internet Reached
    // -------------------------------------------------------------------------
    final isGatewayUnreachable =
        gateway != null &&
        (gateway.status == DiagnosticStatus.degraded ||
            gateway.status == DiagnosticStatus.failureConfirmed ||
            gateway.status == DiagnosticStatus.suspected);

    if (isGatewayUnreachable && (isIpv4Online || isDnsWorking)) {
      findings.add(
        RootCauseFinding(
          id: 'gateway_icmp_suppressed_external_ok',
          title: 'Gateway Ping Unresponsive (External Internet Working)',
          description:
              'The upstream ISP gateway did not respond to ICMP ping, but the router successfully reached external destinations. The ISP gateway firmware is configured to silently discard ICMP packets.',
          status: DiagnosticStatus.healthy,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: [
            'External internet destinations responded normally.',
          ],
          contradictoryEvidence: [...gateway.evidence.facts],
          recommendedSteps: [
            'No action required. This is normal behavior for many fiber and cable broadband providers.',
          ],
          actionType: FindingActionType.informational,
          primaryScope: DiagnosticScope.addressing,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Rule 7: Total External Reachability Failure (ISP / Upstream Outage)
    // -------------------------------------------------------------------------
    final isGatewayDown =
        gateway != null && gateway.status == DiagnosticStatus.failureConfirmed;
    final isAllExternalDown =
        ipv4Ext != null &&
        ipv4Ext.status == DiagnosticStatus.failureConfirmed &&
        !isDnsWorking;

    if (uplink != null &&
        uplink.status == DiagnosticStatus.healthy &&
        isAllExternalDown) {
      final confidence = isGatewayDown
          ? DiagnosticConfidence.high
          : DiagnosticConfidence.moderate;

      findings.add(
        RootCauseFinding(
          id: 'upstream_isp_outage',
          title: 'Upstream Internet Outage / Unreachable',
          description:
              'The router\'s WAN interface is connected with an assigned IP address, but no external destinations (Cloudflare, Google, Quad9, root DNS) could be reached. This points toward an ISP upstream gateway failure, routing blackout, or disconnected optical link.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: confidence,
          supportingEvidence: [
            'WAN interface reports link UP with valid addressing.',
            if (gateway != null) ...gateway.evidence.facts,
            ...ipv4Ext.evidence.facts,
          ],
          contradictoryEvidence: [],
          recommendedSteps: [
            'Restart your optical fiber terminal (ONT) or cable modem.',
            'Check for ISP service outages in your area.',
            'Verify account billing or authentication status with your service provider.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.ipv4,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Rule 8: IPv4 Healthy but Configured IPv6 Connectivity Failing
    // -------------------------------------------------------------------------
    if (capabilities.isIpv6Configured &&
        ipv6Ext != null &&
        (ipv6Ext.status == DiagnosticStatus.failureConfirmed ||
            ipv6Ext.status == DiagnosticStatus.degraded) &&
        isIpv4Online) {
      findings.add(
        RootCauseFinding(
          id: 'ipv6_degraded_ipv4_healthy',
          title: 'IPv6 Connectivity Impaired (IPv4 Functional)',
          description:
              'IPv4 internet access is operational, but IPv6 connectivity is failing or unverified. Dual-stack clients may experience delays while waiting for IPv6 connection attempts to time out before falling back to IPv4 (Happy Eyeballs).',
          status: DiagnosticStatus.degraded,
          confidence: DiagnosticConfidence.moderate,
          supportingEvidence: [
            'IPv4 reachability passed all checks.',
            ...ipv6Ext.evidence.facts,
          ],
          contradictoryEvidence: [],
          recommendedSteps: [
            'Inspect IPv6 prefix delegation and router advertisements (odhcpd) under Interfaces.',
            'Verify whether your ISP supports native IPv6 (DHCPv6-PD) or requires 6in4/6to4 tunneling.',
            'If IPv6 is not provided by your ISP, consider disabling IPv6 on the WAN interface to prevent client latency.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.ipv6,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Rule 9: IPv6 Not Configured (Explicitly Distinguish from Outage)
    // -------------------------------------------------------------------------
    if (!capabilities.isIpv6Configured &&
        (ipv6Ext == null ||
            ipv6Ext.status == DiagnosticStatus.notApplicable ||
            ipv6Ext.status == DiagnosticStatus.healthy)) {
      // Not an issue - informational note only if IPv4 is healthy
      if (isIpv4Online) {
        findings.add(
          const RootCauseFinding(
            id: 'ipv6_not_configured',
            title: 'IPv4-Only Network (IPv6 Not Configured)',
            description:
                'The router is operating in IPv4-only mode. No global IPv6 prefix or gateway is assigned. This is normal for networks that do not utilize IPv6.',
            status: DiagnosticStatus.healthy,
            confidence: DiagnosticConfidence.high,
            supportingEvidence: [
              'No global unicast IPv6 address found on active interfaces.',
            ],
            contradictoryEvidence: [],
            recommendedSteps: [],
            actionType: FindingActionType.informational,
            primaryScope: DiagnosticScope.ipv6,
          ),
        );
      }
    }

    // -------------------------------------------------------------------------
    // Rule 10: Router Internet Working, Client Forwarding / NAT Impairment
    // -------------------------------------------------------------------------
    if (isIpv4Online &&
        forwarding != null &&
        forwarding.status == DiagnosticStatus.failureConfirmed) {
      findings.add(
        RootCauseFinding(
          id: 'client_forwarding_firewall_blocked',
          title: 'Router Has Internet, but LAN Client Forwarding is Blocked',
          description:
              'The router itself can reach the internet, but firewall forwarding rules or NAT (masquerading) prevent devices on the local LAN network from reaching the WAN uplink.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: forwarding.evidence.facts,
          contradictoryEvidence: [],
          recommendedSteps: [
            'Open Firewall & Security settings and ensure forwarding from the "lan" zone to the "wan" zone is set to ACCEPT.',
            'Ensure "Masquerading" (NAT) is enabled on the WAN firewall zone.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.clientForwarding,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Rule 11: Router Has Internet, Client-Side Connectivity Unverified
    // -------------------------------------------------------------------------
    if (isIpv4Online &&
        (forwarding == null || forwarding.status == DiagnosticStatus.healthy) &&
        findings.where((f) => f.status.isProblem).isEmpty) {
      findings.add(
        const RootCauseFinding(
          id: 'router_healthy_client_unverified',
          title: 'Router Internet Reachability Verified',
          description:
              'The router successfully resolved external DNS and communicated with independent internet endpoints. If a specific device cannot access the internet, the issue is likely client-specific (e.g. Wi-Fi signal, static IP misconfiguration, or device firewall).',
          status: DiagnosticStatus.healthy,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: [
            'All router-originated connectivity probes passed.',
            'LAN-to-WAN forwarding policy verified in firewall configuration.',
          ],
          contradictoryEvidence: [],
          recommendedSteps: [
            'If a specific smartphone or computer has issues, verify its IP address, gateway, and DNS settings under Clients.',
            'Verify device Wi-Fi connection strength and DHCP lease status.',
          ],
          actionType: FindingActionType.informational,
          primaryScope: DiagnosticScope.clientForwarding,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Rule 12: MTU Path Restriction Detected
    // -------------------------------------------------------------------------
    if (mtu != null && mtu.status == DiagnosticStatus.degraded) {
      findings.add(
        RootCauseFinding(
          id: 'path_mtu_fragmentation_issue',
          title: 'Path MTU Fragmentation / Clamping Issue Detected',
          description:
              'Large packets encountering fragmentation issues along the upstream path. This can cause slow page loads, SSL/TLS handshake timeouts, or VPN stalls.',
          status: DiagnosticStatus.degraded,
          confidence: DiagnosticConfidence.moderate,
          supportingEvidence: mtu.evidence.facts,
          contradictoryEvidence: [],
          recommendedSteps: [
            'Enable MSS clamping in Firewall settings (iptables/nftables mssfix).',
            'If using PPPoE, ensure interface MTU is set to 1492 or clamped appropriately.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.pathMtu,
        ),
      );
    }

    return findings;
  }

  /// Synthesizes an overall system status and human-readable summary.
  (DiagnosticStatus, String) synthesizeOverall({
    required List<DiagnosticTestResult> testResults,
    required List<RootCauseFinding> findings,
  }) {
    // If no tests ran
    if (testResults.isEmpty) {
      return (
        DiagnosticStatus.notTested,
        'Diagnostics have not yet been executed. Tap "Run Diagnostics" to begin.',
      );
    }

    // If management API failed
    final mgmtApi = testResults.firstWhere(
      (t) => t.id == 'router_management_api',
      orElse: () => DiagnosticTestResult(
        id: '',
        title: '',
        scope: DiagnosticScope.managementApi,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.low,
        explanation: '',
        whyItMatters: '',
        startedAt: DateTime.now(),
      ),
    );
    if (mgmtApi.status == DiagnosticStatus.failureConfirmed) {
      return (
        DiagnosticStatus.failureConfirmed,
        'Cannot communicate with router management API. Router status could not be verified.',
      );
    }

    // Check for confirmed critical failures in findings
    final criticalProblems = findings.where(
      (f) => f.status == DiagnosticStatus.failureConfirmed,
    );
    if (criticalProblems.isNotEmpty) {
      final top = criticalProblems.first;
      return (DiagnosticStatus.failureConfirmed, top.title);
    }

    // Check for degraded issues
    final degradedProblems = findings.where(
      (f) =>
          f.status == DiagnosticStatus.degraded ||
          f.status == DiagnosticStatus.suspected,
    );
    if (degradedProblems.isNotEmpty) {
      final top = degradedProblems.first;
      return (top.status, top.title);
    }

    // Check if external IPv4 and DNS tests passed
    final ipv4 = testResults.firstWhere(
      (t) => t.id == 'ipv4_external_reachability',
      orElse: () => DiagnosticTestResult(
        id: '',
        title: '',
        scope: DiagnosticScope.ipv4,
        status: DiagnosticStatus.inconclusive,
        confidence: DiagnosticConfidence.low,
        explanation: '',
        whyItMatters: '',
        startedAt: DateTime.now(),
      ),
    );
    final dns = testResults.firstWhere(
      (t) => t.id == 'dns_resolution',
      orElse: () => DiagnosticTestResult(
        id: '',
        title: '',
        scope: DiagnosticScope.dns,
        status: DiagnosticStatus.inconclusive,
        confidence: DiagnosticConfidence.low,
        explanation: '',
        whyItMatters: '',
        startedAt: DateTime.now(),
      ),
    );

    if (ipv4.status == DiagnosticStatus.healthy &&
        dns.status == DiagnosticStatus.healthy) {
      return (
        DiagnosticStatus.healthy,
        'Internet connection is operational. Router reachability and DNS resolution verified.',
      );
    }

    // Fallback based on test results
    if (testResults.any((t) => t.status == DiagnosticStatus.failureConfirmed)) {
      return (
        DiagnosticStatus.failureConfirmed,
        'One or more diagnostic checks confirmed connectivity failures.',
      );
    }
    if (testResults.any((t) => t.status == DiagnosticStatus.degraded)) {
      return (
        DiagnosticStatus.degraded,
        'Network connectivity is partially available with degraded performance or protocol errors.',
      );
    }

    return (
      DiagnosticStatus.inconclusive,
      'Diagnostic observations were inconclusive. Check individual test details below.',
    );
  }
}
