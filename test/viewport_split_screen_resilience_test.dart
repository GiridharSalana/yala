// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/services/update_checker_service.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import 'package:yet_another_luci_app/widgets/ban_wireless_client_dialog.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/wifi_qr_dialog.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('LuciBreakpoints Multi-Window & Freeform Sizing Tests', () {
    testWidgets('Evaluates correctly on narrow phone split-view (360x360)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late bool isTabletResult;
      late bool isExpandedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isTabletResult = LuciBreakpoints.isTablet(context);
              isExpandedResult = LuciBreakpoints.isExpanded(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isTabletResult, isFalse);
      expect(isExpandedResult, isFalse);
    });

    testWidgets(
      'Correctly prevents vertical rail collapse in short landscape split-screen (720x340)',
      (WidgetTester tester) async {
        // In landscape multi-window split view, width may exceed 600, but height < 400.
        // It must cleanly fall back to bottom navigation instead of overflowing.
        tester.view.physicalSize = const Size(720, 340);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = LuciBreakpoints.isTablet(context);
                isExpandedResult = LuciBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        // Height is 340 (< 400), so isTablet should be false
        expect(isTabletResult, isFalse);
        expect(isExpandedResult, isFalse);
      },
    );

    testWidgets(
      'Activates tablet mode only when both width >= 600 and height >= 400',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = LuciBreakpoints.isTablet(context);
                isExpandedResult = LuciBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isTabletResult, isTrue);
        expect(isExpandedResult, isFalse);
      },
    );

    testWidgets(
      'Activates expanded layout on wide tablet/desktop viewports (1280x800)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = LuciBreakpoints.isTablet(context);
                isExpandedResult = LuciBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isTabletResult, isTrue);
        expect(isExpandedResult, isTrue);
      },
    );

    testWidgets(
      'Detects Apple Duo / dual-screen spanned mode and enables tablet layout',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1350, 900);
        tester.view.devicePixelRatio = 1.0;
        tester.view.displayFeatures = const [
          DisplayFeature(
            bounds: Rect.fromLTWH(660, 0, 30, 900),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ];
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetDisplayFeatures);

        late bool hasHinge;
        late bool isSpanned;
        late bool isTablet;
        late Rect? hingeBounds;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                hasHinge = LuciBreakpoints.hasHinge(context);
                isSpanned = LuciBreakpoints.isDualScreenSpanned(context);
                isTablet = LuciBreakpoints.isTablet(context);
                hingeBounds = LuciBreakpoints.getHingeBounds(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(hasHinge, isTrue);
        expect(isSpanned, isTrue);
        expect(isTablet, isTrue);
        expect(hingeBounds, const Rect.fromLTWH(660, 0, 30, 900));
      },
    );
  });

  group('Dialog Responsive Viewport Resilience Tests', () {
    testWidgets(
      'Update Available dialog renders without overflow in narrow 300dp popup view',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(300, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    UpdateCheckerService.showUpdateAvailableDialog(
                      context,
                      currentVersion: '2.0.0',
                      latestVersion: '2.1.0',
                      releaseNotes: 'Bug fixes and performance improvements.',
                      downloadUrl: 'https://github.com/example/releases',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Update Available'), findsOneWidget);
        expect(find.text('v2.0.0'), findsOneWidget);
        expect(find.text('v2.1.0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Pre-Release build dialog renders without overflow in short 320dp split screen',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 320);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    UpdateCheckerService.showAheadOfReleaseDialog(
                      context,
                      currentVersion: '2.2.0',
                      latestGithubVersion: '2.0.0',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Pre-Release Build'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Up to date dialog renders without overflow in very small popup (260x360)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(260, 360);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    UpdateCheckerService.showUpToDateDialog(
                      context,
                      currentVersion: '2.0.0',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Up to Date'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'BanWirelessClientDialog renders without overflow in narrow 320x500 popup view',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => BanWirelessClientDialog(
                        macAddress: '11:22:33:44:55:66',
                        displayName: 'Galaxy-S24-Ultra',
                        onBanConfirmed: (sec) async {},
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(BanWirelessClientDialog), findsOneWidget);
        expect(find.text('Ban Client from Wi-Fi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Accessibility Large Font Scaling & Clamping Tests', () {
    testWidgets(
      'AddStaticLeaseDialog renders without overflow at 1.45x maximum clamped font scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final clampedTextScaler = mediaQuery.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.45,
              );
              return MediaQuery(
                data: mediaQuery.copyWith(textScaler: clampedTextScaler),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => const AddStaticLeaseDialog(),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(AddStaticLeaseDialog), findsOneWidget);
        expect(find.text('Add Static Lease'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'BanWirelessClientDialog renders without overflow at 1.45x maximum clamped font scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final clampedTextScaler = mediaQuery.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.45,
              );
              return MediaQuery(
                data: mediaQuery.copyWith(textScaler: clampedTextScaler),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => BanWirelessClientDialog(
                          macAddress: '11:22:33:44:55:66',
                          displayName: 'Galaxy-S24-Ultra',
                          onBanConfirmed: (sec) async {},
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(BanWirelessClientDialog), findsOneWidget);
        expect(find.text('Ban Client from Wi-Fi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LuciGuardrail.confirmSaveOrDiscardChanges stacks 3 buttons without overflow at 1.45x font scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final clampedTextScaler = mediaQuery.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.45,
              );
              return MediaQuery(
                data: mediaQuery.copyWith(textScaler: clampedTextScaler),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.45)),
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      LuciGuardrail.confirmSaveOrDiscardChanges(
                        context,
                        title: 'Discard Unsaved Profile Changes?',
                        count: 4,
                        itemLabel: 'profile rules',
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              SystemChannels.platform,
              (MethodCall methodCall) async => null,
            );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Discard Unsaved Profile Changes?'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Discard & Leave'), findsOneWidget);
        expect(find.text('Save & Exit'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'WifiQrDialog renders responsive layout without overflow at 1.45x scale on 320x480 view',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const testInterface = WirelessInterface(
          ifName: 'wlan0',
          sectionName: 'default_radio0',
          ssid: 'OpenWrt-Ultra-Long-Network-Name-For-Stress-Testing',
          mode: 'ap',
          encryption: 'psk2',
          securityMode: WifiSecurityMode.wpa2Psk,
          pmfState: PmfState.optional,
          channel: '36',
          isEnabled: true,
          stations: [],
          key: 'VerySecretPassword123!',
          rawConfig: {},
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              builder: (context, child) {
                final mediaQuery = MediaQuery.of(context);
                final clampedTextScaler = mediaQuery.textScaler.clamp(
                  minScaleFactor: 0.85,
                  maxScaleFactor: 1.45,
                );
                return MediaQuery(
                  data: mediaQuery.copyWith(textScaler: clampedTextScaler),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.45)),
                child: Builder(
                  builder: (context) => Scaffold(
                    body: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) =>
                              const WifiQrDialog(interface: testInterface),
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(WifiQrDialog), findsOneWidget);
        expect(find.text('Wi-Fi Quick Connect'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'OsPlatformIntegration.showFileDownloadedPrompt renders cleanly on 320x480 at 1.45x scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final dummyResult = FileSaveResult(
          filePath:
              '/storage/emulated/0/Download/backup-openwrt-2026-09-28.tar.gz',
          isPublicDownloads: true,
          storageMethodLabel: 'Public Downloads Folder',
        );

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final clampedTextScaler = mediaQuery.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.45,
              );
              return MediaQuery(
                data: mediaQuery.copyWith(textScaler: clampedTextScaler),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.45)),
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      OsPlatformIntegration.showFileDownloadedPrompt(
                        context,
                        dummyResult,
                        title: 'Backup Downloaded Successfully',
                        fileLabel: 'Backup Path',
                        icon: Icons.check_circle_outline,
                        accentColor: Colors.teal,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              SystemChannels.platform,
              (MethodCall methodCall) async => null,
            );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Backup Downloaded Successfully'), findsOneWidget);
        expect(find.text('Public Downloads Folder'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
