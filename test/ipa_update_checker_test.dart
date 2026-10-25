// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yala/config/app_config.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/screens/settings_screen.dart';
import 'package:yala/services/update_checker_service.dart';

void main() {
  setUp(() {
    AppConfig.debugIsIpaBuild = null;
    AppConfig.debugIsFdroidBuild = false;
    PackageInfo.setMockInitialValues(
      appName: 'Yet Another LuCI App',
      packageName: 'com.nightcode.yala',
      version: '2.2.5',
      buildNumber: '220',
      buildSignature: '',
    );
  });

  tearDown(() {
    AppConfig.debugIsIpaBuild = null;
    AppConfig.debugIsFdroidBuild = null;
  });

  final mockReleasesList = [
    {
      'tag_name': 'v2.5.1',
      'name': 'YALA v2.5.1',
      'draft': false,
      'prerelease': false,
      'html_url': 'https://github.com/nightcodex7/yala/releases/tag/v2.5.1',
      'body': 'Android stable release notes',
      'assets': [
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url':
              'https://github.com/nightcodex7/yala/releases/download/v2.5.1/app-arm64-v8a-release.apk',
        },
      ],
    },
    {
      'tag_name': 'v2.5.1-beta-ipa',
      'name': 'YALA v2.5.1 (iOS Beta)',
      'draft': false,
      'prerelease': true,
      'html_url':
          'https://github.com/nightcodex7/yala/releases/tag/v2.5.1-beta-ipa',
      'body': 'iOS sideloadable beta release notes',
      'assets': [
        {
          'name': 'Yet-Another-LuCI-App.ipa',
          'browser_download_url':
              'https://github.com/nightcodex7/yala/releases/download/v2.5.1-beta-ipa/Yet-Another-LuCI-App.ipa',
        },
        {
          'name': 'Yet-Another-LuCI-App.ipa.sha256',
          'browser_download_url':
              'https://github.com/nightcodex7/yala/releases/download/v2.5.1-beta-ipa/Yet-Another-LuCI-App.ipa.sha256',
        },
      ],
    },
    {
      'tag_name': 'v2.2.5',
      'name': 'YALA v2.2.5',
      'draft': false,
      'prerelease': false,
      'html_url': 'https://github.com/nightcodex7/yala/releases/tag/v2.2.5',
      'body': 'Previous stable release notes',
      'assets': [],
    },
    {
      'tag_name': 'v2.2.5-beta-ipa',
      'name': 'YALA v2.2.5 (iOS Beta)',
      'draft': false,
      'prerelease': true,
      'html_url':
          'https://github.com/nightcodex7/yala/releases/tag/v2.2.5-beta-ipa',
      'body': 'Previous beta release notes',
      'assets': [
        {'name': 'Yet-Another-LuCI-App.ipa'},
      ],
    },
  ];

  group('UpdateCheckerService Release Classification & Selection', () {
    test('isIpaBetaRelease correctly detects iOS beta releases', () {
      expect(
        UpdateCheckerService.isIpaBetaRelease(mockReleasesList[1]),
        isTrue,
      );
      expect(
        UpdateCheckerService.isIpaBetaRelease(mockReleasesList[3]),
        isTrue,
      );
      expect(
        UpdateCheckerService.isIpaBetaRelease(mockReleasesList[0]),
        isFalse,
      );
      expect(
        UpdateCheckerService.isIpaBetaRelease(mockReleasesList[2]),
        isFalse,
      );
      expect(
        UpdateCheckerService.isIpaBetaRelease({
          'tag_name': 'v2.6.0-beta-ipa',
          'draft': true, // drafts should never match
          'prerelease': true,
        }),
        isFalse,
      );
    });

    test('isStableRelease correctly detects non-beta stable releases', () {
      expect(UpdateCheckerService.isStableRelease(mockReleasesList[0]), isTrue);
      expect(UpdateCheckerService.isStableRelease(mockReleasesList[2]), isTrue);
      expect(
        UpdateCheckerService.isStableRelease(mockReleasesList[1]),
        isFalse,
      );
      expect(
        UpdateCheckerService.isStableRelease(mockReleasesList[3]),
        isFalse,
      );
      expect(
        UpdateCheckerService.isStableRelease({
          'tag_name': 'v2.5.1',
          'draft': true, // draft should never match
          'prerelease': false,
        }),
        isFalse,
      );
    });

    test('selectTargetRelease chooses iOS beta for IPA builds exclusively', () {
      final ipaTarget = UpdateCheckerService.selectTargetRelease(
        mockReleasesList,
        isIpaBuild: true,
      );
      expect(ipaTarget, isNotNull);
      expect(ipaTarget!['tag_name'], equals('v2.5.1-beta-ipa'));
      expect(ipaTarget['prerelease'], isTrue);

      final stableTarget = UpdateCheckerService.selectTargetRelease(
        mockReleasesList,
        isIpaBuild: false,
      );
      expect(stableTarget, isNotNull);
      expect(stableTarget!['tag_name'], equals('v2.5.1'));
      expect(stableTarget['prerelease'], isFalse);
    });
  });

  group('UpdateCheckerService Version Comparison', () {
    test('Compares current and beta release versions properly', () {
      // 2.2.5 is older than 2.5.1-beta-ipa
      expect(
        UpdateCheckerService.compareVersions('2.2.5', '2.5.1-beta-ipa'),
        lessThan(0),
      );

      // 2.5.1 matches 2.5.1-beta-ipa base version
      expect(
        UpdateCheckerService.compareVersions('2.5.1', '2.5.1-beta-ipa'),
        equals(0),
      );

      // 2.6.0 is ahead of 2.5.1-beta-ipa
      expect(
        UpdateCheckerService.compareVersions('2.6.0', '2.5.1-beta-ipa'),
        greaterThan(0),
      );

      // Suffix without -
      expect(
        UpdateCheckerService.compareVersions('2.5.1', '2.5.2-beta-ipa'),
        lessThan(0),
      );

      // Build number comparison when base is equal
      expect(
        UpdateCheckerService.compareVersions('2.5.1+228', '2.5.1+229'),
        lessThan(0),
      );
      expect(
        UpdateCheckerService.compareVersions('2.5.1+230', '2.5.1+229'),
        greaterThan(0),
      );
    });
  });

  group('Update Dialog UI Rendering for IPA Builds vs Standard', () {
    testWidgets('Renders Update Dialog with Redirect Button for IPA builds', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  UpdateCheckerService.showUpdateAvailableDialog(
                    context,
                    currentVersion: '2.2.5',
                    latestVersion: '2.5.1-beta-ipa',
                    releaseNotes: 'Fixes and new features for iOS',
                    downloadUrl:
                        'https://github.com/nightcodex7/yala/releases/tag/v2.5.1-beta-ipa',
                    isIpaBuild: true,
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('v2.2.5'), findsOneWidget);
      expect(find.text('v2.5.1-beta-ipa'), findsOneWidget);

      // Action button should be View Release redirect button with open in new icon
      expect(find.text('View Release'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
      // Standard direct Download button must NOT be present for IPA builds
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('Renders Standard Download Dialog for non-IPA builds', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  UpdateCheckerService.showUpdateAvailableDialog(
                    context,
                    currentVersion: '2.2.5',
                    latestVersion: '2.5.1',
                    releaseNotes: 'Fixes and new features for Android',
                    downloadUrl:
                        'https://github.com/nightcodex7/yala/releases/tag/v2.5.1',
                    isIpaBuild: false,
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      // View Release redirect button must NOT be present for standard builds
      expect(find.text('View Release'), findsNothing);
    });

    testWidgets('Renders Up to Date dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  UpdateCheckerService.showUpToDateDialog(
                    context,
                    currentVersion: '2.5.1',
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Up to Date'), findsOneWidget);
    });
  });

  group('Manual Updates Tile in Settings', () {
    testWidgets('Settings renders standard Check for Updates tile', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final targetFinder = find.text('Check for Updates');
      await tester.scrollUntilVisible(targetFinder, 300);
      await tester.pumpAndSettle();

      expect(targetFinder, findsOneWidget);
      expect(
        find.text('Check for new release builds on GitHub'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.system_update_rounded), findsOneWidget);
    });
  });

  group('Full Manual Check Flow with Mock Client', () {
    testWidgets(
      'checkForUpdates with isIpa: true selects iOS beta release and shows redirect button',
      (tester) async {
        final mockClient = MockClient((request) async {
          return http.Response(
            json.encode(mockReleasesList),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    UpdateCheckerService.checkForUpdates(
                      context,
                      isIpa: true,
                      client: mockClient,
                    );
                  },
                  child: const Text('Check Updates'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Check Updates'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Update Available'), findsOneWidget);
        expect(find.text('View Release'), findsOneWidget);
        expect(find.text('Download'), findsNothing);
      },
    );

    testWidgets(
      'checkForUpdates with isIpa: false selects stable release and shows download button',
      (tester) async {
        final mockClient = MockClient((request) async {
          return http.Response(
            json.encode(mockReleasesList),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    UpdateCheckerService.checkForUpdates(
                      context,
                      isIpa: false,
                      client: mockClient,
                    );
                  },
                  child: const Text('Check Updates'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Check Updates'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Update Available'), findsOneWidget);
        expect(find.text('Download'), findsOneWidget);
        expect(find.text('View Release'), findsNothing);
      },
    );
  });
}
