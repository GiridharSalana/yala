// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/modules/adguard_home/controllers/adguard_controller.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import 'package:yala/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yala/modules/adguard_home/services/mock_adguard_api_service.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_filter_lists_dialog.dart';
import 'package:yala/modules/adguard_home/widgets/adguard_filtering_card.dart';
import 'package:yala/services/secure_storage_service.dart';

class TestDioAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options) handler;

  TestDioAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> storage = {};

  @override
  Future<String?> readValue(String key) async => storage[key];

  @override
  Future<void> writeValue(String key, String value) async {
    storage[key] = value;
  }

  @override
  Future<void> deleteValue(String key) async {
    storage.remove(key);
  }

  @override
  Future<void> deleteAdGuardCredentials(String routerId) async {
    storage.remove('agh_creds_$routerId');
  }

  @override
  Future<void> saveCredentials({
    required String ipAddress,
    required String username,
    required String password,
    required bool useHttps,
  }) async {}

  @override
  Future<void> clearCredentials() async {}

  @override
  Future<Map<String, String?>> getCredentials() async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('AdGuardFilterList & AdGuardFilteringStatus Models', () {
    test('parses blocklists and allowlists correctly from JSON', () {
      final json = {
        'enabled': true,
        'interval': 24,
        'filters': [
          {
            'id': 1,
            'name': 'AdGuard DNS filter',
            'url': 'https://example.com/filter1.txt',
            'rules_count': 60000,
            'enabled': true,
            'last_updated': '2026-10-10T10:00:00Z',
          },
          {
            'id': 2,
            'name': 'Disabled List',
            'url': 'https://example.com/filter2.txt',
            'rules_count': 5000,
            'enabled': false,
            'last_updated': '2026-10-09T08:00:00Z',
          },
        ],
        'whitelist_filters': [
          {
            'id': 10,
            'name': 'My Whitelist',
            'url': 'https://example.com/whitelist.txt',
            'rules_count': 50,
            'enabled': true,
            'last_updated': '2026-10-11T12:00:00Z',
          },
        ],
        'user_rules': [
          '||tracker.com^',
          '@@||allowed.com^',
        ],
      };

      final status = AdGuardFilteringStatus.fromJson(json);
      expect(status.enabled, isTrue);
      expect(status.interval, 24);
      expect(status.filterLists.length, 2);
      expect(status.filterLists[0].url, 'https://example.com/filter1.txt');
      expect(status.filterLists[0].whitelist, isFalse);
      expect(status.filterLists[1].enabled, isFalse);

      expect(status.whitelistFilters.length, 1);
      expect(status.whitelistFilters[0].name, 'My Whitelist');
      expect(status.whitelistFilters[0].whitelist, isTrue);
      expect(status.whitelistFilters[0].rulesCount, 50);

      // Total enabled rules = 60000 (enabled filter) + 50 (enabled whitelist) + 2 (user rules) = 60052
      expect(status.totalRulesCount, 60052);
    });

    test('AdGuardFilterList copyWith preserves and modifies fields', () {
      const list = AdGuardFilterList(
        id: 1,
        name: 'List A',
        url: 'https://a.com',
        rulesCount: 100,
        enabled: true,
        lastUpdated: '2026-10-01',
        whitelist: false,
      );

      final modified = list.copyWith(
        name: 'List B',
        enabled: false,
        whitelist: true,
      );

      expect(modified.id, 1);
      expect(modified.name, 'List B');
      expect(modified.url, 'https://a.com');
      expect(modified.rulesCount, 100);
      expect(modified.enabled, isFalse);
      expect(modified.lastUpdated, '2026-10-01');
      expect(modified.whitelist, isTrue);
    });
  });

  group('AdGuardApiService Network Endpoints', () {
    late Dio testDio;
    late FakeSecureStorageService fakeStorage;
    late AdGuardApiService apiService;
    final capturedRequests = <RequestOptions>[];

    setUp(() {
      capturedRequests.clear();
      testDio = Dio(BaseOptions(baseUrl: 'http://192.168.1.1:3000'));
      testDio.httpClientAdapter = TestDioAdapter((options) async {
        capturedRequests.add(options);
        return ResponseBody.fromString('OK', 200, headers: {
          Headers.contentTypeHeader: [Headers.textPlainContentType],
        });
      });

      fakeStorage = FakeSecureStorageService();
      apiService = AdGuardApiService(
        routerId: 'router-test',
        host: '192.168.1.1',
        port: 3000,
        secureStorageService: fakeStorage,
        dioOverride: testDio,
      );
    });

    test('addFilterList sends POST /control/filtering/add_url with correct payload', () async {
      final res = await apiService.addFilterList(
        name: 'Test Filter',
        url: 'https://example.com/rules.txt',
        whitelist: false,
      );

      expect(res.isSuccess, isTrue);
      expect(capturedRequests.length, 1);
      final req = capturedRequests.first;
      expect(req.method, 'POST');
      expect(req.path.endsWith('/control/filtering/add_url'), isTrue);
      expect(req.data, {
        'name': 'Test Filter',
        'url': 'https://example.com/rules.txt',
        'whitelist': false,
      });
    });

    test('setFilterList sends POST /control/filtering/set_url with correct payload', () async {
      final res = await apiService.setFilterList(
        url: 'https://example.com/old.txt',
        name: 'Updated Name',
        newUrl: 'https://example.com/new.txt',
        enabled: true,
        whitelist: true,
      );

      expect(res.isSuccess, isTrue);
      expect(capturedRequests.length, 1);
      final req = capturedRequests.first;
      expect(req.method, 'POST');
      expect(req.path.endsWith('/control/filtering/set_url'), isTrue);
      expect(req.data, {
        'url': 'https://example.com/old.txt',
        'data': {
          'name': 'Updated Name',
          'url': 'https://example.com/new.txt',
          'enabled': true,
        },
        'whitelist': true,
      });
    });

    test('removeFilterList sends POST /control/filtering/remove_url with correct payload', () async {
      final res = await apiService.removeFilterList(
        url: 'https://example.com/remove.txt',
        whitelist: false,
      );

      expect(res.isSuccess, isTrue);
      expect(capturedRequests.length, 1);
      final req = capturedRequests.first;
      expect(req.method, 'POST');
      expect(req.path.endsWith('/control/filtering/remove_url'), isTrue);
      expect(req.data, {
        'url': 'https://example.com/remove.txt',
        'whitelist': false,
      });
    });

    test('refreshFilterLists refreshes blocklists and allowlists when whitelist is null', () async {
      final res = await apiService.refreshFilterLists();

      expect(res.isSuccess, isTrue);
      expect(capturedRequests.length, 2);
      expect(capturedRequests[0].path.endsWith('/control/filtering/refresh'), isTrue);
      expect(capturedRequests[0].data, {'whitelist': false});
      expect(capturedRequests[1].path.endsWith('/control/filtering/refresh'), isTrue);
      expect(capturedRequests[1].data, {'whitelist': true});
    });

    test('refreshFilterLists refreshes only specified category when whitelist is provided', () async {
      final res = await apiService.refreshFilterLists(whitelist: true);

      expect(res.isSuccess, isTrue);
      expect(capturedRequests.length, 1);
      expect(capturedRequests[0].path.endsWith('/control/filtering/refresh'), isTrue);
      expect(capturedRequests[0].data, {'whitelist': true});
    });
  });

  group('MockAdGuardApiService In-Memory Filter Lists CRUD', () {
    late MockAdGuardApiService mockApi;

    setUp(() {
      mockApi = MockAdGuardApiService(requiresAuth: false);
    });

    test('supports adding new blocklist and allowlist', () async {
      final initialRes = await mockApi.getFilteringStatus();
      expect(initialRes.data!.filterLists.length, 2);
      expect(initialRes.data!.whitelistFilters.length, 0);

      // Add blocklist
      final addBlock = await mockApi.addFilterList(
        name: 'New Blocklist',
        url: 'https://newblock.com/list.txt',
        whitelist: false,
      );
      expect(addBlock.isSuccess, isTrue);
      expect(mockApi.addFilterListCallCount, 1);

      // Add allowlist
      final addAllow = await mockApi.addFilterList(
        name: 'New Allowlist',
        url: 'https://newallow.com/list.txt',
        whitelist: true,
      );
      expect(addAllow.isSuccess, isTrue);
      expect(mockApi.addFilterListCallCount, 2);

      final updatedRes = await mockApi.getFilteringStatus();
      expect(updatedRes.data!.filterLists.length, 3);
      expect(updatedRes.data!.whitelistFilters.length, 1);
      expect(
        updatedRes.data!.filterLists.any((f) => f.name == 'New Blocklist'),
        isTrue,
      );
      expect(
        updatedRes.data!.whitelistFilters.any((f) => f.name == 'New Allowlist'),
        isTrue,
      );
    });

    test('supports editing existing filter list properties', () async {
      final editRes = await mockApi.setFilterList(
        url: 'https://adaway.org/hosts.txt',
        name: 'AdAway Custom',
        newUrl: 'https://adaway.org/hosts_v2.txt',
        enabled: false,
        whitelist: false,
      );

      expect(editRes.isSuccess, isTrue);
      expect(mockApi.setFilterListCallCount, 1);

      final updatedRes = await mockApi.getFilteringStatus();
      final item = updatedRes.data!.filterLists
          .firstWhere((f) => f.url == 'https://adaway.org/hosts_v2.txt');
      expect(item.name, 'AdAway Custom');
      expect(item.enabled, isFalse);
    });

    test('supports removing existing filter list', () async {
      final removeRes = await mockApi.removeFilterList(
        url: 'https://adaway.org/hosts.txt',
        whitelist: false,
      );

      expect(removeRes.isSuccess, isTrue);
      expect(mockApi.removeFilterListCallCount, 1);

      final updatedRes = await mockApi.getFilteringStatus();
      expect(updatedRes.data!.filterLists.length, 1);
      expect(
        updatedRes.data!.filterLists.any((f) => f.url == 'https://adaway.org/hosts.txt'),
        isFalse,
      );
    });

    test('supports manual refresh updating timestamps', () async {
      final refreshRes = await mockApi.refreshFilterLists();
      expect(refreshRes.isSuccess, isTrue);
      expect(mockApi.refreshFilterListsCallCount, 1);

      final updatedRes = await mockApi.getFilteringStatus();
      expect(updatedRes.data!.filterLists.first.lastUpdated, isNotNull);
    });
  });

  group('AdGuardController Filter Lists Management', () {
    late MockAdGuardApiService mockApi;
    late ProviderContainer container;
    late AdGuardController controller;

    setUp(() {
      mockApi = MockAdGuardApiService(
        routerId: 'reviewer-mock-router',
        requiresAuth: false,
      );
      container = ProviderContainer();
      controller = AdGuardController(
        container.read(adguardControllerProvider('reviewer-mock-router').notifier).ref,
        'reviewer-mock-router',
        apiServiceOverride: mockApi,
      );
    });

    tearDown(() {
      controller.dispose();
      container.dispose();
    });

    test('validates URL and rejects invalid formats before API call', () async {
      await controller.refresh();

      // Empty name
      final res1 = await controller.addFilterList(
        name: '',
        url: 'https://valid.com',
        whitelist: false,
      );
      expect(res1, isFalse);
      expect(controller.currentState.filterListActionError, isNotNull);

      // Invalid scheme (ftp)
      final res2 = await controller.addFilterList(
        name: 'FTP list',
        url: 'ftp://bad.com',
        whitelist: false,
      );
      expect(res2, isFalse);
      expect(
        controller.currentState.filterListActionError,
        contains('Invalid URL'),
      );
    });

    test('rejects duplicate URLs in the same category', () async {
      await controller.refresh();

      final res = await controller.addFilterList(
        name: 'Duplicate',
        url: 'https://adaway.org/hosts.txt',
        whitelist: false,
      );

      expect(res, isFalse);
      expect(
        controller.currentState.filterListActionError,
        contains('already exists'),
      );
      expect(mockApi.addFilterListCallCount, 0);
    });

    test('toggles and edits filter list successfully updating state', () async {
      await controller.refresh();
      final originalList = controller.currentState.filtering!.filterLists.first;

      final toggleRes = await controller.toggleFilterList(
        list: originalList,
        enabled: !originalList.enabled,
      );
      expect(toggleRes, isTrue);
      expect(
        controller.currentState.filtering!.filterLists.first.enabled,
        !originalList.enabled,
      );
    });

    test('removes filter list successfully updating state', () async {
      await controller.refresh();
      expect(controller.currentState.filtering!.filterLists.length, 2);

      final removeRes = await controller.removeFilterList(
        url: 'https://adaway.org/hosts.txt',
        whitelist: false,
      );
      expect(removeRes, isTrue);
      expect(controller.currentState.filtering!.filterLists.length, 1);
    });
  });

  group('AdGuardFilterListsDialog UI & Widget Tests', () {
    late MockAdGuardApiService mockApi;
    late ProviderContainer container;
    late AdGuardController controller;

    setUp(() {
      mockApi = MockAdGuardApiService(
        routerId: 'reviewer-mock-router',
        requiresAuth: false,
      );
      mockApi.mockWhitelistFilters = [
        const AdGuardFilterList(
          id: 3,
          name: 'Custom Allow Rules',
          url: 'https://example.com/whitelist.txt',
          rulesCount: 15,
          enabled: true,
          lastUpdated: '2026-10-07T10:00:00Z',
          whitelist: true,
        ),
      ];
      container = ProviderContainer();
      controller = AdGuardController(
        container.read(adguardControllerProvider('reviewer-mock-router').notifier).ref,
        'reviewer-mock-router',
        apiServiceOverride: mockApi,
      );
    });

    tearDown(() {
      controller.dispose();
      container.dispose();
    });

    testWidgets('renders tabs, list items, search, and toggle switch', (tester) async {
      await controller.refresh();

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AdGuardFilterListsDialog.show(
                context,
                controller: controller,
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Check dialog elements
      expect(find.byKey(const Key('agh_filter_lists_dialog')), findsOneWidget);
      expect(find.byKey(const Key('agh_filter_lists_tab_blocklists')), findsOneWidget);
      expect(find.byKey(const Key('agh_filter_lists_tab_allowlists')), findsOneWidget);
      expect(find.byKey(const Key('agh_filter_lists_search_field')), findsOneWidget);
      expect(find.text('AdGuard DNS filter'), findsOneWidget);
      expect(find.text('AdAway Default Blocklist'), findsOneWidget);

      // Search filtering
      await tester.enterText(
        find.byKey(const Key('agh_filter_lists_search_field')),
        'adaway',
      );
      await tester.pumpAndSettle();

      expect(find.text('AdGuard DNS filter'), findsNothing);
      expect(find.text('AdAway Default Blocklist'), findsOneWidget);

      // Clear search
      await tester.enterText(
        find.byKey(const Key('agh_filter_lists_search_field')),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.text('AdGuard DNS filter'), findsOneWidget);

      // Switch to Allowlists tab
      await tester.tap(find.byKey(const Key('agh_filter_lists_tab_allowlists')));
      await tester.pumpAndSettle();

      expect(find.text('Custom Allow Rules'), findsOneWidget);
    });

    testWidgets('Add dialog opens, fills curated preset, and submits', (tester) async {
      await controller.refresh();

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AdGuardFilterListsDialog.show(
                context,
                controller: controller,
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap Add Filter List button
      await tester.tap(find.byKey(const Key('agh_add_filter_list_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_add_filter_list_dialog')), findsOneWidget);

      // Tap preset chip 'OISD Basic'
      await tester.tap(find.byKey(const Key('agh_filter_list_preset_OISD Basic')));
      await tester.pumpAndSettle();

      // Verify fields were auto-populated
      expect(find.text('OISD Basic'), findsWidgets);
      expect(find.text('https://small.oisd.nl'), findsOneWidget);

      // Tap Add submit button
      await tester.tap(find.byKey(const Key('agh_add_filter_submit_button')));
      await tester.pumpAndSettle();

      // Verify modal dismissed and list added
      expect(find.byKey(const Key('agh_add_filter_list_dialog')), findsNothing);
      expect(find.text('OISD Basic'), findsOneWidget);
      expect(mockApi.addFilterListCallCount, 1);
    });

    testWidgets('Remove list prompts confirmation dialog and executes removal', (tester) async {
      await controller.refresh();

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AdGuardFilterListsDialog.show(
                context,
                controller: controller,
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap delete on AdAway
      const deleteKey = Key('agh_filter_list_delete_https://adaway.org/hosts.txt');
      expect(find.byKey(deleteKey), findsOneWidget);
      await tester.tap(find.byKey(deleteKey));
      await tester.pumpAndSettle();

      // Confirmation dialog displayed
      expect(find.byKey(const Key('agh_delete_confirm_dialog')), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.byKey(const Key('agh_delete_confirm_button')));
      await tester.pumpAndSettle();

      // Confirmation dialog dismissed and item removed
      expect(find.byKey(const Key('agh_delete_confirm_dialog')), findsNothing);
      expect(find.text('AdAway Default Blocklist'), findsNothing);
      expect(mockApi.removeFilterListCallCount, 1);
    });
  });

  group('AdGuardFilteringCard Integration', () {
    testWidgets('Metric tile and action button trigger onManageFilterLists callback', (tester) async {
      bool manageFilterListsCalled = false;
      bool manageUserRulesCalled = false;

      const filteringStatus = AdGuardFilteringStatus(
        enabled: true,
        filterLists: [
          AdGuardFilterList(
            id: 1,
            name: 'List 1',
            rulesCount: 1000,
            enabled: true,
            lastUpdated: '2026-10-10',
          ),
        ],
        userRules: ['||bad.com^'],
        totalRulesCount: 1001,
      );

      await tester.pumpWidget(
        _buildTestApp(
          AdGuardFilteringCard(
            filtering: filteringStatus,
            onManageFilterLists: () {
              manageFilterListsCalled = true;
            },
            onManageUserRules: () {
              manageUserRulesCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Filter Lists metric tile
      await tester.tap(find.byKey(const Key('agh_filter_lists_count')));
      await tester.pumpAndSettle();
      expect(manageFilterListsCalled, isTrue);

      // Redundant bottom buttons removed
      expect(find.byKey(const Key('agh_manage_filter_lists_button')), findsNothing);
      expect(find.byKey(const Key('agh_manage_user_rules_button')), findsNothing);

      // Tap User Rules metric tile
      await tester.tap(find.byKey(const Key('agh_user_rules_count')));
      await tester.pumpAndSettle();
      expect(manageUserRulesCalled, isTrue);
    });
  });
}
