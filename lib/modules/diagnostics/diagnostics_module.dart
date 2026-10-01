// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/diagnostics_screen.dart';

class DiagnosticsModule extends LuciModule {
  @override
  String get id => 'diagnostics';

  @override
  String get name => 'Network Diagnostics';

  @override
  String get description =>
      'Connectivity test, ping, traceroute, DNS lookup & full report export';

  @override
  IconData get icon => Icons.troubleshoot_rounded;

  @override
  IconData get selectedIcon => Icons.troubleshoot;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 32;

  @override
  bool get showInBottomNav => false;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const DiagnosticsScreen();
  }
}
