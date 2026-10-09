// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:yala/config/app_config.dart';
import 'package:yala/design/luci_theme.dart';
import 'package:yala/services/secure_storage_service.dart';
import 'package:yala/services/router_service.dart';
import 'package:yala/services/throughput_service.dart';
import 'package:yala/state/controllers/throughput_controller.dart';
import 'package:yala/state/controllers/dashboard_controller.dart';
import 'package:yala/state/controllers/package_controller.dart';
import 'package:yala/state/controllers/network_actions_controller.dart';
import 'package:yala/state/controllers/client_controller.dart';
import 'package:yala/state/controllers/session_controller.dart';
import 'package:yala/models/rpc_result.dart';
import 'package:yala/models/client.dart';
import 'package:yala/modules/parental_controls/models/parental_profile.dart';
import 'package:yala/modules/parental_controls/controllers/parental_controls_controller.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/models/dashboard_preferences.dart';
import 'package:yala/services/interfaces/auth_service_interface.dart';
import 'package:yala/services/interfaces/api_service_interface.dart';
import 'package:yala/services/interfaces/ssh_service_interface.dart';
import 'package:yala/services/api_service.dart';
import 'package:yala/services/service_factory.dart';
import 'package:yala/utils/http_client_manager.dart';
import 'package:yala/utils/logger.dart';
import 'package:yala/utils/os_platform_integration.dart';
import 'package:yala/modules/package_manager/models/package_info.dart';
import 'package:yala/models/router_capabilities.dart';
import 'package:yala/models/network_topology.dart';
import 'package:yala/modules/firewall_security/models/firewall_info.dart';
import 'package:yala/modules/services_system/models/ddns_info.dart';
import 'package:yala/modules/sqm/models/sqm_queue.dart';
import 'package:yala/modules/wireless_management/models/wireless_info.dart';
import 'package:yala/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yala/modules/diagnostics/models/flush_dns_result.dart';

enum RouterConnectionStatus { connected, reconnecting, disconnected }

class _RouterCommand {
  final String command;
  final List<String> args;

  const _RouterCommand(this.command, this.args);
}

class AppState extends ChangeNotifier {
  static AppState? _instance;

  late final SecureStorageService _secureStorageService;
  IApiService? _apiService;
  IAuthService? _authService;
  ISshService? _sshService;
  RouterService? _routerService;

  ISshService? get sshService => _sshService;

  @visibleForTesting
  void setSshServiceForTesting(ISshService service) => _sshService = service;

  @visibleForTesting
  void setDashboardDataForTesting(Map<String, dynamic>? data) {
    _dashboardController?.setDashboardDataForTesting(data);
    notifyListeners();
  }

  @visibleForTesting
  void setIsDashboardLoadingForTesting(bool loading) {
    _dashboardController?.setIsDashboardLoadingForTesting(loading);
    notifyListeners();
  }

  @visibleForTesting
  void setCapabilitiesForTesting(RouterCapabilities? capabilities) {
    _dashboardController?.setCapabilitiesForTesting(capabilities);
    notifyListeners();
  }

  @visibleForTesting
  void setDashboardPreferencesForTesting(DashboardPreferences prefs) {
    _sessionController?.setDashboardPreferencesForTesting(prefs);
    notifyListeners();
  }

  @visibleForTesting
  void setConnectionStatusForTesting(RouterConnectionStatus status) {
    _connectionStatus = status;
    notifyListeners();
  }

  @visibleForTesting
  void notifyRouterBackOnlineForTesting({required bool success}) {
    _notifyRouterBackOnline(success: success);
  }

  ThroughputService? _throughputService;
  ThroughputController? _throughputController;
  SessionController? _sessionController;
  PackageController? _packageController;
  NetworkActionsController? _networkActionsController;
  AccessControlTimerLifecycleManager? _accessControlTimerLifecycleManager;
  ClientController? _clientController;
  DashboardController? _dashboardController;
  final HttpClientManager _httpClientManager = HttpClientManager();

  // Router Capabilities State
  RouterCapabilities? get capabilities => _dashboardController?.capabilities;
  bool get isMissingRpcPackages {
    final caps = capabilities;
    return caps != null &&
        !caps.probeFailed &&
        caps.ubusObjects.isNotEmpty &&
        (!caps.isRpcComplete) &&
        !reviewerModeEnabled;
  }

  // Reviewer mode state
  bool get reviewerModeEnabled =>
      _sessionController?.reviewerModeEnabled ?? false;

  SessionController? get sessionController => _sessionController;

  bool _isLoading = false;
  String? _errorMessage;

  RouterConnectionStatus _connectionStatus = RouterConnectionStatus.connected;
  RouterConnectionStatus get connectionStatus => _connectionStatus;

  Timer? _throughputTimer;
  final int _throughputIntervalSeconds = 2;
  int get throughputIntervalSeconds =>
      _throughputController?.throughputIntervalSeconds ??
      _throughputIntervalSeconds;
  Timer? _pollingTimer;
  int _pollAttempts = 0;
  static const int _maxPollAttempts =
      40; // Max 40 attempts = ~5 minutes with backoff

  // Add rebooting state
  bool _isRebooting = false;
  bool get isRebooting => _isRebooting;

  // Wi-Fi Access Control auto-revert state
  bool get isAccessControlPendingConfirmation =>
      _networkActionsController?.isAccessControlPendingConfirmation ?? false;
  int get accessControlCountdownSeconds =>
      _networkActionsController?.accessControlCountdownSeconds ?? 25;

  // Theme mode state
  ThemeMode get themeMode => _sessionController?.themeMode ?? ThemeMode.system;
  AppThemePalette get themePalette =>
      _sessionController?.themePalette ?? AppThemePalette.amber;
  bool get useDynamicTheme => _sessionController?.useDynamicTheme ?? false;

  // Selected locale (null = System default)
  Locale? get locale => _sessionController?.locale;

  // Clients view mode (aggregate across routers)
  bool get clientsAggregateAllRouters =>
      _sessionController?.clientsAggregateAllRouters ?? true;

  // Dashboard preferences state
  DashboardPreferences get dashboardPreferences =>
      _sessionController?.dashboardPreferences ?? DashboardPreferences();

  List<model.Router> get routers => _sessionController?.routers ?? [];
  model.Router? get selectedRouter => _sessionController?.selectedRouter;
  String? get currentRouterIp => _sessionController?.currentRouterIp;
  RouterService? get routerService => _routerService;

  VoidCallback? onRouterBackOnline;
  final List<void Function(bool success)> _routerBackOnlineListeners = [];

  void addRouterBackOnlineListener(void Function(bool success) listener) {
    if (!_routerBackOnlineListeners.contains(listener)) {
      _routerBackOnlineListeners.add(listener);
    }
  }

  void removeRouterBackOnlineListener(void Function(bool success) listener) {
    _routerBackOnlineListeners.remove(listener);
  }

  void _notifyRouterBackOnline({required bool success}) {
    onRouterBackOnline?.call();
    for (final listener in List<void Function(bool success)>.from(
      _routerBackOnlineListeners,
    )) {
      try {
        listener(success);
      } catch (e) {
        // Safe dispatch against unhandled errors in listener
      }
    }
  }

  // Add requestedTab for programmatic tab switching
  int? requestedTab;
  String? requestedInterfaceToScroll;
  ClientCategoryFilter? requestedClientCategoryFilter;

  // Custom Guest WiFi section overrides & exclusions
  final Set<String> _customGuestSections = {};
  final Set<String> _excludedGuestSections = {};

  Set<String> get customGuestSections => Set.unmodifiable(_customGuestSections);
  Set<String> get excludedGuestSections =>
      Set.unmodifiable(_excludedGuestSections);

  bool isCustomGuestSection(String sectionName) =>
      _customGuestSections.contains(sectionName);
  bool isExcludedGuestSection(String sectionName) =>
      _excludedGuestSections.contains(sectionName);

  void markAsGuestSection(String sectionName) {
    _excludedGuestSections.remove(sectionName);
    _customGuestSections.add(sectionName);
    notifyListeners();
  }

  void markAsStandardSection(String sectionName) {
    _customGuestSections.remove(sectionName);
    _excludedGuestSections.add(sectionName);
    notifyListeners();
  }

  void resetGuestSectionOverride(String sectionName) {
    _customGuestSections.remove(sectionName);
    _excludedGuestSections.remove(sectionName);
    notifyListeners();
  }

  void requestTab(
    int index, {
    String? interfaceToScroll,
    ClientCategoryFilter? clientCategoryFilter,
  }) {
    requestedTab = index;
    requestedInterfaceToScroll = interfaceToScroll;
    requestedClientCategoryFilter = clientCategoryFilter;
    notifyListeners();
  }

  late final Future<void> _initFuture;

  AppState._() {
    _initFuture = _initialize();
  }

  static AppState get instance {
    return _instance ??= AppState._();
  }

  /// Completes when routers, session controller, and secure storage are ready.
  Future<void> ensureInitialized() => _initFuture;

  Future<void> _initialize() async {
    // Configure default storage service first
    ServiceContainer.configure(reviewerMode: false);
    _secureStorageService = ServiceContainer.instance.factory
        .createSecureStorageService();
    _initializeServices();

    final storedReviewerMode = await _secureStorageService.readValue(
      AppConfig.reviewerModeKey,
    );
    if (storedReviewerMode == 'true') {
      await _sessionController?.setReviewerMode(true);
    }

    await _sessionController?.loadThemeMode();
    await _sessionController?.loadDynamicTheme();
    await _sessionController?.loadLocale();
    await loadRouters(); // Load routers on app start (sets selectedRouter)
    await _sessionController
        ?.migrateGlobalDashboardPreferencesIfNeeded(); // Proactively migrate legacy prefs
    await _sessionController?.loadClientsViewMode();
    await loadDashboardPreferences(); // Load prefs scoped to selected router
    await _loadPendingAccessControlState();
  }

  void _initializeServices() {
    final reviewerMode = _sessionController?.reviewerModeEnabled ?? false;
    // Configure the service container based on reviewer mode
    ServiceContainer.configure(reviewerMode: reviewerMode);

    // Create services using the factory
    final factory = ServiceContainer.instance.factory;
    _authService = factory.createAuthService();
    _apiService = factory.createApiService();
    _sshService = factory.createSshService();
    _routerService = factory.createRouterService();
    _throughputService = factory.createThroughputService();
    _throughputController = ThroughputController(
      throughputService: _throughputService!,
    );
    _dashboardController = DashboardController(
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      sshServiceRef: () => _sshService,
      routerServiceRef: () => _routerService,
      secureStorageServiceRef: () => _secureStorageService,
      throughputControllerRef: () => _throughputController,
      dashboardPreferencesRef: () => dashboardPreferences,
      reviewerModeRef: () => reviewerModeEnabled,
      tryAutoLogin: tryAutoLogin,
      fetchPublicIps: fetchPublicIps,
      setPublicIps: (v4, v6) {
        _sessionController?.setPublicIps(v4, v6);
      },
      setConnectionStatus: (status) {
        switch (status) {
          case DashboardConnectionStatus.connected:
            _connectionStatus = RouterConnectionStatus.connected;
            break;
          case DashboardConnectionStatus.reconnecting:
            _connectionStatus = RouterConnectionStatus.reconnecting;
            break;
          case DashboardConnectionStatus.disconnected:
            _connectionStatus = RouterConnectionStatus.disconnected;
            break;
        }
      },
      startThroughputTimer: _startThroughputTimer,
      processDhcpLeases: _processDhcpLeases,
      notifyListeners: notifyListeners,
    );
    _sessionController ??= SessionController(
      initialReviewerMode: reviewerMode,
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      routerServiceRef: () => _routerService,
      secureStorageServiceRef: () => _secureStorageService,
      httpClientManagerRef: () => _httpClientManager,
      dashboardControllerRef: () => _dashboardController,
      cancelThroughputTimer: _cancelThroughputTimer,
      startThroughputTimer: _startThroughputTimer,
      fetchDashboardData: fetchDashboardData,
      initializeServices: _initializeServices,
      setLoadingState: (loading) => _isLoading = loading,
      setErrorState: setError,
      notifyListeners: notifyListeners,
      onSessionReset: () {
        _customGuestSections.clear();
        _excludedGuestSections.clear();
        ParentalControlsController.instance.reset();
        _clientController?.resetState();
        _networkActionsController?.resetState();
        _throughputController?.cancelAndClear();
        invalidateStaticLeasesCache();
      },
    );
    _packageController = PackageController(
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      routerServiceRef: () => _routerService,
      capabilitiesRef: () => capabilities,
      reviewerModeRef: () => reviewerModeEnabled,
      refreshDashboard: fetchDashboardData,
      redetectCapabilities: redetectCapabilities,
    );
    _networkActionsController = NetworkActionsController(
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      routerServiceRef: () => _routerService,
      reviewerModeRef: () => reviewerModeEnabled,
      dashboardDataRef: () => dashboardData,
      refreshDashboard: fetchDashboardData,
      redetectCapabilities: redetectCapabilities,
      notifyListeners: notifyListeners,
    );
    _accessControlTimerLifecycleManager = AccessControlTimerLifecycleManager(
      controller: _networkActionsController!,
    );
    _clientController = ClientController(
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      routerServiceRef: () => _routerService,
      reviewerModeRef: () => reviewerModeEnabled,
      dashboardDataRef: () => dashboardData,
      executeRouterCommandOutput: executeRouterCommandOutput,
      processDhcpLeases: _processDhcpLeases,
      onClientsUpdated: notifyListeners,
    );
  }

  bool _hasShownReviewerNotice = false;
  bool get hasShownReviewerNotice => _hasShownReviewerNotice;

  void markReviewerNoticeShown() {
    _hasShownReviewerNotice = true;
  }

  void resetReviewerNoticeFlag() {
    _hasShownReviewerNotice = false;
  }

  Future<void> setReviewerMode(bool enabled, {BuildContext? context}) async {
    if (enabled) {
      _hasShownReviewerNotice = false;
    }
    _customGuestSections.clear();
    _excludedGuestSections.clear();
    ParentalControlsController.instance.reset();
    _clientController?.resetState();
    _networkActionsController?.resetState();
    _throughputController?.cancelAndClear();
    invalidateStaticLeasesCache();
    await _sessionController?.setReviewerMode(enabled, context: context);
  }

  /// Generic secure storage read — used by feature modules (e.g. Parental Controls).
  Future<String?> secureRead(String key) async {
    return _secureStorageService.readValue(key);
  }

  /// Generic secure storage write — used by feature modules (e.g. Parental Controls).
  Future<void> secureWrite(String key, String value) async {
    await _secureStorageService.writeValue(key, value);
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _sessionController!.setThemeMode(mode);

  Future<void> setThemePalette(AppThemePalette palette) =>
      _sessionController!.setThemePalette(palette);

  Future<void> setDynamicTheme(bool enable) =>
      _sessionController!.setDynamicTheme(enable);

  Future<void> setLocale(Locale? locale) =>
      _sessionController!.setLocale(locale);

  Future<void> setClientsAggregateAllRouters(bool aggregate) =>
      _sessionController!.setClientsAggregateAllRouters(aggregate);

  Future<void> loadDashboardPreferences() =>
      _sessionController!.loadDashboardPreferences();

  Future<void> saveDashboardPreferences(DashboardPreferences prefs) =>
      _sessionController!.saveDashboardPreferences(prefs);

  String? get sysauth => _sessionController?.sysauth;
  bool get isAuthenticated => sysauth != null && sysauth!.isNotEmpty;
  bool get hasActiveSession => isAuthenticated || reviewerModeEnabled;
  IApiService? get apiService => _apiService;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void setError(String? error) {
    if (error == null || error.trim().isEmpty) {
      _errorMessage = null;
    } else {
      _errorMessage = error;
    }
    notifyListeners();
  }

  Map<String, dynamic>? get dashboardData =>
      _dashboardController?.dashboardData;

  /// Count of active wireless interfaces (SSIDs) across all radios
  int get activeWirelessInterfacesCount {
    final wireless = dashboardData?['wireless'] as Map<String, dynamic>?;
    if (wireless == null) return 0;
    int count = 0;
    wireless.forEach((_, radio) {
      if (radio is Map<String, dynamic>) {
        final interfaces = radio['interfaces'] as List<dynamic>?;
        if (interfaces != null) {
          for (final iface in interfaces) {
            if (iface is Map<String, dynamic>) {
              final config = iface['config'] as Map<String, dynamic>?;
              if (config != null &&
                  config['disabled'] != true &&
                  config['mode'] == 'ap') {
                count++;
              }
            }
          }
        }
      }
    });
    return count;
  }

  /// Count of active wireless radios
  int get activeWirelessRadiosCount {
    final wireless = dashboardData?['wireless'] as Map<String, dynamic>?;
    if (wireless == null) return 0;
    int count = 0;
    wireless.forEach((_, radio) {
      if (radio is Map<String, dynamic>) {
        if (radio['up'] == true && radio['disabled'] != true) {
          count++;
        }
      }
    });
    return count;
  }

  List<double> get rxHistory => _throughputController?.rxHistory ?? [];
  List<double> get txHistory => _throughputController?.txHistory ?? [];
  double get currentRxRate => _throughputController?.currentRxRate ?? 0.0;
  double get currentTxRate => _throughputController?.currentTxRate ?? 0.0;
  bool get isDashboardLoading =>
      _dashboardController?.isDashboardLoading ?? false;
  String? get dashboardError => _dashboardController?.dashboardError;

  String? get publicIpv4 => _sessionController?.publicIpv4;
  String? get publicIpv6 => _sessionController?.publicIpv6;
  bool get isFetchingPublicIps =>
      _sessionController?.isFetchingPublicIps ?? false;

  Future<void> fetchPublicIps({BuildContext? context}) =>
      _sessionController!.fetchPublicIps(context: context);

  // Interface-specific throughput getters
  List<double> getRxHistoryForInterface(String interface) {
    final deviceName = getDeviceNameForInterface(interface);
    return _throughputController?.getRxHistoryForInterface(
          deviceName ?? interface,
        ) ??
        [];
  }

  List<double> getTxHistoryForInterface(String interface) {
    final deviceName = getDeviceNameForInterface(interface);
    return _throughputController?.getTxHistoryForInterface(
          deviceName ?? interface,
        ) ??
        [];
  }

  double getCurrentRxRateForInterface(String interface) {
    final deviceName = getDeviceNameForInterface(interface);
    return _throughputController?.getCurrentRxRateForInterface(
          deviceName ?? interface,
        ) ??
        0.0;
  }

  double getCurrentTxRateForInterface(String interface) {
    final deviceName = getDeviceNameForInterface(interface);
    return _throughputController?.getCurrentTxRateForInterface(
          deviceName ?? interface,
        ) ??
        0.0;
  }

  Future<void> loadRouters() => _sessionController!.loadRouters();

  Future<void> addRouter(model.Router router) =>
      _sessionController!.addRouter(router);

  Future<void> removeRouter(String id) => _sessionController!.removeRouter(id);

  Future<void> selectRouter(String id, {BuildContext? context}) async {
    _customGuestSections.clear();
    _excludedGuestSections.clear();
    ParentalControlsController.instance.reset();
    _clientController?.resetState();
    _networkActionsController?.resetState();
    _throughputController?.cancelAndClear();
    invalidateStaticLeasesCache();
    await _sessionController!.selectRouter(id, context: context);
  }

  Future<void> updateRouter(model.Router router) =>
      _sessionController!.updateRouter(router);

  Future<void> updateRouterName(String id, String? name) =>
      _sessionController!.updateRouterName(id, name);

  Future<FileSaveResult?> exportRouterProfiles() =>
      _sessionController!.exportRouterProfiles();

  Future<RouterImportResult> importRouterProfilesFromFile() =>
      _sessionController!.importRouterProfilesFromFile();

  Future<RouterImportResult> importRoutersFromJson(String jsonContent) =>
      _sessionController!.importRoutersFromJson(jsonContent);

  Future<bool> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    bool fromRouter = false,
    String? routerName,
    BuildContext? context,
  }) => _sessionController!.login(
    ip,
    user,
    pass,
    useHttps,
    fromRouter: fromRouter,
    routerName: routerName,
    context: context,
  );

  Future<void> logout() async {
    _customGuestSections.clear();
    _excludedGuestSections.clear();
    ParentalControlsController.instance.reset();
    _clientController?.resetState();
    _networkActionsController?.resetState();
    _throughputController?.cancelAndClear();
    invalidateStaticLeasesCache();
    await _sessionController!.logout();
  }

  /// Action to re-detect capabilities for the active router
  Future<void> redetectCapabilities() async {
    await _dashboardController?.redetectCapabilities();
  }

  /// Update package engine dynamically if detected during package operations
  void updatePackageEngine(PackageManagerEngine engine) {
    _dashboardController?.updatePackageEngine(engine);
  }

  /// Probe and cache actual ubus objects, methods, package manager engine, firewall backend, and network model.
  Future<RouterCapabilities> probeRouterCapabilities({
    bool forceRefresh = false,
  }) async {
    return await _dashboardController?.probeRouterCapabilities(
          forceRefresh: forceRefresh,
        ) ??
        RouterCapabilities.conservative('unknown');
  }

  Future<void> fetchDashboardData({bool force = false}) async {
    await _dashboardController?.fetchDashboardData(force: force);
    await fetchClientsForSelectedRouter();
  }

  /// Lazy capability-aware fetch returning a list of installed OpenWrtPackage objects
  Future<RpcResult<List<OpenWrtPackage>>> fetchInstalledPackages() =>
      _packageController!.fetchInstalledPackages();

  /// Capability-aware fetch for installed packages returning RpcResult
  Future<RpcResult<dynamic>> fetchPackagesDataResult() =>
      _packageController!.fetchPackagesDataResult();

  /// Capability-aware fetch for available packages returning list of OpenWrtPackage
  Future<RpcResult<List<OpenWrtPackage>>> fetchAvailablePackages() =>
      _packageController!.fetchAvailablePackages();

  /// Fetch complete LuCI-parity package overview (installed, available, upgradable, disk space)
  Future<RpcResult<PackageManagerOverview>> fetchPackageManagerOverview() =>
      _packageController!.fetchPackageManagerOverview();

  /// Capability-aware fetch for available packages returning RpcResult
  Future<RpcResult<dynamic>> fetchAvailablePackagesDataResult() =>
      _packageController!.fetchAvailablePackagesDataResult();

  /// Capability-aware fetch for network switch / VLAN topology returning `RpcResult<NetworkTopology>`
  Future<RpcResult<NetworkTopology>> fetchNetworkTopologyResult() async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    if (ip == null || _authService?.sysauth == null) {
      return RpcResult.networkError('No active router session');
    }
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;

    final model = capabilities?.networkModel ?? NetworkModel.unknown;
    if (model == NetworkModel.unknown) {
      return RpcResult.methodNotFound(
        'Network model is unknown or in conservative fallback mode',
      );
    }

    try {
      final rawRpc = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'network'},
      );

      final rpcRes = RpcResult.fromUbusResponse<NetworkTopology>(rawRpc, (
        data,
      ) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          if (model == NetworkModel.dsa) {
            return DsaTopologyParser.parse(map, null);
          } else {
            return SwconfigTopologyParser.parse(map, null);
          }
        }
        return NetworkTopology.unavailable(
          model,
          'Invalid network config payload format',
        );
      });

      if (rpcRes.status == RpcCallStatus.methodNotFound) {
        Logger.warning(
          'Network topology fetch returned methodNotFound. Triggering background capability re-probe.',
        );
        unawaited(redetectCapabilities());
      }

      return rpcRes;
    } catch (e) {
      return RpcResult.networkError(
        'Network error fetching switch topology: $e',
      );
    }
  }

  /// Capability-aware fetch for firewall configuration returning `RpcResult<FirewallOverview>`
  Future<RpcResult<FirewallOverview>> fetchFirewallOverviewResult() async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    if (ip == null || _authService?.sysauth == null) {
      return RpcResult.networkError('No active router session');
    }
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final backend = capabilities?.firewallBackend ?? FirewallBackend.fw4;

    try {
      final rawRpc = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'firewall'},
      );

      final rpcRes = RpcResult.fromUbusResponse<FirewallOverview>(rawRpc, (
        data,
      ) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          return FirewallOverview.fromUciData(
            map,
            backend: backend,
            isReviewerMode: reviewerModeEnabled,
          );
        }
        return FirewallOverview.unavailable(
          backend,
          'Invalid firewall config payload format',
        );
      });

      if (rpcRes.status == RpcCallStatus.methodNotFound) {
        Logger.warning(
          'Firewall config fetch returned methodNotFound. Triggering background capability re-probe.',
        );
        unawaited(redetectCapabilities());
      }

      return rpcRes;
    } catch (e) {
      return RpcResult.networkError(
        'Network error fetching firewall overview: $e',
      );
    }
  }

  /// Capability-aware fetch for wireless configuration returning `RpcResult<WirelessOverview>`
  Future<RpcResult<WirelessOverview>> fetchWirelessOverviewResult() async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    if (ip == null || _authService?.sysauth == null) {
      return RpcResult.networkError('No active router session');
    }
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;

    try {
      final rawRpc = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'luci-rpc',
        method: 'getWirelessDevices',
        params: {},
      );

      final rpcRes = RpcResult.fromUbusResponse<WirelessOverview>(rawRpc, (
        data,
      ) {
        return WirelessOverview.fromDashboardData({
          'wireless': data,
        }, isReviewerMode: reviewerModeEnabled);
      });

      if (rpcRes.status == RpcCallStatus.methodNotFound) {
        Logger.warning(
          'Wireless devices fetch returned methodNotFound. Triggering background capability re-probe.',
        );
        unawaited(redetectCapabilities());
      }

      return rpcRes;
    } catch (e) {
      return RpcResult.networkError(
        'Network error fetching wireless overview: $e',
      );
    }
  }

  /// Manage software packages on OpenWrt (OPKG / APK) returning classified RpcResult
  Future<RpcResult<String>> managePackageResult({
    required String packageName,
    required String action,
  }) => _packageController!.managePackageResult(
    packageName: packageName,
    action: action,
  );

  /// Backward compatible wrapper for managePackage
  Future<bool> managePackage({
    required String packageName,
    required String action,
  }) => _packageController!.managePackage(
    packageName: packageName,
    action: action,
  );

  /// Query free disk space in bytes for package operations (/overlay or /)
  Future<int?> getFreeDiskSpace() =>
      _packageController?.getFreeDiskSpace() ?? Future.value(null);

  /// Update package lists from feeds (/usr/libexec/package-manager-call update)
  Future<RpcResult<String>> updatePackageLists() =>
      _packageController!.updatePackageLists();

  /// Safely install single package by exact name
  Future<RpcResult<String>> installPackage(String packageName) =>
      _packageController!.installPackage(packageName);

  /// Safely remove single package by exact name
  Future<RpcResult<String>> removePackage(String packageName) =>
      _packageController!.removePackage(packageName);

  /// Safely upgrade single package by exact name
  Future<RpcResult<String>> upgradePackage(String packageName) =>
      _packageController!.upgradePackage(packageName);

  /// Install custom package from URL or custom name
  Future<RpcResult<String>> installCustomPackage(String target) =>
      _packageController!.installCustomPackage(target);

  /// Check and fetch upgradable packages returning classified RpcResult
  Future<RpcResult<List<OpenWrtPackage>>> fetchUpgradablePackagesResult() =>
      _packageController!.fetchUpgradablePackagesResult();

  /// Backward compatible wrapper for fetchUpgradablePackages
  Future<List<OpenWrtPackage>> fetchUpgradablePackages() =>
      _packageController!.fetchUpgradablePackages();

  /// Execute generic router shell command via file.exec RPC
  Future<dynamic> callRpc(
    String object,
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (reviewerModeEnabled ||
        _apiService == null ||
        selectedRouter == null ||
        _authService?.sysauth == null) {
      return null;
    }
    return await _apiService!.call(
      selectedRouter!.ipAddress,
      _authService!.sysauth!,
      selectedRouter!.useHttps,
      object: object,
      method: method,
      params: params,
    );
  }

  Future<bool> executeRouterCommand(String command, List<String> args) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    if (ip == null || _authService?.sysauth == null) return false;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;

    final normalized = _normalizeRouterCommand(command, args);
    final execCommand = normalized.command;
    final execArgs = normalized.args;

    // Resilient service action interception:
    // Commands matching `/etc/init.d/<service>` with an action argument (e.g. restart, reload)
    // will be rejected with permission denied [6] by OpenWrt file.exec rpcd ACLs.
    // Route them through the native rc.init ubus service dispatcher instead.
    if (execCommand.startsWith('/etc/init.d/') && execArgs.isNotEmpty) {
      final serviceName = execCommand.replaceFirst('/etc/init.d/', '').trim();
      final action = execArgs[0].trim();
      if (serviceName.isNotEmpty && action.isNotEmpty) {
        final ok = await manageServiceAction(serviceName, action);
        if (ok) return true;
      }
    }

    final isShellCmd =
        execCommand == 'sh' ||
        execCommand == '/bin/sh' ||
        execCommand == 'ash' ||
        execCommand == '/bin/ash';
    final cmdStr = isShellCmd && execArgs.length >= 2 && execArgs[0] == '-c'
        ? execArgs[1]
        : ([execCommand, ...execArgs]).join(' ');

    try {
      final res = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': execCommand, 'params': execArgs, 'args': execArgs},
      );
      if (_isSuccessResponse(res)) return true;
    } catch (_) {}

    try {
      final res = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', cmdStr],
          'args': ['-c', cmdStr],
        },
      );
      if (_isSuccessResponse(res)) return true;
    } catch (_) {}

    try {
      final res = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': 'sh',
          'params': ['-c', cmdStr],
          'args': ['-c', cmdStr],
        },
      );
      if (_isSuccessResponse(res)) return true;
    } catch (_) {}

    return false;
  }

  bool _isSuccessResponse(dynamic res) {
    return RpcResult.fromUbusResponse<dynamic>(res, (data) => data).isSuccess;
  }

  String? _extractStdout(dynamic res) {
    if (res == null) return null;
    if (res is String) return res;

    if (res is List) {
      if (res.isEmpty) return null;
      for (final item in res) {
        if (item is Map) {
          final out = item['stdout'] ?? item['data'] ?? item['out'];
          if (out != null) return out.toString();
        } else if (item is String && item.isNotEmpty && item != '0') {
          return item;
        }
      }
    } else if (res is Map) {
      final out = res['stdout'] ?? res['data'] ?? res['out'];
      if (out != null) return out.toString();
      final result = res['result'];
      if (result != null) return _extractStdout(result);
    }
    return null;
  }

  /// Execute generic router shell command via file.exec or file.read RPC and return output String
  Future<String?> executeRouterCommandOutput(
    String command,
    List<String> args,
  ) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    if (ip == null || _authService?.sysauth == null) return null;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;

    final normalized = _normalizeRouterCommand(command, args);
    final execCommand = normalized.command;
    final execArgs = normalized.args;
    final isShellCmd =
        execCommand == 'sh' ||
        execCommand == '/bin/sh' ||
        execCommand == 'ash' ||
        execCommand == '/bin/ash';
    final cmdStr = isShellCmd && execArgs.length >= 2 && execArgs[0] == '-c'
        ? execArgs[1]
        : ([execCommand, ...execArgs]).join(' ');

    final readPath = _readPathForCommand(execCommand, execArgs);
    if (readPath != null) {
      try {
        final readRes = await _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'file',
          method: 'read',
          params: {'path': readPath},
        );
        final out = _extractStdout(readRes);
        if (out != null && out.trim().isNotEmpty) return out;
      } catch (_) {}
    }

    // 1. Direct exec
    try {
      final res = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': execCommand, 'params': execArgs, 'args': execArgs},
      );
      final out = _extractStdout(res);
      if (out != null && out.trim().isNotEmpty) return out;
    } catch (_) {}

    // 2. Shell exec fallbacks
    try {
      final res = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', cmdStr],
          'args': ['-c', cmdStr],
        },
      );
      final out = _extractStdout(res);
      if (out != null && out.trim().isNotEmpty) return out;
    } catch (_) {}

    try {
      final res = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': 'sh',
          'params': ['-c', cmdStr],
          'args': ['-c', cmdStr],
        },
      );
      final out = _extractStdout(res);
      if (out != null && out.trim().isNotEmpty) return out;
    } catch (_) {}

    // 3. File read fallback
    if (execCommand == 'cat' && execArgs.isNotEmpty) {
      try {
        final readRes = await _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'file',
          method: 'read',
          params: {'path': execArgs.last},
        );
        final out = _extractStdout(readRes);
        if (out != null && out.trim().isNotEmpty) return out;
      } catch (_) {}
    }

    return null;
  }

  _RouterCommand _normalizeRouterCommand(String command, List<String> args) {
    if (command == 'sh' || command == 'ash' || command == 'bash') {
      return _RouterCommand('/bin/sh', args);
    }
    if (command == 'cat') {
      return _RouterCommand('/bin/cat', args);
    }
    if (command == 'ip' || command == '/sbin/ip') {
      if (args.contains('-4') || args.contains('-6')) {
        return _RouterCommand('/sbin/ip', args);
      }
      if (args.isEmpty || args[0] == 'neigh') {
        final remaining = args.isNotEmpty ? args.sublist(1) : <String>[];
        return _RouterCommand('/sbin/ip', ['-4', 'neigh', ...remaining]);
      }
      return _RouterCommand('/sbin/ip', args);
    }
    if (command == 'bridge' || command == '/sbin/bridge') {
      return _RouterCommand('/sbin/bridge', args);
    }
    if ((command == 'sysupgrade' || command == '/sbin/sysupgrade') &&
        (args.contains('-l') || args.contains('--list-backup'))) {
      return const _RouterCommand('/sbin/sysupgrade', ['--list-backup']);
    }
    if (command == 'wifi') {
      return _RouterCommand('/sbin/wifi', args);
    }
    if (command == 'reboot') {
      return _RouterCommand('/sbin/reboot', args);
    }
    if (command == 'firstboot') {
      return _RouterCommand('/sbin/firstboot', args);
    }
    return _RouterCommand(command, args);
  }

  String? _readPathForCommand(String command, List<String> args) {
    if (args.isEmpty) return null;
    if (command == 'cat' || command == '/bin/cat') {
      return args.last;
    }
    return null;
  }

  Map<String, dynamic> _processDhcpLeases(Map<String, dynamic> rawDhcpData) {
    final rawStr =
        rawDhcpData['data']?.toString() ??
        rawDhcpData['stdout']?.toString() ??
        '';
    final leases = <Map<String, dynamic>>[];

    for (final line in rawStr.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        final timestamp = int.tryParse(parts[0]) ?? 0;
        final macAddress = parts[1];
        final ipAddress = parts[2];
        final hostname = parts[3] == '*' ? 'Unknown' : parts[3];

        leases.add({
          'expires': timestamp,
          'macaddr': macAddress,
          'ipaddr': ipAddress,
          'hostname': hostname,
          'activetime': 0,
          'leasetime': timestamp,
        });
      }
    }

    return {'dhcp_leases': leases, 'leases': leases};
  }

  String? getDeviceNameForInterface(String interfaceName) =>
      _dashboardController?.getDeviceNameForInterface(interfaceName) ??
      interfaceName;

  void setThroughputInterval(int seconds) {
    if (_throughputController?.setInterval(
          seconds,
          isRebooting: _isRebooting,
          onTick: _updateThroughputOnly,
        ) ??
        false) {
      notifyListeners();
    }
  }

  bool _isDashboardTabActive = true;

  /// Returns true if the dashboard tab is currently active.
  bool get isDashboardTabActive => _isDashboardTabActive;

  /// Updates whether the dashboard tab is active. Automatically pauses or resumes throughput polling.
  void setDashboardTabActive(bool active) {
    if (_isDashboardTabActive == active) return;
    _isDashboardTabActive = active;
    if (active) {
      resumeThroughputTimer(immediateTick: true);
    } else {
      pauseThroughputTimer();
    }
  }

  void _startThroughputTimer({bool immediateTick = true}) {
    if (!_isDashboardTabActive || !hasActiveSession) return;
    _throughputController?.startTimer(
      isRebooting: _isRebooting,
      onTick: _updateThroughputOnly,
    );
    if (immediateTick && !_isRebooting) {
      Future.microtask(_updateThroughputOnly);
    }
  }

  bool _isUserScrolling = false;
  bool _pendingNotificationWhileScrolling = false;

  /// Returns true if the user is actively scrolling a view in the app.
  bool get isUserScrolling => _isUserScrolling;

  /// Updates current user scroll state to pause/resume background UI updates during active gesture scrolling.
  void setScrollState(bool isScrolling) {
    if (_isUserScrolling == isScrolling) return;
    _isUserScrolling = isScrolling;
    if (!isScrolling && _pendingNotificationWhileScrolling) {
      _pendingNotificationWhileScrolling = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isUserScrolling) {
          notifyListeners();
        }
      });
    }
  }

  /// Deferrable listener notification: avoids triggering frame rebuilds mid-scrolling to eliminate jitters
  /// and suppresses background throughput rebuilds when not viewing the Dashboard tab.
  void notifyListenersDeferrable() {
    if (_isUserScrolling) {
      _pendingNotificationWhileScrolling = true;
    } else if (_isDashboardTabActive) {
      _pendingNotificationWhileScrolling = false;
      notifyListeners();
    }
  }

  bool _isHeavyTaskRunning = false;
  bool get isHeavyTaskRunning => _isHeavyTaskRunning;
  void setHeavyTaskRunning(bool running) {
    _isHeavyTaskRunning = running;
  }

  bool _isUpdatingThroughput = false;

  /// Updates only throughput data without refetching the entire dashboard
  Future<void> _updateThroughputOnly() async {
    // Don't try to update throughput during reboot, heavy tasks, or concurrent updates
    if (_isRebooting || _isHeavyTaskRunning || _isUpdatingThroughput) {
      return;
    }
    _isUpdatingThroughput = true;
    try {
      if (reviewerModeEnabled) {
        // For reviewer mode, get network devices and system info
        try {
          final results = await Future.wait([
            _apiService!.callSimple('network', 'device', {}),
            _apiService!.callSimple('system', 'info', {}),
          ]);
          final rawNet = results[0][1];
          final networkData = rawNet is Map
              ? Map<String, dynamic>.from(rawNet)
              : null;
          final rawSys = results[1][1];
          final sysInfoData = rawSys is Map
              ? Map<String, dynamic>.from(rawSys)
              : null;
          if (sysInfoData != null) {
            _dashboardController?.updateSysInfo(sysInfoData);
          }

          final wanDeviceNames = {'eth0'}; // Mock WAN device

          // Resolve specific interface from preferences
          final specificInterface =
              ThroughputController.resolveSpecificInterface(
                dashboardPreferences,
                deviceNameResolver: (iface) => getDeviceNameForInterface(iface),
              );

          _throughputController?.updateThroughput(
            networkData,
            wanDeviceNames,
            specificInterface: specificInterface,
          );
          notifyListenersDeferrable();
        } catch (e) {
          // Don't log throughput update errors as they're non-critical
        }
        return;
      }

      if (_routerService?.selectedRouter == null ||
          _authService?.sysauth == null) {
        return;
      }

      final ip = _routerService!.selectedRouter!.ipAddress;
      final useHttps = _routerService!.selectedRouter!.useHttps;

      try {
        // Fetch network devices and system info in parallel for real-time charts
        final results = await Future.wait([
          _apiService!.call(
            ip,
            _authService!.sysauth!,
            useHttps,
            object: 'luci-rpc',
            method: 'getNetworkDevices',
            params: {},
          ),
          _apiService!.call(
            ip,
            _authService!.sysauth!,
            useHttps,
            object: 'system',
            method: 'info',
            params: {},
          ),
        ]);

        final netResult = results[0];
        final sysResult = results[1];

        if (sysResult is List && sysResult.length > 1 && sysResult[0] == 0) {
          final rawSys = sysResult[1];
          final sysInfoData = rawSys is Map
              ? Map<String, dynamic>.from(rawSys)
              : null;
          if (sysInfoData != null) {
            _dashboardController?.updateSysInfo(sysInfoData);
          }
        }

        dynamic netDataResult = netResult;
        if (netDataResult is! List ||
            netDataResult.length <= 1 ||
            netDataResult[0] != 0) {
          try {
            netDataResult = await _apiService!.call(
              ip,
              _authService!.sysauth!,
              useHttps,
              object: 'network.device',
              method: 'status',
              params: {},
            );
          } catch (_) {}
        }

        if (netDataResult is List &&
            netDataResult.length > 1 &&
            netDataResult[0] == 0) {
          final rawNet = netDataResult[1];
          final networkData = rawNet is Map
              ? Map<String, dynamic>.from(rawNet)
              : null;

          final rawDump = dashboardData?['interfaceDump'];
          final interfaceDump = rawDump is Map
              ? Map<String, dynamic>.from(rawDump)
              : null;
          final wanDeviceNames =
              ThroughputController.resolveNetdevKeysForThroughput(
                networkData,
                interfaceDump,
              );

          // Resolve specific interface from preferences
          final specificInterface =
              ThroughputController.resolveSpecificInterface(
                dashboardPreferences,
                deviceNameResolver: (iface) => getDeviceNameForInterface(iface),
              );

          _throughputController?.updateThroughput(
            networkData,
            wanDeviceNames,
            specificInterface: specificInterface,
          );
          notifyListenersDeferrable();
        }
      } catch (e) {
        // Don't log throughput update errors as they're non-critical
      }
    } finally {
      _isUpdatingThroughput = false;
    }
  }

  void startThroughputTimer() {
    _startThroughputTimer();
  }

  void cancelThroughputTimer() {
    _throughputController?.cancelAndClear();
  }

  /// Pauses periodic throughput polling without clearing accumulated rate history.
  void pauseThroughputTimer() {
    _throughputController?.pauseTimer();
  }

  /// Resumes periodic throughput polling if the dashboard tab is active, a session is active, and not rebooting.
  void resumeThroughputTimer({bool immediateTick = false}) {
    if (_isDashboardTabActive && hasActiveSession && !_isRebooting) {
      _throughputController?.resumeTimer(
        isRebooting: _isRebooting,
        onTick: _updateThroughputOnly,
        immediateTick: immediateTick,
      );
    }
  }

  void _cancelThroughputTimer() {
    cancelThroughputTimer();
  }

  Future<bool> reboot({BuildContext? context}) async {
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    // Cancel throughput timer before starting reboot to prevent "client closed" errors
    _cancelThroughputTimer();

    _isRebooting = true;
    notifyListeners();

    try {
      final result = await _apiService!.reboot(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        context: context,
      );
      // Wait 30 seconds before starting to poll for router availability
      // Some routers take longer to reboot
      Future.delayed(const Duration(seconds: 30), () {
        _pollRouterAvailability();
      });
      return result;
    } catch (e) {
      _isRebooting = false;
      notifyListeners();
      return false;
    }
  }

  void _pollRouterAvailability() {
    // Reset poll attempts
    _pollAttempts = 0;
    _pollingTimer?.cancel();

    // Start polling with exponential backoff
    _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    if (_pollAttempts >= _maxPollAttempts) {
      // Max attempts reached, stop polling
      _isRebooting = false;
      notifyListeners();
      // print('[Reboot] Timeout: Router did not come back online after $_maxPollAttempts attempts');

      // Notify UI that router reboot timed out
      _notifyRouterBackOnline(success: false);
      return;
    }

    // Calculate delay with exponential backoff: 3s, 3s, 5s, 8s, 12s, 18s, then 20s intervals
    int delaySeconds;
    if (_pollAttempts < 2) {
      delaySeconds = 3;
    } else if (_pollAttempts < 4) {
      delaySeconds = 5;
    } else if (_pollAttempts < 6) {
      delaySeconds = 8;
    } else if (_pollAttempts < 8) {
      delaySeconds = 12;
    } else if (_pollAttempts < 10) {
      delaySeconds = 18;
    } else {
      delaySeconds = 20; // Cap at 20 seconds for remaining attempts
    }

    _pollingTimer = Timer(Duration(seconds: delaySeconds), () async {
      _pollAttempts++;
      final available = await _pingRouter();

      if (available) {
        // Router is back online
        _pollingTimer?.cancel();
        _pollingTimer = null;
        _isRebooting = false;
        _pollAttempts = 0;
        notifyListeners();

        // Notify UI that router is back online
        _notifyRouterBackOnline(success: true);

        // Force relogin
        if (_routerService?.selectedRouter != null) {
          await login(
            _routerService!.selectedRouter!.ipAddress,
            _routerService!.selectedRouter!.username,
            _routerService!.selectedRouter!.password,
            _routerService!.selectedRouter!.useHttps,
          );
        }
      } else {
        // Schedule next poll
        _scheduleNextPoll();
      }
    });
  }

  Future<bool> _pingRouter() async {
    if (_authService?.ipAddress == null) return false;

    // Clear cached HTTP clients for this host to avoid stale connections
    if (_pollAttempts == 0) {
      _httpClientManager.disposeClient(
        _authService!.ipAddress!,
        _authService!.useHttps,
      );
    }

    // Try multiple endpoints in order
    final scheme = _authService!.useHttps ? 'https' : 'http';
    final endpoints = [
      '/', // Root
      '/cgi-bin/luci/', // LuCI login page
      '/cgi-bin/luci/admin', // Admin page
    ];

    for (final endpoint in endpoints) {
      try {
        final url = '$scheme://${_authService!.ipAddress}$endpoint';

        // Create a fresh Dio client for pinging to avoid certificate/connection issues
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            followRedirects: false,
            validateStatus: (code) => code != null && code >= 200 && code < 500,
          ),
        );

        if (_authService!.useHttps) {
          final adapter = IOHttpClientAdapter();
          adapter.createHttpClient = () {
            final httpClient = HttpClient();
            httpClient.connectionTimeout = const Duration(seconds: 15);
            // Accept any cert for ping only
            httpClient.badCertificateCallback = (cert, host, port) => true;
            return httpClient;
          };
          dio.httpClientAdapter = adapter;
        }

        // print('[Ping] Attempt $_pollAttempts: Checking $url');
        final response = await dio.get(url);
        // print('[Ping] Response from $endpoint: ${response.statusCode}');

        // Accept various status codes as "alive"
        final isAlive =
            response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 500;

        if (isAlive) {
          if (_pollAttempts > 5) {
            // If we've been polling for a while and get a response,
            // wait a bit more to ensure services are fully started
            await Future.delayed(const Duration(seconds: 10));
          }
          return true;
        }
      } catch (e) {
        // Try next endpoint
        if (endpoint == endpoints.last) {
          // print('[Ping] All endpoints failed on attempt $_pollAttempts');
          // print('[Ping] Last error: ${e.toString()}');

          if (e is SocketException) {
            // print('[Ping] Socket error: ${e.message}, OS Error: ${e.osError}');
          } else if (e is HandshakeException) {
            // print('[Ping] SSL handshake error - router may still be starting');
          }
        }
      }
    }

    return false;
  }

  Future<bool> checkRouterAvailability() async {
    if (reviewerModeEnabled || _authService?.ipAddress == null) {
      return reviewerModeEnabled;
    }
    return await _authService!.checkRouterAvailability(
      _authService!.ipAddress!,
      _authService!.useHttps,
    );
  }

  Set<String> get pausedInternetMacs =>
      _networkActionsController?.pausedInternetMacs ?? {};

  Set<String> get bannedWirelessMacs =>
      _networkActionsController?.bannedWirelessMacs ?? {};

  bool isInternetPaused(String mac) =>
      _networkActionsController?.isInternetPaused(mac) ?? false;

  bool isWirelessBanned(String mac) =>
      _networkActionsController?.isWirelessBanned(mac) ?? false;

  bool isRestrictedOrBanned(String mac) =>
      isInternetPaused(mac) || isWirelessBanned(mac);

  Future<bool> disconnectWirelessClient(
    String macAddress, {
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  }) => _networkActionsController!.disconnectWirelessClient(
    macAddress,
    iface: iface,
    banTimeSeconds: banTimeSeconds,
    context: context,
  );

  Future<bool> pauseClientInternet(
    String macAddress, {
    required bool pause,
    BuildContext? context,
  }) => _networkActionsController!.pauseClientInternet(
    macAddress,
    pause: pause,
    context: context,
  );

  Future<bool> applyParentalProfileDns({
    required String profileId,
    required List<String> macAddresses,
    required List<String>? dnsServers,
    BuildContext? context,
  }) => _networkActionsController!.applyParentalProfileDns(
    profileId: profileId,
    macAddresses: macAddresses,
    dnsServers: dnsServers,
    context: context,
  );

  Future<List<ParentalProfile>?> fetchParentalProfiles({
    BuildContext? context,
  }) => _networkActionsController!.fetchParentalProfiles(context: context);

  Future<bool> saveParentalProfile({
    required ParentalProfile profile,
    BuildContext? context,
  }) => _networkActionsController!.saveParentalProfile(
    profile: profile,
    context: context,
  );

  Future<bool> deleteParentalProfile({
    required String profileId,
    BuildContext? context,
  }) => _networkActionsController!.deleteParentalProfile(
    profileId: profileId,
    context: context,
  );

  Future<bool> addStaticLease({
    required String macAddress,
    required String targetIp,
    required String hostname,
    String? targetIp6,
    String? duid,
    String? leaseTime,
    BuildContext? context,
  }) async {
    final res = await _networkActionsController!.addStaticLease(
      macAddress: macAddress,
      targetIp: targetIp,
      hostname: hostname,
      targetIp6: targetIp6,
      duid: duid,
      leaseTime: leaseTime,
      context: context,
    );
    if (res) {
      invalidateStaticLeasesCache();
      // Refresh in background — do NOT await so the loading toast transitions
      // to success immediately rather than waiting for a full network round-trip.
      unawaited(fetchDashboardData());
      unawaited(fetchClientsForSelectedRouter());
    }
    return res;
  }

  Future<bool> deleteStaticLease({
    required String macAddress,
    String? targetIp,
    String? hostname,
    String? duid,
    BuildContext? context,
  }) async {
    invalidateStaticLeasesCache();
    final res = await _networkActionsController!.deleteStaticLease(
      macAddress: macAddress,
      targetIp: targetIp,
      hostname: hostname,
      duid: duid,
      context: context,
    );
    invalidateStaticLeasesCache();
    // Refresh data in background — do NOT await so the loading toast can be
    // replaced immediately by the success/error toast in the caller.
    if (res) {
      unawaited(fetchDashboardData());
      unawaited(fetchClientsForSelectedRouter());
    }
    return res;
  }

  Future<bool> forceRefreshDhcpLeases({BuildContext? context}) async {
    final res = await _networkActionsController!.forceRefreshDhcpLeases(
      context: context,
    );
    await fetchClientsForSelectedRouter();
    await fetchDashboardData();

    if (dashboardData != null) {
      dashboardData!['forcePurged'] = true;
      dashboardData!['forcePurgedAt'] = DateTime.now().millisecondsSinceEpoch;
      if (clients.isNotEmpty) {
        dashboardData!['clients'] = clients
            .map(
              (c) => {
                'macAddress': c.macAddress,
                'ipAddress': c.ipAddress,
                'hostname': c.hostname,
                'isConnected': c.isConnected,
                'isOnline': c.isConnected,
                'isStaticLease': c.isStaticLease,
              },
            )
            .toList();
      }
    }

    notifyListenersDeferrable();
    return res;
  }

  Future<bool> refreshClientConnection({
    required String macAddress,
    BuildContext? context,
  }) => _networkActionsController!.refreshClientConnection(
    macAddress: macAddress,
    context: context,
  );

  Future<bool> updateRouterHostname(
    String newHostname, {
    BuildContext? context,
  }) => _networkActionsController!.updateRouterHostname(
    newHostname,
    context: context,
  );

  Future<int> flushUnusedDhcpLeases({
    List<Client>? clients,
    List<String>? macsToFlush,
    BuildContext? context,
  }) => _networkActionsController!.flushUnusedDhcpLeases(
    clients: clients,
    macsToFlush: macsToFlush,
    context: context,
  );

  Future<bool> banWirelessClient(
    String macAddress, {
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  }) => _networkActionsController!.banWirelessClient(
    macAddress,
    iface: iface,
    banTimeSeconds: banTimeSeconds,
    context: context,
  );

  Future<bool> unbanWirelessClient(
    String macAddress, {
    BuildContext? context,
  }) => _networkActionsController!.unbanWirelessClient(
    macAddress,
    context: context,
  );

  Future<Map<String, List<Map<String, dynamic>>>>
  fetchRestrictedAndBannedClientsLive({BuildContext? context}) async {
    if (reviewerModeEnabled) {
      return {
        'restricted': [
          {
            'mac': '11:22:33:44:55:66',
            'name': 'Restricted-Tablet',
            'ip': '192.168.1.150',
            'type': 'restricted',
          },
        ],
        'banned': [
          {
            'mac': '99:88:77:66:55:44',
            'name': 'Banned-Guest-Phone',
            'ip': 'N/A',
            'type': 'banned',
          },
        ],
      };
    }
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return {'restricted': [], 'banned': []};
    }
    final data = await _apiService!.fetchRestrictedAndBannedClientsLive(
      _authService!.ipAddress!,
      _authService!.sysauth!,
      _authService!.useHttps,
      context: context,
    );

    data['restricted'] ??= [];
    data['banned'] ??= [];

    // Ensure all locally tracked banned & paused MACs are included instantly
    final bannedSet = data['banned']!
        .map((e) => e['mac']?.toString().toUpperCase() ?? '')
        .where((m) => m.isNotEmpty)
        .toSet();

    for (final mac in bannedWirelessMacs) {
      if (!bannedSet.contains(mac)) {
        bannedSet.add(mac);
        data['banned']!.add({
          'mac': mac,
          'name': mac,
          'ip': 'N/A',
          'type': 'banned',
          'source': 'Wi-Fi Access Control (Banned)',
        });
      }
    }

    final restrictedSet = data['restricted']!
        .map((e) => e['mac']?.toString().toUpperCase() ?? '')
        .where((m) => m.isNotEmpty)
        .toSet();

    for (final mac in pausedInternetMacs) {
      if (!restrictedSet.contains(mac)) {
        restrictedSet.add(mac);
        data['restricted']!.add({
          'mac': mac,
          'name': mac,
          'ip': 'N/A',
          'type': 'restricted',
          'source': 'Internet Access Paused',
        });
      }
    }

    // Enrich names and IP addresses from clients list
    final clientMap = {
      for (final c in clients)
        c.macAddress.toUpperCase().replaceAll('-', ':'): c,
    };

    for (final listKey in ['restricted', 'banned']) {
      for (final item in data[listKey]!) {
        final mac =
            item['mac']?.toString().toUpperCase().replaceAll('-', ':') ?? '';
        final client = clientMap[mac];
        if (client != null) {
          if (item['name'] == null || item['name'] == mac) {
            item['name'] = client.displayName;
          }
          if (item['ip'] == null || item['ip'] == 'N/A') {
            item['ip'] = client.ipAddress;
          }
        }
      }
    }

    _networkActionsController?.updatePausedInternetMacs(restrictedSet);
    _networkActionsController?.updateBannedWirelessMacs(bannedSet);

    return data;
  }

  Future<bool> setSsidEnabled(
    String ifaceSection,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 300));
      await fetchDashboardData();
      return true;
    }
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }
    final res = await _apiService!.setSsidEnabled(
      _authService!.ipAddress!,
      _authService!.sysauth!,
      _authService!.useHttps,
      ifaceSection: ifaceSection,
      enabled: enabled,
      context: context,
    );
    if (res) {
      unawaited(fetchDashboardData());
    }
    return res;
  }

  static const String _wifiAccessControlPendingKey =
      'wifi_access_control_pending_revert';

  Future<void> _saveAccessControlPendingState(int startTimeMs) async {
    try {
      final payload = {
        'timestamp': startTimeMs,
        'priorMaclist': _networkActionsController?.priorMaclistSnapshot ?? {},
        'priorMacfilter':
            _networkActionsController?.priorMacfilterSnapshot ?? {},
      };
      await _secureStorageService.writeValue(
        _wifiAccessControlPendingKey,
        jsonEncode(payload),
      );
    } catch (e, stack) {
      Logger.exception('Failed to save access control pending state', e, stack);
    }
  }

  Future<void> _clearAccessControlPendingState() async {
    try {
      await _secureStorageService.deleteValue(_wifiAccessControlPendingKey);
    } catch (e, stack) {
      Logger.exception(
        'Failed to clear access control pending state',
        e,
        stack,
      );
    }
  }

  Future<void> _loadPendingAccessControlState() async {
    try {
      final jsonStr = await _secureStorageService.readValue(
        _wifiAccessControlPendingKey,
      );
      if (jsonStr == null || jsonStr.isEmpty) return;
      // Auto-revert timer removed per developer requirement.
      // Any previously unconfirmed access control state is cleared on app resume.
      await _clearAccessControlPendingState();
    } catch (e, stack) {
      Logger.exception('Failed to load pending access control state', e, stack);
    }
  }

  Future<bool> applyWifiAccessControl({
    required Map<String, List<String>> newMaclistByIface,
    required Map<String, String> newMacfilterByIface,
    required Map<String, List<String>> priorMaclistSnapshot,
    required Map<String, String> priorMacfilterSnapshot,
    BuildContext? context,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final success = await _networkActionsController!.applyWifiAccessControl(
      newMaclistByIface: newMaclistByIface,
      newMacfilterByIface: newMacfilterByIface,
      priorMaclistSnapshot: priorMaclistSnapshot,
      priorMacfilterSnapshot: priorMacfilterSnapshot,
      context: context,
    );

    if (success) {
      await _saveAccessControlPendingState(nowMs);
    } else {
      await _clearAccessControlPendingState();
    }
    return success;
  }

  Future<bool> confirmWifiAccessControlChanges() async {
    await _clearAccessControlPendingState();
    return await _networkActionsController!.confirmWifiAccessControlChanges();
  }

  Future<bool> revertWifiAccessControlChanges({BuildContext? context}) async {
    await _clearAccessControlPendingState();
    return await _networkActionsController!.revertWifiAccessControlChanges(
      context: (context != null && context.mounted) ? context : null,
    );
  }

  Future<bool> autoFixPermissions({BuildContext? context}) async {
    // Verify if permissions and packages are already verified and complete before modifying the router
    final freshCaps = await probeRouterCapabilities(forceRefresh: true);
    if (freshCaps.isRpcComplete) {
      Logger.info(
        'autoFixPermissions: Router permissions and RPC packages are already verified and complete. Skipping redundant fix script.',
      );
      notifyListeners();
      return true;
    }

    if (context != null && context.mounted) {
      final rpcSuccess = await _networkActionsController!.autoFixPermissions(
        context: context,
      );
      if (rpcSuccess) return true;
    } else {
      final rpcSuccess = await _networkActionsController!.autoFixPermissions();
      if (rpcSuccess) return true;
    }

    final ip = selectedRouter?.ipAddress;
    final username = selectedRouter?.username ?? 'root';
    String? password = selectedRouter?.password;
    if (password == null || password.isEmpty) {
      final creds = await _secureStorageService.getCredentials();
      password = creds['password'];
    }

    if (ip != null &&
        password != null &&
        password.isNotEmpty &&
        _sshService != null) {
      Logger.info(
        'HTTP RPC autoFixPermissions restricted. Falling back to SSH for $username@$ip...',
      );
      final fixScript = ApiService.getPermissionsFixScript();

      final res = await _sshService!.executeCommand(
        host: ip,
        username: username,
        password: password,
        command: fixScript,
      );

      if (res.success) {
        Logger.info('Automated SSH autoFixPermissions succeeded on $ip');
        await redetectCapabilities();
        await fetchDashboardData();
        notifyListeners();
        return true;
      }
    }

    return false;
  }

  Future<bool> installNativeTemperatureHandler({BuildContext? context}) async {
    final ip = selectedRouter?.ipAddress;
    final auth = sysauth;
    final useHttps = selectedRouter?.useHttps ?? false;
    if (ip == null) return false;

    // 1. Try native OpenWrt HTTP ubus RPC first (if firmware permissions allow it)
    if (auth != null) {
      try {
        final rpcSuccess = await _apiService!.installNativeTemperatureHandler(
          ip,
          auth,
          useHttps,
          context: context,
        );
        if (rpcSuccess) {
          await fetchDashboardData();
          return true;
        }
      } catch (e) {
        Logger.warning('HTTP RPC install attempt failed: $e');
      }
    }

    // 2. Fall back to SSH installation using router credentials
    final router = selectedRouter;
    final username = router?.username ?? 'root';
    String? password = router?.password;
    if (password == null || password.isEmpty) {
      final creds = await _secureStorageService.getCredentials();
      password = creds['password'];
    }

    if (password != null && password.isNotEmpty && _sshService != null) {
      Logger.info(
        'HTTP RPC installation was restricted. Falling back to SSH installation for $username@$ip...',
      );
      const installScript =
          'mkdir -p /usr/libexec/rpcd /usr/share/rpcd/acl.d && '
          'cat << \'EOF\' > /usr/libexec/rpcd/luci.temp-status\n'
          '#!/bin/sh\n'
          'case "\$1" in\n'
          'list) echo \'{"getSensors":{}}\' ;;\n'
          'call) case "\$2" in getSensors)\n'
          'hw=""; for h in /sys/class/hwmon/hwmon*; do [ -d "\$h" ] || continue; n=\$(cat "\$h/name" 2>/dev/null || echo hwmon); s=""; for t in "\$h"/temp*_input; do [ -f "\$t" ] || continue; v=\$(cat "\$t" 2>/dev/null); [ -n "\$v" ] || continue; l=\$(cat "\${t%_input}_label" 2>/dev/null); i="\${t##*/}"; [ -n "\$s" ] && s="\$s," || true; s="\$s{\\"item\\":\\"\$i\\",\\"label\\":\\"\$l\\",\\"temp\\":\$v}"; done; [ -n "\$s" ] && { [ -n "\$hw" ] && hw="\$hw," || true; hw="\$hw{\\"title\\":\\"\$n\\",\\"item\\":\\"\${h##*/}\\",\\"sources\\":[\$s]}"; }; done\n'
          'tz=""; for z in /sys/class/thermal/thermal_zone*; do [ -d "\$z" ] || continue; v=\$(cat "\$z/temp" 2>/dev/null); [ -n "\$v" ] || continue; y=\$(cat "\$z/type" 2>/dev/null || echo tz); [ -n "\$tz" ] && tz="\$tz," || true; tz="\$tz{\\"title\\":\\"\$y\\",\\"item\\":\\"\${z##*/}\\",\\"sources\\":[{\\"item\\":\\"temp\\",\\"label\\":\\"\$y\\",\\"temp\\":\$v}]}"; done\n'
          'printf \'{"sensors":{"0":[%s],"1":[%s]}}\\n\' "\$hw" "\$tz" ;; esac ;; esac\n'
          'EOF\n'
          'chmod +x /usr/libexec/rpcd/luci.temp-status && '
          'cat << \'EOF\' > /usr/share/rpcd/acl.d/luci-app-temp-status.json\n'
          '{"luci-app-temp-status":{"description":"Native Temperature RPC Handler","read":{"ubus":{"luci.temp-status":["getSensors"]}}}}\n'
          'EOF\n'
          '(/etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null || true)';

      final res = await _sshService!.executeCommand(
        host: ip,
        username: username,
        password: password,
        command: installScript,
      );

      if (res.success) {
        Logger.info('Automated SSH temperature installation succeeded on $ip');
        await fetchDashboardData();
        return true;
      } else {
        Logger.warning(
          'Automated SSH temperature installation failed: ${res.errorMessage ?? res.stderr}',
        );
      }
    }

    return false;
  }

  Future<bool> manageServiceAction(
    String serviceName,
    String action, {
    BuildContext? context,
  }) => _networkActionsController!.manageServiceAction(
    serviceName,
    action,
    context: context,
  );

  Future<bool> saveCronJobs(
    List<String> cronLines, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        dashboardData!['cronJobs'] = List<String>.from(cronLines);
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.saveCronJobs(
      ip,
      sysauth!,
      useHttps,
      cronLines: cronLines,
      context: context,
    );

    if (success) {
      if (dashboardData != null) {
        dashboardData!['cronJobs'] = List<String>.from(cronLines);
      }
      notifyListeners();
    }

    return success;
  }

  Future<bool> saveDdnsInstance(
    DdnsInstance instance, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        final overview = DdnsOverview.fromDashboardData(
          dashboardData,
          isReviewerMode: true,
        );
        final list = List<DdnsInstance>.from(overview.instances);
        final existingIdx = list.indexWhere((i) => i.name == instance.name);
        if (existingIdx >= 0) {
          list[existingIdx] = instance;
        } else {
          list.add(instance);
        }
        dashboardData!['ddns'] = {
          'global': {'is_enabled': '1'},
          for (final item in list)
            item.name: item.toUciParams()..['.type'] = 'service',
        };
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.saveDdnsInstance(
      ip,
      sysauth!,
      useHttps,
      instance: instance,
      context: context,
    );

    if (success) {
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<bool> deleteDdnsInstance(
    String instanceName, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null && dashboardData!['ddns'] is Map) {
        (dashboardData!['ddns'] as Map).remove(instanceName);
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.deleteDdnsInstance(
      ip,
      sysauth!,
      useHttps,
      instanceName: instanceName,
      context: context,
    );

    if (success) {
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<DdnsValidationResult> testDdnsConfiguration(
    DdnsInstance instance, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      return _apiService!.testDdnsConfiguration(
        '',
        '',
        false,
        instance: instance,
        context: context,
      );
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) {
      return const DdnsValidationResult(
        isValid: false,
        errorMessage: 'No active router session',
      );
    }
    final useHttps = selectedRouter?.useHttps ?? false;

    return _apiService!.testDdnsConfiguration(
      ip,
      sysauth!,
      useHttps,
      instance: instance,
      context: context,
    );
  }

  Future<bool> toggleGlobalDdns(bool enable, {BuildContext? context}) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        dashboardData!['ddns'] ??= {};
        dashboardData!['ddns']['global'] = {'is_enabled': enable ? '1' : '0'};
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.toggleGlobalDdns(
      ip,
      sysauth!,
      useHttps,
      enable: enable,
      context: context,
    );

    if (success) {
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<bool> saveSqmQueue(SqmQueue queue, {BuildContext? context}) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        dashboardData!['sqm'] ??= {};
        dashboardData!['sqm'][queue.name] = queue.toUciParams();
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.saveSqmQueue(
      ip,
      sysauth!,
      useHttps,
      queue: queue,
      context: context,
    );

    if (success) {
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<bool> deleteSqmQueue(
    String sectionName, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null && dashboardData!['sqm'] is Map) {
        (dashboardData!['sqm'] as Map).remove(sectionName);
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.deleteSqmQueue(
      ip,
      sysauth!,
      useHttps,
      sectionName: sectionName,
      context: context,
    );

    if (success) {
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<bool> toggleSqmService(bool enable, {BuildContext? context}) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        dashboardData!['initScripts'] ??= {};
        dashboardData!['initScripts']['sqm'] = {
          'enabled': enable,
          'running': enable,
        };
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.toggleSqmService(
      ip,
      sysauth!,
      useHttps,
      enable: enable,
      context: context,
    );

    if (success) {
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<FlushDnsResult> flushDns({BuildContext? context}) async {
    if (reviewerModeEnabled) {
      return FlushDnsResult.success(
        flushedResolvers: const ['dnsmasq'],
        message: 'DNS cache flushed successfully (simulated).',
      );
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null || _apiService == null) {
      return FlushDnsResult.failure('No active router session');
    }
    final useHttps = selectedRouter?.useHttps ?? false;

    return _apiService!.flushDns(ip, sysauth!, useHttps, context: context);
  }

  Future<bool> updateFirewallCustomRuleStatus(
    String sectionKey,
    bool enabled, {
    BuildContext? context,
  }) => _networkActionsController!.updateFirewallCustomRuleStatus(
    sectionKey,
    enabled,
    context: context,
  );

  Future<bool> updateFirewallFlowOffloading({
    required bool software,
    required bool hardware,
    String sectionKey = '@defaults[0]',
    BuildContext? context,
  }) => _networkActionsController!.updateFirewallFlowOffloading(
    software: software,
    hardware: hardware,
    sectionKey: sectionKey,
    context: context,
  );

  Future<bool> updateWiredInterfaceStatus(
    String interfaceName,
    bool enabled, {
    BuildContext? context,
  }) => _networkActionsController!.updateWiredInterfaceStatus(
    interfaceName,
    enabled,
    context: context,
  );

  Future<bool> updateWirelessInterfaceStatus(
    String sectionKey,
    bool enabled, {
    BuildContext? context,
  }) => _networkActionsController!.updateWirelessInterfaceStatus(
    sectionKey,
    enabled,
    context: context,
  );

  Future<bool> restartWiredInterface(
    String interfaceName, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      final ip = _authService!.ipAddress!;
      final sysauth = _authService!.sysauth!;
      final useHttps = _authService!.useHttps;
      final ctx = (context != null && context.mounted) ? context : null;

      bool success = false;

      // 1. Direct binary exec via rpcd: /sbin/ifdown and /sbin/ifup
      try {
        final downRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/sbin/ifdown',
            'params': [interfaceName],
          },
          context: (ctx != null && ctx.mounted) ? ctx : null,
        );
        await Future.delayed(const Duration(milliseconds: 400));
        final upRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/sbin/ifup',
            'params': [interfaceName],
          },
          context: (ctx != null && ctx.mounted) ? ctx : null,
        );
        if (_apiService!.execSucceeded(upRes) ||
            _apiService!.execSucceeded(downRes)) {
          success = true;
        }
      } catch (_) {}

      // 2. ubus network.interface down & up
      if (!success) {
        try {
          final downRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'network.interface.$interfaceName',
            method: 'down',
            params: {},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          await Future.delayed(const Duration(milliseconds: 400));
          final upRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'network.interface.$interfaceName',
            method: 'up',
            params: {},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          if ((downRes is List && downRes.isNotEmpty && downRes[0] == 0) ||
              (upRes is List && upRes.isNotEmpty && upRes[0] == 0)) {
            success = true;
          }
        } catch (_) {}
      }

      // 3. Shell fallback
      if (!success) {
        final execRes = await _apiService!.systemExec(
          ip,
          sysauth,
          useHttps,
          command:
              'ifdown $interfaceName 2>/dev/null; sleep 1; ifup $interfaceName 2>/dev/null',
          context: (ctx != null && ctx.mounted) ? ctx : null,
        );
        if (_apiService!.execSucceeded(execRes)) {
          success = true;
        }
      }

      return success;
    } catch (e, stack) {
      Logger.exception(
        'restartWiredInterface failed for $interfaceName',
        e,
        stack,
      );
      return false;
    }
  }

  Future<bool> restartWirelessInterface(
    String sectionKey, {
    String? radioName,
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      final ip = _authService!.ipAddress!;
      final sysauth = _authService!.sysauth!;
      final useHttps = _authService!.useHttps;
      final ctx = (context != null && context.mounted) ? context : null;

      bool success = false;

      // 1. Direct binary exec via rpcd: /sbin/wifi reload [radioName]
      final wifiReloadArgs = (radioName != null && radioName.isNotEmpty)
          ? ['reload', radioName]
          : ['reload'];
      try {
        final reloadRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {'command': '/sbin/wifi', 'params': wifiReloadArgs},
          context: ctx,
        );
        if (_apiService!.execSucceeded(reloadRes)) {
          success = true;
        }
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('socket') ||
            errStr.contains('connection reset') ||
            errStr.contains('broken pipe') ||
            errStr.contains('connection closed') ||
            errStr.contains('clientexception')) {
          success = true;
        }
      }

      // 2. Direct binary exec via rpcd: /sbin/wifi down [radioName] && /sbin/wifi up [radioName]
      if (!success) {
        final wifiDownArgs = (radioName != null && radioName.isNotEmpty)
            ? ['down', radioName]
            : ['down'];
        final wifiUpArgs = (radioName != null && radioName.isNotEmpty)
            ? ['up', radioName]
            : ['up'];
        try {
          await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'file',
            method: 'exec',
            params: {'command': '/sbin/wifi', 'params': wifiDownArgs},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          await Future.delayed(const Duration(milliseconds: 500));
          final upRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'file',
            method: 'exec',
            params: {'command': '/sbin/wifi', 'params': wifiUpArgs},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          if (_apiService!.execSucceeded(upRes)) {
            success = true;
          }
        } catch (_) {}
      }

      // 3. ubus network.wireless down/up if radioName is available
      if (!success && radioName != null && radioName.isNotEmpty) {
        try {
          final downRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'network.wireless',
            method: 'down',
            params: {'device': radioName},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          await Future.delayed(const Duration(milliseconds: 400));
          final upRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'network.wireless',
            method: 'up',
            params: {'device': radioName},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          if ((downRes is List && downRes.isNotEmpty && downRes[0] == 0) ||
              (upRes is List && upRes.isNotEmpty && upRes[0] == 0)) {
            success = true;
          }
        } catch (_) {}
      }

      // 4. Shell fallback via systemExec
      if (!success) {
        final rName = (radioName != null && radioName.isNotEmpty)
            ? radioName
            : '';
        final cmd = rName.isNotEmpty
            ? 'wifi reload $rName 2>/dev/null || (wifi down $rName 2>/dev/null; sleep 1; wifi up $rName 2>/dev/null) || wifi reload'
            : 'wifi reload 2>/dev/null || (wifi down 2>/dev/null; sleep 1; wifi up 2>/dev/null)';

        final execRes = await _apiService!.systemExec(
          ip,
          sysauth,
          useHttps,
          command: cmd,
          context: (ctx != null && ctx.mounted) ? ctx : null,
        );
        if (_apiService!.execSucceeded(execRes)) {
          success = true;
        }
      }

      return success;
    } catch (e, stack) {
      Logger.exception(
        'restartWirelessInterface failed for $sectionKey',
        e,
        stack,
      );
      return false;
    }
  }

  Future<bool> setWirelessRadioState(
    String device,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      // Simulate operation for reviewer mode
      await Future.delayed(const Duration(milliseconds: 500));
      await fetchDashboardData();
      return true;
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      // 1. Set the disabled state
      await _apiService!.uciSet(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        section: device,
        values: {'disabled': enabled ? '0' : '1'},
        context: context,
      );

      // 2. Commit the changes
      await _apiService!.uciCommit(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        context: context?.mounted == true ? context : null,
      );

      // 3. Reload wifi to apply changes
      await _apiService!.systemExec(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        command: 'wifi reload',
        context: context?.mounted == true ? context : null,
      );

      // Refresh dashboard data to reflect the change
      await fetchDashboardData();

      return true;
    } catch (e) {
      _errorMessage = 'Failed to toggle Wi-Fi: $e';
      notifyListeners();
      return false;
    }
  }

  /// Fetches live configuration for a specific wireless section from router UCI
  Future<Map<String, dynamic>?> fetchWirelessSectionConfig(
    String sectionName,
  ) async {
    if (reviewerModeEnabled ||
        _apiService == null ||
        _authService?.sysauth == null ||
        _authService?.ipAddress == null) {
      return null;
    }
    try {
      final rawRpc = await _apiService!.call(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'wireless', 'section': sectionName},
      );
      if (rawRpc is List && rawRpc.length > 1 && rawRpc[0] == 0) {
        final values = rawRpc[1];
        if (values is Map<String, dynamic>) {
          final valuesMap = values['values'] ?? values;
          if (valuesMap is Map) {
            return Map<String, dynamic>.from(valuesMap);
          }
        }
      }
    } catch (e) {
      Logger.debug(
        'fetchWirelessSectionConfig failed for section $sectionName: $e',
      );
    }
    return null;
  }

  /// Auto-migrates anonymous `cfg######` wifi-iface sections to named `wifinet#` identifiers.
  /// Returns the number of sections that were renamed (0 means nothing needed fixing).
  /// This prevents the "Wireless configuration migration" dialog in the LuCI web UI.
  Future<int> migrateAnonymousWirelessSections() async {
    if (reviewerModeEnabled ||
        _apiService == null ||
        _authService?.sysauth == null ||
        _authService?.ipAddress == null) {
      return 0;
    }
    return _apiService!.migrateAnonymousWirelessSections(
      _authService!.ipAddress!,
      _authService!.sysauth!,
      _authService!.useHttps,
    );
  }

  /// Fetches hardware-supported encryptions and ciphers directly from iwinfo/ubus for a specific wireless section
  Future<Map<String, List<Map<String, String>>>>
  fetchWirelessHardwareCapabilities({
    required String sectionName,
    String? radioName,
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled ||
        _apiService == null ||
        _authService?.sysauth == null ||
        _authService?.ipAddress == null) {
      return _fallbackHardwareCapabilities();
    }

    return _apiService!.fetchWirelessHardwareCapabilities(
      sectionName: sectionName,
      radioName: radioName,
      ipAddress: _authService!.ipAddress!,
      sysauth: _authService!.sysauth!,
      useHttps: _authService!.useHttps,
      context: context,
    );
  }

  Future<Map<String, dynamic>> fetchWirelessRadioCapabilities({
    required String radioName,
    BuildContext? context,
  }) async {
    if (_apiService == null ||
        _authService?.sysauth == null ||
        _authService?.ipAddress == null) {
      return {};
    }

    return _apiService!.fetchWirelessRadioCapabilities(
      radioName: radioName,
      ipAddress: _authService!.ipAddress!,
      sysauth: _authService!.sysauth!,
      useHttps: _authService!.useHttps,
      context: context,
    );
  }

  Map<String, List<Map<String, String>>> _fallbackHardwareCapabilities() {
    return {'encryptions': fallbackEncryptions, 'ciphers': fallbackCiphers};
  }

  List<Map<String, String>> get fallbackEncryptions => [
    {'value': 'sae', 'label': 'WPA3-SAE (Personal / Strict)'},
    {'value': 'sae-mixed', 'label': 'WPA2/WPA3 Mixed (Transitional)'},
    {'value': 'psk2', 'label': 'WPA2-PSK (CCMP / AES)'},
    {'value': 'psk', 'label': 'WPA-PSK (Legacy / WPA1)'},
    {'value': 'owe', 'label': 'Enhanced Open (OWE)'},
    {'value': 'none', 'label': 'Open / No Encryption'},
  ];

  List<Map<String, String>> get fallbackCiphers => [
    {'value': 'auto', 'label': 'Auto (Hardware Default)'},
    {'value': 'ccmp', 'label': 'CCMP (AES)'},
    {'value': 'gcmp256', 'label': 'GCMP-256 (High Security)'},
    {'value': 'gcmp128', 'label': 'GCMP-128'},
    {'value': 'tkip', 'label': 'TKIP (Legacy)'},
  ];

  Future<bool> tryAutoLogin({
    bool force = false,
    bool fetchDashboard = true,
    BuildContext? context,
  }) => _sessionController!.tryAutoLogin(
    force: force,
    fetchDashboard: fetchDashboard,
    context: context,
  );

  /// Handles app resumption when screen turns on or app returns from background
  Future<void> handleAppResume() async {
    await _sessionController?.handleAppResume();
    if (!reviewerModeEnabled && selectedRouter != null) {
      unawaited(fetchPublicIps());
    }
  }

  /// Fetch all associated wireless MAC addresses from all wireless interfaces
  Future<Set<String>> fetchAllAssociatedWirelessMacs() async {
    if (reviewerModeEnabled) {
      // Use the interface method for mock/reviewer mode
      final stationsMap = await _apiService!.fetchAssociatedStations();
      final macs = <String>{};
      stationsMap.forEach((_, stations) {
        macs.addAll(stations.map((m) => m.toLowerCase()));
      });
      return macs;
    } else {
      // Use the context-aware method for real API calls
      if (_routerService?.selectedRouter == null ||
          _authService?.sysauth == null) {
        return {};
      }

      final ip = _routerService!.selectedRouter!.ipAddress;
      final useHttps = _routerService!.selectedRouter!.useHttps;

      final stationsMap = await _apiService!
          .fetchAllAssociatedWirelessMacsWithContext(
            ipAddress: ip,
            sysauth: _authService!.sysauth!,
            useHttps: useHttps,
          );
      final macs = <String>{};
      stationsMap.forEach((_, stations) {
        macs.addAll(stations.map((m) => m.toLowerCase()));
      });

      // Also include configured wireless maclist entries from dashboard data
      final wirelessConfig =
          dashboardData?['uciWirelessConfig'] ?? dashboardData?['wireless'];
      if (wirelessConfig is Map<String, dynamic>) {
        wirelessConfig.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            final maclist = v['maclist'] ?? v['config']?['maclist'];
            if (maclist is List) {
              for (final item in maclist) {
                if (item != null && item.toString().isNotEmpty) {
                  macs.add(item.toString().toLowerCase());
                }
              }
            }
          }
        });
      }

      return macs;
    }
  }

  @override
  void dispose() {
    if (identical(this, _instance)) {
      return;
    }
    _throughputController?.dispose();
    _networkActionsController?.dispose();
    _accessControlTimerLifecycleManager?.dispose();
    _throughputTimer?.cancel();
    _pollingTimer?.cancel();
    _pollAttempts = 0;
    _isRebooting = false;
    super.dispose();
  }

  /// Aggregates DHCP leases across all configured routers and classifies clients
  /// as wireless if their MAC appears in any router's associated stations list.
  Future<List<Client>> fetchAggregatedClients({
    void Function(List<Client> clients)? onIncrementalUpdate,
  }) => _clientController!.fetchAggregatedClients(
    onIncrementalUpdate: onIncrementalUpdate,
  );

  bool get isClientsLoading => _clientController?.isFetchingClients ?? false;
  bool get hasFetchedClients => _clientController?.hasFetchedClients ?? false;

  /// Whether a Dumb AP is detected or present in the current setup
  bool get hasDumbAp =>
      (_clientController?.hasDumbAp ?? false) ||
      clients.any((c) => c.isDumbApClient) ||
      routers.length > 1;

  /// Clients associated with / connected via a Dumb AP
  List<Client> get dumbApClients =>
      clients.where((c) => c.isDumbApClient).toList();

  int get dumbApClientsCount => dumbApClients.length;

  /// Returns clients for the currently selected router only
  Future<List<Client>> fetchClientsForSelectedRouter() =>
      _clientController!.fetchClientsForSelectedRouter();

  @visibleForTesting
  set clientControllerForTesting(ClientController? controller) {
    _clientController = controller;
  }

  @visibleForTesting
  ClientController? get clientControllerForTesting => _clientController;

  set clients(List<Client> clientList) {
    _clientController?.lastFetchedClients = clientList;
  }

  List<Client> get clients {
    if (_clientController?.lastFetchedClients != null &&
        _clientController!.lastFetchedClients!.isNotEmpty) {
      return _clientController!.lastFetchedClients!;
    }

    final clientList = <Client>[];
    final data = dashboardData;
    final rawHostHints = data?['hostHints'];
    final hostHints = rawHostHints is Map
        ? Map<String, dynamic>.from(rawHostHints)
        : const <String, dynamic>{};

    // Extract raw leases supporting dhcpLeases (camelCase), dhcp_leases (snake_case), and leases
    dynamic rawLeases =
        data?['dhcpLeases'] ?? data?['dhcp_leases'] ?? data?['leases'];
    if (rawLeases is Map && rawLeases['dhcp_leases'] is List) {
      rawLeases = rawLeases['dhcp_leases'];
    }

    // Extract wireless MACs from wirelessStations map or knownWirelessMacs
    final rawStations = data?['wirelessStations'];
    final wirelessStations = rawStations is Map
        ? Map<String, dynamic>.from(rawStations)
        : const <String, dynamic>{};
    final wirelessMacs = <String>{
      ...(_clientController?.knownWirelessMacs ?? {}),
    };
    wirelessStations.forEach((iface, list) {
      if (list is List) {
        for (final item in list) {
          if (item is Map && item['mac'] != null) {
            wirelessMacs.add(
              item['mac'].toString().toUpperCase().replaceAll('-', ':'),
            );
          } else if (item is String) {
            wirelessMacs.add(item.toUpperCase().replaceAll('-', ':'));
          }
        }
      }
    });

    if (rawLeases is List) {
      for (final l in rawLeases) {
        if (l is Map) {
          final c = Client.fromLease(l.cast<String, dynamic>());
          final normMac = c.macAddress.toUpperCase().replaceAll('-', ':');
          final isWireless = wirelessMacs.contains(normMac);
          final hint = hostHints[normMac];
          final staticName = hint?['staticLeaseName']?.toString();
          final isStatic = hint?['isStaticLease'] == true;

          clientList.add(
            c.copyWith(
              connectionType: isWireless
                  ? ConnectionType.wireless
                  : (c.connectionType == ConnectionType.unknown
                        ? ConnectionType.wired
                        : c.connectionType),
              isConnected: true,
              staticLeaseName: staticName,
              isStaticLease: isStatic,
            ),
          );
        }
      }
    }

    hostHints.forEach((mac, info) {
      final normMac = mac.toUpperCase().replaceAll('-', ':');
      if (!clientList.any(
        (c) => c.macAddress.toUpperCase().replaceAll('-', ':') == normMac,
      )) {
        final hintName =
            info['name']?.toString() ??
            info['staticLeaseName']?.toString() ??
            normMac;
        final ipaddrs = info['ipaddrs'] as List?;
        final ip = (ipaddrs != null && ipaddrs.isNotEmpty)
            ? ipaddrs.first.toString()
            : (info['staticLeaseIp']?.toString() ?? 'N/A');
        final isStatic = info['isStaticLease'] == true;
        final isWireless = wirelessMacs.contains(normMac);
        clientList.add(
          Client(
            ipAddress: ip,
            macAddress: normMac,
            hostname: hintName,
            isConnected: isWireless,
            connectionType: isWireless
                ? ConnectionType.wireless
                : ConnectionType.unknown,
            isStaticLease: isStatic,
            staticLeaseName: info['staticLeaseName']?.toString(),
          ),
        );
      }
    });

    return clientList;
  }

  /// Finds a matching Client model by MAC address (case-insensitive & colon-normalized).
  Client? findClientByMac(String macAddress) {
    if (macAddress.trim().isEmpty) return null;
    final norm = macAddress
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');
    for (final c in clients) {
      final cNorm = c.macAddress
          .toUpperCase()
          .replaceAll('-', ':')
          .split(':')
          .map((b) => b.length == 1 ? '0$b' : b)
          .join(':');
      if (cNorm == norm) return c;
    }
    return null;
  }

  Map<String, dynamic>? _lastDashboardDataForStaticLeases;
  Map<String, DhcpStaticMapping>? _cachedStaticMappingsByMac;
  Set<String>? _cachedStaticLeaseMacs;

  void _ensureStaticLeasesCache() {
    final currentData = dashboardData;
    if (_cachedStaticMappingsByMac != null &&
        identical(_lastDashboardDataForStaticLeases, currentData)) {
      return;
    }
    _lastDashboardDataForStaticLeases = currentData;
    final mappingMap = <String, DhcpStaticMapping>{};
    final macSet = <String>{};

    if (currentData != null) {
      final dhcpOverview = DhcpDnsOverview.fromDashboardData(
        currentData,
        isReviewerMode: reviewerModeEnabled,
      );
      for (final mapping in dhcpOverview.staticMappings) {
        final macs = mapping.macAddress
            .toUpperCase()
            .replaceAll('-', ':')
            .split(',')
            .map((m) => m.trim())
            .map(
              (b) => b
                  .split(':')
                  .map((part) => part.length == 1 ? '0$part' : part)
                  .join(':'),
            );
        for (final m in macs) {
          if (m.isNotEmpty) {
            mappingMap[m] = mapping;
            macSet.add(m);
          }
        }
      }
    }
    _cachedStaticMappingsByMac = mappingMap;
    _cachedStaticLeaseMacs = macSet;
  }

  /// Invalidates cached static lease mappings to force recomputation on next access.
  void invalidateStaticLeasesCache() {
    _cachedStaticMappingsByMac = null;
    _cachedStaticLeaseMacs = null;
    _lastDashboardDataForStaticLeases = null;
    notifyListenersDeferrable();
  }

  /// Configured static lease MAC addresses for fast O(1) membership checks.
  Set<String> get configuredStaticLeaseMacs {
    _ensureStaticLeasesCache();
    return _cachedStaticLeaseMacs ?? const {};
  }

  /// Finds a static DHCP lease mapping for the given MAC address, if configured on the router.
  DhcpStaticMapping? findStaticLeaseByMac(String macAddress) {
    if (macAddress.trim().isEmpty) return null;
    final normMac = macAddress
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');

    _ensureStaticLeasesCache();
    return _cachedStaticMappingsByMac?[normMac];
  }

  /// Returns a union set of associated wireless MAC addresses across all routers
  Future<Set<String>> fetchAllAssociatedWirelessMacsAggregated() =>
      _clientController!.fetchAllAssociatedWirelessMacsAggregated();

  /// Returns a combined list of DHCP lease maps from all routers
  Future<List<Map<String, dynamic>>> fetchAggregatedDhcpLeases() =>
      _clientController!.fetchAggregatedDhcpLeases();

  // --- VPN & Secure Tunnels Management Actions ---

  /// Toggle an OpenVPN instance enabled state and manage service action
  Future<bool> toggleOpenVpnInstance(String name, bool enable) =>
      _networkActionsController!.toggleOpenVpnInstance(name, enable);

  /// Toggle Tailscale mesh daemon enabled state
  Future<bool> toggleTailscale(bool enable) =>
      _networkActionsController!.toggleTailscale(enable);

  /// Toggle NextDNS encrypted DNS daemon state
  Future<bool> toggleNextDns(bool enable) =>
      _networkActionsController!.toggleNextDns(enable);

  /// Toggle Cloudflared tunnel daemon enabled state
  Future<bool> toggleCloudflared(bool enable) =>
      _networkActionsController!.toggleCloudflared(enable);

  /// Bring WireGuard interface up or down
  Future<bool> toggleWireguardInterface(String ifaceName, bool bringUp) =>
      _networkActionsController!.toggleWireguardInterface(ifaceName, bringUp);

  /// Restart a VPN service daemon by service name
  Future<bool> restartVpnService(String serviceName) =>
      _networkActionsController!.restartVpnService(serviceName);

  String? get pendingSectionName =>
      _networkActionsController?.pendingSectionName;
  String? get pendingTargetType => _networkActionsController?.pendingTargetType;
  dynamic get pendingTargetRadio =>
      _networkActionsController?.pendingTargetRadio;
  dynamic get pendingTargetInterface =>
      _networkActionsController?.pendingTargetInterface;

  /// Apply wireless interface configuration updates with staged rollback protection
  Future<bool> applyWirelessInterfaceConfig({
    required String sectionName,
    required Map<String, String> newValues,
    required Map<String, String> priorValuesSnapshot,
    dynamic targetRadio,
    dynamic targetInterface,
    BuildContext? context,
  }) => _networkActionsController!.applyWirelessInterfaceConfig(
    sectionName: sectionName,
    newValues: newValues,
    priorValuesSnapshot: priorValuesSnapshot,
    targetRadio: targetRadio,
    targetInterface: targetInterface,
    context: context,
  );

  /// Apply physical wireless radio configuration updates with staged rollback protection
  Future<bool> applyWirelessRadioConfig({
    required String sectionName,
    required Map<String, String> newValues,
    required Map<String, String> priorValuesSnapshot,
    dynamic targetRadio,
    BuildContext? context,
  }) => _networkActionsController!.applyWirelessRadioConfig(
    sectionName: sectionName,
    newValues: newValues,
    priorValuesSnapshot: priorValuesSnapshot,
    targetRadio: targetRadio,
    context: context,
  );

  /// Provision a new virtual SSID interface under a physical wireless radio
  Future<bool> addWirelessInterface({
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    required String network,
    BuildContext? context,
  }) => _networkActionsController!.addWirelessInterface(
    radioName: radioName,
    ssid: ssid,
    encryption: encryption,
    key: key,
    network: network,
    context: context,
  );

  /// Delete a virtual SSID interface section from wireless configuration
  Future<bool> deleteWirelessInterface({
    required String sectionName,
    BuildContext? context,
  }) => _networkActionsController!.deleteWirelessInterface(
    sectionName: sectionName,
    context: context,
  );

  /// Provision isolated Guest Network spanning network, dhcp, firewall, and wireless configs
  Future<bool> provisionGuestNetwork({
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    String guestIp = '192.168.2.1',
    bool isolateClients = true,
    String network = 'guest',
    // Advanced radio settings
    String? country,
    String? channel,
    String? htMode,
    String? txPower,
    // Fast roaming (802.11r/k/v)
    bool ieee80211r = false,
    bool ftOverDs = false,
    bool ftPskGenerateLocal = false,
    String? mobilityDomain,
    // Wireless advanced settings
    bool wmm = true,
    bool hidden = false,
    int? dtimPeriod,
    int? gtkRekey,
    int? inactivityLimit,
    int? maxListenInterval,
    bool disassocLowAck = true,
    bool multicastToUnicast = false,
    bool wds = false,
    // MAC filtering
    String? macfilter,
    List<String>? maclist,
    BuildContext? context,
  }) => _networkActionsController!.provisionGuestNetwork(
    radioName: radioName,
    ssid: ssid,
    encryption: encryption,
    key: key,
    guestIp: guestIp,
    isolateClients: isolateClients,
    network: network,
    country: country,
    channel: channel,
    htMode: htMode,
    txPower: txPower,
    ieee80211r: ieee80211r,
    ftOverDs: ftOverDs,
    ftPskGenerateLocal: ftPskGenerateLocal,
    mobilityDomain: mobilityDomain,
    wmm: wmm,
    hidden: hidden,
    dtimPeriod: dtimPeriod,
    gtkRekey: gtkRekey,
    inactivityLimit: inactivityLimit,
    maxListenInterval: maxListenInterval,
    disassocLowAck: disassocLowAck,
    multicastToUnicast: multicastToUnicast,
    wds: wds,
    macfilter: macfilter,
    maclist: maclist,
    context: context,
  );

  Future<List<String>> fetchNetworkInterfaces({BuildContext? context}) =>
      _networkActionsController!.fetchNetworkInterfaces(context: context);

  /// Active session username (e.g. 'root')
  String get sessionUsername =>
      _routerService?.selectedRouter?.username ?? 'root';

  /// Returns true if logged in user has administrative privileges
  bool get isAdministrativeUser {
    final caps = capabilities;
    if (caps != null) {
      return caps.hasUciWriteAccess;
    }
    final user = sessionUsername.trim().toLowerCase();
    return user == 'root' || user == 'admin' || user.isNotEmpty;
  }
}

/// Normalizes a MAC address string to uppercase colon-separated format
/// with zero-padded octets (e.g. '0a:1B:2c:3d:4E:5f' → '0A:1B:2C:3D:4E:5F').
String normalizeMac(String mac) => mac
    .trim()
    .toUpperCase()
    .replaceAll('-', ':')
    .split(':')
    .map((b) => b.length == 1 ? '0$b' : b)
    .join(':');

/// Minimum interval between active NUD ping sweeps to prevent router CPU load.
const Duration kNeighborProbeInterval = Duration(seconds: 30);

/// Maximum number of target IP addresses probed per NUD ping sweep batch.
const int kNeighborProbeMaxBatch = 10;

/// Pure function to extract non-wireless wired client IPs from DHCP leases that are currently
/// absent from `ip neigh show` or marked INCOMPLETE/FAILED, capped at `maxBatch`.
List<String> selectNeighborProbeTargets(
  List<Map<String, dynamic>> dhcp4Leases,
  Set<String> normalizedWireless,
  List<Map<String, dynamic>> neighClients, {
  String routerIp = '',
  int maxBatch = kNeighborProbeMaxBatch,
}) {
  String normMac(String mac) => normalizeMac(mac);

  final normWireless = normalizedWireless.map(normMac).toSet();

  final candidateIps = <String>{};
  for (final l in dhcp4Leases) {
    final macRaw = l['macaddr']?.toString() ?? l['mac']?.toString() ?? '';
    final ipRaw = l['ipaddr']?.toString() ?? l['ip']?.toString() ?? '';
    final macN = normMac(macRaw);
    if (macN.isNotEmpty &&
        !normWireless.contains(macN) &&
        ipRaw.isNotEmpty &&
        ipRaw != 'N/A' &&
        ipRaw != routerIp) {
      candidateIps.add(ipRaw);
    }
  }

  final missingWiredIps = candidateIps.where((ip) {
    final Map<String, dynamic>? entry = neighClients
        .cast<Map<String, dynamic>?>()
        .firstWhere((n) => n?['ipaddr'] == ip, orElse: () => null);
    if (entry == null) return true;
    final nud = (entry['nud_state']?.toString() ?? '').toUpperCase();
    return nud == 'INCOMPLETE' || nud == 'FAILED';
  }).toList();

  return missingWiredIps.take(maxBatch).toList();
}
