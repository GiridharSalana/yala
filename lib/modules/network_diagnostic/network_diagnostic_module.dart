// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/network_diagnostic_screen.dart';

/// Module registering the production-grade "Why Is My Internet Broken?" diagnostic engine.
class NetworkDiagnosticModule extends LuciModule {
  @override
  String get id => 'network_diagnostic';

  @override
  String get name => 'Network Diagnostic';

  @override
  String get description =>
      'Automated root-cause analysis for internet, WAN, DNS & routing issues';

  @override
  IconData get icon => Icons.troubleshoot_outlined;

  @override
  IconData get selectedIcon => Icons.troubleshoot;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 31;

  @override
  bool get showInBottomNav => false;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const NetworkDiagnosticScreen();
  }
}
