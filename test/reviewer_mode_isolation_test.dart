// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/parental_controls/controllers/parental_controls_controller.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/service_factory.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';

class StubAuthService implements IAuthService {
  String? _sysauth;
  bool _isAuthenticated = false;
  bool _useHttps = false;
  String? _ipAddress;

  @override
  String? get sysauth => _sysauth;
  @override
  bool get isAuthenticated => _isAuthenticated;
  @override
  bool get useHttps => _useHttps;
  @override
  String? get ipAddress => _ipAddress;

  @override
  Future<bool> checkRouterAvailability(
    String ipAddress,
    bool useHttps, {
    BuildContext? context,
  }) async => true;

  @override
  Future<void> login(
    String ip,
    String username,
    String password,
    bool useHttps, {
    dynamic context,
  }) async {
    _sysauth = 'auth_token_for_$ip';
    _isAuthenticated = true;
    _useHttps = useHttps;
    _ipAddress = ip;
  }

  @override
  Future<void> logout() async {
    _sysauth = null;
    _isAuthenticated = false;
    _ipAddress = null;
  }

  @override
  Future<bool> tryAutoLogin(
    String? ip,
    String? username,
    String? password,
    bool? useHttps, {
    bool force = false,
    dynamic context,
  }) async {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reviewer Mode Isolation & Leakage Prevention Tests', () {
    late SecureStorageService secureStorageService;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      secureStorageService = SecureStorageService();
      ServiceContainer.configure(reviewerMode: false);
    });

    test('mockRouter has dedicated non-colliding ID and is recognized by helpers', () {
      final mock = RouterService.mockRouter;
      expect(mock.id, equals(RouterService.reviewerRouterId));
      expect(mock.id, equals('reviewer-mock-router'));
      expect(RouterService.isMockRouter(mock), isTrue);
      expect(RouterService.isMockRouterId(mock.id), isTrue);
      expect(RouterService.isMockRouterId('reviewer://mock-token'), isTrue);

      final realRouter = model.Router(
        id: RouterService.generateId('192.168.1.1', 'root', false),
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      );
      expect(RouterService.isMockRouter(realRouter), isFalse);
      expect(RouterService.isMockRouterId(realRouter.id), isFalse);
      expect(realRouter.id, isNot(equals(mock.id)));
    });

    test('SecureStorageService.saveRouters filters out mock router automatically', () async {
      final realRouter = model.Router(
        id: 'real-router-1',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
        name: 'Home Gateway',
      );

      final mock = RouterService.mockRouter;

      // Attempt to save list containing both real and mock routers
      await secureStorageService.saveRouters([realRouter, mock]);

      // Read back from storage
      final loaded = await secureStorageService.getRouters();
      expect(loaded.length, equals(1));
      expect(loaded.first.id, equals('real-router-1'));
      expect(loaded.any((r) => RouterService.isMockRouter(r)), isFalse);
    });

    test('SecureStorageService.getRouters drops any mock router previously persisted', () async {
      // Artificially inject mock router JSON into raw storage to simulate legacy/corrupted state
      final mockJson = jsonEncode([
        {
          'id': RouterService.reviewerRouterId,
          'ipAddress': '192.168.1.1',
          'username': 'root',
          'password': 'mockpassword',
          'useHttps': false,
          'name': 'Demo Router',
          'lastKnownHostname': 'OpenWrt-Reviewer',
        },
        {
          'id': 'real-router-2',
          'ipAddress': '10.0.0.1',
          'username': 'root',
          'password': 'realpassword',
          'useHttps': false,
          'name': 'Production Gateway',
        },
      ]);
      await secureStorageService.writeValue('routers', mockJson);

      final loaded = await secureStorageService.getRouters();
      expect(loaded.length, equals(1));
      expect(loaded.first.id, equals('real-router-2'));
      expect(loaded.first.ipAddress, equals('10.0.0.1'));
    });

    test('SecureStorageService.getCredentials returns nulls if active router is mock', () async {
      // Artificially set selected router to mock router ID
      await secureStorageService.writeValue(
        'selected_router_id',
        RouterService.reviewerRouterId,
      );

      final creds = await secureStorageService.getCredentials();
      expect(creds['ipAddress'], isNull);
      expect(creds['username'], isNull);
      expect(creds['password'], isNull);
    });

    test('SecureStorageService.saveSelectedRouterId purges key if mock router ID is passed', () async {
      await secureStorageService.saveSelectedRouterId('real-id');
      expect(await secureStorageService.getSelectedRouterId(), equals('real-id'));

      // Now pass mock router id
      await secureStorageService.saveSelectedRouterId(RouterService.reviewerRouterId);
      expect(await secureStorageService.getSelectedRouterId(), isNull);
    });

    test('RouterService in Reviewer Mode operates purely in-memory and blocks persistence', () async {
      final reviewerRouterService = RouterService(isReviewerMode: true);
      await reviewerRouterService.loadRouters();

      expect(reviewerRouterService.routers.length, equals(1));
      expect(reviewerRouterService.selectedRouter?.id, equals(RouterService.reviewerRouterId));

      // Attempt adding a router in reviewer mode
      final tempRouter = model.Router(
        id: 'temp-router',
        ipAddress: '192.168.2.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      );
      await reviewerRouterService.addRouter(tempRouter);

      // Verify that underlying storage was NEVER modified
      final rawStored = await secureStorageService.readValue('routers');
      expect(rawStored, isNull);

      // Verify export is empty in reviewer mode
      final exported = reviewerRouterService.exportRoutersAsJson();
      expect(exported, isEmpty);

      // Verify import is rejected in reviewer mode
      final importResult = await reviewerRouterService.importRoutersFromJson(
        jsonEncode([tempRouter.toJson()]),
      );
      expect(importResult.success, isFalse);
    });

    test('RouterService in production purges any leaked mock router on loadRouters', () async {
      // Seed storage with real and leaked mock router
      await secureStorageService.writeValue(
        'routers',
        jsonEncode([
          RouterService.mockRouter.toJson(),
          {
            'id': 'real-router-3',
            'ipAddress': '192.168.1.1',
            'username': 'root',
            'password': 'realpass',
            'useHttps': false,
          },
        ]),
      );
      await secureStorageService.writeValue(
        'selected_router_id',
        RouterService.reviewerRouterId,
      );

      final prodRouterService = RouterService(isReviewerMode: false);
      await prodRouterService.loadRouters();

      // Mock router must be purged from memory and storage
      expect(prodRouterService.routers.length, equals(1));
      expect(prodRouterService.routers.first.id, equals('real-router-3'));
      expect(prodRouterService.selectedRouter?.id, equals('real-router-3'));

      final storageSelectedId = await secureStorageService.getSelectedRouterId();
      expect(storageSelectedId, equals('real-router-3'));
    });

    test('ParentalControlsController does not persist store in Reviewer Mode or for mock router', () async {
      final appState = AppState.instance;
      await appState.setReviewerMode(true);
      final controller = ParentalControlsController.instance;
      controller.reset();

      final res = await controller.persistStore(appState);
      expect(res.success, isTrue);

      // Secure storage should have no parental controls keys
      final storedKey = await secureStorageService.readValue(
        'parental_controls_store_v1:${RouterService.reviewerRouterId}',
      );
      expect(storedKey, isNull);

      await appState.setReviewerMode(false);
    });

    test('SessionController.logout restores ServiceContainer, resets states, and reloads clean profiles', () async {
      bool sessionResetCalled = false;
      final stubAuthService = StubAuthService();
      final prodRouterService = RouterService(isReviewerMode: false);

      final sessionController = SessionController(
        initialReviewerMode: true,
        apiServiceRef: () => null,
        authServiceRef: () => stubAuthService,
        routerServiceRef: () => prodRouterService,
        secureStorageServiceRef: () => secureStorageService,
        httpClientManagerRef: () => HttpClientManager(),
        dashboardControllerRef: () => null,
        cancelThroughputTimer: () {},
        startThroughputTimer: () {},
        fetchDashboardData: ({bool force = false}) async {},
        initializeServices: () {},
        setLoadingState: (_) {},
        setErrorState: (_) {},
        notifyListeners: () {},
        onSessionReset: () {
          sessionResetCalled = true;
        },
      );

      expect(sessionController.reviewerModeEnabled, isTrue);

      // Perform logout
      await sessionController.logout();

      // Check reviewer mode disabled
      expect(sessionController.reviewerModeEnabled, isFalse);
      expect(sessionResetCalled, isTrue);

      // Verify ServiceContainer was restored to production
      expect(ServiceContainer.instance.factory, isA<ProductionServiceFactory>());
    });
  });
}
