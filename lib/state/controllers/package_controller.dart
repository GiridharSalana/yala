// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/models/rpc_result.dart';
import 'package:yala/modules/package_manager/models/package_info.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/interfaces/auth_service_interface.dart';
import 'package:yala/services/router_service.dart';
import 'package:yala/utils/logger.dart';

List<OpenWrtPackage> _parseJsonPackagesIsolate(String rawJson) {
  return PackageManagerOverview.parseJsonPackages(
    rawJson,
    isInstalled: true,
    managerType: PackageManagerType.apk,
  );
}

List<OpenWrtPackage> _parseAvailableJsonPackagesIsolate(String rawJson) {
  return PackageManagerOverview.parseJsonPackages(
    rawJson,
    isInstalled: false,
    managerType: PackageManagerType.apk,
  );
}

/// Encapsulates all package manager RPC operations — install, remove,
/// upgrade, list-installed, list-available, and list-upgradable.
///
/// Designed to achieve 100% functional parity with the LuCI web package manager.
class PackageController {
  PackageController({
    required IApiService? Function() apiServiceRef,
    required IAuthService? Function() authServiceRef,
    required RouterService? Function() routerServiceRef,
    required RouterCapabilities? Function() capabilitiesRef,
    required bool Function() reviewerModeRef,
    required Future<void> Function() refreshDashboard,
    required Future<void> Function() redetectCapabilities,
  }) : _apiServiceRef = apiServiceRef,
       _authServiceRef = authServiceRef,
       _routerServiceRef = routerServiceRef,
       _capabilitiesRef = capabilitiesRef,
       _reviewerModeRef = reviewerModeRef,
       _refreshDashboard = refreshDashboard,
       _redetectCapabilities = redetectCapabilities;

  // Accessor closures — avoid holding stale references after router switch
  final IApiService? Function() _apiServiceRef;
  final IAuthService? Function() _authServiceRef;
  final RouterService? Function() _routerServiceRef;
  final RouterCapabilities? Function() _capabilitiesRef;
  final bool Function() _reviewerModeRef;
  final Future<void> Function() _refreshDashboard;
  final Future<void> Function() _redetectCapabilities;

  // ── Convenience accessors ──────────────────────────────────────

  String? get _ip => _routerServiceRef()?.selectedRouter?.ipAddress;
  String? get _sysauth => _authServiceRef()?.sysauth;
  bool get _useHttps => _routerServiceRef()?.selectedRouter?.useHttps ?? false;
  bool get _isReviewerMode => _reviewerModeRef();
  PackageManagerEngine get _engine =>
      _capabilitiesRef()?.packageEngine ?? PackageManagerEngine.opkg;

  /// Critical packages that should never be accidentally uninstalled
  static const Set<String> criticalSystemPackages = {
    'base-files',
    'busybox',
    'dropbear',
    'kernel',
    'libc',
    'libgcc',
    'luci',
    'luci-base',
    'luci-mod-admin-full',
    'luci-mod-status',
    'luci-app-package-manager',
    'netifd',
    'rpcd',
    'rpcd-mod-file',
    'rpcd-mod-luci',
    'rpcd-mod-rrdns',
    'rpcd-mod-ucode',
    'uhttpd',
    'apk-mbedtls',
    'apk-openssl',
    'opkg',
    'ubus',
    'ubusd',
    'uci',
  };

  /// Check whether a package is a critical core package
  static bool isCriticalPackage(String name) {
    final lower = name.toLowerCase().trim();
    return criticalSystemPackages.contains(lower) ||
        lower.startsWith('luci-mod-') ||
        lower == 'kernel' ||
        lower.startsWith('kmod-');
  }

  // ── Helper Output Parsing ──────────────────────────────────────

  /// Safely parse helper exec JSON or fallback to raw stdout
  static RpcResult<String> _parsePackageHelperOutput(dynamic rpcResponse) {
    if (rpcResponse is List && rpcResponse.length > 1 && rpcResponse[0] == 0) {
      final resMap = rpcResponse[1];
      if (resMap is Map) {
        final rawStdout = resMap['stdout']?.toString().trim() ?? '';
        final rawStderr = resMap['stderr']?.toString().trim() ?? '';
        final execCode = resMap['code'] as int? ?? 0;

        // Check if stdout contains LuCI package-manager-call JSON payload
        if (rawStdout.startsWith('{') && rawStdout.endsWith('}')) {
          try {
            final json = jsonDecode(rawStdout) as Map<String, dynamic>;
            final innerCode = json['code'] as int? ?? 0;
            final innerStderr = json['stderr']?.toString().trim() ?? '';
            final innerStdout = json['stdout']?.toString().trim() ?? '';

            if (innerCode != 0) {
              final err = innerStderr.isNotEmpty
                  ? innerStderr
                  : (innerStdout.isNotEmpty
                        ? innerStdout
                        : 'Package manager command failed (exit code $innerCode)');
              return RpcResult.failed(err, code: innerCode);
            }
            return RpcResult.success(
              innerStdout.isNotEmpty
                  ? innerStdout
                  : 'Action completed successfully',
            );
          } catch (_) {}
        }

        if (execCode != 0) {
          final err = rawStderr.isNotEmpty
              ? rawStderr
              : (rawStdout.isNotEmpty
                    ? rawStdout
                    : 'Command failed with exit code $execCode');
          if (execCode == 127) {
            return RpcResult.methodNotFound(err);
          } else if (execCode == 126 ||
              err.toLowerCase().contains('permission denied')) {
            return RpcResult.permissionDenied(err);
          }
          return RpcResult.failed(err, code: execCode);
        }

        return RpcResult.success(rawStdout);
      }
    }
    return RpcResult.fromUbusResponse<String>(rpcResponse, (d) => d.toString());
  }

  /// Safely parse helper exec JSON string or fallback to raw stdout
  static RpcResult<String> _parseHelperOutputString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        final innerCode = json['code'] as int? ?? 0;
        final innerStderr = json['stderr']?.toString().trim() ?? '';
        final innerStdout = json['stdout']?.toString().trim() ?? '';

        if (innerCode != 0) {
          final err = innerStderr.isNotEmpty
              ? innerStderr
              : (innerStdout.isNotEmpty
                    ? innerStdout
                    : 'Package manager command failed (exit code $innerCode)');
          return RpcResult.failed(err, code: innerCode);
        }
        return RpcResult.success(
          innerStdout.isNotEmpty
              ? innerStdout
              : 'Action completed successfully',
        );
      } catch (_) {}
    }
    return RpcResult.success(trimmed);
  }

  void _syncDetectedEngine(PackageManagerEngine detected) {
    if (_capabilitiesRef()?.packageEngine != detected) {
      Logger.info(
        'Package engine mismatch detected: $detected vs cached ${_capabilitiesRef()?.packageEngine}. Requesting capability re-probe.',
      );
      unawaited(_redetectCapabilities());
    }
  }

  // ── Public API ─────────────────────────────────────────────────

  /// Fetch installed OpenWrt packages using LuCI's official backend with fallbacks
  Future<RpcResult<List<OpenWrtPackage>>> fetchInstalledPackages() async {
    if (_isReviewerMode) {
      final overview = PackageManagerOverview.fromDashboardData(
        null,
        isReviewerMode: true,
      );
      return RpcResult.success(overview.installedPackages);
    }

    if (_ip == null || _sysauth == null) {
      return RpcResult.networkError('No active router session');
    }

    final api = _apiServiceRef()!;
    final ip = _ip!;
    final sysauth = _sysauth!;
    final useHttps = _useHttps;
    var engine = _engine;

    // 1. Primary: LuCI streaming cgi-exec for /usr/libexec/package-manager-call list-installed
    // This bypasses the 256KB rpcd buffer limit (RPC_FILE_MAX_SIZE) that causes file.exec to fail
    // with code 8 on routers with large package counts (e.g. 237 packages returning 728KB JSON).
    try {
      final cgiOutput = await api.execDirectCgi(
        ip,
        sysauth,
        useHttps,
        command: '/usr/libexec/package-manager-call',
        params: ['list-installed'],
      );

      if (cgiOutput != null && cgiOutput.trim().isNotEmpty) {
        final trimmed = cgiOutput.trim();
        if (trimmed.startsWith('[')) {
          engine = PackageManagerEngine.apk;
          final packages = await compute(_parseJsonPackagesIsolate, trimmed);
          if (packages.isNotEmpty) {
            _syncDetectedEngine(engine);
            return RpcResult.success(packages);
          }
        } else if (trimmed.contains('Package: ') || trimmed.contains('P:')) {
          if (trimmed.contains('Package: apk-mbedtls') ||
              trimmed.contains('Package: apk-openssl') ||
              trimmed.contains('P:')) {
            engine = PackageManagerEngine.apk;
          }
          final packages = PackageManagerOverview.parseControlBlocks(
            trimmed,
            isInstalled: true,
            type: engine,
          );
          if (packages.isNotEmpty) {
            _syncDetectedEngine(engine);
            return RpcResult.success(packages);
          }
        }
      }
    } catch (e) {
      Logger.warning('execDirectCgi list-installed failed: $e');
    }

    // 2. Secondary fallback: file.exec /usr/libexec/package-manager-call list-installed
    try {
      final helperRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/usr/libexec/package-manager-call',
          'params': ['list-installed'],
        },
      );

      if (helperRpc is List && helperRpc.length > 1 && helperRpc[0] == 0) {
        final data = helperRpc[1];
        if (data is Map && data['stdout'] != null) {
          final stdout = data['stdout'].toString().trim();
          if (stdout.startsWith('[')) {
            engine = PackageManagerEngine.apk;
            final packages = await compute(_parseJsonPackagesIsolate, stdout);
            if (packages.isNotEmpty) {
              _syncDetectedEngine(engine);
              return RpcResult.success(packages);
            }
          } else if (stdout.contains('Package: ') || stdout.contains('P:')) {
            if (stdout.contains('Package: apk-mbedtls') ||
                stdout.contains('Package: apk-openssl') ||
                stdout.contains('P:')) {
              engine = PackageManagerEngine.apk;
            }
            final packages = PackageManagerOverview.parseControlBlocks(
              stdout,
              isInstalled: true,
              type: engine,
            );
            if (packages.isNotEmpty) {
              _syncDetectedEngine(engine);
              return RpcResult.success(packages);
            }
          }
        }
      }
    } catch (_) {}

    // 2. Secondary fallback: file.exec apk list / opkg list-installed
    try {
      final cmd = engine == PackageManagerEngine.apk ? 'apk' : 'opkg';
      final listArgs = engine == PackageManagerEngine.apk
          ? ['list', '--installed']
          : ['list-installed'];
      final rawRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': cmd, 'params': listArgs},
      );

      if (rawRpc is List && rawRpc.length > 1 && rawRpc[0] == 0) {
        final data = rawRpc[1];
        if (data is Map && data['stdout'] != null) {
          final stdout = data['stdout'].toString();
          if (stdout.trim().isNotEmpty) {
            final overview = PackageManagerOverview.fromDashboardData({
              'installedPackages': stdout,
              'packageManager': engine.name,
            });
            if (overview.installedPackages.isNotEmpty) {
              return RpcResult.success(overview.installedPackages);
            }
          }
        }
      }
    } catch (_) {}

    // 3. Tertiary fallback: rpc-sys packagelist
    try {
      final sysRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'rpc-sys',
        method: 'packagelist',
        params: <String, dynamic>{},
      );

      if (sysRpc is List && sysRpc.length > 1 && sysRpc[0] == 0) {
        final data = sysRpc[1];
        if (data is Map && data['packages'] is Map) {
          final overview = PackageManagerOverview.fromDashboardData({
            'installedPackages': data,
            'packageManager': engine.name,
          });
          if (overview.installedPackages.isNotEmpty) {
            return RpcResult.success(overview.installedPackages);
          }
        }
      }
    } catch (_) {}

    // 4. Quaternary fallback: file.read on /lib/apk/db/installed or /usr/lib/opkg/status
    try {
      final path = engine == PackageManagerEngine.apk
          ? '/lib/apk/db/installed'
          : '/usr/lib/opkg/status';
      final readRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'read',
        params: {'path': path},
      );

      if (readRpc is List && readRpc.length > 1 && readRpc[0] == 0) {
        final data = readRpc[1];
        if (data is Map && data['data'] != null) {
          final content = data['data'].toString();
          final overview = PackageManagerOverview.fromDashboardData({
            'installedPackages': content,
            'packageManager': engine.name,
          });
          if (overview.installedPackages.isNotEmpty) {
            return RpcResult.success(overview.installedPackages);
          }
        }
      }
    } catch (_) {}

    return RpcResult.failed('Could not read installed packages from router.');
  }

  /// Backward-compatible method returning raw data payload
  Future<RpcResult<dynamic>> fetchPackagesDataResult() async {
    final res = await fetchInstalledPackages();
    if (res.isSuccess && res.data != null) {
      return RpcResult.success(res.data);
    }
    return RpcResult(
      status: res.status,
      errorMessage: res.errorMessage,
      errorCode: res.errorCode,
    );
  }

  /// Fetch available repository packages from OpenWrt package feeds
  Future<RpcResult<List<OpenWrtPackage>>> fetchAvailablePackages() async {
    if (_isReviewerMode) {
      final overview = PackageManagerOverview.fromDashboardData(
        null,
        isReviewerMode: true,
      );
      return RpcResult.success(overview.availablePackages);
    }

    if (_ip == null || _sysauth == null) {
      return RpcResult.networkError('No active router session');
    }

    final api = _apiServiceRef()!;
    final ip = _ip!;
    final sysauth = _sysauth!;
    final useHttps = _useHttps;
    var engine = _engine;

    // 1. Primary: LuCI streaming cgi-exec for /usr/libexec/package-manager-call list-available
    // LuCI available feeds can be 12MB+; streaming cgi-exec handles this with zero rpcd limit.
    try {
      final cgiOutput = await api.execDirectCgi(
        ip,
        sysauth,
        useHttps,
        command: '/usr/libexec/package-manager-call',
        params: ['list-available'],
      );

      if (cgiOutput != null && cgiOutput.trim().isNotEmpty) {
        final trimmed = cgiOutput.trim();
        if (trimmed.startsWith('[')) {
          engine = PackageManagerEngine.apk;
          final packages = await compute(
            _parseAvailableJsonPackagesIsolate,
            trimmed,
          );
          if (packages.isNotEmpty) {
            _syncDetectedEngine(engine);
            return RpcResult.success(packages);
          }
        } else if (trimmed.contains('Package: ')) {
          final packages = PackageManagerOverview.parseControlBlocks(
            trimmed,
            isInstalled: false,
            type: engine,
          );
          if (packages.isNotEmpty) {
            return RpcResult.success(packages);
          }
        }
      }
    } catch (e) {
      Logger.warning('execDirectCgi list-available failed: $e');
    }

    // 2. Secondary fallback: file.exec /usr/libexec/package-manager-call list-available
    try {
      final helperRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/usr/libexec/package-manager-call',
          'params': ['list-available'],
        },
      );

      if (helperRpc is List && helperRpc.length > 1 && helperRpc[0] == 0) {
        final data = helperRpc[1];
        if (data is Map && data['stdout'] != null) {
          final stdout = data['stdout'].toString().trim();
          if (stdout.startsWith('[')) {
            engine = PackageManagerEngine.apk;
            final packages = await compute(
              _parseAvailableJsonPackagesIsolate,
              stdout,
            );
            if (packages.isNotEmpty) {
              _syncDetectedEngine(engine);
              return RpcResult.success(packages);
            }
          } else if (stdout.contains('Package: ')) {
            final packages = PackageManagerOverview.parseControlBlocks(
              stdout,
              isInstalled: false,
              type: engine,
            );
            if (packages.isNotEmpty) {
              return RpcResult.success(packages);
            }
          }
        }
      }
    } catch (_) {}

    // 3. Tertiary fallback: file.exec apk list / opkg list
    try {
      final cmd = engine == PackageManagerEngine.apk ? 'apk' : 'opkg';
      final listArgs = ['list'];
      final rawRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': cmd, 'params': listArgs},
      );

      if (rawRpc is List && rawRpc.length > 1 && rawRpc[0] == 0) {
        final data = rawRpc[1];
        if (data is Map && data['stdout'] != null) {
          final stdout = data['stdout'].toString();
          if (stdout.trim().isNotEmpty) {
            final overview = PackageManagerOverview.fromDashboardData({
              'availablePackages': stdout,
              'packageManager': engine.name,
            });
            if (overview.availablePackages.isNotEmpty) {
              return RpcResult.success(overview.availablePackages);
            }
          }
        }
      }
    } catch (_) {}

    return RpcResult.success([]);
  }

  /// Backward-compatible method returning available packages
  Future<RpcResult<dynamic>> fetchAvailablePackagesDataResult() async {
    final res = await fetchAvailablePackages();
    if (res.isSuccess && res.data != null) {
      return RpcResult.success(res.data);
    }
    return RpcResult(
      status: res.status,
      errorMessage: res.errorMessage,
      errorCode: res.errorCode,
    );
  }

  /// Check and fetch upgradable packages returning classified RpcResult
  Future<RpcResult<List<OpenWrtPackage>>>
  fetchUpgradablePackagesResult() async {
    if (_isReviewerMode) {
      final overview = PackageManagerOverview.fromDashboardData(
        null,
        isReviewerMode: true,
      );
      return RpcResult.success(overview.upgradablePackages);
    }

    final installedRes = await fetchInstalledPackages();
    final availableRes = await fetchAvailablePackages();

    final installed = installedRes.data ?? [];
    final available = availableRes.data ?? [];

    final overview = PackageManagerOverview.fromDashboardData({
      'installedPackages': installed,
      'availablePackages': available,
      'packageManager': _engine.name,
    });

    return RpcResult.success(overview.upgradablePackages);
  }

  /// Backward-compatible wrapper for fetchUpgradablePackages
  Future<List<OpenWrtPackage>> fetchUpgradablePackages() async {
    final res = await fetchUpgradablePackagesResult();
    return res.data ?? [];
  }

  /// Query free disk space in bytes for package operations (inspecting /overlay and fallback to /)
  Future<int?> getFreeDiskSpace() async {
    if (_isReviewerMode) {
      return 1024 * 1024 * 50; // 50 MB mock in reviewer mode
    }
    if (_ip == null || _sysauth == null) return null;

    try {
      final api = _apiServiceRef()!;
      final ip = _ip!;
      final sysauth = _sysauth!;
      final useHttps = _useHttps;
      final mountRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'luci',
        method: 'getMountPoints',
        params: <String, dynamic>{},
      );
      if (mountRpc is List && mountRpc.length > 1 && mountRpc[0] == 0) {
        final data = mountRpc[1];
        final list = (data is Map && data['result'] is List)
            ? data['result'] as List
            : (data is List ? data : []);
        Map? overlayMount;
        Map? rootMount;
        for (final m in list) {
          if (m is Map) {
            if (m['mount'] == '/overlay') overlayMount = m;
            if (m['mount'] == '/') rootMount = m;
          }
        }
        final target = overlayMount ?? rootMount;
        if (target != null && target['free'] is num) {
          return (target['free'] as num).toInt();
        } else if (target != null && target['avail'] is num) {
          return (target['avail'] as num).toInt();
        }
      }

      final sysInfo = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'system',
        method: 'info',
        params: <String, dynamic>{},
      );
      if (sysInfo is List && sysInfo.length > 1 && sysInfo[0] == 0) {
        final data = sysInfo[1];
        if (data is Map &&
            data['root'] is Map &&
            data['root']['avail'] is num) {
          return (data['root']['avail'] as num).toInt() * 1024;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetch full LuCI overview: installed, available, upgradable, and free disk space
  Future<RpcResult<PackageManagerOverview>>
  fetchPackageManagerOverview() async {
    if (_isReviewerMode) {
      final overview = PackageManagerOverview.fromDashboardData(
        null,
        isReviewerMode: true,
      );
      return RpcResult.success(overview);
    }

    final installedRes = await fetchInstalledPackages();
    if (!installedRes.isSuccess || installedRes.data == null) {
      return RpcResult(
        status: installedRes.status,
        errorMessage:
            installedRes.errorMessage ?? 'Failed to load installed packages',
        errorCode: installedRes.errorCode,
      );
    }

    final installed = installedRes.data!;

    // Fetch available in parallel or sequential
    final availableRes = await fetchAvailablePackages();
    final available = availableRes.data ?? [];

    // Query free disk space via luci.getMountPoints (matching LuCI web), falling back to system.info
    final freeDiskSpace = await getFreeDiskSpace();

    final activeEngine =
        (installed.isNotEmpty &&
            installed.first.managerType == PackageManagerEngine.apk)
        ? PackageManagerEngine.apk
        : _engine;

    final overview = PackageManagerOverview.fromDashboardData({
      'packageManager': activeEngine.name,
      'installedPackages': installed,
      'availablePackages': available,
      'freeDiskSpace': freeDiskSpace,
    });

    return RpcResult.success(overview);
  }

  /// Update package lists from feeds/repositories (/usr/libexec/package-manager-call update)
  Future<RpcResult<String>> updatePackageLists() async {
    if (_isReviewerMode) {
      return RpcResult.success(
        'Package lists updated successfully (Reviewer Mode)',
      );
    }
    return managePackageResult(packageName: '', action: 'update');
  }

  /// Safely install a single package by exact name
  Future<RpcResult<String>> installPackage(String packageName) async {
    final clean = packageName.trim();
    if (clean.isEmpty) {
      return RpcResult.failed('Package name cannot be empty');
    }
    if (!RegExp(r'^[a-zA-Z0-9_\-\.\+]+$').hasMatch(clean)) {
      return RpcResult.failed(
        'Invalid package name "$clean". Only alphanumeric characters, dashes, underscores, dots, and plus signs are permitted.',
      );
    }
    return managePackageResult(packageName: clean, action: 'install');
  }

  /// Safely uninstall a single package by exact name without cascading deletion
  Future<RpcResult<String>> removePackage(String packageName) async {
    final clean = packageName.trim();
    if (clean.isEmpty) {
      return RpcResult.failed('Package name cannot be empty');
    }
    if (!RegExp(r'^[a-zA-Z0-9_\-\.\+]+$').hasMatch(clean)) {
      return RpcResult.failed(
        'Invalid package name "$clean". Only alphanumeric characters, dashes, underscores, dots, and plus signs are permitted.',
      );
    }
    return managePackageResult(packageName: clean, action: 'remove');
  }

  /// Safely upgrade a single package by exact name
  Future<RpcResult<String>> upgradePackage(String packageName) async {
    final clean = packageName.trim();
    if (clean.isEmpty) {
      return RpcResult.failed('Package name cannot be empty');
    }
    if (!RegExp(r'^[a-zA-Z0-9_\-\.\+]+$').hasMatch(clean)) {
      return RpcResult.failed(
        'Invalid package name "$clean". Only alphanumeric characters, dashes, underscores, dots, and plus signs are permitted.',
      );
    }
    return managePackageResult(packageName: clean, action: 'upgrade');
  }

  /// Install a custom package from a URL or custom package name
  Future<RpcResult<String>> installCustomPackage(String target) async {
    final clean = target.trim();
    if (clean.isEmpty) {
      return RpcResult.failed(
        'Package name, URL, or file path cannot be empty',
      );
    }
    return managePackageResult(packageName: clean, action: 'install');
  }

  /// Manage software packages on OpenWrt (OPKG / APK) returning classified RpcResult
  Future<RpcResult<String>> managePackageResult({
    required String packageName,
    required String action,
  }) async {
    if (_isReviewerMode) {
      return RpcResult.success(
        'Action $action on "$packageName" completed successfully (Reviewer Mode)',
      );
    }
    if (_ip == null || _sysauth == null) {
      return RpcResult.networkError('No active router session');
    }

    final engine = _engine;
    if (engine == PackageManagerEngine.none) {
      return RpcResult.methodNotFound(
        'No package manager detected on this router',
      );
    }

    final api = _apiServiceRef()!;
    final ip = _ip!;
    final sysauth = _sysauth!;
    final useHttps = _useHttps;
    final isApk = engine == PackageManagerEngine.apk;
    final cmd = isApk ? 'apk' : 'opkg';
    final cleanPkg = packageName.trim();

    // 1. LuCI universal backend via streaming cgi-exec:
    try {
      final List<String> helperArgs;
      if (action == 'update') {
        helperArgs = ['update'];
      } else if (cleanPkg.isNotEmpty) {
        helperArgs = [action, cleanPkg];
      } else {
        helperArgs = [action];
      }

      final cgiRes = await api.execDirectCgi(
        ip,
        sysauth,
        useHttps,
        command: '/usr/libexec/package-manager-call',
        params: helperArgs,
      );

      if (cgiRes != null && cgiRes.trim().isNotEmpty) {
        final parsed = _parseHelperOutputString(cgiRes);
        if (parsed.isSuccess) {
          await _refreshDashboard();
        }
        return parsed;
      }
    } catch (_) {}

    // 2. Secondary fallback: file.exec /usr/libexec/package-manager-call
    try {
      final List<String> helperArgs;
      if (action == 'update') {
        helperArgs = ['update'];
      } else if (cleanPkg.isNotEmpty) {
        helperArgs = [action, cleanPkg];
      } else {
        helperArgs = [action];
      }

      final helperRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/usr/libexec/package-manager-call',
          'params': helperArgs,
        },
      );

      final parsedHelper = _parsePackageHelperOutput(helperRpc);
      // If package-manager-call executed (even if command failed), return its structured result
      if (!parsedHelper.isMethodNotFound) {
        if (parsedHelper.isSuccess) {
          await _refreshDashboard();
        }
        return parsedHelper;
      }
    } catch (_) {}

    // 2. Direct binary fallback (apk / opkg)
    try {
      List<String> rawArgs;
      if (action == 'install') {
        rawArgs = isApk ? ['add', cleanPkg] : ['install', cleanPkg];
      } else if (action == 'remove') {
        rawArgs = isApk ? ['del', cleanPkg] : ['remove', cleanPkg];
      } else if (action == 'update') {
        rawArgs = ['update'];
      } else if (action == 'upgrade') {
        rawArgs = isApk
            ? ['add', '--upgrade', cleanPkg]
            : ['upgrade', cleanPkg];
      } else {
        rawArgs = [action];
        if (cleanPkg.isNotEmpty) rawArgs.add(cleanPkg);
      }

      final rawRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': cmd, 'params': rawArgs},
      );

      final result = RpcResult.classifyExecResult<String>(rawRpc, (data) {
        if (data is Map && data['stdout'] != null) {
          return data['stdout'].toString();
        }
        return 'Action completed successfully';
      });

      if (result.status == RpcCallStatus.methodNotFound) {
        Logger.warning(
          'Package action returned methodNotFound. Triggering background capability re-probe.',
        );
        unawaited(_redetectCapabilities());
      }

      if (result.isSuccess) {
        await _refreshDashboard();
      }

      return result;
    } catch (e) {
      Logger.error('Failed package action $action for $cleanPkg: $e');
      return RpcResult.networkError(
        'Network error executing package action: $e',
      );
    }
  }

  /// Backward-compatible wrapper for managePackage
  Future<bool> managePackage({
    required String packageName,
    required String action,
  }) async {
    final res = await managePackageResult(
      packageName: packageName,
      action: action,
    );
    return res.isSuccess;
  }
}
