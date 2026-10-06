// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/modules/package_manager/models/package_info.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/state/controllers/package_controller.dart';

void main() {
  group('Package Manager Engine Wiring Tests', () {
    test('PackageManagerType is unified with PackageManagerEngine', () {
      expect(PackageManagerType.opkg, equals(PackageManagerEngine.opkg));
      expect(PackageManagerType.apk, equals(PackageManagerEngine.apk));
      expect(PackageManagerType.none, equals(PackageManagerEngine.none));
    });

    test('classifyExecResult maps exit code 127 to methodNotFound', () {
      final execPayload = [
        0,
        {'code': 127, 'stdout': '', 'stderr': 'opkg: command not found'},
      ];

      final result = RpcResult.classifyExecResult<String>(
        execPayload,
        (data) => data['stdout'],
      );
      expect(result.status, equals(RpcCallStatus.methodNotFound));
      expect(result.isMethodNotFound, isTrue);
    });

    test(
      'classifyExecResult maps exit code 126 and permission denied stderr to permissionDenied',
      () {
        final execPayload = [
          0,
          {
            'code': 126,
            'stdout': '',
            'stderr': 'Permission denied executing command',
          },
        ];

        final result = RpcResult.classifyExecResult<String>(
          execPayload,
          (data) => data['stdout'],
        );
        expect(result.status, equals(RpcCallStatus.permissionDenied));
        expect(result.isPermissionDenied, isTrue);
      },
    );

    test(
      'classifyExecResult maps non-zero exit code to failed with raw stderr detail',
      () {
        final execPayload = [
          0,
          {
            'code': 1,
            'stdout': '',
            'stderr':
                'opkg_install_cmd: Cannot install package luci-app-test: No space left on device',
          },
        ];

        final result = RpcResult.classifyExecResult<String>(
          execPayload,
          (data) => data['stdout'],
        );
        expect(result.status, equals(RpcCallStatus.failed));
        expect(result.errorMessage, contains('No space left on device'));
      },
    );

    test('classifyExecResult maps exit code 0 to success', () {
      final execPayload = [
        0,
        {'code': 0, 'stdout': 'base-files - 1570-r23805\n', 'stderr': ''},
      ];

      final result = RpcResult.classifyExecResult<String>(
        execPayload,
        (data) => data['stdout'],
      );
      expect(result.status, equals(RpcCallStatus.success));
      expect(result.isSuccess, isTrue);
      expect(result.data, equals('base-files - 1570-r23805\n'));
    });

    test(
      'fromDashboardData parses package-manager-call OPKG status output on APK routers',
      () {
        const sampleOutput = '''
Package: apk-mbedtls
Version: 3.0.5-r2
Depends: libc, libmbedtls21
Status: install ok installed
Description: apk package manager (mbedtls)

Package: base-files
Version: 1696~b21cfa8f8c
Status: install ok installed
Description: OpenWrt base files
''';
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': sampleOutput,
        });
        expect(overview.installedPackages.length, 2);
        expect(overview.installedPackages[0].name, 'apk-mbedtls');
        expect(overview.installedPackages[0].version, '3.0.5-r2');
        expect(overview.installedPackages[1].name, 'base-files');
      },
    );

    test(
      'fromDashboardData returns empty installed list when RPC data is missing',
      () {
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': null,
        });
        expect(overview.installedPackages, isEmpty);
        expect(overview.availablePackages, isEmpty);
      },
    );

    test('OpenWrtPackageRepository correctly parses OPKG feeds', () {
      const line =
          'src/gz openwrt_core https://downloads.openwrt.org/snapshots/packages/x86_64/base';
      final repo = OpenWrtPackageRepository.parseOpkgLine(line);

      expect(repo, isNotNull);
      expect(repo!.name, equals('openwrt_core'));
      expect(
        repo.url,
        equals('https://downloads.openwrt.org/snapshots/packages/x86_64/base'),
      );
      expect(repo.engine, equals(PackageManagerEngine.opkg));
    });

    test('OpenWrtPackageRepository correctly parses APK repositories', () {
      const line =
          'https://downloads.openwrt.org/snapshots/packages/x86_64/base';
      final repo = OpenWrtPackageRepository.parseApkLine(line);

      expect(repo, isNotNull);
      expect(
        repo!.url,
        equals('https://downloads.openwrt.org/snapshots/packages/x86_64/base'),
      );
      expect(repo.engine, equals(PackageManagerEngine.apk));
    });

    test(
      'PackageManagerOverview parses OPKG status file blocks (/usr/lib/opkg/status)',
      () {
        const opkgStatus = '''
Package: base-files
Version: 1570-r23805
Status: install ok installed
Architecture: x86_64
Description: OpenWrt core base files

Package: luci-app-firewall
Version: 1.0.0-1
Status: install ok installed
Description: Firewall configuration user interface
''';
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'opkg',
          'installedPackages': opkgStatus,
        });

        expect(overview.installedPackages.length, equals(2));
        expect(overview.installedPackages[0].name, equals('base-files'));
        expect(overview.installedPackages[0].version, equals('1570-r23805'));
        expect(overview.installedPackages[1].name, equals('luci-app-firewall'));
      },
    );

    test(
      'PackageManagerOverview parses APK database blocks (/lib/apk/db/installed)',
      () {
        const apkDb = '''
C:Q1abc123
P:zlib
V:1.2.13-r1
T:Compression library

C:Q1def456
P:busybox
V:1.36.1-r2
T:Essential command line utilities
''';
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': apkDb,
        });

        expect(overview.installedPackages.length, equals(2));
        expect(overview.installedPackages[0].name, equals('zlib'));
        expect(overview.installedPackages[0].version, equals('1.2.13-r1'));
        expect(overview.installedPackages[1].name, equals('busybox'));
      },
    );

    test(
      'PackageManagerOverview parses apk info -v single-word output lines',
      () {
        const apkInfo = '''
zlib-1.2.13-r1
busybox-1.36.1-r2
luci-mod-status-24.10.0-r1
''';
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': apkInfo,
        });

        expect(overview.installedPackages.length, equals(3));
        expect(overview.installedPackages[0].name, equals('zlib'));
        expect(overview.installedPackages[0].version, equals('1.2.13-r1'));
        expect(overview.installedPackages[1].name, equals('busybox'));
        expect(overview.installedPackages[1].version, equals('1.36.1-r2'));
      },
    );

    test(
      'fileExecParams and fileExecArgs preserve RPC compatibility for file.exec',
      () {
        final params = RealApiService.fileExecParams(
          '/usr/libexec/package-manager-call',
          ['list-installed'],
        );
        expect(
          params,
          containsPair('command', '/usr/libexec/package-manager-call'),
        );
        expect(params, contains('params'));
        expect(params, isNot(contains('args')));

        final args = RealApiService.fileExecArgs(
          '/usr/libexec/package-manager-call',
          ['list-installed'],
        );
        expect(
          args,
          containsPair('command', '/usr/libexec/package-manager-call'),
        );
        expect(args, contains('args'));
        expect(args, isNot(contains('params')));
      },
    );

    test(
      'RpcResult correctly identifies permissionDenied status (ubus code 6)',
      () {
        final ubusPermError = [6, 'Access denied'];
        final res = RpcResult.fromUbusResponse<String>(
          ubusPermError,
          (d) => d.toString(),
        );
        expect(res.isPermissionDenied, isTrue);
        expect(res.status, equals(RpcCallStatus.permissionDenied));
      },
    );

    test(
      'OpenWrtPackage formattedSize formats bytes, KB, and MB accurately',
      () {
        const pkgBytes = OpenWrtPackage(
          name: 'tiny',
          version: '1.0',
          description: 'tiny pkg',
          managerType: PackageManagerType.opkg,
          installedSize: '512',
          isInstalled: true,
        );
        expect(pkgBytes.formattedSize, equals('512 B'));

        const pkgKb = OpenWrtPackage(
          name: 'medium',
          version: '1.0',
          description: 'medium pkg',
          managerType: PackageManagerType.opkg,
          installedSize: '20480',
          isInstalled: true,
        );
        expect(pkgKb.formattedSize, equals('20.0 KB'));

        const pkgMb = OpenWrtPackage(
          name: 'large',
          version: '1.0',
          description: 'large pkg',
          managerType: PackageManagerType.apk,
          installedSize: '2097152',
          isInstalled: true,
        );
        expect(pkgMb.formattedSize, equals('2.00 MB'));
      },
    );

    test('OpenWrtPackage fileExtension reflects engine correctly', () {
      const opkgPkg = OpenWrtPackage(
        name: 'test',
        version: '1.0',
        description: '',
        managerType: PackageManagerType.opkg,
        isInstalled: true,
      );
      expect(opkgPkg.fileExtension, equals('.ipk'));

      const apkPkg = OpenWrtPackage(
        name: 'test',
        version: '1.0',
        description: '',
        managerType: PackageManagerType.apk,
        isInstalled: true,
      );
      expect(apkPkg.fileExtension, equals('.apk'));
    });

    test('parseControlBlocks parses full metadata for opkg/apk output', () {
      const blockData = '''
Package: luci-app-wireguard
Version: 1.2.3-1
Depends: wireguard-tools, luci-base
Section: luci
Architecture: all
Installed-Size: 15360
License: Apache-2.0
Description: WireGuard Status and Configuration Web UI

Package: wireguard-tools
Version: 1.0.20210914-1
Depends: kmod-wireguard
Section: net
Architecture: x86_64
Installed-Size: 32768
License: GPL-2.0
Description: WireGuard tools (wg, wg-quick)
''';

      final packages = PackageManagerOverview.parseControlBlocks(
        blockData,
        isInstalled: true,
        type: PackageManagerType.opkg,
      );

      expect(packages.length, equals(2));

      final p1 = packages[0];
      expect(p1.name, equals('luci-app-wireguard'));
      expect(p1.version, equals('1.2.3-1'));
      expect(p1.dependencies, equals('wireguard-tools, luci-base'));
      expect(p1.section, equals('luci'));
      expect(p1.architecture, equals('all'));
      expect(p1.installedSize, equals('15360'));
      expect(p1.license, equals('Apache-2.0'));
      expect(
        p1.description,
        equals('WireGuard Status and Configuration Web UI'),
      );
      expect(p1.isInstalled, isTrue);

      final p2 = packages[1];
      expect(p2.name, equals('wireguard-tools'));
      expect(p2.version, equals('1.0.20210914-1'));
      expect(p2.dependencies, equals('kmod-wireguard'));
      expect(p2.section, equals('net'));
      expect(p2.architecture, equals('x86_64'));
      expect(p2.installedSize, equals('32768'));
      expect(p2.license, equals('GPL-2.0'));
    });

    test(
      'parseApkDb parses APK db installed entries with dependencies and license',
      () {
        const apkData = '''
C:Q1test123
P:curl
V:8.5.0-r0
T:Command line tool for transferring data with URLs
I:450560
D:libcurl ca-certificates
L:MIT

C:Q1test456
P:libcurl
V:8.5.0-r0
T:Multi-protocol file transfer library
I:720896
D:libmbedtls
L:MIT
''';

        final packages = PackageManagerOverview.parseApkDb(apkData);
        expect(packages.length, equals(2));

        final curl = packages[0];
        expect(curl.name, equals('curl'));
        expect(curl.version, equals('8.5.0-r0'));
        expect(
          curl.description,
          equals('Command line tool for transferring data with URLs'),
        );
        expect(curl.installedSize, equals('450560'));
        expect(curl.dependencies, equals('libcurl ca-certificates'));
        expect(curl.license, equals('MIT'));
        expect(curl.managerType, equals(PackageManagerType.apk));
        expect(curl.isInstalled, isTrue);
      },
    );

    test(
      'upgradablePackages identifies packages with newer versions available',
      () {
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': [
            {'name': 'curl', 'version': '8.4.0-r0'},
            {'name': 'busybox', 'version': '1.36.1-r1'},
          ],
          'availablePackages': [
            {'name': 'curl', 'version': '8.5.0-r0'},
            {'name': 'busybox', 'version': '1.36.1-r1'},
            {'name': 'htop', 'version': '3.3.0'},
          ],
        });

        final updates = overview.upgradablePackages;
        expect(updates.length, equals(1));
        expect(updates[0].name, equals('curl'));
        expect(updates[0].version, equals('8.4.0-r0'));
        expect(updates[0].newVersion, equals('8.5.0-r0'));
        expect(updates[0].hasUpdate, isTrue);
      },
    );

    test(
      'PackageController.isCriticalPackage safeguards system core components',
      () {
        // Core system components must be detected as critical
        expect(PackageController.isCriticalPackage('luci'), isTrue);
        expect(PackageController.isCriticalPackage('luci-base'), isTrue);
        expect(PackageController.isCriticalPackage('base-files'), isTrue);
        expect(PackageController.isCriticalPackage('dropbear'), isTrue);
        expect(PackageController.isCriticalPackage('busybox'), isTrue);
        expect(PackageController.isCriticalPackage('kernel'), isTrue);
        expect(PackageController.isCriticalPackage('netifd'), isTrue);
        expect(PackageController.isCriticalPackage('rpcd'), isTrue);
        expect(PackageController.isCriticalPackage('apk-mbedtls'), isTrue);
        expect(PackageController.isCriticalPackage('opkg'), isTrue);
        expect(PackageController.isCriticalPackage('libc'), isTrue);

        // User applications should not be critical
        expect(
          PackageController.isCriticalPackage('luci-app-wireguard'),
          isFalse,
        );
        expect(PackageController.isCriticalPackage('curl'), isFalse);
        expect(PackageController.isCriticalPackage('htop'), isFalse);
        expect(PackageController.isCriticalPackage('iperf3'), isFalse);
      },
    );

    test('Package name regex validator enforces single package isolation', () {
      final validRegex = RegExp(r'^[a-zA-Z0-9_\-\.\+]+$');

      // Valid names
      expect(validRegex.hasMatch('luci-app-wireguard'), isTrue);
      expect(validRegex.hasMatch('kmod-crypto-aead+test'), isTrue);
      expect(validRegex.hasMatch('libopenssl3'), isTrue);
      expect(validRegex.hasMatch('base-files_1570'), isTrue);

      // Invalid names containing command injection, spaces, shell chars
      expect(validRegex.hasMatch('pkg1 pkg2'), isFalse);
      expect(validRegex.hasMatch('pkg1; rm -rf /'), isFalse);
      expect(validRegex.hasMatch('pkg1 && evil'), isFalse);
      expect(validRegex.hasMatch('pkg1 | cat'), isFalse);
      expect(validRegex.hasMatch('`reboot`'), isFalse);
      expect(validRegex.hasMatch('*'), isFalse);
      expect(validRegex.hasMatch(''), isFalse);
    });

    test(
      'parseJsonPackages accurately parses APK package-manager-call JSON output',
      () {
        final jsonList = [
          {
            'package': 'apk-mbedtls-3.0.5-r2',
            'name': 'apk-mbedtls',
            'version': '3.0.5-r2',
            'description': 'apk package manager (mbedtls)',
            'arch': 'x86_64',
            'license': 'GPL-2.0',
            'installed-size': 19821,
            'file-size': 9821,
            'depends': ['libc', 'libmbedtls21', 'zlib'],
            'status': ['installed'],
          },
          {
            'package': 'luci-base-git-24.010',
            'name': 'luci-base',
            'version': 'git-24.010',
            'description': 'LuCI core libraries',
            'arch': 'all',
            'license': 'Apache-2.0',
            'installed-size': 145000,
            'file-size': 65000,
            'depends': ['rpcd', 'ucode'],
            'status': ['installed'],
          },
        ];

        final packages = PackageManagerOverview.parseJsonPackages(
          jsonList,
          isInstalled: true,
          managerType: PackageManagerType.apk,
        );

        expect(packages.length, equals(2));
        final apkPkg = packages[0];
        expect(apkPkg.name, equals('apk-mbedtls'));
        expect(apkPkg.version, equals('3.0.5-r2'));
        expect(apkPkg.dependencies, equals('libc, libmbedtls21, zlib'));
        expect(apkPkg.installedSize, equals('19821'));
        expect(apkPkg.size, equals('9821'));
        expect(apkPkg.isInstalled, isTrue);
        expect(apkPkg.managerType, equals(PackageManagerType.apk));
        expect(apkPkg.fileExtension, equals('.apk'));
      },
    );

    test(
      'fromDashboardData detects JSON array string and switches engine to APK',
      () {
        final jsonString = jsonEncode([
          {
            'package': 'wireguard-tools-1.0.20210914-1',
            'name': 'wireguard-tools',
            'version': '1.0.20210914-1',
            'description': 'WireGuard tools',
            'arch': 'x86_64',
            'installed-size': 32768,
            'status': ['installed'],
          },
        ]);

        // Even if router capabilities or cache erroneously said 'opkg':
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'opkg',
          'installedPackages': jsonString,
        });

        expect(overview.activeManager, equals(PackageManagerType.apk));
        expect(overview.installedPackages.length, equals(1));
        expect(
          overview.installedPackages.first.name,
          equals('wireguard-tools'),
        );
        expect(overview.installedPackages.first.fileExtension, equals('.apk'));
      },
    );

    test(
      '237 packages payload parses accurately without truncation or data loss',
      () {
        final sampleList = List.generate(
          237,
          (i) => {
            'package': 'pkg-$i-1.0.0',
            'name': 'pkg-$i',
            'version': '1.0.0',
            'description': 'Sample package number $i',
            'arch': 'x86_64',
            'installed-size': 1024 * (i + 1),
            'file-size': 512 * (i + 1),
            'status': ['installed'],
          },
        );

        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': sampleList,
        });

        expect(overview.installedPackages.length, equals(237));
        expect(overview.activeManager, equals(PackageManagerType.apk));
        expect(overview.installedPackages[0].fileExtension, equals('.apk'));
        expect(overview.installedPackages[236].fileExtension, equals('.apk'));
      },
    );

    test('isInsufficientStorage detects out of space errors accurately', () {
      final apkError = RpcResult<String>.failed(
        'ERROR: ip-tiny-6.18.0-r2: failed to extract usr/libexec/ip-tiny: No space left on device\n'
        'ERROR: ip-tiny-6.18.0-r2: No space left on device\n'
        'ERROR: System state may be inconsistent: failed to write database: No space left on device',
        code: 5,
      );
      expect(apkError.isInsufficientStorage, isTrue);
      expect(
        apkError.userFriendlyPackageError,
        equals('Insufficient storage space on router (No space left on device).'),
      );

      final opkgError = RpcResult<String>.failed(
        'Collected errors:\n'
        ' * verify_pkg_installable: Only 64kb available on filesystem /overlay, pkg ddns-scripts needs 350kb.\n'
        ' * opkg_install_cmd: Cannot install package ddns-scripts.',
        code: 1,
      );
      expect(opkgError.isInsufficientStorage, isTrue);
      expect(
        opkgError.userFriendlyPackageError,
        equals('Insufficient storage space on router (No space left on device).'),
      );

      final normalError = RpcResult<String>.failed(
        'ERROR: unable to select packages:\n  ddns-scripts-bogus (no such package)',
        code: 1,
      );
      expect(normalError.isInsufficientStorage, isFalse);
      expect(
        normalError.userFriendlyPackageError,
        equals('unable to select packages:'),
      );
    });

    test('fromUbusResponse and classifyExecResult recognize ubus timeout code 7', () {
      final ubusTimeout = RpcResult.fromUbusResponse<String>(
        [7],
        (d) => d.toString(),
      );
      expect(ubusTimeout.status, equals(RpcCallStatus.failed));
      expect(ubusTimeout.errorCode, equals(7));
      expect(ubusTimeout.errorMessage, contains('timed out on router (ubus error 7)'));

      final execTimeout = RpcResult.classifyExecResult<String>(
        [7],
        (d) => d.toString(),
      );
      expect(execTimeout.status, equals(RpcCallStatus.failed));
      expect(execTimeout.errorCode, equals(7));
      expect(execTimeout.errorMessage, contains('timed out on router (ubus error 7)'));
    });

    test('PackageController.getFreeDiskSpace returns mock bytes in reviewer mode', () async {
      final controller = PackageController(
        apiServiceRef: () => null,
        authServiceRef: () => null,
        routerServiceRef: () => null,
        capabilitiesRef: () => null,
        reviewerModeRef: () => true,
        refreshDashboard: () async {},
        redetectCapabilities: () async {},
      );

      final freeSpace = await controller.getFreeDiskSpace();
      expect(freeSpace, isNotNull);
      expect(freeSpace, equals(50 * 1024 * 1024));
    });
  });
}

