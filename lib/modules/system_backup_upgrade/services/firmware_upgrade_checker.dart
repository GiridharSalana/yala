// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:yala/utils/logger.dart';
import '../models/router_upgrade_scan.dart';
import '../models/upgrade_models.dart';

/// Checks for firmware upgrade availability for a given router scan.
///
/// For official OpenWrt devices, queries the official OpenWrt Attended
/// Sysupgrade / Chef metadata API (sysupgrade.openwrt.org / downloads.openwrt.org)
/// to detect available point releases and release branch updates, matching
/// the exact board name and target against official device profiles.
///
/// For vendor-specific or independent distributions (GL.iNet, Gargoyle,
/// ImmortalWrt), provides verified guidance and links to their release portals.
class FirmwareUpgradeChecker {
  final Dio? dio;

  const FirmwareUpgradeChecker({this.dio});

  static const String _overviewUrl =
      'https://sysupgrade.openwrt.org/json/v1/overview.json';
  static const String _latestUrl =
      'https://sysupgrade.openwrt.org/json/v1/latest.json';
  static const String _downloadsBase = 'https://downloads.openwrt.org/releases';

  Dio _getDio() {
    return dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            headers: {'User-Agent': 'YALA-Mobile-OpenWrt-Client'},
          ),
        );
  }

  /// Check firmware upgrade availability for a given [RouterUpgradeScan].
  Future<FirmwareUpgradeAvailability> check(RouterUpgradeScan scan) async {
    Logger.info(
      'FirmwareUpgradeChecker.check: family=${scan.firmwareFamily.value}, '
      'release=${scan.distribRelease.value}, target=${scan.distribTarget.value}, '
      'board=${scan.boardName.value}',
    );

    if (scan.firmwareFamily.isUnknown ||
        scan.firmwareFamily.value == FirmwareFamily.unknown) {
      return FirmwareUpgradeAvailability(
        status: UpgradeAvailabilityStatus.compatibilityUnverifiable,
        currentVersion: scan.distribRelease.value,
        explanation:
            'Firmware family could not be determined. Automatic upgrade '
            'discovery requires a known firmware distribution. Use manual '
            'image upload to flash a verified image.',
      );
    }

    final family = scan.firmwareFamily.value!;
    switch (family) {
      case FirmwareFamily.openWrt:
        return _checkOpenWrt(scan);
      case FirmwareFamily.immortalWrt:
        return _reportUnsupportedSource(
          scan,
          channel: 'ImmortalWrt',
          detail:
              'ImmortalWrt has its own release channel. Visit '
              'https://downloads.immortalwrt.org/ to find the appropriate '
              'sysupgrade image for your device (${scan.boardName.value ?? 'unknown'}).',
        );
      case FirmwareFamily.glINet:
        return _reportUnsupportedSource(
          scan,
          channel: 'GL.iNet Firmware',
          detail:
              'GL.iNet firmware is vendor-specific and distributed through '
              'GL.iNet\'s portal. Visit https://dl.gl-inet.com/ or use the '
              'GL.iNet Admin Panel to obtain the correct image for your model.',
        );
      case FirmwareFamily.gargoyle:
        return _reportUnsupportedSource(
          scan,
          channel: 'Gargoyle Router OS',
          detail:
              'Gargoyle has its own release channel. Visit '
              'https://www.gargoyle-router.com/ for the appropriate image.',
        );
      case FirmwareFamily.lede:
        return _reportUnsupportedSource(
          scan,
          channel: 'LEDE Reboot',
          detail:
              'LEDE was merged into OpenWrt. Visit '
              'https://openwrt.org/downloads to find a modern OpenWrt image.',
        );
      case FirmwareFamily.unknown:
        return FirmwareUpgradeAvailability(
          status: UpgradeAvailabilityStatus.unsupportedFirmwareSource,
          currentVersion: scan.distribRelease.value,
          channelDescription: 'Unknown firmware family',
          explanation:
              'Firmware family is unknown. Automatic upgrade discovery '
              'is unavailable. Use manual image upload.',
        );
    }
  }

  FirmwareUpgradeAvailability _reportUnsupportedSource(
    RouterUpgradeScan scan, {
    required String channel,
    required String detail,
  }) {
    return FirmwareUpgradeAvailability(
      status: UpgradeAvailabilityStatus.unsupportedFirmwareSource,
      currentVersion: scan.distribRelease.value,
      channelDescription: channel,
      explanation: detail,
    );
  }

  /// Official OpenWrt automated upgrade check.
  Future<FirmwareUpgradeAvailability> _checkOpenWrt(
    RouterUpgradeScan scan,
  ) async {
    final rawCurrent = scan.distribRelease.value;
    if (rawCurrent == null || rawCurrent.trim().isEmpty) {
      return const FirmwareUpgradeAvailability(
        status: UpgradeAvailabilityStatus.currentVersionUnknown,
        channelDescription: 'OpenWrt',
        explanation:
            'Current firmware version could not be determined from the router. '
            'Manual inspection or upgrade is required.',
      );
    }

    final target = scan.distribTarget.value?.trim();
    final board = scan.boardName.value?.trim();

    if (target == null || target.isEmpty || board == null || board.isEmpty) {
      return FirmwareUpgradeAvailability(
        status: UpgradeAvailabilityStatus.compatibilityUnverifiable,
        currentVersion: rawCurrent,
        channelDescription: 'OpenWrt',
        explanation:
            'Router target architecture (${target ?? "unknown"}) or board '
            'name (${board ?? "unknown"}) could not be reliably verified. '
            'Check manually at https://downloads.openwrt.org/.',
      );
    }

    // Clean current version string (strip revision or trailing descriptors)
    final cleanCurrent = rawCurrent
        .replaceAll(RegExp(r'^(v|OpenWrt\s*)', caseSensitive: false), '')
        .split(RegExp(r'[\s\+]'))
        .first
        .trim();

    final client = _getDio();

    try {
      // 1. Fetch release overview metadata
      Map<String, dynamic>? overviewData;
      List<String> latestReleases = [];

      try {
        final res = await client.get<Map<String, dynamic>>(_overviewUrl);
        if (res.data != null) {
          overviewData = res.data;
          if (overviewData?['latest'] is List) {
            latestReleases = (overviewData!['latest'] as List)
                .map((e) => e.toString())
                .toList();
          }
        }
      } catch (e) {
        Logger.warning(
          'Overview metadata fetch failed, trying latest.json: $e',
        );
        try {
          final res = await client.get<Map<String, dynamic>>(_latestUrl);
          if (res.data != null && res.data?['latest'] is List) {
            latestReleases = (res.data!['latest'] as List)
                .map((e) => e.toString())
                .toList();
          }
        } catch (e2) {
          Logger.error('Both overview.json and latest.json failed: $e2');
          return FirmwareUpgradeAvailability(
            status: UpgradeAvailabilityStatus.updateSourceUnavailable,
            currentVersion: rawCurrent,
            channelDescription: 'OpenWrt',
            explanation:
                'Unable to connect to OpenWrt update servers. Please check '
                'your internet connection and try again.',
          );
        }
      }

      // 2. Determine target candidate versions to check
      // First, extract branch from current version (e.g., '25.12' from '25.12.1' or '25.12.5')
      final branch = _extractBranch(cleanCurrent);
      String? bestCandidate;

      if (overviewData != null &&
          overviewData['branches'] is Map &&
          branch != null) {
        final branches = overviewData['branches'] as Map<String, dynamic>;
        if (branches.containsKey(branch)) {
          final branchInfo = branches[branch];
          if (branchInfo is Map && branchInfo['versions'] is List) {
            final versions = (branchInfo['versions'] as List)
                .map((e) => e.toString())
                .where((v) => !v.contains('SNAPSHOT') && !v.contains('rc'))
                .toList();
            if (versions.isNotEmpty) {
              // The versions list in overview.json is ordered newest first (e.g. ['25.12.6', '25.12.5', ...])
              bestCandidate = versions.first;
            }
          }
        }
      }

      // If branch candidate is not newer than current, check if a newer stable release branch exists in latestReleases
      if (bestCandidate == null ||
          compareVersions(bestCandidate, cleanCurrent) <= 0) {
        for (final latest in latestReleases) {
          if (compareVersions(latest, cleanCurrent) > 0) {
            bestCandidate = latest;
            break;
          }
        }
      }

      // If still no newer candidate found, router is already on latest release!
      if (bestCandidate == null ||
          compareVersions(bestCandidate, cleanCurrent) <= 0) {
        return FirmwareUpgradeAvailability(
          status: UpgradeAvailabilityStatus.currentVersionLatest,
          currentVersion: rawCurrent,
          latestVersion: bestCandidate ?? cleanCurrent,
          channelDescription: 'OpenWrt',
          explanation:
              'Your router is running the latest official OpenWrt release '
              '($rawCurrent) for this branch.',
        );
      }

      // 3. Query profiles.json for the candidate version and target
      final candidateVersion = bestCandidate;
      final profilesUrl =
          '$_downloadsBase/$candidateVersion/targets/$target/profiles.json';
      Logger.info('Querying OpenWrt profiles: $profilesUrl for board: $board');

      Response<Map<String, dynamic>> profilesRes;
      try {
        profilesRes = await client.get<Map<String, dynamic>>(profilesUrl);
      } catch (e) {
        Logger.error('Failed to fetch profiles.json from $profilesUrl: $e');
        return FirmwareUpgradeAvailability(
          status: UpgradeAvailabilityStatus.noMatchingImageFound,
          currentVersion: rawCurrent,
          latestVersion: candidateVersion,
          channelDescription: 'OpenWrt',
          explanation:
              'A newer OpenWrt release ($candidateVersion) exists, but profiles '
              'for target $target could not be retrieved from the server.',
        );
      }

      final profilesData = profilesRes.data;
      if (profilesData == null || profilesData['profiles'] is! Map) {
        return FirmwareUpgradeAvailability(
          status: UpgradeAvailabilityStatus.noMatchingImageFound,
          currentVersion: rawCurrent,
          latestVersion: candidateVersion,
          channelDescription: 'OpenWrt',
          explanation:
              'Release $candidateVersion exists, but the profile index is invalid.',
        );
      }

      final profiles = profilesData['profiles'] as Map<String, dynamic>;
      Map<String, dynamic>? matchedProfile;
      String? matchedProfileKey;

      // Match strategy 1: supported_devices contains board name (case-insensitive)
      for (final entry in profiles.entries) {
        final profile = entry.value;
        if (profile is Map && profile['supported_devices'] is List) {
          final devices = (profile['supported_devices'] as List)
              .map((d) => d.toString().toLowerCase())
              .toList();
          if (devices.contains(board.toLowerCase())) {
            matchedProfile = profile as Map<String, dynamic>;
            matchedProfileKey = entry.key;
            break;
          }
        }
      }

      // Match strategy 2: Normalized profile key matching
      if (matchedProfile == null) {
        final normalizedBoard1 = board.replaceAll(',', '_').toLowerCase();
        final normalizedBoard2 = board
            .replaceAll(',', '_')
            .replaceAll('-', '_')
            .toLowerCase();

        for (final entry in profiles.entries) {
          final keyLower = entry.key.toLowerCase();
          if (keyLower == normalizedBoard1 || keyLower == normalizedBoard2) {
            matchedProfile = entry.value as Map<String, dynamic>?;
            matchedProfileKey = entry.key;
            break;
          }
        }
      }

      if (matchedProfile == null) {
        return FirmwareUpgradeAvailability(
          status: UpgradeAvailabilityStatus.noMatchingImageFound,
          currentVersion: rawCurrent,
          latestVersion: candidateVersion,
          channelDescription: 'OpenWrt',
          explanation:
              'OpenWrt $candidateVersion is available for target $target, but '
              'no official profile was found matching board "$board".',
        );
      }

      // Extract sysupgrade image from matched profile
      final images = matchedProfile['images'];
      Map<String, dynamic>? sysupgradeImage;

      if (images is List) {
        for (final img in images) {
          if (img is Map && img['type'] == 'sysupgrade') {
            sysupgradeImage = img as Map<String, dynamic>;
            break;
          }
        }
        // Fallback: look for image filename containing 'sysupgrade'
        if (sysupgradeImage == null) {
          for (final img in images) {
            if (img is Map &&
                (img['name'] as String?)?.contains('sysupgrade') == true) {
              sysupgradeImage = img as Map<String, dynamic>;
              break;
            }
          }
        }
      }

      if (sysupgradeImage == null) {
        return FirmwareUpgradeAvailability(
          status: UpgradeAvailabilityStatus.noMatchingImageFound,
          currentVersion: rawCurrent,
          latestVersion: candidateVersion,
          channelDescription: 'OpenWrt',
          explanation:
              'A profile for $board was found in OpenWrt $candidateVersion, '
              'but no compatible sysupgrade image is available.',
        );
      }

      final imageName = sysupgradeImage['name'] as String;
      final sha256 = sysupgradeImage['sha256'] as String?;
      final size = sysupgradeImage['size'] as int?;
      final downloadUrl =
          '$_downloadsBase/$candidateVersion/targets/$target/$imageName';

      String? modelTitle;
      if (matchedProfile['titles'] is List &&
          (matchedProfile['titles'] as List).isNotEmpty) {
        final titleObj = (matchedProfile['titles'] as List).first;
        if (titleObj is Map) {
          final vendor = titleObj['vendor']?.toString() ?? '';
          final model = titleObj['model']?.toString() ?? '';
          final variant = titleObj['variant']?.toString() ?? '';
          modelTitle = '$vendor $model $variant'.trim();
        }
      }
      modelTitle ??= matchedProfileKey ?? scan.modelName.value;

      return FirmwareUpgradeAvailability(
        status: UpgradeAvailabilityStatus.upgradeAvailable,
        currentVersion: rawCurrent,
        latestVersion: candidateVersion,
        channelDescription: 'OpenWrt',
        downloadUrl: downloadUrl,
        sha256: sha256,
        imageSizeBytes: size,
        imageName: imageName,
        modelTitle: modelTitle,
        explanation:
            'A new official OpenWrt release ($candidateVersion) is available '
            'for your device ($modelTitle).',
      );
    } catch (e, stack) {
      Logger.error('FirmwareUpgradeChecker error checking OpenWrt: $e', stack);
      return FirmwareUpgradeAvailability(
        status: UpgradeAvailabilityStatus.updateSourceUnavailable,
        currentVersion: rawCurrent,
        channelDescription: 'OpenWrt',
        explanation:
            'Unable to complete upgrade check: $e. Check your internet '
            'connection or verify manually at https://downloads.openwrt.org/.',
      );
    }
  }

  /// Extracts the major/minor release branch (e.g. '25.12' from '25.12.1' or '24.10.8').
  static String? _extractBranch(String version) {
    final parts = version.split('.');
    if (parts.length >= 2) {
      return '${parts[0]}.${parts[1]}';
    }
    return null;
  }

  /// Compares two version strings (e.g. '25.12.6' and '25.12.1').
  /// Returns 1 if a > b, -1 if a < b, and 0 if equal.
  static int compareVersions(String a, String b) {
    String clean(String v) => v
        .replaceAll(RegExp(r'^(v|OpenWrt\s*)', caseSensitive: false), '')
        .split(RegExp(r'[\s\+]'))
        .first
        .trim();

    final cleanA = clean(a);
    final cleanB = clean(b);

    if (cleanA == cleanB) return 0;

    final partsA = _parseVersion(cleanA);
    final partsB = _parseVersion(cleanB);

    final maxLen = partsA.numbers.length > partsB.numbers.length
        ? partsA.numbers.length
        : partsB.numbers.length;

    for (int i = 0; i < maxLen; i++) {
      final numA = i < partsA.numbers.length ? partsA.numbers[i] : 0;
      final numB = i < partsB.numbers.length ? partsB.numbers[i] : 0;
      if (numA != numB) {
        return numA.compareTo(numB);
      }
    }

    // Handle pre-releases: non-prerelease is newer than prerelease
    if (partsA.prerelease == null && partsB.prerelease != null) return 1;
    if (partsA.prerelease != null && partsB.prerelease == null) return -1;
    if (partsA.prerelease != null && partsB.prerelease != null) {
      return partsA.prerelease!.compareTo(partsB.prerelease!);
    }

    return 0;
  }

  static _ParsedVersion _parseVersion(String v) {
    final dashIdx = v.indexOf('-');
    String mainPart = v;
    String? prerelease;

    if (dashIdx != -1) {
      mainPart = v.substring(0, dashIdx);
      prerelease = v.substring(dashIdx + 1);
    }

    final numbers = mainPart
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();

    return _ParsedVersion(numbers, prerelease);
  }
}

class _ParsedVersion {
  final List<int> numbers;
  final String? prerelease;

  const _ParsedVersion(this.numbers, this.prerelease);
}
