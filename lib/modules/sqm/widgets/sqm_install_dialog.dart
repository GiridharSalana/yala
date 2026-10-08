// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yala/design/luci_design_system.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/modules/storage_monitoring/models/storage_info.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/widgets/rpc_permissions_dialog.dart';

/// Modal dialog for one-click SQM installation with dual package options:
/// 1. `sqm-scripts` (Backend only, recommended for low storage; clearly notes no LuCI web controls)
/// 2. `luci-app-sqm` (Web interface + scripts; requires ~500 KB free storage)
///
/// On-demand storage assessment is performed strictly when this dialog opens.
class SqmInstallDialog extends ConsumerStatefulWidget {
  const SqmInstallDialog({super.key});

  @override
  ConsumerState<SqmInstallDialog> createState() => _SqmInstallDialogState();
}

class _SqmInstallDialogState extends ConsumerState<SqmInstallDialog> {
  String _selectedPackage = 'sqm-scripts';
  bool _isLuciInsufficientStorage = false;
  bool _isStorageExhaustedOrReadOnly = false;
  int _availableBytes = 0;
  String _targetMountPath = '/overlay';
  PackageManagerEngine _pkgMgr = PackageManagerEngine.none;

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appStateProvider);
    _pkgMgr = appState.capabilities?.packageEngine ?? PackageManagerEngine.none;
    _assessStorageAndCapabilities(appState);
  }

  void _assessStorageAndCapabilities(AppState appState) {
    _pkgMgr = appState.capabilities?.packageEngine ?? PackageManagerEngine.none;

    final dashboardData = appState.dashboardData;
    final storageOverview = StorageOverview.fromRpcData(
      dashboardData?['mountPoints'] ?? dashboardData?['sysInfo'],
      isReviewerMode: appState.reviewerModeEnabled,
    );
    final targetMount = storageOverview.overlayFs ?? storageOverview.rootFs;

    _targetMountPath = targetMount?.mountPath ?? '/overlay';
    _availableBytes = targetMount?.availableBytes ?? 0;

    // Requirement thresholds
    const int luciMinBytes = 500 * 1024; // ~500 KB
    const int scriptsMinBytes = 100 * 1024; // ~100 KB

    if (targetMount != null &&
        targetMount.isReadOnly &&
        targetMount.mountPath != '/rom') {
      _isStorageExhaustedOrReadOnly = true;
      _isLuciInsufficientStorage = true;
    } else if ((_availableBytes <= 0 && targetMount != null) ||
        (_availableBytes > 0 && _availableBytes < scriptsMinBytes)) {
      _isStorageExhaustedOrReadOnly = true;
      _isLuciInsufficientStorage = true;
    } else if (_availableBytes >= scriptsMinBytes &&
        _availableBytes < luciMinBytes) {
      _isStorageExhaustedOrReadOnly = false;
      _isLuciInsufficientStorage = true;
      if (_selectedPackage == 'luci-app-sqm') {
        _selectedPackage = 'sqm-scripts';
      }
    } else {
      // Sufficient storage for both
      _isStorageExhaustedOrReadOnly = false;
      _isLuciInsufficientStorage = false;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    _assessStorageAndCapabilities(appState);
    final isRpcMissing = appState.isMissingRpcPackages;

    final canInstall = !_isStorageExhaustedOrReadOnly && !isRpcMissing;

    return AlertDialog(
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: LuciColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.speed_rounded,
              color: LuciColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: LuciSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.modSqmInstallTitle ?? 'Install Smart Queue Management',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _pkgMgr == PackageManagerEngine.apk
                      ? 'Package Engine: APK'
                      : _pkgMgr == PackageManagerEngine.opkg
                      ? 'Package Engine: OPKG'
                      : 'Bufferbloat Mitigation',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Storage assessment indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.storage_rounded,
                    size: 16,
                    color: _isLuciInsufficientStorage
                        ? LuciStatusColors.warning
                        : LuciStatusColors.connected,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Free space in $_targetMountPath: ${_formatBytes(_availableBytes)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LuciSpacing.md),

            if (isRpcMissing) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.shade700.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.amber.shade800,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Package installation is restricted because router RPC permissions are missing.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LuciSpacing.sm),
            ],

            Text(
              l10n?.modSqmInstallChooseMethod ?? 'Select Installation Package:',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: LuciSpacing.xs),

            // Option 1: sqm-scripts
            _buildOptionCard(
              context: context,
              value: 'sqm-scripts',
              title: 'sqm-scripts',
              tag: l10n?.modSqmOptionBackendOnlyTag ?? 'Backend Only (~150 KB)',
              description:
                  l10n?.modSqmOptionScriptsDesc ??
                  'Installs core traffic shaping scripts. Ideal for storage-constrained routers.',
              warningNotice: isRpcMissing
                  ? 'Router RPC permissions missing. Installing packages requires RPC execution permissions.'
                  : (_isStorageExhaustedOrReadOnly
                        ? 'Insufficient storage: requires ~100 KB free in $_targetMountPath, but only ${_formatBytes(_availableBytes)} is available.'
                        : (l10n?.modSqmNoticeNoLuciWeb ??
                              'SQM controls will be fully accessible within YALA, but will NOT appear in the LuCI browser web interface.')),
              warningColor: isRpcMissing
                  ? Colors.amber.shade800
                  : (_isStorageExhaustedOrReadOnly
                        ? LuciStatusColors.error
                        : LuciStatusColors.info),
              warningIcon: isRpcMissing
                  ? Icons.lock_outline_rounded
                  : (_isStorageExhaustedOrReadOnly
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded),
              isEnabled: !isRpcMissing && !_isStorageExhaustedOrReadOnly,
            ),

            const SizedBox(height: LuciSpacing.sm),

            // Option 2: luci-app-sqm
            _buildOptionCard(
              context: context,
              value: 'luci-app-sqm',
              title: 'luci-app-sqm',
              tag: l10n?.modSqmOptionFullTag ?? 'Web UI + Scripts (~500 KB)',
              description:
                  l10n?.modSqmOptionLuciDesc ??
                  'Full package providing both backend shaping scripts and the browser LuCI web interface.',
              warningNotice: isRpcMissing
                  ? 'Router RPC permissions missing. Installing packages requires RPC execution permissions.'
                  : (_isLuciInsufficientStorage
                        ? (l10n?.modSqmNoticeInsufficientStorage(
                                _targetMountPath,
                                _formatBytes(_availableBytes),
                              ) ??
                              'Insufficient storage: requires ~500 KB free in $_targetMountPath, but only ${_formatBytes(_availableBytes)} is available.')
                        : null),
              warningColor: isRpcMissing
                  ? Colors.amber.shade800
                  : LuciStatusColors.error,
              warningIcon: isRpcMissing
                  ? Icons.lock_outline_rounded
                  : Icons.warning_amber_rounded,
              isEnabled:
                  !isRpcMissing &&
                  !_isLuciInsufficientStorage &&
                  !_isStorageExhaustedOrReadOnly,
            ),

            if (_isStorageExhaustedOrReadOnly) ...[
              const SizedBox(height: LuciSpacing.sm),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LuciStatusColors.errorBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: LuciStatusColors.errorBorder(context),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: LuciColors.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n?.modSqmStorageReadOnlyNotice ??
                            'Storage filesystem is read-only or full. Package installation cannot proceed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: LuciStatusColors.errorText(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
        if (isRpcMissing)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop(null);
              RpcPermissionsDialog.show(
                context,
                actionName: 'SQM Installation',
              );
            },
            icon: const Icon(Icons.build_circle_outlined, size: 18),
            label: const Text('Fix Permissions'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
            ),
          )
        else
          FilledButton.icon(
            onPressed: canInstall
                ? () => Navigator.of(context).pop(_selectedPackage)
                : null,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(l10n?.actionInstallNow ?? 'Install Now'),
          ),
      ],
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required String value,
    required String title,
    required String tag,
    required String description,
    required bool isEnabled,
    String? warningNotice,
    Color? warningColor,
    IconData? warningIcon,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selectedPackage == value && isEnabled;

    final cardBorder = isSelected
        ? Border.all(color: LuciColors.primary, width: 2)
        : Border.all(
            color: isEnabled
                ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          );

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.45,
      child: InkWell(
        onTap: isEnabled
            ? () {
                setState(() {
                  _selectedPackage = value;
                });
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? LuciColors.primary.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: isEnabled ? 0.35 : 0.15,
                  ),
            borderRadius: BorderRadius.circular(12),
            border: cardBorder,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? LuciColors.primary
                            : (isEnabled
                                  ? theme.colorScheme.outline
                                  : theme.colorScheme.outlineVariant),
                        width: 2,
                      ),
                      color: isSelected
                          ? LuciColors.primary
                          : Colors.transparent,
                    ),
                    child: isSelected
                        ? const Center(
                            child: Icon(
                              Icons.circle,
                              size: 10,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tag,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 4),
                child: Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (warningNotice != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (warningColor ?? LuciColors.primary).withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (warningColor ?? LuciColors.primary).withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          warningIcon ?? Icons.info_outline_rounded,
                          size: 14,
                          color: warningColor ?? LuciColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            warningNotice,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color:
                                  warningColor ?? theme.colorScheme.onSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
