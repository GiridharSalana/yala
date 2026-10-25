// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/firewall_security/models/firewall_info.dart';
import 'package:yala/modules/firewall_security/utils/firewall_validator.dart';

void main() {
  group('FirewallValidator Protocol Overlap Tests', () {
    test('Identical and wildcard protocols overlap', () {
      expect(FirewallValidator.protocolsOverlap('tcp', 'tcp'), isTrue);
      expect(FirewallValidator.protocolsOverlap('udp', 'udp'), isTrue);
      expect(FirewallValidator.protocolsOverlap('any', 'tcp'), isTrue);
      expect(FirewallValidator.protocolsOverlap(null, 'tcp'), isTrue);
      expect(FirewallValidator.protocolsOverlap('', 'udp'), isTrue);
      expect(FirewallValidator.protocolsOverlap('all', 'icmp'), isTrue);
    });

    test(
      'TCP/UDP compound protocol overlaps with TCP and UDP but not ICMP',
      () {
        expect(FirewallValidator.protocolsOverlap('tcp udp', 'tcp'), isTrue);
        expect(FirewallValidator.protocolsOverlap('tcpudp', 'udp'), isTrue);
        expect(FirewallValidator.protocolsOverlap('tcp+udp', 'tcp'), isTrue);
        expect(FirewallValidator.protocolsOverlap('tcp udp', 'icmp'), isFalse);
      },
    );

    test('Disjoint protocols do not overlap', () {
      expect(FirewallValidator.protocolsOverlap('tcp', 'udp'), isFalse);
      expect(FirewallValidator.protocolsOverlap('icmp', 'tcp'), isFalse);
    });
  });

  group('FirewallValidator Port Overlap Tests', () {
    test('Wildcard and empty ports overlap with any port', () {
      expect(FirewallValidator.portsOverlap(null, '80'), isTrue);
      expect(FirewallValidator.portsOverlap('', '443'), isTrue);
      expect(FirewallValidator.portsOverlap('*', '22'), isTrue);
      expect(FirewallValidator.portsOverlap('any', '8080'), isTrue);
    });

    test('Exact port matches and disjoint ports', () {
      expect(FirewallValidator.portsOverlap('80', '80'), isTrue);
      expect(FirewallValidator.portsOverlap('80', '81'), isFalse);
      expect(FirewallValidator.portsOverlap('443', '8443'), isFalse);
    });

    test('Port range overlaps', () {
      expect(FirewallValidator.portsOverlap('80-90', '85'), isTrue);
      expect(FirewallValidator.portsOverlap('80:90', '90'), isTrue);
      expect(FirewallValidator.portsOverlap('80-90', '91'), isFalse);
      expect(FirewallValidator.portsOverlap('80-100', '90-110'), isTrue);
      expect(FirewallValidator.portsOverlap('80-90', '91-100'), isFalse);
    });

    test('Comma-separated port lists', () {
      expect(FirewallValidator.portsOverlap('80,443', '443'), isTrue);
      expect(FirewallValidator.portsOverlap('80, 443', '80'), isTrue);
      expect(FirewallValidator.portsOverlap('80, 443', '8080'), isFalse);
      expect(FirewallValidator.portsOverlap('80, 8000-8010', '8005'), isTrue);
    });
  });

  group('FirewallValidator CIDR & IP Overlap Tests', () {
    test('Wildcards and all-zero subnets overlap with everything', () {
      expect(FirewallValidator.cidrsOverlap(null, '192.168.1.1'), isTrue);
      expect(FirewallValidator.cidrsOverlap('*', '10.0.0.1'), isTrue);
      expect(
        FirewallValidator.cidrsOverlap('0.0.0.0/0', '192.168.1.100'),
        isTrue,
      );
      expect(FirewallValidator.cidrsOverlap('::/0', '2001:db8::1'), isTrue);
    });

    test('IPv4 exact match and subnet containment', () {
      expect(
        FirewallValidator.cidrsOverlap('192.168.1.10', '192.168.1.10'),
        isTrue,
      );
      expect(
        FirewallValidator.cidrsOverlap('192.168.1.0/24', '192.168.1.50'),
        isTrue,
      );
      expect(
        FirewallValidator.cidrsOverlap('192.168.1.0/24', '192.168.1.0/28'),
        isTrue,
      );
      expect(
        FirewallValidator.cidrsOverlap('192.168.1.0/24', '192.168.2.0/24'),
        isFalse,
      );
      expect(
        FirewallValidator.cidrsOverlap('10.0.0.0/8', '192.168.1.1'),
        isFalse,
      );
    });

    test('IPv6 exact match and subnet containment', () {
      expect(
        FirewallValidator.cidrsOverlap('2001:db8::1', '2001:db8::1'),
        isTrue,
      );
      expect(
        FirewallValidator.cidrsOverlap('2001:db8::/32', '2001:db8:1::1'),
        isTrue,
      );
      expect(
        FirewallValidator.cidrsOverlap('2001:db8::/32', '2001:db9::/32'),
        isFalse,
      );
    });

    test('Cross-family IPv4 and IPv6 do not overlap', () {
      expect(
        FirewallValidator.cidrsOverlap('192.168.1.1', '2001:db8::1'),
        isFalse,
      );
      expect(
        FirewallValidator.cidrsOverlap('192.168.1.0/24', 'fe80::1'),
        isFalse,
      );
    });
  });

  group('FirewallValidator Port Forward Conflict & Safety Tests', () {
    const existingFwd = FirewallPortForwarding(
      sectionKey: 'cfg100',
      name: 'Web-Fwd',
      srcZone: 'wan',
      srcPort: '8080',
      destZone: 'lan',
      destIp: '192.168.1.50',
      destPort: '80',
      proto: 'tcp',
      enabled: true,
    );

    test('Exact 4-tuple conflict is detected', () {
      const candidate = FirewallPortForwarding(
        sectionKey: 'cfg200',
        name: 'Another-Web',
        srcZone: 'wan',
        srcPort: '8080',
        destZone: 'lan',
        destIp: '192.168.1.60',
        destPort: '80',
        proto: 'tcp',
        enabled: true,
      );

      final conflict = FirewallValidator.checkPortForwardConflict(candidate, [
        existingFwd,
      ]);
      expect(conflict.hasConflict, isTrue);
      expect(conflict.conflictingSectionKey, equals('cfg100'));
      expect(conflict.reason, contains('8080'));
    });

    test('Different port or different protocol does not conflict', () {
      const diffPort = FirewallPortForwarding(
        sectionKey: 'cfg201',
        name: 'Diff-Port',
        srcZone: 'wan',
        srcPort: '8081',
        destZone: 'lan',
        destIp: '192.168.1.50',
        destPort: '80',
        proto: 'tcp',
      );
      final r1 = FirewallValidator.checkPortForwardConflict(diffPort, [
        existingFwd,
      ]);
      expect(r1.hasConflict, isFalse);

      const diffProto = FirewallPortForwarding(
        sectionKey: 'cfg202',
        name: 'Diff-Proto',
        srcZone: 'wan',
        srcPort: '8080',
        destZone: 'lan',
        destIp: '192.168.1.50',
        destPort: '80',
        proto: 'udp',
      );
      final r2 = FirewallValidator.checkPortForwardConflict(diffProto, [
        existingFwd,
      ]);
      expect(r2.hasConflict, isFalse);
    });

    test('Self-update ignores matching sectionKey', () {
      const updateSelf = FirewallPortForwarding(
        sectionKey: 'cfg100',
        name: 'Web-Fwd-Renamed',
        srcZone: 'wan',
        srcPort: '8080',
        destZone: 'lan',
        destIp: '192.168.1.50',
        destPort: '80',
        proto: 'tcp',
      );
      final res = FirewallValidator.checkPortForwardConflict(updateSelf, [
        existingFwd,
      ]);
      expect(res.hasConflict, isFalse);
    });

    test('Management port safety flags router admin ports 80, 443, 22', () {
      const adminFwd = FirewallPortForwarding(
        sectionKey: 'cfg300',
        name: 'Router-Admin-Direct',
        srcZone: 'wan',
        srcPort: '443',
        destZone: 'lan',
        destIp: '192.168.1.1',
        destPort: '443',
        proto: 'tcp',
      );
      final warning = FirewallValidator.checkManagementPortSafety(
        adminFwd,
        routerLanIp: '192.168.1.1',
      );
      expect(warning.isUnsafe, isTrue);
      expect(warning.port, equals(443));
      expect(warning.reason, contains('443'));

      const safeFwd = FirewallPortForwarding(
        sectionKey: 'cfg301',
        name: 'Safe-Game-Server',
        srcZone: 'wan',
        srcPort: '25565',
        destZone: 'lan',
        destIp: '192.168.1.150',
        destPort: '25565',
        proto: 'tcp',
      );
      final safeRes = FirewallValidator.checkManagementPortSafety(
        safeFwd,
        routerLanIp: '192.168.1.1',
      );
      expect(safeRes.isUnsafe, isFalse);
    });
  });

  group('FirewallValidator IP Family Conflict Dimensions', () {
    test(
      'familiesOverlap handles explicit, wildcard, and disjoint families correctly',
      () {
        expect(FirewallValidator.familiesOverlap('ipv4', 'ipv4'), isTrue);
        expect(FirewallValidator.familiesOverlap('ipv6', 'ipv6'), isTrue);
        expect(FirewallValidator.familiesOverlap('ipv4', 'ipv6'), isFalse);
        expect(FirewallValidator.familiesOverlap('ipv6', 'ipv4'), isFalse);
        expect(FirewallValidator.familiesOverlap('any', 'ipv4'), isTrue);
        expect(FirewallValidator.familiesOverlap('any', 'ipv6'), isTrue);
        expect(FirewallValidator.familiesOverlap('any', 'any'), isTrue);
        expect(FirewallValidator.familiesOverlap(null, 'ipv4'), isTrue);
        expect(FirewallValidator.familiesOverlap('ipv6', null), isTrue);
      },
    );

    test(
      'IPv4 + IPv4 port forwards conflict on same external port with wildcard srcIp',
      () {
        const existingIpv4 = FirewallPortForwarding(
          sectionKey: 'fwd_v4_1',
          name: 'IPv4-Web',
          srcZone: 'wan',
          srcPort: '443',
          destZone: 'lan',
          destIp: '192.168.1.100',
          destPort: '443',
          proto: 'tcp',
          family: 'ipv4',
          srcIp: null, // wildcard
        );
        const candidateIpv4 = FirewallPortForwarding(
          sectionKey: 'fwd_v4_2',
          name: 'Another-IPv4-Web',
          srcZone: 'wan',
          srcPort: '443',
          destZone: 'lan',
          destIp: '192.168.1.101',
          destPort: '443',
          proto: 'tcp',
          family: 'ipv4',
          srcIp: null, // wildcard
        );

        final result = FirewallValidator.checkPortForwardConflict(
          candidateIpv4,
          [existingIpv4],
        );
        expect(result.hasConflict, isTrue);
        expect(result.conflictingSectionKey, equals('fwd_v4_1'));
      },
    );

    test(
      'IPv6 + IPv6 port forwards conflict on same external port with wildcard srcIp',
      () {
        const existingIpv6 = FirewallPortForwarding(
          sectionKey: 'fwd_v6_1',
          name: 'IPv6-Web',
          srcZone: 'wan',
          srcPort: '443',
          destZone: 'lan',
          destIp: 'fd00::100',
          destPort: '443',
          proto: 'tcp',
          family: 'ipv6',
          srcIp: null, // wildcard
        );
        const candidateIpv6 = FirewallPortForwarding(
          sectionKey: 'fwd_v6_2',
          name: 'Another-IPv6-Web',
          srcZone: 'wan',
          srcPort: '443',
          destZone: 'lan',
          destIp: 'fd00::101',
          destPort: '443',
          proto: 'tcp',
          family: 'ipv6',
          srcIp: null, // wildcard
        );

        final result = FirewallValidator.checkPortForwardConflict(
          candidateIpv6,
          [existingIpv6],
        );
        expect(result.hasConflict, isTrue);
        expect(result.conflictingSectionKey, equals('fwd_v6_1'));
      },
    );

    test(
      'IPv4 + IPv6 port forwards do NOT conflict even on same external port and wildcard srcIp',
      () {
        const existingIpv4 = FirewallPortForwarding(
          sectionKey: 'fwd_v4',
          name: 'IPv4-Web-Coexist',
          srcZone: 'wan',
          srcPort: '443',
          destZone: 'lan',
          destIp: '192.168.1.100',
          destPort: '443',
          proto: 'tcp',
          family: 'ipv4',
          srcIp: null, // wildcard
        );
        const candidateIpv6 = FirewallPortForwarding(
          sectionKey: 'fwd_v6',
          name: 'IPv6-Web-Coexist',
          srcZone: 'wan',
          srcPort: '443',
          destZone: 'lan',
          destIp: 'fd00::100',
          destPort: '443',
          proto: 'tcp',
          family: 'ipv6',
          srcIp: null, // wildcard
        );

        // IPv6 candidate against existing IPv4 rule
        final r1 = FirewallValidator.checkPortForwardConflict(candidateIpv6, [
          existingIpv4,
        ]);
        expect(r1.hasConflict, isFalse);

        // IPv4 candidate against existing IPv6 rule
        final r2 = FirewallValidator.checkPortForwardConflict(existingIpv4, [
          candidateIpv6,
        ]);
        expect(r2.hasConflict, isFalse);
      },
    );

    test('Disjoint explicit source IPs across families do not conflict', () {
      const existingIpv4 = FirewallPortForwarding(
        sectionKey: 'fwd_v4_explicit',
        name: 'IPv4-Specific',
        srcZone: 'wan',
        srcPort: '80',
        destZone: 'lan',
        destIp: '192.168.1.10',
        destPort: '80',
        proto: 'tcp',
        family: 'any',
        srcIp: '198.51.100.1',
      );
      const candidateIpv6 = FirewallPortForwarding(
        sectionKey: 'fwd_v6_explicit',
        name: 'IPv6-Specific',
        srcZone: 'wan',
        srcPort: '80',
        destZone: 'lan',
        destIp: 'fd00::10',
        destPort: '80',
        proto: 'tcp',
        family: 'any',
        srcIp: '2001:db8::1',
      );

      final res = FirewallValidator.checkPortForwardConflict(candidateIpv6, [
        existingIpv4,
      ]);
      expect(res.hasConflict, isFalse);
    });
  });

  group('FirewallValidator Destination Zone Conflict Dimensions', () {
    const baseRule = FirewallPortForwarding(
      sectionKey: 'cfg_base',
      name: 'Base-Forward',
      srcZone: 'wan',
      srcPort: '5000',
      destZone: 'lan',
      destIp: '192.168.1.50',
      destPort: '5000',
      proto: 'tcp',
      family: 'ipv4',
    );

    test(
      'Same source zone, protocol, port, source CIDR, family, same destination zone -> conflict',
      () {
        const sameDestCandidate = FirewallPortForwarding(
          sectionKey: 'cfg_same_dest',
          name: 'Same-Dest-Forward',
          srcZone: 'wan',
          srcPort: '5000',
          destZone: 'lan',
          destIp: '192.168.1.51',
          destPort: '5000',
          proto: 'tcp',
          family: 'ipv4',
        );

        final res = FirewallValidator.checkPortForwardConflict(
          sameDestCandidate,
          [baseRule],
        );
        expect(res.hasConflict, isTrue);
        expect(res.conflictingSectionKey, equals('cfg_base'));
      },
    );

    test(
      'Same source zone, protocol, port, source CIDR, family, different destination zone -> no conflict',
      () {
        const diffDestCandidate = FirewallPortForwarding(
          sectionKey: 'cfg_diff_dest',
          name: 'DMZ-Forward',
          srcZone: 'wan',
          srcPort: '5000',
          destZone: 'dmz',
          destIp: '192.168.2.50',
          destPort: '5000',
          proto: 'tcp',
          family: 'ipv4',
        );

        final res = FirewallValidator.checkPortForwardConflict(
          diffDestCandidate,
          [baseRule],
        );
        expect(res.hasConflict, isFalse);
      },
    );
  });
}
