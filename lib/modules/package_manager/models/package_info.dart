// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:yala/models/router_capabilities.dart';

/// Unify package manager enum across application
typedef PackageManagerType = PackageManagerEngine;

/// Unified software package model supporting OPKG (.ipk) and Alpine Package Keeper (.apk) formats.
class OpenWrtPackage {
  final String name;
  final String version;
  final String? architecture;
  final String description;
  final String? size;
  final String? installedSize;
  final String? repositorySize;
  final String? dependencies;
  final String? license;
  final String? section;
  final String? newVersion;
  final bool isInstalled;
  final bool hasUpdate;
  final PackageManagerType managerType;

  const OpenWrtPackage({
    required this.name,
    required this.version,
    this.architecture,
    required this.description,
    this.size,
    this.installedSize,
    this.repositorySize,
    this.dependencies,
    this.license,
    this.section,
    this.newVersion,
    required this.isInstalled,
    this.hasUpdate = false,
    this.managerType = PackageManagerType.opkg,
  });

  OpenWrtPackage copyWith({
    String? name,
    String? version,
    String? architecture,
    String? description,
    String? size,
    String? installedSize,
    String? repositorySize,
    String? dependencies,
    String? license,
    String? section,
    String? newVersion,
    bool? isInstalled,
    bool? hasUpdate,
    PackageManagerType? managerType,
  }) {
    return OpenWrtPackage(
      name: name ?? this.name,
      version: version ?? this.version,
      architecture: architecture ?? this.architecture,
      description: description ?? this.description,
      size: size ?? this.size,
      installedSize: installedSize ?? this.installedSize,
      repositorySize: repositorySize ?? this.repositorySize,
      dependencies: dependencies ?? this.dependencies,
      license: license ?? this.license,
      section: section ?? this.section,
      newVersion: newVersion ?? this.newVersion,
      isInstalled: isInstalled ?? this.isInstalled,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      managerType: managerType ?? this.managerType,
    );
  }

  factory OpenWrtPackage.fromJson(
    Map<String, dynamic> json, {
    bool isInstalled = true,
    bool hasUpdate = false,
    PackageManagerType managerType = PackageManagerType.opkg,
  }) {
    bool installed = isInstalled;
    if (json.containsKey('status')) {
      final s = json['status'];
      if (s is List) {
        installed = s.contains('installed');
      } else if (s is String) {
        installed = s.contains('installed');
      }
    }

    String? depsStr;
    final d = json['depends'] ?? json['dependencies'];
    if (d is List) {
      depsStr = d.map((e) => e.toString()).join(', ');
    } else if (d != null) {
      depsStr = d.toString();
    }

    return OpenWrtPackage(
      name:
          json['name']?.toString() ??
          json['package']?.toString() ??
          json['pkg']?.toString() ??
          'unknown-package',
      version:
          json['version']?.toString() ?? json['ver']?.toString() ?? '1.0.0',
      architecture:
          json['architecture']?.toString() ?? json['arch']?.toString(),
      description:
          json['description']?.toString() ??
          json['desc']?.toString() ??
          'OpenWrt package',
      size:
          json['size']?.toString() ??
          json['file-size']?.toString() ??
          json['installed_size']?.toString(),
      installedSize:
          json['installed_size']?.toString() ??
          json['installed-size']?.toString() ??
          json['installsize']?.toString(),
      repositorySize:
          json['repository_size']?.toString() ??
          json['file-size']?.toString() ??
          json['size']?.toString(),
      dependencies: depsStr,
      license: json['license']?.toString(),
      section: json['section']?.toString(),
      newVersion:
          json['new_version']?.toString() ?? json['newVersion']?.toString(),
      isInstalled: installed,
      hasUpdate:
          hasUpdate || json['has_update'] == true || json['upgradable'] == true,
      managerType: managerType,
    );
  }

  String get fileExtension =>
      managerType == PackageManagerType.apk ? '.apk' : '.ipk';

  /// Human-readable formatted size (e.g. "102 KB", "1.4 MB")
  String? get formattedSize {
    final raw = installedSize ?? size ?? repositorySize;
    if (raw == null || raw.isEmpty) return null;
    final bytes = int.tryParse(raw);
    if (bytes == null) return raw;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// Represents a LuCI application plugin (luci-app-*).
class LuciApp {
  final String id;
  final String name;
  final String packageName;
  final String description;
  final IconData icon;
  final bool isInstalled;
  final String? installedVersion;

  const LuciApp({
    required this.id,
    required this.name,
    required this.packageName,
    required this.description,
    required this.icon,
    required this.isInstalled,
    this.installedVersion,
  });
}

/// Complete overview container for package manager (OPKG/APK) and LuCI apps.
class PackageManagerOverview {
  final PackageManagerType activeManager;
  final List<OpenWrtPackage> installedPackages;
  final List<OpenWrtPackage> availablePackages;
  final List<OpenWrtPackage> upgradablePackages;
  final List<LuciApp> discoveredLuciApps;
  final int? freeDiskSpace;

  const PackageManagerOverview({
    required this.activeManager,
    required this.installedPackages,
    required this.availablePackages,
    this.upgradablePackages = const [],
    required this.discoveredLuciApps,
    this.freeDiskSpace,
  });

  /// Parse standard RFC-822 / Debian / OPKG / APK package control blocks
  static List<OpenWrtPackage> parseControlBlocks(
    String rawText, {
    required bool isInstalled,
    required PackageManagerType type,
    bool hasUpdate = false,
  }) {
    final packages = <OpenWrtPackage>[];
    final blocks = rawText.split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) continue;
      if (trimmedBlock.contains('Status: ') &&
          isInstalled &&
          !trimmedBlock.contains('installed')) {
        continue;
      }
      String? pkgName;
      String? pkgVer;
      String pkgDesc = '';
      String? pkgArch;
      String? pkgSize;
      String? pkgInstalledSize;
      String? pkgDeps;
      String? pkgLicense;
      String? pkgSection;

      bool readingDesc = false;

      for (final line in trimmedBlock.split('\n')) {
        if (line.startsWith('Package: ')) {
          pkgName = line.substring(9).trim();
          readingDesc = false;
        } else if (line.startsWith('Version: ')) {
          pkgVer = line.substring(9).trim();
          readingDesc = false;
        } else if (line.startsWith('Architecture: ')) {
          pkgArch = line.substring(14).trim();
          readingDesc = false;
        } else if (line.startsWith('Installed-Size: ')) {
          pkgInstalledSize = line.substring(16).trim();
          readingDesc = false;
        } else if (line.startsWith('Size: ')) {
          pkgSize = line.substring(6).trim();
          readingDesc = false;
        } else if (line.startsWith('Depends: ')) {
          pkgDeps = line.substring(9).trim();
          readingDesc = false;
        } else if (line.startsWith('License: ')) {
          pkgLicense = line.substring(9).trim();
          readingDesc = false;
        } else if (line.startsWith('Section: ')) {
          pkgSection = line.substring(9).trim();
          readingDesc = false;
        } else if (line.startsWith('Description: ')) {
          pkgDesc = line.substring(13).trim();
          readingDesc = true;
        } else if (readingDesc &&
            (line.startsWith(' ') || line.startsWith('\t'))) {
          pkgDesc += ' ${line.trim()}';
        } else {
          readingDesc = false;
        }
      }

      if (pkgName != null && pkgName.isNotEmpty) {
        packages.add(
          OpenWrtPackage(
            name: pkgName,
            version: pkgVer ?? (isInstalled ? 'installed' : 'available'),
            architecture: pkgArch,
            description: pkgDesc.isEmpty
                ? 'OpenWrt package ($pkgName)'
                : pkgDesc,
            size: pkgSize,
            installedSize: pkgInstalledSize,
            dependencies: pkgDeps,
            license: pkgLicense,
            section: pkgSection,
            isInstalled: isInstalled,
            hasUpdate: hasUpdate,
            managerType: type,
          ),
        );
      }
    }
    return packages;
  }

  /// Parse Alpine Package Keeper internal database blocks (/lib/apk/db/installed)
  static List<OpenWrtPackage> parseApkDb(String rawText) {
    final packages = <OpenWrtPackage>[];
    final blocks = rawText.split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      String? pkgName;
      String? pkgVer;
      String pkgDesc = '';
      String? pkgSize;
      String? pkgDeps;
      String? pkgLicense;
      String? pkgArch;

      for (final line in block.split('\n')) {
        if (line.startsWith('P:')) {
          pkgName = line.substring(2).trim();
        } else if (line.startsWith('V:')) {
          pkgVer = line.substring(2).trim();
        } else if (line.startsWith('T:')) {
          pkgDesc = line.substring(2).trim();
        } else if (line.startsWith('I:')) {
          pkgSize = line.substring(2).trim();
        } else if (line.startsWith('D:')) {
          pkgDeps = line.substring(2).trim();
        } else if (line.startsWith('L:')) {
          pkgLicense = line.substring(2).trim();
        } else if (line.startsWith('A:')) {
          pkgArch = line.substring(2).trim();
        }
      }

      if (pkgName != null && pkgName.isNotEmpty) {
        packages.add(
          OpenWrtPackage(
            name: pkgName,
            version: pkgVer ?? 'installed',
            description: pkgDesc.isEmpty ? 'APK package ($pkgName)' : pkgDesc,
            size: pkgSize,
            installedSize: pkgSize,
            dependencies: pkgDeps,
            license: pkgLicense,
            architecture: pkgArch,
            isInstalled: true,
            managerType: PackageManagerType.apk,
          ),
        );
      }
    }
    return packages;
  }

  /// Safely parse JSON array (e.g. from APK query or package-manager-call) into OpenWrtPackage list
  static List<OpenWrtPackage> parseJsonPackages(
    dynamic rawJson, {
    bool isInstalled = true,
    PackageManagerType managerType = PackageManagerType.apk,
  }) {
    final list = rawJson is String ? jsonDecode(rawJson) : rawJson;
    if (list is! List) return <OpenWrtPackage>[];
    final packages = <OpenWrtPackage>[];
    for (final item in list) {
      if (item is Map) {
        packages.add(
          OpenWrtPackage.fromJson(
            Map<String, dynamic>.from(item),
            isInstalled: isInstalled,
            managerType: managerType,
          ),
        );
      }
    }
    return packages;
  }

  factory PackageManagerOverview.fromDashboardData(
    Map<String, dynamic>? data, {
    bool isReviewerMode = false,
  }) {
    final installed = <OpenWrtPackage>[];
    final available = <OpenWrtPackage>[];
    PackageManagerType type = PackageManagerType.opkg;

    if (data != null) {
      // Check if OpenWrt 24.10+ APK manager is active
      final mgrStr =
          data['packageManager']?.toString() ?? data['pkg_mgr']?.toString();
      if (mgrStr == 'apk' || data.containsKey('apkPackages')) {
        type = PackageManagerType.apk;
      }

      dynamic installedRaw =
          data['installedPackages'] ??
          data['apkPackages'] ??
          data['opkgPackages'];
      if (installedRaw is Map) {
        if (installedRaw.containsKey('packages')) {
          installedRaw = installedRaw['packages'];
        } else if (installedRaw.containsKey('result')) {
          final res = installedRaw['result'];
          if (res is Map && res.containsKey('packages')) {
            installedRaw = res['packages'];
          } else if (res is Map || res is List) {
            installedRaw = res;
          }
        }
      }

      if (installedRaw is String) {
        final trimmed = installedRaw.trim();
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is List) {
              installedRaw = decoded;
              type = PackageManagerType.apk;
            }
          } catch (_) {}
        }
      }

      if (installedRaw is String) {
        if (installedRaw.contains('Package: ') &&
            (installedRaw.contains('Status: ') ||
                installedRaw.contains('Version: '))) {
          installed.addAll(
            parseControlBlocks(installedRaw, isInstalled: true, type: type),
          );
        } else if (installedRaw.contains('P:') && installedRaw.contains('V:')) {
          installed.addAll(parseApkDb(installedRaw));
        } else {
          // Line based output (opkg list-installed / apk list --installed)
          final lines = installedRaw.split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty ||
                trimmed.startsWith('#') ||
                trimmed.startsWith('WARNING')) {
              continue;
            }

            String pkgName;
            String pkgVer = 'installed';
            String pkgDesc = '';

            if (trimmed.contains(' - ')) {
              final parts = trimmed.split(' - ');
              pkgName = parts[0].trim();
              if (parts.length > 1) pkgVer = parts[1].trim();
              if (parts.length > 2) pkgDesc = parts[2].trim();
            } else if (trimmed.contains(' ')) {
              final parts = trimmed.split(RegExp(r'\s+'));
              pkgName = parts[0].trim();
              if (parts.length > 1) pkgVer = parts[1].trim();
              if (parts.length > 2) pkgDesc = parts.sublist(2).join(' ');
            } else {
              final match = RegExp(
                r'^([a-zA-Z0-9_\-]+?)-([0-9].*)$',
              ).firstMatch(trimmed);
              if (match != null) {
                pkgName = match.group(1)!;
                pkgVer = match.group(2)!;
              } else {
                pkgName = trimmed;
              }
            }

            if (pkgName.isNotEmpty &&
                pkgName != 'Package:' &&
                pkgName != 'Status:') {
              installed.add(
                OpenWrtPackage(
                  name: pkgName,
                  version: pkgVer,
                  description: pkgDesc.isEmpty
                      ? 'OpenWrt package ($pkgName)'
                      : pkgDesc,
                  isInstalled: true,
                  managerType: type,
                ),
              );
            }
          }
        }
      } else if (installedRaw is List) {
        for (final item in installedRaw) {
          if (item is Map<String, dynamic>) {
            installed.add(
              OpenWrtPackage.fromJson(
                item,
                isInstalled: true,
                managerType: type,
              ),
            );
          } else if (item is OpenWrtPackage) {
            installed.add(item);
          } else if (item is String && item.isNotEmpty) {
            installed.add(
              OpenWrtPackage(
                name: item,
                version: 'installed',
                description: 'OpenWrt package ($item)',
                isInstalled: true,
                managerType: type,
              ),
            );
          }
        }
      } else if (installedRaw is Map) {
        Map targetMap = installedRaw;
        if (targetMap['packages'] is Map) {
          targetMap = targetMap['packages'] as Map;
        } else if (targetMap['result'] is Map) {
          targetMap = targetMap['result'] as Map;
        }
        targetMap.forEach((pkgName, val) {
          final nameStr = pkgName.toString();
          if (nameStr == 'packages' || nameStr == 'result') return;
          if (val is Map) {
            installed.add(
              OpenWrtPackage.fromJson(
                Map<String, dynamic>.from(val),
                isInstalled: true,
                managerType: type,
              ),
            );
          } else {
            installed.add(
              OpenWrtPackage(
                name: nameStr,
                version: val?.toString() ?? 'installed',
                description: 'OpenWrt package ($nameStr)',
                isInstalled: true,
                managerType: type,
              ),
            );
          }
        });
      }

      dynamic availableRaw = data['availablePackages'];
      if (availableRaw is String) {
        final trimmed = availableRaw.trim();
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is List) {
              availableRaw = decoded;
              type = PackageManagerType.apk;
            }
          } catch (_) {}
        }
      }

      if (availableRaw is String) {
        if (availableRaw.contains('Package: ')) {
          available.addAll(
            parseControlBlocks(availableRaw, isInstalled: false, type: type),
          );
        } else {
          final lines = availableRaw.split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
            if (trimmed.contains(' - ')) {
              final parts = trimmed.split(' - ');
              final pkgName = parts[0].trim();
              final pkgVer = parts.length > 1 ? parts[1].trim() : 'available';
              final pkgDesc = parts.length > 2
                  ? parts[2].trim()
                  : 'OpenWrt repository package';
              if (!installed.any((p) => p.name == pkgName)) {
                available.add(
                  OpenWrtPackage(
                    name: pkgName,
                    version: pkgVer,
                    description: pkgDesc,
                    isInstalled: false,
                    managerType: type,
                  ),
                );
              }
            } else {
              final parts = trimmed.split(RegExp(r'\s+'));
              final pkgName = parts[0];
              final pkgVer = parts.length > 1 ? parts[1] : 'available';
              final pkgDesc = parts.length > 2
                  ? parts.sublist(2).join(' ')
                  : 'OpenWrt repository package';
              if (!installed.any((p) => p.name == pkgName)) {
                available.add(
                  OpenWrtPackage(
                    name: pkgName,
                    version: pkgVer,
                    description: pkgDesc,
                    isInstalled: false,
                    managerType: type,
                  ),
                );
              }
            }
          }
        }
      } else if (availableRaw is List) {
        for (final item in availableRaw) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            if (map.containsKey('arch') ||
                map.containsKey('file-size') ||
                map.containsKey('origin')) {
              type = PackageManagerType.apk;
            }
            available.add(
              OpenWrtPackage.fromJson(
                map,
                isInstalled: false,
                managerType: type,
              ),
            );
          } else if (item is OpenWrtPackage) {
            available.add(item);
          }
        }
      } else if (availableRaw is Map) {
        availableRaw.forEach((_, item) {
          if (item is Map<String, dynamic>) {
            available.add(
              OpenWrtPackage.fromJson(
                item,
                isInstalled: false,
                managerType: type,
              ),
            );
          }
        });
      }
    }

    // Upgradable packages detection
    final upgradable = <OpenWrtPackage>[];
    if (data != null && data['upgradablePackages'] != null) {
      final upRaw = data['upgradablePackages'];
      if (upRaw is List<OpenWrtPackage>) {
        upgradable.addAll(upRaw);
      } else if (upRaw is String && upRaw.contains('Package: ')) {
        upgradable.addAll(
          parseControlBlocks(
            upRaw,
            isInstalled: true,
            type: type,
            hasUpdate: true,
          ),
        );
      } else if (upRaw is List) {
        for (final item in upRaw) {
          if (item is Map<String, dynamic>) {
            upgradable.add(
              OpenWrtPackage.fromJson(
                item,
                isInstalled: true,
                hasUpdate: true,
                managerType: type,
              ),
            );
          } else if (item is OpenWrtPackage) {
            upgradable.add(item);
          }
        }
      }
    }

    // Cross-reference installed and available to identify upgradable packages
    if (available.isNotEmpty) {
      final availMap = {for (final a in available) a.name: a};
      for (int i = 0; i < installed.length; i++) {
        final inst = installed[i];
        final avail = availMap[inst.name];
        if (avail != null &&
            avail.version != inst.version &&
            avail.version != 'available' &&
            inst.version != 'installed') {
          final updated = inst.copyWith(
            hasUpdate: true,
            newVersion: avail.version,
          );
          installed[i] = updated;
          if (!upgradable.any((u) => u.name == inst.name)) {
            upgradable.add(updated);
          }
        }
      }
    }

    // Extract free disk space
    int? freeSpace;
    if (data != null) {
      if (data['freeDiskSpace'] is num) {
        freeSpace = (data['freeDiskSpace'] as num).toInt();
      } else if (data['rootInfo'] is Map &&
          (data['rootInfo'] as Map)['avail'] is num) {
        // system.info root space is in KB
        freeSpace = ((data['rootInfo'] as Map)['avail'] as num).toInt() * 1024;
      }
    }

    // Default mock package list only if in Reviewer Mode
    if (isReviewerMode) {
      if (installed.isEmpty) {
        installed.addAll([
          OpenWrtPackage(
            name: 'luci-base',
            version: 'git-23.330.60124',
            description: 'LuCI core JavaScript and MVC framework',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-mod-admin-full',
            version: 'git-23.330.60124',
            description: 'LuCI Administration User Interface',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'dnsmasq-full',
            version: '2.89-1',
            description: 'DNS forwarder and DHCP server with DNSSEC support',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'wireguard-tools',
            version: '1.0.20210914-1',
            description: 'WireGuard control utilities',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'firewall4',
            version: '2023-09-12',
            description: 'OpenWrt nftables-based firewall manager',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'dropbear',
            version: '2022.82-2',
            description: 'Small SSH daemon',
            isInstalled: true,
            managerType: type,
          ),
        ]);
      }

      if (available.isEmpty) {
        available.addAll([
          OpenWrtPackage(
            name: 'luci-app-adguardhome',
            version: '1.8.2-1',
            description:
                'AdGuard Home network-wide ad blocker LuCI integration',
            isInstalled: false,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-app-sqm',
            version: '1.5.0-1',
            description:
                'Smart Queue Management (Bufferbloat control) interface',
            isInstalled: false,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-app-ttyd',
            version: '1.7.3-1',
            description: 'Web-based terminal command line interface',
            isInstalled: false,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-app-aria2',
            version: '1.0.3-2',
            description: 'Lightweight multi-protocol download manager LuCI app',
            isInstalled: false,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-app-samba4',
            version: '4.18.5-1',
            description: 'Samba4 Windows network file sharing server interface',
            isInstalled: false,
            managerType: type,
          ),
        ]);
      }

      if (upgradable.isEmpty) {
        upgradable.addAll([
          OpenWrtPackage(
            name: 'luci-app-firewall',
            version: 'git-23.332',
            newVersion: 'git-24.010',
            description: 'Firewall management interface upgrade',
            isInstalled: true,
            hasUpdate: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'dnsmasq',
            version: '2.89-1',
            newVersion: '2.90-1',
            description: 'DHCP and DNS server security update',
            isInstalled: true,
            hasUpdate: true,
            managerType: type,
          ),
        ]);
      }
    }

    // Helper to check if a package is installed
    bool isPkgInstalled(String targetPkgName) {
      final cleanTarget = targetPkgName.toLowerCase().trim();
      final coreName = cleanTarget.replaceFirst('luci-app-', '');
      return installed.any((p) {
        final pName = p.name.toLowerCase().trim();
        return pName == cleanTarget ||
            pName == 'luci-app-$coreName' ||
            (coreName.length > 3 && pName == coreName);
      });
    }

    String? getPkgVersion(String targetPkgName) {
      final cleanTarget = targetPkgName.toLowerCase().trim();
      final coreName = cleanTarget.replaceFirst('luci-app-', '');
      for (final p in installed) {
        final pName = p.name.toLowerCase().trim();
        if (pName == cleanTarget ||
            pName == 'luci-app-$coreName' ||
            (coreName.length > 3 && pName == coreName)) {
          return p.version;
        }
      }
      return null;
    }

    // Known LuCI applications catalog
    final knownApps = <LuciApp>[
      LuciApp(
        id: 'adguardhome',
        name: 'AdGuard Home',
        packageName: 'luci-app-adguardhome',
        description: 'Network-wide advertisement and tracker blocking server',
        icon: Icons.shield,
        isInstalled: isPkgInstalled('luci-app-adguardhome'),
        installedVersion: getPkgVersion('luci-app-adguardhome'),
      ),
      LuciApp(
        id: 'wireguard',
        name: 'WireGuard VPN',
        packageName: 'luci-app-wireguard',
        description: 'Extremely simple yet fast modern VPN manager',
        icon: Icons.vpn_lock,
        isInstalled: isPkgInstalled('luci-app-wireguard'),
        installedVersion: getPkgVersion('luci-app-wireguard'),
      ),
      LuciApp(
        id: 'sqm',
        name: 'SQM QoS',
        packageName: 'luci-app-sqm',
        description:
            'Smart Queue Management to eliminate latency & bufferbloat',
        icon: Icons.speed,
        isInstalled: isPkgInstalled('luci-app-sqm'),
        installedVersion: getPkgVersion('luci-app-sqm'),
      ),
      LuciApp(
        id: 'ttyd',
        name: 'Terminal (ttyd)',
        packageName: 'luci-app-ttyd',
        description: 'Web-based terminal shell execution command line',
        icon: Icons.terminal,
        isInstalled: isPkgInstalled('luci-app-ttyd'),
        installedVersion: getPkgVersion('luci-app-ttyd'),
      ),
      LuciApp(
        id: 'aria2',
        name: 'Aria2 Downloader',
        packageName: 'luci-app-aria2',
        description: 'Multi-protocol download utility (HTTP/FTP/BitTorrent)',
        icon: Icons.downloading,
        isInstalled: isPkgInstalled('luci-app-aria2'),
        installedVersion: getPkgVersion('luci-app-aria2'),
      ),
      LuciApp(
        id: 'samba4',
        name: 'Samba Network Share',
        packageName: 'luci-app-samba4',
        description: 'SMB/CIFS local file server for USB storage sharing',
        icon: Icons.folder_shared,
        isInstalled: isPkgInstalled('luci-app-samba4'),
        installedVersion: getPkgVersion('luci-app-samba4'),
      ),
    ];

    // Automatically discover any other installed luci-app-* packages from router
    for (final pkg in installed) {
      if (pkg.name.startsWith('luci-app-')) {
        final alreadyInCatalog = knownApps.any(
          (app) => app.packageName == pkg.name,
        );
        if (!alreadyInCatalog) {
          final rawName = pkg.name.replaceFirst('luci-app-', '');
          final formattedTitle = rawName
              .split('-')
              .map(
                (w) => w.isNotEmpty
                    ? '${w[0].toUpperCase()}${w.substring(1)}'
                    : '',
              )
              .join(' ');

          knownApps.add(
            LuciApp(
              id: rawName,
              name: formattedTitle,
              packageName: pkg.name,
              description: 'OpenWrt LuCI module integration ($rawName)',
              icon: Icons.widgets_outlined,
              isInstalled: true,
              installedVersion: pkg.version,
            ),
          );
        }
      }
    }

    // Ensure activeManager is APK if apk packages or apk tools are present
    if (type == PackageManagerType.opkg) {
      if (installed.any(
            (p) =>
                p.name.startsWith('apk-') ||
                p.name == 'apk' ||
                p.managerType == PackageManagerType.apk,
          ) ||
          available.any(
            (p) =>
                p.name.startsWith('apk-') ||
                p.name == 'apk' ||
                p.managerType == PackageManagerType.apk,
          )) {
        type = PackageManagerType.apk;
      }
    }

    final finalInstalled = type == PackageManagerType.apk
        ? installed
              .map(
                (p) => p.managerType == PackageManagerType.apk
                    ? p
                    : p.copyWith(managerType: PackageManagerType.apk),
              )
              .toList()
        : installed;
    final finalAvailable = type == PackageManagerType.apk
        ? available
              .map(
                (p) => p.managerType == PackageManagerType.apk
                    ? p
                    : p.copyWith(managerType: PackageManagerType.apk),
              )
              .toList()
        : available;
    final finalUpgradable = type == PackageManagerType.apk
        ? upgradable
              .map(
                (p) => p.managerType == PackageManagerType.apk
                    ? p
                    : p.copyWith(managerType: PackageManagerType.apk),
              )
              .toList()
        : upgradable;

    return PackageManagerOverview(
      activeManager: type,
      installedPackages: finalInstalled,
      availablePackages: finalAvailable,
      upgradablePackages: finalUpgradable,
      discoveredLuciApps: knownApps,
      freeDiskSpace: freeSpace,
    );
  }

  int get upgradableCount => upgradablePackages.isNotEmpty
      ? upgradablePackages.length
      : installedPackages.where((p) => p.hasUpdate).length;

  /// Formatted free disk space (e.g. "56.0 KB", "12.4 MB")
  String? get formattedFreeSpace {
    if (freeDiskSpace == null) return null;
    final bytes = freeDiskSpace!;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get managerTitle => 'OPKG/APK Package Manager';
}

/// Package feed/repository definition supporting OPKG and APK feed parsing.
class OpenWrtPackageRepository {
  final String name;
  final String url;
  final bool isEnabled;
  final PackageManagerEngine engine;

  const OpenWrtPackageRepository({
    required this.name,
    required this.url,
    this.isEnabled = true,
    required this.engine,
  });

  /// Parse OPKG config line: e.g. "src/gz openwrt_core https://downloads.openwrt.org/..."
  static OpenWrtPackageRepository? parseOpkgLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 3 &&
        (parts[0].startsWith('src') || parts[0] == 'dest')) {
      return OpenWrtPackageRepository(
        name: parts[1],
        url: parts[2],
        engine: PackageManagerEngine.opkg,
      );
    }
    return null;
  }

  /// Parse APK repositories line: e.g. "https://downloads.openwrt.org/snapshots/packages/x86_64/base"
  static OpenWrtPackageRepository? parseApkLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    String name = 'repository';
    String url = trimmed;
    if (trimmed.startsWith('@')) {
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        name = parts[0].substring(1);
        url = parts[1];
      }
    } else {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        name = uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => 'repo',
        );
      }
    }
    return OpenWrtPackageRepository(
      name: name,
      url: url,
      engine: PackageManagerEngine.apk,
    );
  }
}
