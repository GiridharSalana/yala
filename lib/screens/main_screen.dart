// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/screens/dashboard_screen.dart';
import 'package:yala/screens/clients_screen.dart';
import 'package:yala/screens/interfaces_screen.dart';
import 'package:yala/screens/more_screen.dart';
import 'package:yala/modules/wireless_management/screens/wireless_management_screen.dart';
import 'package:yala/main.dart';
import 'package:yala/state/app_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yala/widgets/scroll_jitter_guard.dart';
import 'package:yala/design/luci_design_system.dart';
import 'package:yala/utils/gateway_utils.dart';
import 'package:yala/services/secure_storage_service.dart';
import 'package:yala/screens/login_screen.dart';
import 'package:yala/utils/os_platform_integration.dart';
import 'package:yala/l10n/app_localizations.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;
  final String? interfaceToScroll;

  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  /// Exposes multi-line nav measurement for adaptive layout testing and inspection.
  static bool shouldUseMultiLineNav({
    required BuildContext context,
    required double slotWidth,
    required List<String> labels,
    required TextScaler textScaler,
  }) => _MainScreenState.shouldUseMultiLineNav(
    context: context,
    slotWidth: slotWidth,
    labels: labels,
    textScaler: textScaler,
  );

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String? _currentInterfaceToScroll;
  final Set<int> _activatedTabs = {0};
  final List<int> _tabHistory = [0];
  bool _isRedirectingToLogin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 4);
    }
    _activatedTabs.add(_selectedIndex);
    _tabHistory.clear();
    _tabHistory.add(_selectedIndex);
    _currentInterfaceToScroll = widget.interfaceToScroll;
    if (_selectedIndex != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(appStateProvider).setDashboardTabActive(false);
        }
      });
    }
  }

  AppState? _appState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = ref.read(appStateProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appState?.pauseThroughputTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final appState = ref.read(appStateProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      appState.pauseThroughputTimer();
    } else if (state == AppLifecycleState.resumed) {
      appState.handleAppResume();
      if (_selectedIndex == 0) {
        appState.resumeThroughputTimer(immediateTick: true);
      } else {
        appState.setDashboardTabActive(false);
      }
    }
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.interfaceToScroll != oldWidget.interfaceToScroll) {
      _currentInterfaceToScroll = widget.interfaceToScroll;
    }

    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 4);
      _activatedTabs.add(_selectedIndex);
      _tabHistory.remove(_selectedIndex);
      _tabHistory.add(_selectedIndex);
    }
  }

  void _clearInterfaceToScroll() {
    if (_currentInterfaceToScroll != null) {
      setState(() {
        _currentInterfaceToScroll = null;
      });
    }
  }

  void _onItemTapped(int index) {
    FocusScope.of(context).unfocus();
    final safeIndex = index.clamp(0, 4);
    if (_selectedIndex == safeIndex) return;
    setState(() {
      _selectedIndex = safeIndex;
      _activatedTabs.add(safeIndex);
      _tabHistory.remove(safeIndex);
      _tabHistory.add(safeIndex);
    });

    ref.read(appStateProvider).setDashboardTabActive(safeIndex == 0);

    if (_selectedIndex != 1 && _currentInterfaceToScroll != null) {
      _clearInterfaceToScroll();
    }
  }

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.exit_to_app_rounded,
                color: colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n?.exitDialogTitle ?? 'Exit Yala?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n?.exitDialogMessage ??
                'Are you sure you want to exit the application?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(l10n?.actionExit ?? 'Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);

    // Guardrail: If session is completely unauthenticated and not in reviewer mode,
    // redirect smoothly to LoginScreen instead of leaving the app on a blank main screen.
    if (appState.hasActiveSession || appState.sessionBootstrapActive) {
      _isRedirectingToLogin = false;
    } else if (!appState.isLoading && !_isRedirectingToLogin) {
      _isRedirectingToLogin = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final state = ref.read(appStateProvider);
        if (state.hasActiveSession ||
            state.sessionBootstrapActive ||
            state.isLoading) {
          _isRedirectingToLogin = false;
          return;
        }
        if (mounted &&
            !ref.read(appStateProvider).hasActiveSession &&
            !ref.read(appStateProvider).isLoading) {
          final creds = await SecureStorageService().getCredentials();
          final detectedGateway = await GatewayUtils.detectGatewayIp();

          if (!mounted) return;
          final currentState = ref.read(appStateProvider);
          if (currentState.hasActiveSession || currentState.isLoading) {
            _isRedirectingToLogin = false;
            return;
          }

          final effectiveIp =
              (creds['ipAddress'] != null && creds['ipAddress']!.isNotEmpty)
              ? creds['ipAddress']
              : detectedGateway;

          if (!mounted || !context.mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => LoginScreen(
                initialIp: effectiveIp,
                initialUsername: creds['username'],
                initialPassword: creds['password'],
              ),
            ),
            (route) => false,
          );
        } else {
          _isRedirectingToLogin = false;
        }
      });
    }

    if (appState.requestedTab != null &&
        appState.requestedTab != _selectedIndex) {
      final safeRequestedTab = appState.requestedTab!.clamp(0, 4);
      final requestedInterface = appState.requestedInterfaceToScroll;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).unfocus();
        setState(() {
          _selectedIndex = safeRequestedTab;
          _activatedTabs.add(safeRequestedTab);
          _tabHistory.remove(safeRequestedTab);
          _tabHistory.add(safeRequestedTab);
          if (requestedInterface != null) {
            _currentInterfaceToScroll = requestedInterface;
          }
        });
        ref.read(appStateProvider).setDashboardTabActive(safeRequestedTab == 0);
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
      });
    }

    if (appState.reviewerModeEnabled &&
        !appState.hasShownReviewerNotice &&
        !appState.isDashboardLoading &&
        appState.dashboardData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowReviewerNotice();
      });
    }

    final isRebooting = appState.isRebooting;
    final colorScheme = Theme.of(context).colorScheme;
    final isTablet = LuciBreakpoints.isTablet(context);
    final l10n = AppLocalizations.of(context);

    // Build the shared IndexedStack content used in both phone and tablet layouts
    final body = ScrollJitterGuard(
      child: IndexedStack(
        index: _selectedIndex,
        children: [
          _activatedTabs.contains(0)
              ? DashboardScreen(isTabActive: _selectedIndex == 0)
              : const SizedBox.shrink(),
          _activatedTabs.contains(1)
              ? InterfacesScreen(
                  scrollToInterface: _currentInterfaceToScroll,
                  onScrollComplete: _clearInterfaceToScroll,
                  isTabActive: _selectedIndex == 1,
                )
              : const SizedBox.shrink(),
          _activatedTabs.contains(2)
              ? ClientsScreen(isTabActive: _selectedIndex == 2)
              : const SizedBox.shrink(),
          _activatedTabs.contains(3)
              ? WirelessManagementScreen(isTabActive: _selectedIndex == 3)
              : const SizedBox.shrink(),
          _activatedTabs.contains(4)
              ? const MoreScreen()
              : const SizedBox.shrink(),
        ],
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 1. If currently on a secondary tab, navigate back to previous tab or Dashboard
        if (_tabHistory.length > 1) {
          setState(() {
            _tabHistory.removeLast();
            final previousTab = _tabHistory.last;
            _selectedIndex = previousTab;
            if (_selectedIndex != 1 && _currentInterfaceToScroll != null) {
              _clearInterfaceToScroll();
            }
          });
          ref.read(appStateProvider).setDashboardTabActive(_selectedIndex == 0);
          return;
        } else if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
            _tabHistory.clear();
            _tabHistory.add(0);
            if (_currentInterfaceToScroll != null) {
              _clearInterfaceToScroll();
            }
          });
          ref.read(appStateProvider).setDashboardTabActive(true);
          return;
        }

        // 2. Already on Dashboard (root) — prompt user with exit confirmation dialog
        final shouldExit = await _showExitConfirmationDialog(context);
        if (shouldExit == true && context.mounted) {
          await OsPlatformIntegration.exitApp(context: context);
        }
      },
      // ── Tablet / Chromebook / DeX layout: NavigationRail on the left ─────────
      child: isTablet
          ? Scaffold(
              body: Row(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            selectedIndex: _selectedIndex,
                            onDestinationSelected: isRebooting
                                ? null
                                : _onItemTapped,
                            labelType: NavigationRailLabelType.all,
                            useIndicator: true,
                            indicatorColor: colorScheme.primaryContainer,
                            selectedIconTheme: IconThemeData(
                              color: colorScheme.onPrimaryContainer,
                            ),
                            unselectedIconTheme: IconThemeData(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            selectedLabelTextStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                            unselectedLabelTextStyle: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            backgroundColor: colorScheme.surfaceContainer,
                            destinations: [
                              NavigationRailDestination(
                                icon: const Icon(Icons.dashboard_outlined),
                                selectedIcon: const Icon(
                                  Icons.dashboard_rounded,
                                ),
                                label: Text(l10n?.navDashboard ?? 'Dashboard'),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.lan_outlined),
                                selectedIcon: const Icon(Icons.lan),
                                label: Text(
                                  l10n?.navInterfaces ?? 'Interfaces',
                                ),
                              ),
                              NavigationRailDestination(
                                icon: Builder(
                                  builder: (context) {
                                    final connectedCount = appState.clients
                                        .where((c) => c.isConnected)
                                        .length;
                                    return Badge(
                                      isLabelVisible: connectedCount > 0,
                                      label: Text(
                                        connectedCount > 99
                                            ? '99+'
                                            : '$connectedCount',
                                      ),
                                      child: const Icon(Icons.people_outline),
                                    );
                                  },
                                ),
                                selectedIcon: const Icon(Icons.people),
                                label: Text(l10n?.navClients ?? 'Clients'),
                              ),
                              NavigationRailDestination(
                                icon: Builder(
                                  builder: (context) {
                                    final wirelessCount =
                                        appState.activeWirelessInterfacesCount;
                                    return Badge(
                                      isLabelVisible: wirelessCount > 0,
                                      label: Text(
                                        wirelessCount > 99
                                            ? '99+'
                                            : '$wirelessCount',
                                      ),
                                      child: const Icon(Icons.wifi_outlined),
                                    );
                                  },
                                ),
                                selectedIcon: const Icon(Icons.wifi),
                                label: Text(l10n?.navWireless ?? 'Wireless'),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.more_horiz_outlined),
                                selectedIcon: const Icon(Icons.more_horiz),
                                label: Text(l10n?.navMore ?? 'More'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(child: body),
                ],
              ),
            )
          // ── Phone layout: Custom bottom navigation bar ─────────────────────
          : Scaffold(
              body: body,
              bottomNavigationBar: Container(
                color: colorScheme.surfaceContainer,
                child: SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textScaler = MediaQuery.textScalerOf(context);
                      final textScale = textScaler.scale(1.0);
                      final slotWidth = constraints.maxWidth / 5.0;

                      final labels = [
                        l10n?.navInterfaces ?? 'Interfaces',
                        l10n?.navClients ?? 'Clients',
                        l10n?.navDashboard ?? 'Dashboard',
                        l10n?.navWireless ?? 'Wireless',
                        l10n?.navMore ?? 'More',
                      ];

                      // Adaptive navigation layout:
                      // If any label wraps beyond 1 line (due to translation or accessibility text scaling),
                      // adapt bar height and items to multi-line mode (68px base, up to 2 lines).
                      // Otherwise, maintain compact single-line mode (54px base).
                      final isMultiLine = shouldUseMultiLineNav(
                        context: context,
                        slotWidth: slotWidth,
                        labels: labels,
                        textScaler: textScaler,
                      );

                      final barHeight = isMultiLine
                          ? (68.0 * textScale).clamp(66.0, 88.0)
                          : (54.0 * textScale).clamp(52.0, 64.0);
                      const centerOffset = 8.0;
                      final stackHeight = barHeight + centerOffset;
                      final centerCircleSize = isMultiLine ? 44.0 : 46.0;
                      const centerIconSize = 22.0;
                      const sideIconSize = 22.0;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        height: stackHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.bottomCenter,
                          children: [
                            // Flat Matt Bottom Bar Container
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              height: barHeight,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainer,
                                border: Border(
                                  top: BorderSide(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Left Wing (Interfaces & Clients)
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _buildNavItem(
                                            index: 1,
                                            label: labels[0],
                                            icon: Icons.lan_outlined,
                                            selectedIcon: Icons.lan,
                                            isRebooting: isRebooting,
                                            isMultiLine: isMultiLine,
                                            iconSize: sideIconSize,
                                          ),
                                        ),
                                        Expanded(
                                          child: _buildNavItem(
                                            index: 2,
                                            label: labels[1],
                                            icon: Icons.people_outline,
                                            selectedIcon: Icons.people,
                                            isRebooting: isRebooting,
                                            isMultiLine: isMultiLine,
                                            iconSize: sideIconSize,
                                            badgeCount: appState.clients
                                                .where((c) => c.isConnected)
                                                .length,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Center Clearance Spacer for Elevated Dashboard Badge
                                  SizedBox(width: slotWidth),
                                  // Right Wing (Wireless & More)
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _buildNavItem(
                                            index: 3,
                                            label: labels[3],
                                            icon: Icons.wifi_outlined,
                                            selectedIcon: Icons.wifi,
                                            isRebooting: isRebooting,
                                            isMultiLine: isMultiLine,
                                            iconSize: sideIconSize,
                                            badgeCount: appState
                                                .activeWirelessInterfacesCount,
                                          ),
                                        ),
                                        Expanded(
                                          child: _buildNavItem(
                                            index: 4,
                                            label: labels[4],
                                            icon: Icons.more_horiz_outlined,
                                            selectedIcon: Icons.more_horiz,
                                            isRebooting: false,
                                            isMultiLine: isMultiLine,
                                            iconSize: sideIconSize,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Solid Flat Matt Circular Center Dashboard Badge Button (Index 0)
                            Align(
                              alignment: Alignment.topCenter,
                              child: Transform.translate(
                                offset: const Offset(0, -centerOffset),
                                child: GestureDetector(
                                  onTap: () {
                                    if (isRebooting) return;
                                    _onItemTapped(0);
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  child: SizedBox(
                                    width: slotWidth,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          curve: Curves.easeInOut,
                                          width: centerCircleSize,
                                          height: centerCircleSize,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _selectedIndex == 0
                                                ? colorScheme.primary
                                                : colorScheme
                                                      .surfaceContainerHigh,
                                            border: Border.all(
                                              color: colorScheme.surface,
                                              width: 2.5,
                                            ),
                                          ),
                                          child: Icon(
                                            _selectedIndex == 0
                                                ? Icons.dashboard_rounded
                                                : Icons.dashboard_outlined,
                                            color: _selectedIndex == 0
                                                ? colorScheme.onPrimary
                                                : colorScheme.onSurfaceVariant,
                                            size: centerIconSize,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2.0,
                                          ),
                                          child: Text(
                                            labels[2],
                                            maxLines: isMultiLine ? 2 : 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: _selectedIndex == 0
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: _selectedIndex == 0
                                                  ? colorScheme.primary
                                                  : colorScheme
                                                        .onSurfaceVariant,
                                              height: 1.15,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }

  /// Determines whether bottom navigation bar needs multi-line height based on label widths.
  static bool shouldUseMultiLineNav({
    required BuildContext context,
    required double slotWidth,
    required List<String> labels,
    required TextScaler textScaler,
  }) {
    if (slotWidth <= 0) return false;
    final availableWidth = (slotWidth - 6.0).clamp(10.0, double.infinity);
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.normal,
      height: 1.15,
    );

    for (final label in labels) {
      if (label.isEmpty) continue;
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 2,
      )..layout(maxWidth: availableWidth);

      if (textPainter.computeLineMetrics().length > 1) {
        return true;
      }
    }
    return false;
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required bool isRebooting,
    required bool isMultiLine,
    required double iconSize,
    int? badgeCount,
  }) {
    final isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    final color = isRebooting
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : (isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant);

    final semanticText =
        '$label, tab ${index + 1} of 5. ${isSelected ? "Currently active tab." : "Double tap to switch to $label."}';

    return Semantics(
      selected: isSelected,
      button: true,
      label: semanticText,
      child: InkWell(
        onTap: isRebooting ? null : () => _onItemTapped(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 2.0,
            vertical: isMultiLine ? 4.0 : 2.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: iconSize + 4,
                    height: iconSize + 4,
                    child: Icon(
                      isSelected ? selectedIcon : icon,
                      color: color,
                      size: iconSize,
                    ),
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.secondary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: isMultiLine ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: color,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _checkAndShowReviewerNotice() {
    if (!mounted) return;
    final appState = ref.read(appStateProvider);
    if (appState.reviewerModeEnabled &&
        !appState.hasShownReviewerNotice &&
        !appState.isDashboardLoading &&
        appState.dashboardData != null) {
      appState.markReviewerNoticeShown();
      _showReviewerInfoDialog(context);
    }
  }

  void _showReviewerInfoDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.rate_review_outlined,
                color: colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reviewer Mode Active',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Simulated Router Session',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
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
              Text(
                'You are exploring Yala in Reviewer Mode.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This session provides pre-loaded mock datasets, simulating live OpenWrt router interfaces, connected clients, and performance metrics without needing an active router connection.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'To manage a physical OpenWrt router, toggle off Reviewer Mode in More > Connection Settings.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11.5,
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
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'GOT IT',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
