// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/adguard_home_screen.dart';
import 'widgets/adguard_dashboard_card.dart';

/// LuCI feature module providing AdGuard Home DNS sinkhole management,
/// service lifecycle control, and telemetry visualization.
class AdGuardHomeModule extends LuciModule {
  @override
  String get id => 'adguard_home';

  @override
  String get name => 'AdGuard Home';

  @override
  String get description =>
      'DNS sinkhole & network-wide ad-blocking management';

  @override
  IconData get icon => Icons.shield_outlined;

  @override
  IconData get selectedIcon => Icons.shield;

  @override
  LuciModuleCategory get category => LuciModuleCategory.security;

  @override
  int get priority => 52;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    final routerId = params?['routerId'] as String?;
    return AdGuardHomeScreen(routerId: routerId);
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    return const AdGuardDashboardCard();
  }
}
