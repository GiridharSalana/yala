// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/widgets/luci_guardrail.dart';

void main() {
  Widget buildTestHost(Future<bool?> Function(BuildContext) onShow) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onShow(context),
            child: const Text('Trigger Guardrail'),
          ),
        ),
      ),
    );
  }

  group('LuciGuardrail.confirmCriticalOperation Tests', () {
    testWidgets('Displays title, description, and hazard details', (tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        buildTestHost((ctx) async {
          dialogResult = await LuciGuardrail.confirmCriticalOperation(
            ctx,
            title: 'Critical Lockout Hazard',
            description: 'You are modifying an active management interface.',
            hazardDetails: [
              'Web interface may be lost',
              'SSH port forwarding will change',
            ],
            confirmLabel: 'Proceed Anyway',
            cancelLabel: 'Abort',
          );
          return dialogResult;
        }),
      );

      await tester.tap(find.text('Trigger Guardrail'));
      await tester.pumpAndSettle();

      expect(find.text('Critical Lockout Hazard'), findsOneWidget);
      expect(
        find.text('You are modifying an active management interface.'),
        findsOneWidget,
      );
      expect(find.text('Web interface may be lost'), findsOneWidget);
      expect(find.text('SSH port forwarding will change'), findsOneWidget);
      expect(find.text('Proceed Anyway'), findsOneWidget);
      expect(find.text('Abort'), findsOneWidget);

      // Tap Abort (Cancel)
      await tester.tap(find.text('Abort'));
      await tester.pumpAndSettle();

      expect(dialogResult, isFalse);
    });

    testWidgets('Direct confirmation without requirement returns true', (tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        buildTestHost((ctx) async {
          dialogResult = await LuciGuardrail.confirmCriticalOperation(
            ctx,
            title: 'Restart Router',
            description: 'The router will reboot.',
            confirmLabel: 'Reboot Now',
            cancelLabel: 'Cancel',
            requireAcknowledgement: false,
          );
          return dialogResult;
        }),
      );

      await tester.tap(find.text('Trigger Guardrail'));
      await tester.pumpAndSettle();

      expect(find.text('Reboot Now'), findsOneWidget);

      await tester.tap(find.text('Reboot Now'));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
    });

    testWidgets('Enforces acknowledgment checkbox before enabling confirm button', (tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        buildTestHost((ctx) async {
          dialogResult = await LuciGuardrail.confirmCriticalOperation(
            ctx,
            title: 'Reset Credentials',
            description: 'Admin password will be wiped.',
            confirmLabel: 'Apply Reset',
            cancelLabel: 'Cancel',
            requireAcknowledgement: true,
            acknowledgementLabel: 'I acknowledge the risk',
          );
          return dialogResult;
        }),
      );

      await tester.tap(find.text('Trigger Guardrail'));
      await tester.pumpAndSettle();

      expect(find.text('I acknowledge the risk'), findsOneWidget);

      // Confirm button is present but disabled
      final confirmFinder = find.widgetWithText(FilledButton, 'Apply Reset');
      expect(confirmFinder, findsOneWidget);
      FilledButton button = tester.widget<FilledButton>(confirmFinder);
      expect(button.onPressed, isNull);

      // Tap acknowledgment checkbox
      await tester.tap(find.text('I acknowledge the risk'));
      await tester.pumpAndSettle();

      // Confirm button should now be enabled
      button = tester.widget<FilledButton>(confirmFinder);
      expect(button.onPressed, isNotNull);

      // Tap confirm button
      await tester.tap(confirmFinder);
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
    });
  });
}
