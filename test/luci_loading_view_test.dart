// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/widgets/luci_loading_states.dart';
import 'package:yala/widgets/luci_loading_view.dart';

Widget _buildTestApp({Widget? child}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child ?? const LuciLoadingView()),
  );
}

void main() {
  group('LuciLoadingView Reusable Loading Component Tests', () {
    testWidgets(
      '1. Renders default humorous captions when captions is omitted',
      (tester) async {
        await tester.pumpWidget(_buildTestApp(child: const LuciLoadingView()));
        await tester.pump();

        // First caption from default captions
        expect(
          find.text('Checking if Earth is flat or round…'),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets('2. Renders custom captions when provided', (tester) async {
      final customCaptions = ['Custom Caption 1', 'Custom Caption 2'];

      await tester.pumpWidget(
        _buildTestApp(child: LuciLoadingView(captions: customCaptions)),
      );
      await tester.pump();

      expect(find.text('Custom Caption 1'), findsOneWidget);
      expect(find.text('Custom Caption 2'), findsNothing);
    });

    testWidgets('3. Rotates captions periodically with configured interval', (
      tester,
    ) async {
      final customCaptions = ['First Step', 'Second Step', 'Third Step'];

      await tester.pumpWidget(
        _buildTestApp(
          child: LuciLoadingView(
            captions: customCaptions,
            rotationInterval: const Duration(seconds: 2),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('First Step'), findsOneWidget);

      // Advance by 2 seconds
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // Animation settling
      expect(find.text('Second Step'), findsOneWidget);

      // Advance another 2 seconds
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Third Step'), findsOneWidget);

      // Advance another 2 seconds -> wraps back to first
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('First Step'), findsOneWidget);
    });

    testWidgets(
      '4. Does not cycle or start periodic timer when caption list has <= 1 item',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const LuciLoadingView(captions: ['Single Static Caption']),
          ),
        );
        await tester.pump();

        expect(find.text('Single Static Caption'), findsOneWidget);

        // Advance time by 10 seconds; should remain unchanged and no timer exceptions
        await tester.pump(const Duration(seconds: 10));
        expect(find.text('Single Static Caption'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Cancels timer immediately on widget disposal with no leaks',
      (tester) async {
        await tester.pumpWidget(_buildTestApp(child: const LuciLoadingView()));
        await tester.pump();

        expect(find.byType(LuciLoadingView), findsOneWidget);

        // Unmount the widget completely
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())),
        );
        await tester.pump();

        expect(find.byType(LuciLoadingView), findsNothing);

        // Advance time; no timers should fire or throw
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      '6. Renders optional skeleton content beneath indicator and captions',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const LuciLoadingView(
              title: 'Custom Loading Title',
              skeleton: Column(
                children: [LuciCardSkeleton(), LuciCardSkeleton()],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Custom Loading Title'), findsOneWidget);
        expect(find.byType(LuciCardSkeleton), findsNWidgets(2));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets('7. Constrained minHeight guarantees layout height stability', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const LuciLoadingView(
            captions: [
              'Short',
              'A very long caption that wraps around multiple lines to test layout constraints and ensure stability across text changes',
            ],
            rotationInterval: Duration(seconds: 1),
          ),
        ),
      );
      await tester.pump();

      final captionBoxFinder = find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox && widget.constraints.minHeight == 44.0,
      );
      expect(captionBoxFinder, findsOneWidget);
    });
  });
}
