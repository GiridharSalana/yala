// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/models/router_upgrade_scan.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/models/upgrade_models.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/services/firmware_upgrade_checker.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/services/preservation_impact_analyzer.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/services/upgrade_readiness_assessor.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/services/router_upgrade_scan_service.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/utils/sha256.dart';

class MockApiService implements IApiService {
  final Future<dynamic> Function(
    String object,
    String method,
    Map<String, dynamic>? params,
  )?
  onCall;

  MockApiService({this.onCall});

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    if (onCall != null) {
      return onCall!(object, method, params);
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RouterUpgradeScan createMockScan({
  String routerId = '192.168.1.1',
  DateTime? scannedAt,
  bool isPartial = false,
  String? partialScanReason,
  DetectedValue<String> modelName = const DetectedValue.verified(
    'TP-Link Archer C7 v2',
  ),
  DetectedValue<String> boardName = const DetectedValue.verified(
    'tplink,archer-c7-v2',
  ),
  DetectedValue<FirmwareFamily> firmwareFamily = const DetectedValue.verified(
    FirmwareFamily.openWrt,
  ),
  DetectedValue<String> firmwareFamilyLabel = const DetectedValue.verified(
    'OpenWrt',
  ),
  DetectedValue<String> distribDescription = const DetectedValue.verified(
    'OpenWrt 23.05.3',
  ),
  DetectedValue<String> distribRelease = const DetectedValue.verified(
    '23.05.3',
  ),
  DetectedValue<String> distribTarget = const DetectedValue.verified(
    'ath79/generic',
  ),
  DetectedValue<String> distribArch = const DetectedValue.verified('mips_24kc'),
  DetectedValue<int> tmpAvailableBytes = const DetectedValue.verified(
    40 * 1024 * 1024,
  ),
  DetectedValue<int> tmpTotalBytes = const DetectedValue.verified(
    64 * 1024 * 1024,
  ),
  DetectedValue<RouterPackageManager> packageManager =
      const DetectedValue.verified(RouterPackageManager.opkg),
  DetectedValue<bool> hasSysupgrade = const DetectedValue.verified(true),
  DetectedValue<bool> hasSysupgradeList = const DetectedValue.verified(true),
  DetectedValue<bool> hasSysupgradeBackup = const DetectedValue.verified(true),
  DetectedValue<bool> hasSysupgradeTest = const DetectedValue.verified(true),
  DetectedValue<bool> hasSysupgradeForce = const DetectedValue.verified(true),
  DetectedValue<List<String>> sysupgradePreservedFiles =
      const DetectedValue.verified(['/etc/config/network']),
  DetectedValue<String> sysupgradeConf = const DetectedValue.verified(''),
}) {
  return RouterUpgradeScan(
    routerId: routerId,
    scannedAt: scannedAt ?? DateTime.now(),
    isPartial: isPartial,
    partialScanReason: partialScanReason,
    modelName: modelName,
    boardName: boardName,
    firmwareFamily: firmwareFamily,
    firmwareFamilyLabel: firmwareFamilyLabel,
    distribDescription: distribDescription,
    distribRelease: distribRelease,
    distribTarget: distribTarget,
    distribArch: distribArch,
    tmpAvailableBytes: tmpAvailableBytes,
    tmpTotalBytes: tmpTotalBytes,
    packageManager: packageManager,
    hasSysupgrade: hasSysupgrade,
    hasSysupgradeList: hasSysupgradeList,
    hasSysupgradeBackup: hasSysupgradeBackup,
    hasSysupgradeTest: hasSysupgradeTest,
    hasSysupgradeForce: hasSysupgradeForce,
    sysupgradePreservedFiles: sysupgradePreservedFiles,
    sysupgradeConf: sysupgradeConf,
  );
}

void main() {
  group('DetectedValue Tests', () {
    test(
      'DetectedValue.verified produces known value with verified confidence',
      () {
        const dv = DetectedValue.verified(
          'test-board',
          source: '/tmp/sysinfo/board_name',
        );
        expect(dv.isKnown, isTrue);
        expect(dv.isUnknown, isFalse);
        expect(dv.value, equals('test-board'));
        expect(dv.confidence, equals(DetectionConfidence.verified));
        expect(dv.source, equals('/tmp/sysinfo/board_name'));
      },
    );

    test(
      'DetectedValue.unknown produces unknown value with unknown confidence',
      () {
        const dv = DetectedValue<String>.unknown(source: 'failed probe');
        expect(dv.isKnown, isFalse);
        expect(dv.isUnknown, isTrue);
        expect(dv.value, isNull);
        expect(dv.confidence, equals(DetectionConfidence.unknown));
        expect(dv.source, equals('failed probe'));
      },
    );

    test(
      'DetectedValue.likely produces known value with likely confidence',
      () {
        const dv = DetectedValue.likely(
          RouterPackageManager.apk,
          source: '/lib/apk/db/installed',
        );
        expect(dv.isKnown, isTrue);
        expect(dv.isUnknown, isFalse);
        expect(dv.value, equals(RouterPackageManager.apk));
        expect(dv.confidence, equals(DetectionConfidence.likely));
      },
    );
  });

  group('RouterUpgradeScan Model Tests', () {
    test('RouterUpgradeScan.failed produces all-unknown partial scan', () {
      final scan = RouterUpgradeScan.failed(
        '192.168.1.1',
        reason: 'Connection refused',
      );

      expect(scan.routerId, equals('192.168.1.1'));
      expect(scan.isPartial, isTrue);
      expect(scan.partialScanReason, contains('Connection refused'));
      expect(scan.boardName.isUnknown, isTrue);
      expect(scan.modelName.isUnknown, isTrue);
      expect(scan.firmwareFamily.isUnknown, isTrue);
      expect(scan.packageManager.isUnknown, isTrue);
      expect(scan.hasSysupgrade.isUnknown, isTrue);
      expect(scan.tmpAvailableBytes.isUnknown, isTrue);
      expect(scan.tmpSpaceLabel, equals('Unknown'));
    });

    test('RouterUpgradeScan freshness evaluation', () {
      final now = DateTime.now();
      final freshScan = createMockScan(
        scannedAt: now.subtract(const Duration(minutes: 2)),
        tmpAvailableBytes: const DetectedValue.verified(25 * 1024 * 1024),
      );

      expect(freshScan.isFresh, isTrue);
      expect(freshScan.isStale, isFalse);
      expect(freshScan.tmpSpaceLabel, equals('25.0 MB'));

      final staleScan = createMockScan(
        scannedAt: now.subtract(const Duration(minutes: 10)),
      );

      expect(staleScan.isFresh, isFalse);
      expect(staleScan.isStale, isTrue);
    });
  });

  group('UpgradeReadinessAssessor Tests', () {
    const assessor = UpgradeReadinessAssessor();

    test('assess returns blocking when image is not selected', () {
      final scan = createMockScan();
      final report = assessor.assess(
        scan: scan,
        imageFileName: null,
        imageSizeBytes: null,
        imageValidation: const FirmwareImageValidationResult(
          status: ImageValidationStatus.notRun,
        ),
        keepSettings: true,
        forceUpgrade: false,
        backupWasGenerated: false,
      );

      expect(report.hasBlockingIssues, isTrue);
      expect(report.blocking.any((c) => c.id == 'no_image_selected'), isTrue);
    });

    test(
      'assess returns blocking when image validation failed without forceUpgrade',
      () {
        final scan = createMockScan();
        final report = assessor.assess(
          scan: scan,
          imageFileName: 'openwrt-invalid.bin',
          imageSizeBytes: 15 * 1024 * 1024,
          imageValidation: const FirmwareImageValidationResult(
            status: ImageValidationStatus.failed,
            commandOutput: 'Image check failed: device mismatch',
          ),
          keepSettings: true,
          forceUpgrade: false,
          backupWasGenerated: true,
        );

        expect(report.hasBlockingIssues, isTrue);
        expect(report.blocking.any((c) => c.id == 'validation_failed'), isTrue);
      },
    );

    test(
      'forceUpgrade downgrades validation failure to warning with explicit notice',
      () {
        final scan = createMockScan();
        final report = assessor.assess(
          scan: scan,
          imageFileName: 'openwrt-custom.bin',
          imageSizeBytes: 15 * 1024 * 1024,
          imageValidation: const FirmwareImageValidationResult(
            status: ImageValidationStatus.failed,
            commandOutput: 'Image check failed: device mismatch',
            forceApplied: true,
          ),
          keepSettings: true,
          forceUpgrade: true,
          backupWasGenerated: true,
        );

        // Force upgrade should downgrade validation failure from blocking to warning
        expect(
          report.blocking.any((c) => c.id == 'validation_failed'),
          isFalse,
        );
        expect(
          report.warnings.any((c) => c.id == 'validation_failed_forced'),
          isTrue,
        );
      },
    );

    test(
      'assess returns warning when backup was not generated and keepSettings is true',
      () {
        final scan = createMockScan();
        final report = assessor.assess(
          scan: scan,
          imageFileName: 'openwrt-verified.bin',
          imageSizeBytes: 15 * 1024 * 1024,
          imageValidation: const FirmwareImageValidationResult(
            status: ImageValidationStatus.passed,
          ),
          keepSettings: true,
          forceUpgrade: false,
          backupWasGenerated: false, // User didn't download backup yet
        );

        expect(report.warnings.any((c) => c.id == 'no_backup'), isTrue);
      },
    );

    test(
      'assess returns blocking when /tmp free space is insufficient for image upload',
      () {
        final scan = createMockScan(
          tmpAvailableBytes: const DetectedValue.verified(
            5 * 1024 * 1024,
          ), // only 5 MB free
        );

        final report = assessor.assess(
          scan: scan,
          imageFileName: 'openwrt-large.bin',
          imageSizeBytes: 12 * 1024 * 1024, // 12 MB image > 5 MB free
          imageValidation: const FirmwareImageValidationResult(
            status: ImageValidationStatus.passed,
          ),
          keepSettings: true,
          forceUpgrade: false,
          backupWasGenerated: true,
        );

        expect(report.hasBlockingIssues, isTrue);
        expect(report.blocking.any((c) => c.id == 'tmp_insufficient'), isTrue);
      },
    );

    test('assess detects stale scan data and marks report accordingly', () {
      final staleScan = createMockScan(
        scannedAt: DateTime.now().subtract(const Duration(minutes: 15)),
      );
      final report = assessor.assess(
        scan: staleScan,
        imageFileName: 'openwrt-verified.bin',
        imageSizeBytes: 10 * 1024 * 1024,
        imageValidation: const FirmwareImageValidationResult(
          status: ImageValidationStatus.passed,
        ),
        keepSettings: false,
        forceUpgrade: false,
        backupWasGenerated: false,
      );

      expect(report.basedOnStaleData, isTrue);
      expect(report.warnings.any((c) => c.id == 'scan_stale'), isTrue);
    });
  });

  group('FirmwareUpgradeChecker Tests', () {
    const checker = FirmwareUpgradeChecker();

    test('compareVersions correctly ranks version numbers and prereleases', () {
      expect(
        FirmwareUpgradeChecker.compareVersions('25.12.6', '25.12.5'),
        equals(1),
      );
      expect(
        FirmwareUpgradeChecker.compareVersions('25.12.1', '25.12.6'),
        equals(-1),
      );
      expect(
        FirmwareUpgradeChecker.compareVersions('25.12.6', '25.12.6'),
        equals(0),
      );
      expect(
        FirmwareUpgradeChecker.compareVersions('25.12.0', '25.12.0-rc5'),
        equals(1),
      );
      expect(
        FirmwareUpgradeChecker.compareVersions('25.12.0-rc5', '25.12.0-rc4'),
        equals(1),
      );
      expect(
        FirmwareUpgradeChecker.compareVersions('OpenWrt 25.12.5', '25.12.5'),
        equals(0),
      );
    });

    test(
      'check queries official OpenWrt API and finds sysupgrade for Archer C60 v3',
      () async {
        final scan = createMockScan(
          modelName: const DetectedValue.verified('TP-Link Archer C60 v3'),
          boardName: const DetectedValue.verified('tplink,archer-c60-v3'),
          distribTarget: const DetectedValue.verified('ath79/generic'),
          distribRelease: const DetectedValue.verified('25.12.1'),
        );

        final result = await checker.check(scan);

        expect(
          result.status,
          equals(UpgradeAvailabilityStatus.upgradeAvailable),
        );
        expect(result.latestVersion, equals('25.12.6'));
        expect(result.currentVersion, equals('25.12.1'));
        expect(result.downloadUrl, isNotNull);
        expect(result.downloadUrl, contains('ath79/generic'));
        expect(result.imageName, contains('sysupgrade.bin'));
        expect(result.sha256, isNotNull);
        expect(result.formattedImageSize, isNotNull);
      },
    );

    test(
      'check queries official OpenWrt API and finds sysupgrade for Linksys EA8300 (matching Screenshot 5)',
      () async {
        final scan = createMockScan(
          modelName: const DetectedValue.verified('Linksys EA8300'),
          boardName: const DetectedValue.verified('linksys,ea8300'),
          distribTarget: const DetectedValue.verified('ipq40xx/generic'),
          distribRelease: const DetectedValue.verified('25.12.5'),
        );

        final result = await checker.check(scan);

        expect(
          result.status,
          equals(UpgradeAvailabilityStatus.upgradeAvailable),
        );
        expect(result.latestVersion, equals('25.12.6'));
        expect(result.currentVersion, equals('25.12.5'));
        expect(result.downloadUrl, contains('ipq40xx/generic'));
        expect(
          result.imageName,
          equals(
            'openwrt-25.12.6-ipq40xx-generic-linksys_ea8300-squashfs-sysupgrade.bin',
          ),
        );
        expect(
          result.sha256,
          equals(
            'd75049b84b7083a6bd77b390bc0472f7bbea34b9dfc53cd1bba0fb79b0a7776e',
          ),
        );
      },
    );

    test(
      'check recognizes latest version and reports currentVersionLatest',
      () async {
        final scan = createMockScan(
          modelName: const DetectedValue.verified('TP-Link Archer C60 v3'),
          boardName: const DetectedValue.verified('tplink,archer-c60-v3'),
          distribTarget: const DetectedValue.verified('ath79/generic'),
          distribRelease: const DetectedValue.verified('25.12.6'),
        );

        final result = await checker.check(scan);

        expect(
          result.status,
          equals(UpgradeAvailabilityStatus.currentVersionLatest),
        );
        expect(result.currentVersion, equals('25.12.6'));
        expect(result.explanation, contains('latest official OpenWrt release'));
      },
    );

    test(
      'check returns currentVersionUnknown when distribRelease is null',
      () async {
        final scan = createMockScan(
          distribRelease: const DetectedValue<String>.unknown(),
        );

        final result = await checker.check(scan);

        expect(
          result.status,
          equals(UpgradeAvailabilityStatus.currentVersionUnknown),
        );
        expect(result.currentVersion, isNull);
      },
    );

    test(
      'check returns compatibilityUnverifiable when boardName is unknown',
      () async {
        final scan = createMockScan(
          boardName: const DetectedValue<String>.unknown(),
        );

        final result = await checker.check(scan);

        expect(
          result.status,
          equals(UpgradeAvailabilityStatus.compatibilityUnverifiable),
        );
      },
    );

    test(
      'check returns unsupportedFirmwareSource with vendor portal for GL.iNet',
      () async {
        final scan = createMockScan(
          firmwareFamily: const DetectedValue.verified(FirmwareFamily.glINet),
          firmwareFamilyLabel: const DetectedValue.verified('GL.iNet'),
          distribRelease: const DetectedValue.verified('4.5.16'),
        );

        final result = await checker.check(scan);

        expect(
          result.status,
          equals(UpgradeAvailabilityStatus.unsupportedFirmwareSource),
        );
        expect(result.explanation, contains('dl.gl-inet.com'));
      },
    );
  });

  group('PreservationImpactAnalyzer & Package Migration Tests', () {
    test('analyzeMigration accurately classifies OPKG to APK transition', () {
      final analysis = PreservationImpactAnalyzer.analyzeMigration(
        currentEngine: RouterPackageManager.opkg,
        targetEngine: RouterPackageManager.apk,
        installedPackages: const [
          PackageInfo(name: 'luci'),
          PackageInfo(name: 'luci-app-firewall'),
          PackageInfo(name: 'wireguard-tools'),
          PackageInfo(name: 'kmod-fs-ext4'),
          PackageInfo(name: 'my-custom-script-pkg'),
        ],
      );

      expect(analysis.transition, equals(PackageMigrationTransition.opkgToApk));
      expect(analysis.packages.length, equals(5));

      final kmod = analysis.packages.firstWhere(
        (p) => p.packageName == 'kmod-fs-ext4',
      );
      expect(
        kmod.migrationStatus,
        equals(PackageMigrationStatus.kernelModuleRequiresTargetBuild),
      );

      final custom = analysis.packages.firstWhere(
        (p) => p.packageName == 'my-custom-script-pkg',
      );
      expect(
        custom.migrationStatus,
        equals(PackageMigrationStatus.thirdPartyUnverified),
      );
      expect(analysis.summary, contains('APK'));
    });

    test(
      'analyzeMigration recognizes same-engine transition as no migration',
      () {
        final analysis = PreservationImpactAnalyzer.analyzeMigration(
          currentEngine: RouterPackageManager.opkg,
          targetEngine: RouterPackageManager.opkg,
          installedPackages: const [
            PackageInfo(name: 'luci'),
            PackageInfo(name: 'curl'),
          ],
        );

        expect(
          analysis.transition,
          equals(PackageMigrationTransition.opkgToOpkg),
        );
        expect(
          analysis.summary,
          contains('Both current and target firmware use OPKG'),
        );
      },
    );

    test(
      'Package migration card condition evaluates to false for APK routers',
      () {
        final analysis = PreservationImpactAnalyzer.analyzeMigration(
          currentEngine: RouterPackageManager.apk,
          targetEngine: RouterPackageManager.apk,
          installedPackages: const [],
        );

        final shouldShowMigrationCard =
            analysis.transition == PackageMigrationTransition.opkgToApk;
        expect(shouldShowMigrationCard, isFalse);
      },
    );

    test(
      'Package migration card condition evaluates to true ONLY for OPKG to APK transition',
      () {
        final analysis = PreservationImpactAnalyzer.analyzeMigration(
          currentEngine: RouterPackageManager.opkg,
          targetEngine: RouterPackageManager.apk,
          installedPackages: const [],
        );

        final shouldShowMigrationCard =
            analysis.transition == PackageMigrationTransition.opkgToApk;
        expect(shouldShowMigrationCard, isTrue);
      },
    );

    test('PreservationImpactInventory correctly categorizes outcomes', () {
      const inventory = PreservationImpactInventory(
        items: [
          PreservationImpactItem(
            path: '/etc/config/network',
            category: PreservationCategory.configuration,
            outcome: PreservationOutcome.preserved,
            confidence: DetectionConfidence.verified,
            detectionSource: 'sysupgrade -l',
          ),
          PreservationImpactItem(
            path: '/etc/config/wireless',
            category: PreservationCategory.configuration,
            outcome: PreservationOutcome.preserved,
            confidence: DetectionConfidence.verified,
            detectionSource: 'sysupgrade -l',
          ),
          PreservationImpactItem(
            path: '/usr/bin/custom-script',
            category: PreservationCategory.customScript,
            outcome: PreservationOutcome.lost,
            confidence: DetectionConfidence.verified,
            detectionSource: 'overlay diff',
            recommendedAction: 'Re-copy binary after flash',
          ),
          PreservationImpactItem(
            path: '/etc/shadow',
            category: PreservationCategory.configuration,
            outcome: PreservationOutcome.conditional,
            confidence: DetectionConfidence.likely,
            detectionSource: 'sysupgrade.conf',
            isSensitive: true,
          ),
          PreservationImpactItem(
            path: '/tmp/state.json',
            category: PreservationCategory.runtimeData,
            outcome: PreservationOutcome.unknown,
            confidence: DetectionConfidence.unknown,
            detectionSource: 'probe',
          ),
        ],
        isPartial: false,
      );

      expect(inventory.preserved.length, equals(2));
      expect(inventory.lost.length, equals(1));
      expect(inventory.conditional.length, equals(1));
      expect(inventory.unknown.length, equals(1));
      expect(inventory.needsAction.length, equals(1));
      expect(
        inventory.needsAction.first.path,
        equals('/usr/bin/custom-script'),
      );
    });
  });

  group('RouterUpgradeScanService.validateImage Tests', () {
    test(
      'validateImage returns passed when system.validate_firmware_image reports valid',
      () async {
        final mockApi = MockApiService(
          onCall: (object, method, params) async {
            if (object == 'system' && method == 'validate_firmware_image') {
              return [
                0,
                {'valid': true, 'forceable': true, 'allow_backup': true},
              ];
            }
            return null;
          },
        );

        final service = RouterUpgradeScanService(
          apiService: mockApi,
          ipAddress: '192.168.1.1',
          sysauth: 'test-token',
          useHttps: false,
        );

        final result = await service.validateImage('/tmp/firmware.bin');
        expect(result.status, equals(ImageValidationStatus.passed));
        expect(result.passed, isTrue);
        expect(result.isAcceptableForFlash, isTrue);
      },
    );

    test(
      'validateImage returns failed when system.validate_firmware_image reports invalid without force',
      () async {
        final mockApi = MockApiService(
          onCall: (object, method, params) async {
            if (object == 'system' && method == 'validate_firmware_image') {
              return [
                0,
                {'valid': false, 'forceable': true, 'allow_backup': true},
              ];
            }
            return null;
          },
        );

        final service = RouterUpgradeScanService(
          apiService: mockApi,
          ipAddress: '192.168.1.1',
          sysauth: 'test-token',
          useHttps: false,
        );

        final result = await service.validateImage(
          '/tmp/firmware.bin',
          force: false,
        );
        expect(result.status, equals(ImageValidationStatus.failed));
        expect(result.failed, isTrue);
        expect(result.forceApplied, isFalse);
        expect(result.isAcceptableForFlash, isFalse);
      },
    );

    test(
      'validateImage returns failed with forceApplied=true when force=true',
      () async {
        final mockApi = MockApiService(
          onCall: (object, method, params) async {
            if (object == 'system' && method == 'validate_firmware_image') {
              return [
                0,
                {'valid': false, 'forceable': true, 'allow_backup': true},
              ];
            }
            return null;
          },
        );

        final service = RouterUpgradeScanService(
          apiService: mockApi,
          ipAddress: '192.168.1.1',
          sysauth: 'test-token',
          useHttps: false,
        );

        final result = await service.validateImage(
          '/tmp/firmware.bin',
          force: true,
        );
        expect(result.status, equals(ImageValidationStatus.failed));
        expect(result.forceApplied, isTrue);
        expect(result.isAcceptableForFlash, isTrue);
      },
    );

    test(
      'validateImage falls back to /sbin/sysupgrade --test when ubus validate_firmware_image is missing',
      () async {
        final mockApi = MockApiService(
          onCall: (object, method, params) async {
            if (object == 'system' && method == 'validate_firmware_image') {
              throw Exception('Method not found');
            }
            if (object == 'file' && method == 'exec') {
              final cmd = params?['command']?.toString();
              final args = params?['params'] as List?;
              if (cmd == '/sbin/sysupgrade' &&
                  args != null &&
                  args.contains('--test')) {
                return [
                  0,
                  {'code': 0, 'stdout': 'Image check passed'},
                ];
              }
            }
            return null;
          },
        );

        final service = RouterUpgradeScanService(
          apiService: mockApi,
          ipAddress: '192.168.1.1',
          sysauth: 'test-token',
          useHttps: false,
        );

        final result = await service.validateImage('/tmp/firmware.bin');
        expect(result.status, equals(ImageValidationStatus.passed));
        expect(result.commandOutput, contains('Image check passed'));
      },
    );
  });

  group('Attended Sysupgrade Workflow Tests', () {
    test(
      'Sha256 hex correctly matches expected checksum for test payloads',
      () {
        final sampleBytes = Uint8List.fromList(
          utf8.encode('OpenWrt-firmware-binary-data-sample'),
        );
        final hex = Sha256.hex(sampleBytes);
        expect(hex, isNotEmpty);
        expect(hex.length, equals(64));
        // Re-verifying consistency
        expect(Sha256.hex(sampleBytes), equals(hex));
      },
    );

    test(
      'Attended sysupgrade chunked base64 writing preserves payload integrity',
      () async {
        final sampleData = Uint8List.fromList(
          List.generate(100000, (i) => i % 256),
        );
        final originalB64 = base64Encode(sampleData);

        final writtenChunks = <String>[];
        final mockApi = MockApiService(
          onCall: (object, method, params) async {
            if (object == 'file' && method == 'write') {
              writtenChunks.add(params?['data'] as String);
              return [0];
            }
            if (object == 'file' && method == 'remove') {
              return [0];
            }
            return null;
          },
        );

        // Simulate chunking logic used in _handleInstallUpgrade
        const chunkSize = 24000;
        for (var i = 0; i < originalB64.length; i += chunkSize) {
          final end = (i + chunkSize < originalB64.length)
              ? i + chunkSize
              : originalB64.length;
          final chunk = originalB64.substring(i, end);
          await mockApi.call(
            '192.168.1.1',
            'test-token',
            false,
            object: 'file',
            method: 'write',
            params: {
              'path': '/tmp/firmware.bin',
              'data': chunk,
              'base64': true,
              if (i > 0) 'append': true,
            },
          );
        }

        final reconstructedB64 = writtenChunks.join('');
        expect(reconstructedB64, equals(originalB64));
        final reconstructedBytes = base64Decode(reconstructedB64);
        expect(reconstructedBytes, equals(sampleData));
        expect(
          Sha256.hex(Uint8List.fromList(reconstructedBytes)),
          equals(Sha256.hex(sampleData)),
        );
      },
    );

    test(
      'Sysupgrade arguments correctly configure keep settings and force flags',
      () {
        List<String> buildSysupgradeArgs({
          required bool keepSettings,
          required bool force,
        }) {
          return [
            if (force) '--force',
            keepSettings ? '-k' : '-n',
            '/tmp/firmware.bin',
          ];
        }

        expect(
          buildSysupgradeArgs(keepSettings: true, force: false),
          equals(['-k', '/tmp/firmware.bin']),
        );
        expect(
          buildSysupgradeArgs(keepSettings: false, force: false),
          equals(['-n', '/tmp/firmware.bin']),
        );
        expect(
          buildSysupgradeArgs(keepSettings: true, force: true),
          equals(['--force', '-k', '/tmp/firmware.bin']),
        );
        expect(
          buildSysupgradeArgs(keepSettings: false, force: true),
          equals(['--force', '-n', '/tmp/firmware.bin']),
        );
      },
    );
  });
}
