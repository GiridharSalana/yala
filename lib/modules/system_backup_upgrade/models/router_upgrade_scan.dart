// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

/// Confidence level of a detected value or check result.
enum DetectionConfidence {
  /// Value was read from a well-known authoritative source and parsed
  /// successfully.
  verified,

  /// Value is inferred or partially confirmed.
  likely,

  /// Value depends on firmware/platform behavior that was not fully verifiable.
  conditional,

  /// Could not determine; source was unavailable, empty, or failed.
  unknown,
}

/// The active package manager environment on the router.
enum RouterPackageManager { opkg, apk, mixed, vendorSpecific, none, unknown }

/// Detected firmware distribution family.
enum FirmwareFamily { openWrt, immortalWrt, glINet, gargoyle, lede, unknown }

/// Represents a detected value with its confidence level and source.
class DetectedValue<T> {
  final T? value;
  final DetectionConfidence confidence;
  final String? source;

  const DetectedValue({
    required this.value,
    required this.confidence,
    this.source,
  });

  /// Returns a [DetectedValue] representing a successfully read value.
  const DetectedValue.verified(this.value, {this.source})
    : confidence = DetectionConfidence.verified;

  /// Returns a [DetectedValue] representing a value that could not be obtained.
  const DetectedValue.unknown({this.source})
    : value = null,
      confidence = DetectionConfidence.unknown;

  /// Returns a [DetectedValue] representing a likely (inferred) value.
  const DetectedValue.likely(this.value, {this.source})
    : confidence = DetectionConfidence.likely;

  bool get isKnown =>
      confidence != DetectionConfidence.unknown && value != null;
  bool get isUnknown => !isKnown;

  @override
  String toString() => 'DetectedValue($value, $confidence, src=$source)';
}

/// Scan result for a single router, collecting all upgrade-relevant information.
///
/// Every field uses [DetectedValue] so that callers can distinguish verified
/// data from unknown/failed detection and never substitute fabricated defaults.
class RouterUpgradeScan {
  /// The router IP address this scan applies to.
  final String routerId;

  /// When this scan was completed.
  final DateTime scannedAt;

  /// Whether the scan was only partially completed (some probes failed).
  final bool isPartial;

  /// Human-readable description of any scan failures.
  final String? partialScanReason;

  // ── Hardware identity ──────────────────────────────────────────────────────

  /// Human-readable model name (e.g. "GL.iNet GL-AX1800").
  final DetectedValue<String> modelName;

  /// Board name / compatibility identifier (e.g. "glinet,gl-ax1800").
  final DetectedValue<String> boardName;

  // ── Firmware identity ──────────────────────────────────────────────────────

  /// Detected firmware family/distribution.
  final DetectedValue<FirmwareFamily> firmwareFamily;

  /// Distribution-specific label (e.g. "GL.iNet Firmware 4.7.0").
  final DetectedValue<String> firmwareFamilyLabel;

  /// DISTRIB_DESCRIPTION from /etc/openwrt_release.
  final DetectedValue<String> distribDescription;

  /// DISTRIB_RELEASE (e.g. "23.05.5").
  final DetectedValue<String> distribRelease;

  /// DISTRIB_TARGET (e.g. "mediatek/filogic").
  final DetectedValue<String> distribTarget;

  /// DISTRIB_ARCH (e.g. "aarch64_cortex-a53").
  final DetectedValue<String> distribArch;

  // ── System resources ───────────────────────────────────────────────────────

  /// /tmp available space in bytes.
  final DetectedValue<int> tmpAvailableBytes;

  /// /tmp total space in bytes.
  final DetectedValue<int> tmpTotalBytes;

  // ── Package manager ────────────────────────────────────────────────────────

  /// Detected package manager type.
  final DetectedValue<RouterPackageManager> packageManager;

  // ── Sysupgrade capabilities ────────────────────────────────────────────────

  /// Whether sysupgrade is available on the router.
  final DetectedValue<bool> hasSysupgrade;

  /// Whether sysupgrade -l (backup list) is supported.
  final DetectedValue<bool> hasSysupgradeList;

  /// Whether sysupgrade -b (backup) is supported.
  final DetectedValue<bool> hasSysupgradeBackup;

  /// Whether sysupgrade -t (test image) is supported.
  final DetectedValue<bool> hasSysupgradeTest;

  /// Whether sysupgrade -F (force) is supported.
  final DetectedValue<bool> hasSysupgradeForce;

  // ── Preserved file list ────────────────────────────────────────────────────

  /// Output of sysupgrade -l (list of files that will be preserved).
  final DetectedValue<List<String>> sysupgradePreservedFiles;

  /// Content of /etc/sysupgrade.conf (custom preserve paths).
  final DetectedValue<String> sysupgradeConf;

  const RouterUpgradeScan({
    required this.routerId,
    required this.scannedAt,
    this.isPartial = false,
    this.partialScanReason,
    required this.modelName,
    required this.boardName,
    required this.firmwareFamily,
    required this.firmwareFamilyLabel,
    required this.distribDescription,
    required this.distribRelease,
    required this.distribTarget,
    required this.distribArch,
    required this.tmpAvailableBytes,
    required this.tmpTotalBytes,
    required this.packageManager,
    required this.hasSysupgrade,
    required this.hasSysupgradeList,
    required this.hasSysupgradeBackup,
    required this.hasSysupgradeTest,
    required this.hasSysupgradeForce,
    required this.sysupgradePreservedFiles,
    required this.sysupgradeConf,
  });

  /// Returns an empty scan representing a completely failed probe.
  factory RouterUpgradeScan.failed(String routerId, {String? reason}) {
    return RouterUpgradeScan(
      routerId: routerId,
      scannedAt: DateTime.now(),
      isPartial: true,
      partialScanReason: reason ?? 'Router scan failed',
      modelName: const DetectedValue.unknown(),
      boardName: const DetectedValue.unknown(),
      firmwareFamily: const DetectedValue.unknown(),
      firmwareFamilyLabel: const DetectedValue.unknown(),
      distribDescription: const DetectedValue.unknown(),
      distribRelease: const DetectedValue.unknown(),
      distribTarget: const DetectedValue.unknown(),
      distribArch: const DetectedValue.unknown(),
      tmpAvailableBytes: const DetectedValue.unknown(),
      tmpTotalBytes: const DetectedValue.unknown(),
      packageManager: const DetectedValue.unknown(),
      hasSysupgrade: const DetectedValue.unknown(),
      hasSysupgradeList: const DetectedValue.unknown(),
      hasSysupgradeBackup: const DetectedValue.unknown(),
      hasSysupgradeTest: const DetectedValue.unknown(),
      hasSysupgradeForce: const DetectedValue.unknown(),
      sysupgradePreservedFiles: const DetectedValue.unknown(),
      sysupgradeConf: const DetectedValue.unknown(),
    );
  }

  /// Whether the scan data is considered fresh (less than 5 minutes old).
  bool get isFresh =>
      DateTime.now().difference(scannedAt) < const Duration(minutes: 5);

  /// Whether the scan data is stale and should be refreshed before a
  /// consequential operation.
  bool get isStale => !isFresh;

  /// Human-readable /tmp space summary.
  String get tmpSpaceLabel {
    final avail = tmpAvailableBytes.value;
    if (avail == null) return 'Unknown';
    if (avail >= 1024 * 1024) {
      return '${(avail / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(avail / 1024).toStringAsFixed(0)} KB';
  }
}
