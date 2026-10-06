// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/sqm_screen.dart';

/// Module descriptor for Smart Queue Management (SQM) / Bufferbloat mitigation.
class SqmModule extends LuciModule {
  @override
  String get id => 'sqm';

  @override
  String get name => 'Smart Queue Management (SQM)';

  @override
  String get description =>
      'Bufferbloat mitigation, traffic shaping, CAKE and FQ-CoDel queueing disciplines';

  @override
  IconData get icon => Icons.speed_outlined;

  @override
  IconData get selectedIcon => Icons.speed_rounded;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 33;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const SqmScreen();
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    return null;
  }
}
