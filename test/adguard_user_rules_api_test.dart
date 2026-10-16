// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yala/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/services/mock_adguard_api_service.dart';

void main() {
  group('MockAdGuardApiService - User Rules API', () {
    late MockAdGuardApiService api;

    setUp(() {
      api = MockAdGuardApiService(requiresAuth: false);
    });

    test('retrieves default filtering status and user rules', () async {
      final res = await api.getFilteringStatus();
      expect(res.isSuccess, isTrue);
      expect(res.data, isNotNull);
      expect(res.data!.enabled, isTrue);
      expect(res.data!.userRules, contains('||tracker.example.com^'));
      expect(res.data!.userRules, contains('||telemetry.sample.net^'));
      expect(res.data!.userRules, contains('@@||allowed.workplace.com^'));
    });

    test('sets user rules successfully and preserves them in getFilteringStatus', () async {
      final newRules = [
        '||tiktok.com^',
        '||doubleclick.net^',
        '@@||workplace.com^',
      ];

      final setRes = await api.setUserRules(newRules);
      expect(setRes.isSuccess, isTrue);
      expect(setRes.data, isTrue);
      expect(api.setUserRulesCallCount, 1);

      final statusRes = await api.getFilteringStatus();
      expect(statusRes.isSuccess, isTrue);
      expect(statusRes.data!.userRules, equals(newRules));
      expect(statusRes.data!.totalRulesCount, 77500 + newRules.length);
    });

    test('simulates network failure when setting user rules', () async {
      api.simulateNetworkFailure = true;

      final res = await api.setUserRules(['||bad.com^']);
      expect(res.isSuccess, isFalse);
      expect(res.error, isNotNull);
      expect(res.error!.type, AdGuardApiErrorType.networkFailure);
    });

    test('simulates timeout when setting user rules', () async {
      api.simulateTimeout = true;

      final res = await api.setUserRules(['||bad.com^']);
      expect(res.isSuccess, isFalse);
      expect(res.error, isNotNull);
      expect(res.error!.type, AdGuardApiErrorType.timeout);
    });

    test('simulates http error when setting user rules', () async {
      api.simulateHttpError = true;
      api.simulatedHttpErrorCode = 502;

      final res = await api.setUserRules(['||bad.com^']);
      expect(res.isSuccess, isFalse);
      expect(res.error, isNotNull);
      expect(res.error!.type, AdGuardApiErrorType.httpError);
      expect(res.error!.statusCode, 502);
    });

    test('requires authentication when requiresAuth is true and unauthenticated', () async {
      final authedApi = MockAdGuardApiService(requiresAuth: true);
      expect(authedApi.isAuthenticated, isFalse);

      final res = await authedApi.setUserRules(['||blocked.com^']);
      expect(res.isSuccess, isFalse);
      expect(res.isAuthRequired, isTrue);
    });
  });

  group('MockAdGuardApiService - Clients API', () {
    late MockAdGuardApiService api;

    setUp(() {
      api = MockAdGuardApiService(requiresAuth: false);
    });

    test('manages clients list in-memory', () async {
      final initialRes = await api.getClients();
      expect(initialRes.isSuccess, isTrue);
      expect(initialRes.data, isEmpty);

      const client1 = AdGuardClient(
        name: 'Work Laptop',
        ids: ['192.168.1.105', 'AA:BB:CC:DD:EE:01'],
        useGlobalSettings: true,
        filteringEnabled: true,
        tags: ['work', 'laptop'],
      );

      final addRes = await api.addClient(client1);
      expect(addRes.isSuccess, isTrue);
      expect(api.addClientCallCount, 1);

      final listAfterAdd = await api.getClients();
      expect(listAfterAdd.data!.length, 1);
      expect(listAfterAdd.data!.first.name, 'Work Laptop');
      expect(listAfterAdd.data!.first.ids, contains('AA:BB:CC:DD:EE:01'));

      final updatedClient = client1.copyWith(
        name: 'Work Laptop Pro',
        blockedServices: const ['tiktok', 'youtube'],
      );

      final updateRes = await api.updateClient('Work Laptop', updatedClient);
      expect(updateRes.isSuccess, isTrue);
      expect(api.updateClientCallCount, 1);

      final listAfterUpdate = await api.getClients();
      expect(listAfterUpdate.data!.length, 1);
      expect(listAfterUpdate.data!.first.name, 'Work Laptop Pro');
      expect(listAfterUpdate.data!.first.blockedServices, contains('tiktok'));
    });

    test('AdGuardClient serializes to and from JSON faithfully', () {
      const client = AdGuardClient(
        name: 'Child Tablet',
        ids: ['192.168.1.120', '11:22:33:44:55:66'],
        useGlobalSettings: false,
        filteringEnabled: true,
        parentalEnabled: true,
        safesearchEnabled: true,
        useGlobalBlockedServices: false,
        blockedServices: ['facebook', 'instagram', 'tiktok'],
        tags: ['kids', 'tablet'],
      );

      final json = client.toJson();
      final revived = AdGuardClient.fromJson(json);

      expect(revived.name, 'Child Tablet');
      expect(revived.ids, equals(['192.168.1.120', '11:22:33:44:55:66']));
      expect(revived.parentalEnabled, isTrue);
      expect(revived.safesearchEnabled, isTrue);
      expect(revived.useGlobalBlockedServices, isFalse);
      expect(revived.blockedServices, contains('tiktok'));
      expect(revived.tags, contains('kids'));
      expect(revived, equals(client));
    });
  });
}
