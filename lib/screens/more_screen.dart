// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yala/main.dart';
import 'package:yala/screens/login_screen.dart';
import 'package:yala/screens/manage_routers_screen.dart';
import 'package:yala/screens/settings_screen.dart';
import 'package:yala/widgets/luci_app_bar.dart';
import 'package:yala/widgets/luci_toast.dart';
import 'package:yala/design/luci_design_system.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yala/config/app_config.dart';
import 'package:yala/utils/http_client_manager.dart';
import 'package:yala/utils/gateway_utils.dart';
import 'package:yala/services/secure_storage_service.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/modules/core/luci_module_registry.dart';
import 'package:yala/widgets/theme_router_logo.dart';
import 'package:yala/l10n/app_localizations.dart';

class _MoreScreenSection extends StatelessWidget {
  final List<Widget> tiles;

  const _MoreScreenSection({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Column(
        children: ListTile.divideTiles(context: context, tiles: tiles).toList(),
      ),
    );
  }
}

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  AppState? _appState;

  @override
  void initState() {
    super.initState();
    // Do not use context here
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = ref.read(appStateProvider);
    _appState!.onRouterBackOnline = _showRouterBackOnlineMessage;
  }

  @override
  void dispose() {
    // Clear the callback before calling super.dispose()
    _appState?.onRouterBackOnline = null;
    super.dispose();
  }

  void _showRouterBackOnlineMessage() {
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      context.showToastSuccess(
        l10n?.moreRouterOnline ?? 'Router Online',
        subtitle:
            l10n?.moreRouterOnlineSubtitle ??
            'Router is back online, reconnecting…',
        actionKey: 'router_reboot',
      );
    }
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final appState = ref.read(appStateProvider);
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Text(l10n?.dialogLogoutTitle ?? 'Logout?'),
          content: SingleChildScrollView(
            child: Text(
              l10n?.dialogLogoutMessage ?? 'Are you sure you want to logout?',
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(l10n?.actionCancel ?? 'Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(l10n?.tileLogout ?? 'Logout'),
              onPressed: () async {
                await appState.logout();
                // Clear all accepted certificates on logout
                await HttpClientManager().clearAcceptedCertificates();
                if (context.mounted) {
                  final creds = await SecureStorageService().getCredentials();
                  final detectedGateway = await GatewayUtils.detectGatewayIp();
                  final effectiveIp =
                      (creds['ipAddress'] != null &&
                          creds['ipAddress']!.isNotEmpty)
                      ? creds['ipAddress']
                      : detectedGateway;

                  if (context.mounted) {
                    await Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => LoginScreen(
                          initialIp: effectiveIp,
                          initialUsername: creds['username'],
                          initialPassword: creds['password'],
                        ),
                      ),
                      (Route<dynamic> route) => false,
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRebootDialog(BuildContext context) async {
    final appState = ref.read(appStateProvider);
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Text(l10n?.dialogRebootTitle ?? 'Reboot Router?'),
          content: SingleChildScrollView(
            child: Text(
              l10n?.dialogRebootMessage ??
                  'This will reboot the router. The app will lose connection until it comes back online. Continue?',
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(l10n?.actionCancel ?? 'Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            FilledButton(
              child: Text(l10n?.dialogRebootConfirm ?? 'Reboot'),
              onPressed: () async {
                final parentContext = Navigator.of(context).context;
                Navigator.of(context).pop();
                const actionKey = 'router_reboot';
                if (parentContext.mounted) {
                  parentContext.showToastLoading(
                    l10n?.dialogRebootToast ?? 'Rebooting Router',
                    subtitle:
                        l10n?.dialogRebootToastSubtitle ??
                        'Router is rebooting... The app will automatically reconnect once online.',
                    actionKey: actionKey,
                    timeout: const Duration(seconds: 45),
                  );
                }
                final success = await appState.reboot(
                  context: parentContext.mounted ? parentContext : null,
                );
                if (parentContext.mounted && !success) {
                  final parentL10n = AppLocalizations.of(parentContext);
                  parentContext.showToastError(
                    parentL10n?.moreRebootFailed ?? 'Reboot Failed',
                    subtitle:
                        parentL10n?.moreRebootFailedSubtitle ??
                        'Failed to send reboot command to router.',
                    actionKey: actionKey,
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    unawaited(
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            actionsOverflowButtonSpacing: 8,
            actionsOverflowDirection: VerticalDirection.down,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const ThemeRouterLogo(width: 28, height: 28, showShadow: false),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Yala',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${l10n?.dialogAboutVersion ?? "Version"} ${info.version}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer.withValues(
                            alpha: 0.7,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'GPL-3.0-or-later',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n?.aboutAppDescription ??
                        'A modern, high-performance OpenWrt router management mobile application.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n?.aboutAttributionCredits ??
                              'Attribution & Credits:',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• ${l10n?.aboutForkNotice ?? "Originally based on cogwheel0/luci-mobile"}\n'
                          '• ${l10n?.aboutOriginalWorkNotice ?? "Original work Copyright (C) 2025–2026 cogwheel0"}\n'
                          '• ${l10n?.aboutModificationsNotice ?? "Modifications Copyright (C) 2026 @nightcodex7"}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showGplLicenseDialog(context);
                        },
                        icon: const Icon(Icons.policy_outlined, size: 16),
                        label: Text(l10n?.btnLicenseGplv3 ?? 'License (GPLv3)'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await launchUrlString(
                            AppConfig.githubRepositoryUrl,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.code_rounded, size: 16),
                        label: Text(l10n?.btnGitHub ?? 'GitHub'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await launchUrlString(
                            AppConfig.upstreamRepositoryUrl,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.fork_right_rounded, size: 16),
                        label: Text(
                          l10n?.btnOriginalProject ?? 'Original Project',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final Uri mailUri = Uri(
                            scheme: 'mailto',
                            path: AppConfig.supportEmail,
                            queryParameters: {
                              'subject': 'Yala Support Request',
                            },
                          );
                          await launchUrlString(
                            mailUri.toString(),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.email_outlined, size: 16),
                        label: Text(l10n?.contactSupportTitle ?? 'Support'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n?.actionClose ?? 'Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGplLicenseDialog(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.policy_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'License & Copyleft (GPLv3)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConfig.licenseName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SPDX-License-Identifier: ${AppConfig.licenseSpdx}',
                      style: LuciTypography.monoStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Credits & Copyright:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '• Original Work: Copyright (C) 2025–2026 cogwheel0 (luci-mobile)\n'
                '• Modifications: Copyright (C) 2026 @nightcodex7',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Copyleft & Freedom Notice:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppConfig.gplWarrantyDisclaimer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await launchUrlString(
                AppConfig.upstreamRepositoryUrl,
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.fork_right_rounded, size: 16),
            label: Text(l10n?.btnOriginalProject ?? 'Original Project'),
          ),
          TextButton.icon(
            onPressed: () async {
              await launchUrlString(
                '${AppConfig.githubRepositoryUrl}/blob/main/LICENSE',
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(l10n?.btnFullGplText ?? 'Full GPL Text'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n?.actionClose ?? 'Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: LuciAppBar(title: l10n?.navMore ?? 'More'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LuciSectionHeader(l10n?.secDeviceManagement ?? 'Device Management'),
            Builder(
              builder: (context) {
                final isRebooting = ref.watch(appStateProvider).isRebooting;
                return _MoreScreenSection(
                  tiles: [
                    _buildMoreTile(
                      context,
                      icon: Icons.router_rounded,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: l10n?.tileManageRouters ?? 'Manage Routers',
                      subtitle:
                          l10n?.tileManageRoutersSubtitle ??
                          'Switch, add, or edit router profiles',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ManageRoutersScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMoreTile(
                      context,
                      icon: Icons.restart_alt,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: l10n?.tileRebootRouter ?? 'Reboot Router',
                      subtitle:
                          l10n?.tileRebootRouterSubtitle ??
                          'Perform a system restart',
                      onTap: isRebooting
                          ? null
                          : () => _showRebootDialog(context),
                      enabled: !isRebooting,
                      showSpinner: isRebooting,
                    ),
                  ],
                );
              },
            ),
            LuciSectionHeader(
              l10n?.secManagementModules ?? 'Management Modules',
            ),
            _MoreScreenSection(
              tiles: LuciModuleRegistry.instance.enabledModules
                  .where((m) => !m.showInBottomNav)
                  .map((module) {
                    final (modName, modDesc) = _getLocalizedModuleInfo(
                      module.id,
                      l10n,
                      module.name,
                      module.description,
                    );
                    return _buildMoreTile(
                      context,
                      icon: module.icon,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: modName,
                      subtitle: modDesc,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => module.buildScreen(context),
                          ),
                        );
                      },
                    );
                  })
                  .toList(),
            ),
            LuciSectionHeader(l10n?.secApplication ?? 'Application'),
            _MoreScreenSection(
              tiles: [
                _buildMoreTile(
                  context,
                  icon: Icons.settings_outlined,
                  iconColor: Theme.of(context).colorScheme.primary,
                  title: l10n?.settingsTitle ?? 'Settings',
                  subtitle:
                      l10n?.moreSettingsSubtitle ?? 'Configure app preferences',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
                _buildMoreTile(
                  context,
                  icon: Icons.info_outline,
                  iconColor: Theme.of(context).colorScheme.secondary,
                  title: l10n?.tileAbout ?? 'About',
                  subtitle:
                      l10n?.tileAboutSubtitle ??
                      'App version, license, and credits',
                  onTap: () => _showAboutDialog(context),
                ),
                _buildMoreTile(
                  context,
                  icon: Icons.logout,
                  iconColor: Theme.of(context).colorScheme.error,
                  title: l10n?.tileLogout ?? 'Logout',
                  subtitle:
                      l10n?.tileLogoutSubtitle ??
                      'End your session and sign out',
                  titleColor: Theme.of(context).colorScheme.error,
                  subtitleColor: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.7),
                  onTap: () => _showLogoutDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  (String, String) _getLocalizedModuleInfo(
    String id,
    AppLocalizations? l10n,
    String defaultName,
    String defaultDesc,
  ) {
    if (l10n == null) return (defaultName, defaultDesc);
    switch (id) {
      case 'system_monitoring':
        return (l10n.modSystemMonitoringName, l10n.modSystemMonitoringDesc);
      case 'storage_monitoring':
        return (l10n.modStorageName, l10n.modStorageDesc);
      case 'charting':
        return (l10n.modChartingName, l10n.modChartingDesc);
      case 'wireless':
      case 'wireless_management':
        return (l10n.modWirelessName, l10n.modWirelessDesc);
      case 'firewall':
      case 'firewall_security':
        return (l10n.modFirewallName, l10n.modFirewallDesc);
      case 'dhcp_dns':
        return (l10n.modDhcpDnsName, l10n.modDhcpDnsDesc);
      case 'services':
      case 'services_system':
        return (l10n.modServicesName, l10n.modServicesDesc);
      case 'vpn':
      case 'vpn_connectivity':
        return (l10n.modVpnName, l10n.modVpnDesc);
      case 'packages':
      case 'package_manager':
        return (l10n.modPackagesName, l10n.modPackagesDesc);
      case 'backup':
      case 'system_backup_upgrade':
        return (l10n.modBackupName, l10n.modBackupDesc);
      case 'parental_controls':
        return (l10n.modParentalControlsName, l10n.modParentalControlsDesc);
      case 'diagnostics':
        return (l10n.modDiagnosticsName, l10n.modDiagnosticsDesc);
      default:
        return (defaultName, defaultDesc);
    }
  }

  Widget _buildMoreTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool enabled = true,
    Color? titleColor,
    Color? subtitleColor,
    bool showSpinner = false,
    bool showBadge = false,
  }) {
    final theme = Theme.of(context);
    // Persistent spinning icon using AnimationController
    Widget spinningIconWidget = Icon(
      icon,
      color: iconColor,
      size: 24,
      semanticLabel: title,
    );
    if (showSpinner) {
      spinningIconWidget = _SpinningIcon(
        icon: icon,
        color: iconColor,
        label: title,
      );
    }
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(10),
              child: spinningIconWidget,
            ),
            if (showBadge)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.pink.shade400,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.favorite,
                    size: 8,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          title,
          style: titleColor != null
              ? LuciTextStyles.cardTitle(context).copyWith(color: titleColor)
              : LuciTextStyles.cardTitle(context),
          semanticsLabel: title,
        ),
        subtitle: Text(
          subtitle,
          style: subtitleColor != null
              ? LuciTextStyles.cardSubtitle(
                  context,
                ).copyWith(color: subtitleColor)
              : LuciTextStyles.cardSubtitle(context),
          semanticsLabel: subtitle,
        ),
        enabled: enabled,
        onTap: enabled ? onTap : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LuciSpacing.lg,
          vertical: 10,
        ),
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        minVerticalPadding: LuciSpacing.md,
        minLeadingWidth: 0,
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}

// Persistent spinning icon widget
class _SpinningIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _SpinningIcon({
    required this.icon,
    required this.color,
    required this.label,
  });
  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 6.28319, // 2 * pi
          child: Icon(
            widget.icon,
            color: widget.color,
            size: 24,
            semanticLabel: widget.label,
          ),
        );
      },
    );
  }
}
