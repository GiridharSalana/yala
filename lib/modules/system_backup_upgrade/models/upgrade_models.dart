// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'router_upgrade_scan.dart';

/// Validation state for a firmware image against the detected router.
enum ImageValidationStatus {
  /// Image passed the router's sysupgrade -t check (non-zero exit = failed,
  /// zero exit = passed; exit status was reliably obtained).
  passed,

  /// sysupgrade -t returned a non-zero exit code or emitted error output.
  failed,

  /// The check ran but the result is inconclusive (e.g., exit status could
  /// not be reliably obtained from the command execution layer).
  inconclusive,

  /// The router does not support sysupgrade -t.
  unsupported,

  /// The check has not been run yet.
  notRun,
}

/// Severity level for an upgrade readiness check item.
enum ReadinessCheckSeverity {
  /// Blocks the normal upgrade path. Must be resolved or explicitly overridden
  /// via a supported force option with documented consequences.
  blocking,

  /// Important concern that should be acknowledged but does not block.
  warning,

  /// Informational only.
  info,

  /// Could not be verified; neither pass nor fail is known.
  unknown,
}

/// A single check in the upgrade readiness report.
class ReadinessCheckItem {
  final String id;
  final String title;
  final String description;
  final ReadinessCheckSeverity severity;

  /// Optional human-readable detail about the detection method or result.
  final String? detail;

  /// Whether this check can be overridden by a force flag.
  final bool canForce;

  const ReadinessCheckItem({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    this.detail,
    this.canForce = false,
  });

  bool get isBlocking => severity == ReadinessCheckSeverity.blocking;
  bool get isWarning => severity == ReadinessCheckSeverity.warning;
  bool get isInfo => severity == ReadinessCheckSeverity.info;
  bool get isUnknown => severity == ReadinessCheckSeverity.unknown;
}

/// Result of the complete upgrade readiness assessment.
class UpgradeReadinessReport {
  final List<ReadinessCheckItem> checks;

  /// Whether the scan used to generate this report is stale.
  final bool basedOnStaleData;

  /// Whether the report is based on a partial scan.
  final bool isPartial;

  const UpgradeReadinessReport({
    required this.checks,
    this.basedOnStaleData = false,
    this.isPartial = false,
  });

  List<ReadinessCheckItem> get blocking =>
      checks.where((c) => c.isBlocking).toList();
  List<ReadinessCheckItem> get warnings =>
      checks.where((c) => c.isWarning).toList();
  List<ReadinessCheckItem> get infos => checks.where((c) => c.isInfo).toList();
  List<ReadinessCheckItem> get unknowns =>
      checks.where((c) => c.isUnknown).toList();

  bool get hasBlockingIssues => blocking.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  int get blockingCount => blocking.length;
  int get warningCount => warnings.length;
  bool get hasForcibleBlockers =>
      blocking.any((c) => c.canForce) && !blocking.any((c) => !c.canForce);

  int get passCount =>
      checks.where((c) => c.severity == ReadinessCheckSeverity.info).length;
}

/// Category of a preservation impact item.
enum PreservationCategory {
  configuration,
  credentials,
  customScript,
  installedPackage,
  runtimeData,
  externalStorage,
  hardwareCalibration,
  luciExtension,
  kernelModule,
  vpnCredential,
  unknown,
}

/// Expected outcome for a preserved item during upgrade.
enum PreservationOutcome {
  /// Will be included in the sysupgrade backup and restored.
  preserved,

  /// Will NOT be included; data is lost unless manually backed up.
  lost,

  /// May or may not be preserved depending on firmware behavior.
  conditional,

  /// Cannot be determined from available information.
  unknown,
}

/// A single item in the preservation impact inventory.
class PreservationImpactItem {
  final String path;
  final PreservationCategory category;
  final String? description;

  /// How this item was detected (e.g. "sysupgrade -l output", "file.stat").
  final String detectionSource;

  final PreservationOutcome outcome;
  final DetectionConfidence confidence;

  /// Recommended action before flashing (null = no action required).
  final String? recommendedAction;

  /// Whether this item is already covered by the current backup.
  final bool coveredByBackup;

  /// Whether this item contains potentially sensitive data. If true,
  /// its value must not be logged or displayed.
  final bool isSensitive;

  const PreservationImpactItem({
    required this.path,
    required this.category,
    this.description,
    required this.detectionSource,
    required this.outcome,
    required this.confidence,
    this.recommendedAction,
    this.coveredByBackup = false,
    this.isSensitive = false,
  });
}

/// Full preservation and upgrade-impact inventory.
class PreservationImpactInventory {
  final List<PreservationImpactItem> items;

  /// Whether this inventory was built from a partial scan.
  final bool isPartial;

  /// Description of any limitations in the scan.
  final String? limitationNote;

  const PreservationImpactInventory({
    required this.items,
    this.isPartial = false,
    this.limitationNote,
  });

  List<PreservationImpactItem> get preserved =>
      items.where((i) => i.outcome == PreservationOutcome.preserved).toList();

  List<PreservationImpactItem> get lost =>
      items.where((i) => i.outcome == PreservationOutcome.lost).toList();

  List<PreservationImpactItem> get conditional =>
      items.where((i) => i.outcome == PreservationOutcome.conditional).toList();

  List<PreservationImpactItem> get unknown =>
      items.where((i) => i.outcome == PreservationOutcome.unknown).toList();

  List<PreservationImpactItem> get needsAction =>
      items.where((i) => i.recommendedAction != null).toList();
}

/// OPKG-to-APK migration classification.
enum PackageMigrationTransition {
  opkgToOpkg,
  apkToApk,
  opkgToApk,
  apkToOpkg,
  mixedOrVendor,
  unknown,
}

/// Classification of an installed package against the target environment.
enum PackageMigrationStatus {
  /// A confirmed equivalent package exists in the target ecosystem.
  confirmed,

  /// A possible equivalent was found but requires manual confirmation.
  possibleEquivalent,

  /// No matching package found in the checked target source.
  noEquivalentFound,

  /// This is a kernel module that requires target-specific rebuild/reinstall.
  kernelModuleRequiresTargetBuild,

  /// Third-party package with unverified feed.
  thirdPartyUnverified,

  /// Could not determine equivalency.
  unknown,
}

/// A single package in the migration analysis.
class PackageMigrationItem {
  final String packageName;
  final String? installedVersion;
  final PackageMigrationStatus migrationStatus;
  final String? targetEquivalentName;
  final String? note;
  final bool isKernelModule;
  final bool isLuciExtension;
  final bool isThirdParty;

  const PackageMigrationItem({
    required this.packageName,
    this.installedVersion,
    required this.migrationStatus,
    this.targetEquivalentName,
    this.note,
    this.isKernelModule = false,
    this.isLuciExtension = false,
    this.isThirdParty = false,
  });
}

/// Full package migration analysis for an upgrade.
class PackageMigrationAnalysis {
  final PackageMigrationTransition transition;
  final List<PackageMigrationItem> packages;

  /// Whether the target package manager could be determined.
  final bool targetPackageManagerKnown;

  /// Whether a trusted target package index was consulted.
  final bool targetIndexConsulted;

  /// Explanation if the target index was not consulted.
  final String? targetIndexUnavailableReason;

  const PackageMigrationAnalysis({
    required this.transition,
    required this.packages,
    this.targetPackageManagerKnown = false,
    this.targetIndexConsulted = false,
    this.targetIndexUnavailableReason,
  });

  bool get isOpkgToApkTransition =>
      transition == PackageMigrationTransition.opkgToApk;

  /// Convenience alias so UI can use `.items` or `.packages`.
  List<PackageMigrationItem> get items => packages;

  /// Human-readable summary of the migration transition.
  String get summary {
    switch (transition) {
      case PackageMigrationTransition.opkgToApk:
        return 'The target firmware uses APK instead of OPKG. '
            'Installed OPKG packages will not carry over automatically. '
            'Review the list below and reinstall via APK after upgrade.';
      case PackageMigrationTransition.apkToOpkg:
        return 'The target firmware uses OPKG instead of APK. '
            'Installed APK packages will not carry over automatically. '
            'Review the list below and reinstall via OPKG after upgrade.';
      case PackageMigrationTransition.opkgToOpkg:
        return 'Both current and target firmware use OPKG. '
            'Installed packages will need to be reinstalled from the OPKG feed after upgrade.';
      case PackageMigrationTransition.apkToApk:
        return 'Both current and target firmware use APK. '
            'Installed packages will need to be reinstalled from the APK feed after upgrade.';
      case PackageMigrationTransition.mixedOrVendor:
        return 'Mixed or vendor-specific package environment detected. '
            'Package migration requires manual assessment.';
      case PackageMigrationTransition.unknown:
        return 'Target package manager is unknown. '
            'Package migration status cannot be assessed automatically.';
    }
  }

  List<PackageMigrationItem> get confirmed => packages
      .where((p) => p.migrationStatus == PackageMigrationStatus.confirmed)
      .toList();

  List<PackageMigrationItem> get needsAttention => packages
      .where((p) => p.migrationStatus != PackageMigrationStatus.confirmed)
      .toList();

  List<PackageMigrationItem> get kernelModules =>
      packages.where((p) => p.isKernelModule).toList();
}

/// The full state of the firmware upload/flash lifecycle.
enum UpgradeOperationPhase {
  idle,
  preparing,
  generatingBackup,
  uploadingFirmware,
  verifyingUpload,
  validatingImage,
  awaitingConfirmation,
  flashCommandSubmitted,
  flashAcceptedByRouter,
  routerBecomingUnavailable,
  waitingForReboot,
  reconnecting,
  reconnected,
  postUpgradeVerification,
  completed,
  failed,
  outcomeUnknown,
}

/// Result of the post-upgrade verification scan.
class PostUpgradeVerificationResult {
  final bool routerResponded;
  final DetectedValue<String> detectedFirmwareVersion;
  final DetectedValue<String> detectedBoardName;
  final bool versionMatchesExpected;
  final String? expectedVersion;
  final String? verificationNote;

  const PostUpgradeVerificationResult({
    required this.routerResponded,
    required this.detectedFirmwareVersion,
    required this.detectedBoardName,
    required this.versionMatchesExpected,
    this.expectedVersion,
    this.verificationNote,
  });
}

/// Result of an image validation check.
class FirmwareImageValidationResult {
  final ImageValidationStatus status;

  /// Raw stdout from sysupgrade -t (may contain relevant diagnostic info).
  final String? commandOutput;

  /// Whether a force flag was explicitly applied.
  final bool forceApplied;

  /// Description of what was bypassed by forcing.
  final String? forceExplanation;

  const FirmwareImageValidationResult({
    required this.status,
    this.commandOutput,
    this.forceApplied = false,
    this.forceExplanation,
  });

  bool get passed => status == ImageValidationStatus.passed;
  bool get failed => status == ImageValidationStatus.failed;
  bool get isInconclusive => status == ImageValidationStatus.inconclusive;
  bool get isUnsupported => status == ImageValidationStatus.unsupported;
  bool get wasRun => status != ImageValidationStatus.notRun;

  /// Whether the overall result is acceptable for proceeding with flash.
  /// A passed result or an inconclusive result (with user acknowledgement)
  /// is acceptable. A failed result is not, even with force (unless forceApplied).
  bool get isAcceptableForFlash =>
      status == ImageValidationStatus.passed ||
      status == ImageValidationStatus.inconclusive ||
      status == ImageValidationStatus.unsupported ||
      (status == ImageValidationStatus.failed && forceApplied);
}

/// Firmware upgrade availability check result.
enum UpgradeAvailabilityStatus {
  /// A verified compatible upgrade is available.
  upgradeAvailable,

  /// The installed version appears to be current.
  currentVersionLatest,

  /// Could not find a matching image for this device.
  noMatchingImageFound,

  /// The update source is unavailable.
  updateSourceUnavailable,

  /// Compatibility could not be verified.
  compatibilityUnverifiable,

  /// The installed version could not be determined.
  currentVersionUnknown,

  /// This device uses a firmware source not supported by automated checking.
  unsupportedFirmwareSource,

  /// Check has not been run.
  notChecked,
}

/// Result of a firmware upgrade availability check.
class FirmwareUpgradeAvailability {
  final UpgradeAvailabilityStatus status;

  /// The latest release version string if found.
  final String? latestVersion;

  /// The currently installed version.
  final String? currentVersion;

  /// Description of the release channel or firmware distribution.
  final String? channelDescription;

  /// Human-readable explanation of why this status was determined.
  final String? explanation;

  /// Direct download URL for the sysupgrade image.
  final String? downloadUrl;

  /// SHA-256 checksum of the sysupgrade image.
  final String? sha256;

  /// Size of the sysupgrade image in bytes.
  final int? imageSizeBytes;

  /// Filename of the sysupgrade image.
  final String? imageName;

  /// Human-readable model or title of the matched device profile.
  final String? modelTitle;

  const FirmwareUpgradeAvailability({
    required this.status,
    this.latestVersion,
    this.currentVersion,
    this.channelDescription,
    this.explanation,
    this.downloadUrl,
    this.sha256,
    this.imageSizeBytes,
    this.imageName,
    this.modelTitle,
  });

  bool get isUpgradeAvailable =>
      status == UpgradeAvailabilityStatus.upgradeAvailable;
  bool get isCurrent =>
      status == UpgradeAvailabilityStatus.currentVersionLatest;

  /// Formatted image size in megabytes (e.g. "7.25 MB").
  String? get formattedImageSize {
    if (imageSizeBytes == null) return null;
    return '${(imageSizeBytes! / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
