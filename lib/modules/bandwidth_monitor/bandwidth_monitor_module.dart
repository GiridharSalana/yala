// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/bandwidth_monitor_screen.dart';

class BandwidthMonitorModule extends LuciModule {
  @override
  String get id => 'bandwidth_monitor';

  @override
  String get name => 'Bandwidth Monitor';

  @override
  String get description =>
      'Real-time per-device bandwidth usage, traffic history charts & LuCI data statistics';

  @override
  IconData get icon => Icons.speed_rounded;

  @override
  IconData get selectedIcon => Icons.speed;

  @override
  LuciModuleCategory get category => LuciModuleCategory.monitoring;

  @override
  int get priority => 19;

  @override
  bool get showInBottomNav => false;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const BandwidthMonitorScreen();
  }
}
