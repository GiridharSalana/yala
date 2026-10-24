// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import '../models/router_upgrade_scan.dart';
import '../models/upgrade_models.dart';

/// Set of file paths that are conventionally considered sensitive.
/// Their values must never appear in logs or UI without redaction.
const _sensitivePathPrefixes = {
  '/etc/shadow',
  '/etc/passwd',
  '/etc/dropbear/',
  '/etc/ssl/',
  '/etc/openvpn/',
  '/etc/wireguard/',
  '/root/.ssh/',
  '/etc/uhttpd.',
  '/etc/luci-uploads/',
};

bool _isSensitivePath(String path) {
  for (final prefix in _sensitivePathPrefixes) {
    if (path.startsWith(prefix) || path == prefix.trimRight()) return true;
  }
  return false;
}

/// Determines the [PreservationCategory] for a given path.
PreservationCategory _categorize(String path) {
  if (path.startsWith('/etc/shadow') || path.startsWith('/etc/passwd')) {
    return PreservationCategory.credentials;
  }
  if (path.startsWith('/etc/dropbear') || path.startsWith('/root/.ssh')) {
    return PreservationCategory.credentials;
  }
  if (path.startsWith('/etc/openvpn') || path.startsWith('/etc/wireguard')) {
    return PreservationCategory.vpnCredential;
  }
  if (path.startsWith('/etc/luci') || path.startsWith('/usr/share/luci')) {
    return PreservationCategory.luciExtension;
  }
  if (path.startsWith('/lib/modules') || path.contains('kmod')) {
    return PreservationCategory.kernelModule;
  }
  if (path.startsWith('/etc/init.d') || path.startsWith('/etc/rc.d')) {
    return PreservationCategory.customScript;
  }
  if (path.startsWith('/etc/crontabs')) {
    return PreservationCategory.customScript;
  }
  if (path.startsWith('/etc/')) {
    return PreservationCategory.configuration;
  }
  if (path.startsWith('/overlay/') || path.startsWith('/usr/')) {
    return PreservationCategory.installedPackage;
  }
  if (path.startsWith('/tmp/')) {
    return PreservationCategory.runtimeData;
  }
  if (path.startsWith('/mnt/') || path.startsWith('/media/')) {
    return PreservationCategory.externalStorage;
  }
  if (path.contains('art') ||
      path.contains('caldata') ||
      path.contains('radio')) {
    return PreservationCategory.hardwareCalibration;
  }
  return PreservationCategory.unknown;
}

/// Analyzes the upgrade impact for configuration, packages, and custom files.
class PreservationImpactAnalyzer {
  final IApiService apiService;
  final String ipAddress;
  final String sysauth;
  final bool useHttps;

  const PreservationImpactAnalyzer({
    required this.apiService,
    required this.ipAddress,
    required this.sysauth,
    required this.useHttps,
  });

  Future<bool> _fileExists(String path) async {
    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'stat',
        params: {'path': path},
      );
      if (res is List && res.length > 1 && res[0] == 0) {
        final data = res[1];
        return data is Map && data.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  /// Build a [PreservationImpactInventory] from a completed [RouterUpgradeScan].
  ///
  /// Uses the scan's sysupgrade -l output and /etc/sysupgrade.conf to classify
  /// each path. Verifies file existence where practical.
  Future<PreservationImpactInventory> analyze(RouterUpgradeScan scan) async {
    final items = <PreservationImpactItem>[];
    final limitations = <String>[];
    bool isPartial = scan.isPartial;

    // Paths confirmed by sysupgrade -l (the actual effective backup list)
    final preservedPaths = scan.sysupgradePreservedFiles.value ?? <String>[];

    // Paths in /etc/sysupgrade.conf (custom entries — a subset of preserved)
    final customPaths = <String>{};
    final confContent = scan.sysupgradeConf.value ?? '';
    for (final line in confContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        customPaths.add(trimmed);
      }
    }

    if (scan.sysupgradePreservedFiles.isUnknown) {
      isPartial = true;
      limitations.add(
        'sysupgrade -l output unavailable; preserved file list is unknown.',
      );
    }

    // Process each path in the preserved list
    for (final path in preservedPaths) {
      final sensitive = _isSensitivePath(path);
      final category = _categorize(path);
      final isCustom = customPaths.any((cp) => path.startsWith(cp));

      // Spot-check a sample of non-sensitive paths for existence
      bool? exists;
      if (!sensitive && items.length < 20) {
        try {
          exists = await _fileExists(
            path.trimRight().replaceAll(RegExp(r'/$'), ''),
          );
        } catch (_) {
          exists = null;
        }
      }

      final detectionSource = isCustom
          ? 'sysupgrade -l + /etc/sysupgrade.conf'
          : 'sysupgrade -l';

      items.add(
        PreservationImpactItem(
          path: path,
          category: category,
          detectionSource: detectionSource,
          outcome: PreservationOutcome.preserved,
          confidence: DetectionConfidence.verified,
          coveredByBackup: true,
          isSensitive: sensitive,
          recommendedAction: exists == false
              ? 'File no longer exists at this path; review /etc/sysupgrade.conf.'
              : null,
        ),
      );
    }

    // Known categories of data typically NOT in sysupgrade backup
    // These are presented as informational — not fabricated specific paths.
    final warnCategories =
        <
          ({
            String path,
            String description,
            PreservationCategory category,
            String action,
          })
        >[
          (
            path: '/overlay/upper/usr/',
            description: 'User-installed packages and binaries',
            category: PreservationCategory.installedPackage,
            action: 'Reinstall required packages after upgrade.',
          ),
          (
            path: '/etc/crontabs/root',
            description: 'Scheduled cron jobs',
            category: PreservationCategory.customScript,
            action: 'Verify cron jobs are included in sysupgrade backup.',
          ),
          (
            path: '/tmp/',
            description: 'Runtime data in /tmp (volatile RAM)',
            category: PreservationCategory.runtimeData,
            action: 'Do not rely on /tmp contents across reboots.',
          ),
        ];

    for (final cat in warnCategories) {
      // Only add if not already covered by the preserved list
      final alreadyCovered = preservedPaths.any((p) => p.startsWith(cat.path));
      if (!alreadyCovered) {
        items.add(
          PreservationImpactItem(
            path: cat.path,
            category: cat.category,
            description: cat.description,
            detectionSource: 'general OpenWrt knowledge (not router-specific)',
            outcome: cat.category == PreservationCategory.runtimeData
                ? PreservationOutcome.lost
                : PreservationOutcome.conditional,
            confidence: DetectionConfidence.conditional,
            recommendedAction: cat.action,
            coveredByBackup: false,
            isSensitive: false,
          ),
        );
      }
    }

    // Check for known sensitive paths that must not appear in logs
    for (final sensitivePath in [
      '/etc/shadow',
      '/etc/dropbear/',
      '/root/.ssh/',
    ]) {
      final inPreserved = preservedPaths.any(
        (p) => p.startsWith(sensitivePath),
      );
      if (!inPreserved) {
        items.add(
          PreservationImpactItem(
            path: sensitivePath,
            category: PreservationCategory.credentials,
            description: 'Credentials file — verify it is included in backup',
            detectionSource: 'expected path check',
            outcome: PreservationOutcome.conditional,
            confidence: DetectionConfidence.conditional,
            recommendedAction:
                'Ensure this path is in sysupgrade backup or document manually.',
            coveredByBackup: false,
            isSensitive: true,
          ),
        );
      }
    }

    final limitNote = limitations.isNotEmpty
        ? limitations.join(' ')
        : (isPartial ? 'Scan was partial; some items may be missing.' : null);

    return PreservationImpactInventory(
      items: items,
      isPartial: isPartial,
      limitationNote: limitNote,
    );
  }

  /// Build a [PackageMigrationAnalysis] based on current package manager state
  /// and an expected target.
  ///
  /// [currentEngine] — the package manager detected on the router.
  /// [targetEngine] — the expected package manager after upgrade, or null if
  /// unknown (which should be represented as unknown, not assumed unchanged).
  static PackageMigrationAnalysis analyzeMigration({
    required RouterPackageManager currentEngine,
    required RouterPackageManager? targetEngine,
    required List<PackageInfo> installedPackages,
  }) {
    PackageMigrationTransition transition;

    if (targetEngine == null) {
      transition = PackageMigrationTransition.unknown;
    } else if (currentEngine == RouterPackageManager.opkg &&
        targetEngine == RouterPackageManager.apk) {
      transition = PackageMigrationTransition.opkgToApk;
    } else if (currentEngine == RouterPackageManager.apk &&
        targetEngine == RouterPackageManager.opkg) {
      transition = PackageMigrationTransition.apkToOpkg;
    } else if (currentEngine == RouterPackageManager.opkg &&
        targetEngine == RouterPackageManager.opkg) {
      transition = PackageMigrationTransition.opkgToOpkg;
    } else if (currentEngine == RouterPackageManager.apk &&
        targetEngine == RouterPackageManager.apk) {
      transition = PackageMigrationTransition.apkToApk;
    } else if (currentEngine == RouterPackageManager.mixed ||
        targetEngine == RouterPackageManager.mixed ||
        currentEngine == RouterPackageManager.vendorSpecific ||
        targetEngine == RouterPackageManager.vendorSpecific) {
      transition = PackageMigrationTransition.mixedOrVendor;
    } else {
      transition = PackageMigrationTransition.unknown;
    }

    // Build per-package classification.
    // We do NOT query a remote package index here — that requires a live
    // router connection and network access. When a trusted source is
    // unavailable, status = unknown.
    final migrationItems = installedPackages.map((pkg) {
      final isKmod = pkg.name.startsWith('kmod-');
      final isLuci = pkg.name.startsWith('luci-');
      final isThirdParty = !_isKnownBasePackage(pkg.name);

      PackageMigrationStatus status;
      String? note;

      if (transition == PackageMigrationTransition.opkgToApk ||
          transition == PackageMigrationTransition.apkToOpkg) {
        if (isKmod) {
          status = PackageMigrationStatus.kernelModuleRequiresTargetBuild;
          note =
              'Kernel modules must match the target firmware kernel. Reinstall from the target feed after upgrade.';
        } else if (isThirdParty) {
          status = PackageMigrationStatus.thirdPartyUnverified;
          note =
              'Third-party package — verify availability in target ecosystem.';
        } else {
          // We cannot query the target package index without network access
          // and knowing the exact target release. Mark as unknown unless
          // we have strong evidence.
          status = PackageMigrationStatus.unknown;
          note =
              'Package equivalency could not be verified without a trusted target package index.';
        }
      } else if (transition == PackageMigrationTransition.opkgToOpkg ||
          transition == PackageMigrationTransition.apkToApk) {
        if (isKmod) {
          status = PackageMigrationStatus.kernelModuleRequiresTargetBuild;
          note =
              'Kernel modules should be reinstalled from the matching release after upgrade.';
        } else {
          // Same ecosystem upgrade — most packages should be available
          status = PackageMigrationStatus.possibleEquivalent;
          note = 'Same package manager — reinstall from standard feed.';
        }
      } else {
        status = PackageMigrationStatus.unknown;
        note =
            'Target package manager unknown; equivalency cannot be assessed.';
      }

      return PackageMigrationItem(
        packageName: pkg.name,
        installedVersion: pkg.version,
        migrationStatus: status,
        isKernelModule: isKmod,
        isLuciExtension: isLuci,
        isThirdParty: isThirdParty,
        note: note,
      );
    }).toList();

    return PackageMigrationAnalysis(
      transition: transition,
      packages: migrationItems,
      targetPackageManagerKnown: targetEngine != null,
      targetIndexConsulted: false,
      targetIndexUnavailableReason: targetEngine != null
          ? 'Target package index was not queried; '
                'equivalency could not be verified remotely.'
          : 'Target package manager could not be determined.',
    );
  }
}

/// Minimal package info carrier (aligned with existing package_info.dart).
class PackageInfo {
  final String name;
  final String? version;

  const PackageInfo({required this.name, this.version});
}

/// Heuristic: known OpenWrt base system packages unlikely to be user-installed.
bool _isKnownBasePackage(String name) {
  const knownBasePrefixes = {
    'base-files',
    'busybox',
    'dropbear',
    'kernel',
    'libc',
    'libgcc',
    'luci-base',
    'luci-mod-',
    'netifd',
    'rpcd',
    'uhttpd',
    'ubus',
    'uci',
    'dnsmasq',
    'firewall',
    'nftables',
    'iptables',
    'ip6tables',
    'kmod-',
    'procd',
    'ubox',
    'ucode',
    'libubus',
    'libuci',
    'libnl',
    'libpcre',
    'libnettle',
  };
  for (final prefix in knownBasePrefixes) {
    if (name == prefix || name.startsWith(prefix)) return true;
  }
  return false;
}
