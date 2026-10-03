// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/services/update_checker_service.dart';

void main() {
  group('UpdateCheckerService', () {
    test('target releases endpoint matches the official repository', () {
      expect(
        UpdateCheckerService.githubReleasesUrl,
        equals('https://api.github.com/repos/GiridharSalana/yala/releases'),
      );
    });

    group('compareVersions', () {
      test('identical versions return 0 (up to date)', () {
        expect(
          UpdateCheckerService.compareVersions('2.1.0', '2.1.0'),
          equals(0),
        );
        expect(
          UpdateCheckerService.compareVersions('2.1.0+224', '2.1.0'),
          equals(0),
        );
        expect(
          UpdateCheckerService.compareVersions('2.0.0', '2.0.0'),
          equals(0),
        );
      });

      test(
        'older current version returns negative integer (update available)',
        () {
          expect(
            UpdateCheckerService.compareVersions('2.0.0', '2.1.0'),
            lessThan(0),
          );
          expect(
            UpdateCheckerService.compareVersions('2.0.9', '2.1.0'),
            lessThan(0),
          );
          expect(
            UpdateCheckerService.compareVersions('1.9.9', '2.0.0'),
            lessThan(0),
          );
          expect(
            UpdateCheckerService.compareVersions('2.1.0', '2.1.1'),
            lessThan(0),
          );
          expect(
            UpdateCheckerService.compareVersions('2.1.0+224', '2.1.1'),
            lessThan(0),
          );
        },
      );

      test(
        'newer current version returns positive integer (pre-release build)',
        () {
          expect(
            UpdateCheckerService.compareVersions('2.1.0', '2.0.0'),
            greaterThan(0),
          );
          expect(
            UpdateCheckerService.compareVersions('2.2.0', '2.1.0'),
            greaterThan(0),
          );
          expect(
            UpdateCheckerService.compareVersions('2.1.1', '2.1.0'),
            greaterThan(0),
          );
        },
      );
    });
  });
}
