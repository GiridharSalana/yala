// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/modules/firewall_security/widgets/block_incoming_traffic_dialog.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  group('Firewall Truncation & Ellipsis Fixes Tests', () {
    testWidgets(
      '1. AppBar title displays full title and backend subtitle without truncation',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildApp(
            Scaffold(
              appBar: AppBar(
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Firewall & Security',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('fw4 / nftables', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Firewall & Security'), findsOneWidget);
        expect(find.text('fw4 / nftables'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Quick Actions subtitles display full multi-line text without clipping',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const portSubtitle =
            'Allow external devices to reach a specific app or service on your home network.';
        const blockSubtitle =
            'Prevent an external address or connection from reaching your network.';

        await tester.pumpWidget(
          buildApp(
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Open a Port',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text(portSubtitle),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Block an Incoming Connection',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text(blockSubtitle),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(portSubtitle), findsOneWidget);
        expect(find.text(blockSubtitle), findsOneWidget);
      },
    );

    testWidgets(
      '3. Add Port Forward Dialog Internal Device segmented button displays Connected Device and Manual IP cleanly',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        bool useManualIp = false;

        await tester.pumpWidget(
          buildApp(
            StatefulBuilder(
              builder: (context, setState) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          icon: Icon(Icons.devices_outlined, size: 18),
                          label: Text('Connected Device'),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          icon: Icon(Icons.edit_outlined, size: 18),
                          label: Text('Manual IP'),
                        ),
                      ],
                      selected: {useManualIp},
                      onSelectionChanged: (set) {
                        setState(() => useManualIp = set.first);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Connected Device'), findsOneWidget);
        expect(find.text('Manual IP'), findsOneWidget);

        await tester.tap(find.text('Manual IP'));
        await tester.pumpAndSettle();
        expect(useManualIp, isTrue);
      },
    );

    testWidgets(
      '4. Block Incoming Traffic Dialog target selector displays IP, Port, and Preset cleanly without ellipses',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        BlockTargetType targetType = BlockTargetType.externalIp;

        await tester.pumpWidget(
          buildApp(
            StatefulBuilder(
              builder: (context, setState) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<BlockTargetType>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: BlockTargetType.externalIp,
                          label: Text('IP'),
                          icon: Icon(Icons.public_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: BlockTargetType.portOrService,
                          label: Text('Port'),
                          icon: Icon(Icons.numbers_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: BlockTargetType.commonApp,
                          label: Text('Preset'),
                          icon: Icon(Icons.security_outlined, size: 18),
                        ),
                      ],
                      selected: {targetType},
                      onSelectionChanged: (set) {
                        setState(() => targetType = set.first);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('IP'), findsOneWidget);
        expect(find.text('Port'), findsOneWidget);
        expect(find.text('Preset'), findsOneWidget);

        await tester.tap(find.text('Port'));
        await tester.pumpAndSettle();
        expect(targetType, equals(BlockTargetType.portOrService));

        await tester.tap(find.text('Preset'));
        await tester.pumpAndSettle();
        expect(targetType, equals(BlockTargetType.commonApp));
      },
    );
  });
}
