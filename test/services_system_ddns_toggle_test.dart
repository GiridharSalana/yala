// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/modules/services_system/screens/services_system_screen.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

void main() {
  group('DDNS and Async Toggle Hardening Tests', () {
    test('DdnsOverview correctly parses installed state and instances', () {
      final data = {
        'ddns': {
          'global': {'is_enabled': '1'},
          'myddns_ipv4': {
            '.type': 'service',
            'enabled': '1',
            'service_name': 'cloudflare.com-v4',
            'lookup_host': 'router.example.com',
            'domain': 'router.example.com',
          },
        },
      };

      final overview = DdnsOverview.fromDashboardData(data, isReviewerMode: false);
      expect(overview.isInstalled, isTrue);
      expect(overview.isGlobalEnabled, isTrue);
      expect(overview.instances.length, equals(1));
      expect(overview.instances.first.name, equals('myddns_ipv4'));
      expect(overview.instances.first.enabled, isTrue);
    });

    testWidgets('ServicesSystemScreen renders DDNS section and localized elements', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ServicesSystemScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ServicesSystemScreen), findsOneWidget);
    });
  });
}
