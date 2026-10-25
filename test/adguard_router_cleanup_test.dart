// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> fakeStorage = {};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          final key = methodCall.arguments?['key'] as String?;
          if (methodCall.method == 'read') {
            return fakeStorage[key];
          }
          if (methodCall.method == 'write') {
            final value = methodCall.arguments?['value'] as String?;
            if (key != null && value != null) {
              fakeStorage[key] = value;
            }
            return null;
          }
          if (methodCall.method == 'delete') {
            if (key != null) fakeStorage.remove(key);
            return null;
          }
          if (methodCall.method == 'readAll') {
            return Map<String, String>.from(fakeStorage);
          }
          if (methodCall.method == 'deleteAll') {
            fakeStorage.clear();
            return null;
          }
          return null;
        });
  });

  setUp(() {
    fakeStorage.clear();
  });

  group('SecureStorageService — AdGuard Profiles & Router Deletion Invariants', () {
    test(
      'saveAdGuardProfile, getAdGuardProfiles, and deleteAdGuardProfile persist accurately',
      () async {
        final storage = SecureStorageService();

        final localProfile = AdGuardInstanceProfile.local(
          routerId: 'router-1',
          host: '192.168.1.1',
        );
        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_pi_100',
          name: 'Raspberry Pi',
          host: '192.168.1.129',
          port: 3000,
        );

        await storage.saveAdGuardProfile(localProfile);
        await storage.saveAdGuardProfile(extProfile);

        final retrieved = await storage.getAdGuardProfiles();
        expect(retrieved.length, equals(2));
        expect(retrieved.any((p) => p.id == 'local_router-1'), isTrue);
        expect(retrieved.any((p) => p.id == 'ext_pi_100'), isTrue);

        await storage.deleteAdGuardProfile('ext_pi_100');
        final remaining = await storage.getAdGuardProfiles();
        expect(remaining.length, equals(1));
        expect(remaining.first.id, equals('local_router-1'));
      },
    );

    test(
      'deleteRouter removes local profile and creds but strictly preserves external profiles',
      () async {
        final storage = SecureStorageService();

        // 1. Create a router with router auth creds and local AGH profile
        const routerId = 'router-to-delete';
        await storage.saveCredentials(
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'router_password',
          useHttps: false,
        );

        final localProfile = AdGuardInstanceProfile.local(
          routerId: routerId,
          host: '192.168.1.1',
        );
        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_keep_me',
          name: 'Dedicated Pi Server',
          host: '192.168.1.129',
          port: 3000,
        );

        await storage.saveAdGuardProfile(localProfile);
        await storage.saveAdGuardProfile(extProfile);

        // Save instance credentials for both
        await storage.saveAdGuardCredentialsForInstance(
          localProfile.id,
          'local_user',
          'local_pass',
        );
        await storage.saveAdGuardCredentialsForInstance(
          extProfile.id,
          'pi_admin',
          'pi_secret_password',
        );

        // Save active AdGuard profile ID for this router
        await storage.saveActiveAdGuardProfileId(routerId, extProfile.id);
        expect(
          await storage.getActiveAdGuardProfileId(routerId),
          equals(extProfile.id),
        );

        // 2. Perform deleteRouter
        await storage.deleteRouter(routerId);

        // 3. Invariants:
        // - Active profile ID for this router is purged
        expect(
          fakeStorage.containsKey('agh_active_profile_$routerId'),
          isFalse,
        );
        expect(await storage.getActiveAdGuardProfileId(routerId), isNull);

        // - Local profile is purged
        final remainingProfiles = await storage.getAdGuardProfiles();
        expect(remainingProfiles.any((p) => p.id == localProfile.id), isFalse);

        // - External profile remains strictly preserved
        expect(remainingProfiles.any((p) => p.id == 'ext_keep_me'), isTrue);

        // - External profile credentials remain strictly preserved
        expect(fakeStorage.containsKey('agh_creds_ext_keep_me'), isTrue);

        // - Local profile credentials are deleted
        expect(
          fakeStorage.containsKey('agh_creds_${localProfile.id}'),
          isFalse,
        );
      },
    );
  });
}
