// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/router_upgrade_scan.dart';
import '../models/upgrade_models.dart';

/// Builds a structured [UpgradeReadinessReport] for a planned sysupgrade
/// operation, given a router scan and the selected firmware image properties.
class UpgradeReadinessAssessor {
  const UpgradeReadinessAssessor();

  /// Assess readiness for a planned flash operation.
  ///
  /// [scan] — the most recent router scan. A stale or partial scan increases
  /// the number of [ReadinessCheckSeverity.unknown] checks.
  ///
  /// [imageFileName] — the filename of the selected firmware image.
  /// [imageSizeBytes] — the raw byte size of the selected image.
  /// [imageValidation] — the result of the sysupgrade -t check (or notRun).
  /// [keepSettings] — whether the user intends to preserve settings (-k).
  /// [forceUpgrade] — whether the user enabled force mode (-F).
  /// [backupWasGenerated] — whether a fresh backup was downloaded.
  UpgradeReadinessReport assess({
    required RouterUpgradeScan scan,
    required String? imageFileName,
    required int? imageSizeBytes,
    required FirmwareImageValidationResult imageValidation,
    required bool keepSettings,
    required bool forceUpgrade,
    required bool backupWasGenerated,
  }) {
    final checks = <ReadinessCheckItem>[];

    // ── Check 1: Scan freshness ──────────────────────────────────────────────
    if (scan.isStale) {
      checks.add(
        const ReadinessCheckItem(
          id: 'scan_stale',
          title: 'Router scan data is outdated',
          description:
              'The router information was collected more than 5 minutes ago. '
              'Refresh the scan before flashing to ensure the reported resources '
              'and configuration are current.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    }
    if (scan.isPartial) {
      checks.add(
        ReadinessCheckItem(
          id: 'scan_partial',
          title: 'Router scan was incomplete',
          description:
              'Some probes failed during router scan: ${scan.partialScanReason ?? 'unknown reason'}. '
              'Compatibility assessment may be inaccurate.',
          severity: ReadinessCheckSeverity.warning,
          detail: scan.partialScanReason,
        ),
      );
    }

    // ── Check 2: Image selected ──────────────────────────────────────────────
    if (imageFileName == null || imageSizeBytes == null) {
      checks.add(
        const ReadinessCheckItem(
          id: 'no_image_selected',
          title: 'No firmware image selected',
          description:
              'Select a sysupgrade-compatible firmware image before proceeding.',
          severity: ReadinessCheckSeverity.blocking,
        ),
      );
    } else {
      checks.add(
        ReadinessCheckItem(
          id: 'image_selected',
          title: 'Firmware image selected',
          description:
              'Image selected: $imageFileName '
              '(${_formatBytes(imageSizeBytes)})',
          severity: ReadinessCheckSeverity.info,
        ),
      );
    }

    // ── Check 3: Image validation ─────────────────────────────────────────────
    if (imageValidation.status == ImageValidationStatus.notRun) {
      checks.add(
        const ReadinessCheckItem(
          id: 'validation_not_run',
          title: 'Image compatibility test not run',
          description:
              'sysupgrade -t has not been run. Proceed with caution — '
              'an incompatible image can render the router unbootable.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else if (imageValidation.status == ImageValidationStatus.passed) {
      checks.add(
        ReadinessCheckItem(
          id: 'validation_passed',
          title: 'Image compatibility test passed',
          description: 'sysupgrade -t reported a valid image (exit code 0).',
          severity: ReadinessCheckSeverity.info,
          detail: imageValidation.commandOutput,
        ),
      );
    } else if (imageValidation.status == ImageValidationStatus.failed) {
      if (forceUpgrade && imageValidation.forceApplied) {
        checks.add(
          ReadinessCheckItem(
            id: 'validation_failed_forced',
            title: 'Image validation FAILED — force override active',
            description:
                'sysupgrade -t indicated an incompatible or invalid image, '
                'but the force upgrade option (-F) is enabled. '
                'Flashing an incompatible image may permanently damage the device.',
            severity: ReadinessCheckSeverity.warning,
            detail: imageValidation.commandOutput,
            canForce: true,
          ),
        );
      } else {
        checks.add(
          ReadinessCheckItem(
            id: 'validation_failed',
            title: 'Image compatibility test FAILED',
            description:
                'sysupgrade -t reported this image as incompatible or invalid. '
                'Do not flash this image. Verify you have the correct '
                'sysupgrade image for your router model and board.',
            severity: ReadinessCheckSeverity.blocking,
            detail: imageValidation.commandOutput,
            canForce: true,
          ),
        );
      }
    } else if (imageValidation.status == ImageValidationStatus.inconclusive) {
      checks.add(
        ReadinessCheckItem(
          id: 'validation_inconclusive',
          title: 'Image compatibility test result is inconclusive',
          description:
              'sysupgrade -t was executed but the exit code could not be '
              'reliably obtained. The image may or may not be compatible. '
              'Proceed only if you have verified compatibility through other means.',
          severity: ReadinessCheckSeverity.warning,
          detail: imageValidation.commandOutput,
        ),
      );
    } else if (imageValidation.status == ImageValidationStatus.unsupported) {
      checks.add(
        const ReadinessCheckItem(
          id: 'validation_unsupported',
          title: 'Image compatibility test not supported',
          description:
              'sysupgrade -t is not available on this router. '
              'Compatibility cannot be verified automatically. '
              'Manually verify the image is correct for your router model and board.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    }

    // ── Check 4: /tmp free space ─────────────────────────────────────────────
    if (scan.tmpAvailableBytes.isUnknown) {
      checks.add(
        const ReadinessCheckItem(
          id: 'tmp_space_unknown',
          title: '/tmp available space unknown',
          description:
              'Available space in /tmp (where the firmware image is stored '
              'before flashing) could not be determined. Ensure there is '
              'sufficient free space before proceeding.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else if (imageSizeBytes != null) {
      final available = scan.tmpAvailableBytes.value!;
      // Require image size + 2 MB headroom
      final required = imageSizeBytes + 2 * 1024 * 1024;
      if (available < required) {
        checks.add(
          ReadinessCheckItem(
            id: 'tmp_insufficient',
            title: 'Insufficient /tmp space for firmware upload',
            description:
                'The image requires ${_formatBytes(imageSizeBytes)} plus '
                '2 MB headroom. Only ${_formatBytes(available)} is available '
                'in /tmp. Free space or use a different router with more RAM.',
            severity: ReadinessCheckSeverity.blocking,
            detail:
                'Available: ${_formatBytes(available)}, '
                'Required: ${_formatBytes(required)}',
          ),
        );
      } else {
        checks.add(
          ReadinessCheckItem(
            id: 'tmp_space_ok',
            title: '/tmp has sufficient space',
            description:
                'Available: ${_formatBytes(available)} — '
                'sufficient for the selected image (${_formatBytes(imageSizeBytes)}).',
            severity: ReadinessCheckSeverity.info,
          ),
        );
      }
    }

    // ── Check 5: sysupgrade availability ─────────────────────────────────────
    if (scan.hasSysupgrade.isUnknown) {
      checks.add(
        const ReadinessCheckItem(
          id: 'sysupgrade_unknown',
          title: 'sysupgrade availability unknown',
          description:
              'Could not determine whether sysupgrade is available on this router.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else if (scan.hasSysupgrade.value == false) {
      checks.add(
        const ReadinessCheckItem(
          id: 'sysupgrade_unavailable',
          title: 'sysupgrade not available',
          description:
              'sysupgrade was not detected on this router. '
              'Firmware flashing via this method is not supported.',
          severity: ReadinessCheckSeverity.blocking,
        ),
      );
    }

    // ── Check 6: Backup status ────────────────────────────────────────────────
    if (!backupWasGenerated) {
      checks.add(
        const ReadinessCheckItem(
          id: 'no_backup',
          title: 'No configuration backup generated',
          description:
              'A configuration backup has not been downloaded in this session. '
              'If settings are lost after flashing, there will be no backup to '
              'restore from. Generate a backup before flashing.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else {
      checks.add(
        const ReadinessCheckItem(
          id: 'backup_generated',
          title: 'Configuration backup has been downloaded',
          description:
              'A configuration backup was downloaded in this session. '
              'Keep it in a safe location for recovery.',
          severity: ReadinessCheckSeverity.info,
        ),
      );
    }

    // ── Check 7: Settings preservation ───────────────────────────────────────
    if (keepSettings) {
      checks.add(
        const ReadinessCheckItem(
          id: 'keep_settings_on',
          title: 'Settings preservation enabled (-k)',
          description:
              'Network, Wi-Fi, and user configuration will be retained '
              'during upgrade. Note: preserved settings may not be fully '
              'compatible across major firmware releases or distribution changes.',
          severity: ReadinessCheckSeverity.info,
        ),
      );
    } else {
      checks.add(
        const ReadinessCheckItem(
          id: 'keep_settings_off',
          title: 'Settings preservation disabled (clean install)',
          description:
              'All configuration will be erased. The router will return to '
              'firmware defaults after flashing. Ensure you have a backup '
              'or can reconfigure the router manually.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    }

    // ── Check 8: Force override ───────────────────────────────────────────────
    if (forceUpgrade) {
      checks.add(
        const ReadinessCheckItem(
          id: 'force_upgrade',
          title: 'Force upgrade mode enabled (-F)',
          description:
              'Force mode bypasses board architecture validation and '
              'compatibility checks. This may cause the router to become '
              'unbootable if the image is incompatible. Enable this only '
              'if you are certain the image is correct for your hardware.',
          severity: ReadinessCheckSeverity.warning,
          canForce: true,
        ),
      );
    }

    // ── Check 9: Board identity ───────────────────────────────────────────────
    if (scan.boardName.isUnknown) {
      checks.add(
        const ReadinessCheckItem(
          id: 'board_unknown',
          title: 'Router board identity unknown',
          description:
              'The router\'s board name could not be detected. '
              'This means compatibility between the selected image and the '
              'actual hardware cannot be verified.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else {
      checks.add(
        ReadinessCheckItem(
          id: 'board_known',
          title: 'Router board identified',
          description:
              'Board: ${scan.boardName.value} (${scan.boardName.confidence.name})',
          severity: ReadinessCheckSeverity.info,
        ),
      );
    }

    // ── Check 10: Power/connection warning ────────────────────────────────────
    checks.add(
      const ReadinessCheckItem(
        id: 'power_warning',
        title: 'Do not interrupt power or connectivity during flash',
        description:
            'Disconnecting power, Ethernet, or the app during firmware '
            'writing can permanently damage the router. Ensure the router '
            'is on a stable power source before proceeding.',
        severity: ReadinessCheckSeverity.info,
      ),
    );

    // ── Check 11: sysupgrade -t support for validation ────────────────────────
    if (scan.hasSysupgradeTest.value == false) {
      checks.add(
        const ReadinessCheckItem(
          id: 'sysupgrade_test_unsupported',
          title: 'Image pre-validation (sysupgrade -t) not supported',
          description:
              'This router does not support the sysupgrade -t compatibility '
              'test. Image compatibility cannot be verified before flashing.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    }

    return UpgradeReadinessReport(
      checks: checks,
      basedOnStaleData: scan.isStale,
      isPartial: scan.isPartial,
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}
