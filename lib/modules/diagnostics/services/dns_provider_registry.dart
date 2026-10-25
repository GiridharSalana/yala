// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/dns_benchmark_models.dart';

/// Central typed registry of verified DNS providers for latency benchmarking.
class DnsProviderRegistry {
  const DnsProviderRegistry._();

  static const DnsProviderMetadata adguard = DnsProviderMetadata(
    id: 'adguard',
    name: 'AdGuard DNS',
    primaryServer: '94.140.14.14',
    secondaryServer: '94.140.15.15',
    ipv6Server: '2a10:50c0::ad1:ff',
    dohUrl: 'https://dns.adguard-dns.com/dns-query',
    description:
        'Default public Anycast resolver with ad, tracker, and malware blocking.',
    features: [
      'Ad blocking',
      'Tracker protection',
      'Phishing protection',
      'DNSSEC',
    ],
  );

  static const DnsProviderMetadata cleanBrowsing = DnsProviderMetadata(
    id: 'cleanbrowsing',
    name: 'CleanBrowsing',
    primaryServer: '185.228.168.9',
    secondaryServer: '185.228.169.9',
    ipv6Server: '2a0d:2a00:1::2',
    dohUrl: 'https://doh.cleanbrowsing.org/doh/security-filter/',
    description:
        'Security filter blocking malicious domains, phishing, and malware.',
    features: ['Malware blocking', 'Phishing protection', 'DNSSEC'],
  );

  static const DnsProviderMetadata cloudflare = DnsProviderMetadata(
    id: 'cloudflare',
    name: 'Cloudflare',
    primaryServer: '1.1.1.1',
    secondaryServer: '1.0.0.1',
    ipv6Server: '2606:4700:4700::1111',
    dohUrl: 'https://cloudflare-dns.com/dns-query',
    description:
        'High-performance, privacy-focused Anycast recursive resolver.',
    features: ['Fast Anycast', 'Zero logging', 'DNSSEC'],
  );

  static const DnsProviderMetadata controlD = DnsProviderMetadata(
    id: 'controld',
    name: 'Control D',
    primaryServer: '76.76.2.0',
    secondaryServer: '76.76.10.0',
    ipv6Server: '2606:1a40::',
    dohUrl: 'https://freedns.controld.com/p0',
    description:
        'Default public Anycast resolver; custom filtering requires profile ID.',
    features: ['Free tier Anycast', 'DNSSEC', 'Optional profile filtering'],
  );

  static const DnsProviderMetadata google = DnsProviderMetadata(
    id: 'google',
    name: 'Google Public DNS',
    primaryServer: '8.8.8.8',
    secondaryServer: '8.8.4.4',
    ipv6Server: '2001:4860:4860::8888',
    dohUrl: 'https://dns.google/dns-query',
    description: 'Global Anycast DNS resolver operated by Google.',
    features: ['Global Anycast', 'High capacity', 'DNSSEC', 'ECS support'],
  );

  static const DnsProviderMetadata nextDns = DnsProviderMetadata(
    id: 'nextdns',
    name: 'NextDNS',
    primaryServer: '45.90.28.0',
    secondaryServer: '45.90.30.0',
    ipv6Server: '2a07:a8c0::',
    dohUrl: 'https://dns.nextdns.io',
    description:
        'Default public Anycast resolver; custom filtering rules require account profile.',
    features: [
      'Anycast infrastructure',
      'DNSSEC',
      'Customizable filtering (with ID)',
    ],
  );

  static const DnsProviderMetadata openDns = DnsProviderMetadata(
    id: 'opendns',
    name: 'OpenDNS',
    primaryServer: '208.67.222.222',
    secondaryServer: '208.67.220.220',
    ipv6Server: '2620:119:35::35',
    dohUrl: 'https://doh.opendns.com/dns-query',
    description:
        'Cisco-operated Anycast DNS with phishing and malicious domain protection.',
    features: ['Cisco Talos intelligence', 'Phishing protection', 'DNSSEC'],
  );

  static const DnsProviderMetadata quad9 = DnsProviderMetadata(
    id: 'quad9',
    name: 'Quad9',
    primaryServer: '9.9.9.9',
    secondaryServer: '149.112.112.112',
    ipv6Server: '2620:fe::fe',
    dohUrl: 'https://dns.quad9.net/dns-query',
    description:
        'Non-profit, privacy-focused recursive resolver with cyber-threat blocking.',
    features: [
      'Threat blocking',
      'Privacy focused',
      'Swiss jurisdiction',
      'DNSSEC',
    ],
  );

  /// All 8 required public DNS providers in strict alphabetical order by display name.
  static const List<DnsProviderMetadata> publicProviders = [
    adguard,
    cleanBrowsing,
    cloudflare,
    controlD,
    google,
    nextDns,
    openDns,
    quad9,
  ];

  /// Builds a [DnsProviderMetadata] representing the router's actively configured resolver.
  static DnsProviderMetadata createRouterDnsProvider({
    required String routerIp,
    required RouterDnsConfig config,
  }) {
    return DnsProviderMetadata(
      id: 'router_current',
      name: 'Current Router DNS',
      primaryServer: routerIp,
      isRouterDns: true,
      description: config.details,
      features: config.isLocalForwarder
          ? ['Local Caching Forwarder', 'LAN Resolution']
          : ['Direct Upstream Resolution'],
    );
  }
}
