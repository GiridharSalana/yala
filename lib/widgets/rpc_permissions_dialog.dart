// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/widgets/luci_toast.dart';

/// Standard dialog displayed when a user attempts to view, configure, or repair
/// router RPC packages or execution permissions.
class RpcPermissionsDialog extends StatelessWidget {
  final String actionName;
  final String? customMessage;

  const RpcPermissionsDialog({
    super.key,
    required this.actionName,
    this.customMessage,
  });

  /// Static helper to display the [RpcPermissionsDialog].
  static Future<void> show(
    BuildContext context, {
    required String actionName,
    String? customMessage,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => RpcPermissionsDialog(
        actionName: actionName,
        customMessage: customMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appState = AppState.instance;
    final caps = appState.capabilities;
    final isComplete = caps?.isRpcComplete == true;

    final isApk = caps?.packageEngine == PackageManagerEngine.apk;
    final remediationCommand = isApk
        ? 'apk update && apk add luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status && /etc/init.d/rpcd restart'
        : 'opkg update && opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status && /etc/init.d/rpcd restart';

    return AlertDialog(
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isComplete ? Colors.teal : Colors.amber.shade700)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isComplete
                  ? Icons.verified_user_rounded
                  : Icons.lock_outline_rounded,
              color: isComplete ? Colors.teal : Colors.amber.shade800,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isComplete
                  ? (l10n?.tileRpcPermissions ?? 'RPC & Permissions')
                  : (l10n?.rpcdPermissionDenied ?? 'Permission Required'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isComplete
                  ? 'Router RPC modules and backend execution permissions are verified and functioning properly.'
                  : (customMessage ??
                        (l10n?.rpcdPermissionDeniedMessage(actionName) ??
                            'Your router does not have permission or RPC support to execute "$actionName".')),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            _buildStatusItem(
              context,
              title: 'LuCI RPC Modules',
              subtitle: 'rpcd-mod-luci, luci-mod-rpc, iwinfo',
              isOk: caps?.hasLuciRpc ?? false,
            ),
            const SizedBox(height: 8),
            _buildStatusItem(
              context,
              title: 'Backend Execution Permissions',
              subtitle: 'ubus session access to file.exec',
              isOk: caps?.hasFileExec ?? false,
            ),
            const SizedBox(height: 8),
            _buildStatusItem(
              context,
              title: 'UCI Configuration Access',
              subtitle: 'ubus session read/write access to uci',
              isOk: caps?.hasUciWriteAccess ?? false,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.terminal_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isComplete
                            ? 'Manual Setup / Verification Script'
                            : 'Manual SSH Command',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    remediationCommand,
                    style: GoogleFonts.geistMono(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: remediationCommand),
                        );
                        context.showToastSuccess(
                          'Command Copied',
                          subtitle: 'Paste into router SSH terminal',
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text(
                        'Copy Command',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            isComplete
                ? (l10n?.btnCancelClose ?? 'Close')
                : (l10n?.btnCancelClose ?? 'Cancel'),
          ),
        ),
        if (isComplete)
          OutlinedButton.icon(
            onPressed: () async {
              final parentContext = Navigator.of(context).context;
              Navigator.of(context).pop();
              const actionKey = 'rpc_repair_dialog';
              LuciToastManager.safeShowLoading(
                parentContext,
                'Re-checking router...',
                subtitle: 'Verifying RPC modules and permissions...',
                actionKey: actionKey,
                timeout: const Duration(seconds: 30),
              );
              final success = await appState.autoFixPermissions(
                context: parentContext.mounted ? parentContext : null,
              );
              if (success) {
                LuciToastManager.safeShowSuccess(
                  null,
                  'Permissions Verified',
                  subtitle: 'RPC modules and permissions are active.',
                  actionKey: actionKey,
                );
              } else {
                LuciToastManager.safeShowError(
                  null,
                  'Verification Incomplete',
                  subtitle: 'Please check your router SSH terminal.',
                  actionKey: actionKey,
                );
              }
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Re-verify / Repair'),
          )
        else
          FilledButton.icon(
            onPressed: () async {
              final parentContext = Navigator.of(context).context;
              Navigator.of(context).pop();
              const actionKey = 'rpc_autofix_dialog';
              LuciToastManager.safeShowLoading(
                parentContext,
                'Fixing permissions...',
                subtitle: 'Installing RPC packages & updating ACLs...',
                actionKey: actionKey,
                timeout: const Duration(seconds: 45),
              );
              final success = await appState.autoFixPermissions(
                context: parentContext.mounted ? parentContext : null,
              );
              if (success) {
                LuciToastManager.safeShowSuccess(
                  null,
                  'Permissions Fixed',
                  subtitle:
                      'RPC packages and permissions granted successfully!',
                  actionKey: actionKey,
                );
              } else {
                LuciToastManager.safeShowError(
                  null,
                  'Permission Fix Failed',
                  subtitle: 'Please run the manual SSH command above.',
                  actionKey: actionKey,
                );
              }
            },
            icon: const Icon(Icons.build_circle_outlined, size: 16),
            label: Text(l10n?.btnFixAutomatically ?? 'Fix Automatically'),
          ),
      ],
    );
  }

  Widget _buildStatusItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool isOk,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          isOk ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: isOk ? Colors.teal : Colors.amber.shade800,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (isOk ? Colors.teal : Colors.amber.shade800).withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isOk ? 'OK' : 'MISSING',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isOk ? Colors.teal : Colors.amber.shade800,
            ),
          ),
        ),
      ],
    );
  }
}
