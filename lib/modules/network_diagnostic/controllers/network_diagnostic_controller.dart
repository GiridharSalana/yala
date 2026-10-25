// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../services/interfaces/api_service_interface.dart';
import '../../../state/app_state.dart';
import '../engine/diagnostic_orchestrator.dart';
import '../models/diagnostic_test_result.dart';
import '../models/network_diagnostic_report.dart';

class NetworkDiagnosticState {
  final bool isAnalyzing;
  final double currentProgress;
  final String? currentStepTitle;
  final NetworkDiagnosticReport? report;
  final List<DiagnosticTestResult> liveResults;
  final String? errorMessage;
  final bool showOnlyIssues;

  const NetworkDiagnosticState({
    this.isAnalyzing = false,
    this.currentProgress = 0.0,
    this.currentStepTitle,
    this.report,
    this.liveResults = const [],
    this.errorMessage,
    this.showOnlyIssues = false,
  });

  NetworkDiagnosticState copyWith({
    bool? isAnalyzing,
    double? currentProgress,
    String? currentStepTitle,
    NetworkDiagnosticReport? report,
    List<DiagnosticTestResult>? liveResults,
    String? errorMessage,
    bool? showOnlyIssues,
  }) {
    return NetworkDiagnosticState(
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      currentProgress: currentProgress ?? this.currentProgress,
      currentStepTitle: currentStepTitle ?? this.currentStepTitle,
      report: report ?? this.report,
      liveResults: liveResults ?? this.liveResults,
      errorMessage: errorMessage,
      showOnlyIssues: showOnlyIssues ?? this.showOnlyIssues,
    );
  }
}

class NetworkDiagnosticController
    extends StateNotifier<NetworkDiagnosticState> {
  final Ref _ref;
  DiagnosticOrchestrator? _orchestrator;

  NetworkDiagnosticController(this._ref)
    : super(const NetworkDiagnosticState());

  AppState get _appState => _ref.read(appStateProvider);
  IApiService? get _apiService => _appState.apiService;

  String? get _ip =>
      _appState.selectedRouter?.ipAddress ??
      (_appState.reviewerModeEnabled ? '192.168.1.1' : null);
  String? get _sysauth =>
      _appState.sysauth ??
      (_appState.reviewerModeEnabled ? 'mock_auth_token' : null);
  bool get _useHttps => _appState.selectedRouter?.useHttps ?? false;

  void toggleShowOnlyIssues() {
    state = state.copyWith(showOnlyIssues: !state.showOnlyIssues);
  }

  Future<void> runDiagnostics() async {
    final ip = _ip;
    final auth = _sysauth;
    final api = _apiService;

    if (ip == null || auth == null || api == null) {
      state = state.copyWith(
        errorMessage: 'Router connection is unavailable or not authenticated.',
      );
      return;
    }

    state = state.copyWith(
      isAnalyzing: true,
      currentProgress: 0.05,
      currentStepTitle: 'Initiating network diagnostics...',
      liveResults: [],
      errorMessage: null,
    );

    _orchestrator = DiagnosticOrchestrator(
      api: api,
      routerCapabilities: _appState.capabilities,
    );

    try {
      final finalReport = await _orchestrator!.runDiagnostics(
        ipAddress: ip,
        sysauth: auth,
        useHttps: _useHttps,
        onProgress: (currentResult, percent) {
          if (!mounted) return;
          final updated = List<DiagnosticTestResult>.from(state.liveResults)
            ..removeWhere((r) => r.id == currentResult.id)
            ..add(currentResult);

          state = state.copyWith(
            currentProgress: percent,
            currentStepTitle: currentResult.title,
            liveResults: updated,
          );
        },
      );

      if (mounted) {
        state = state.copyWith(
          isAnalyzing: false,
          currentProgress: 1.0,
          currentStepTitle: null,
          report: finalReport,
          liveResults: finalReport.testResults,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isAnalyzing: false,
          errorMessage: 'Diagnostic error: $e',
        );
      }
    }
  }

  void cancel() {
    _orchestrator?.cancel();
    state = state.copyWith(
      isAnalyzing: false,
      currentStepTitle: 'Diagnostics cancelled.',
    );
  }
}

final networkDiagnosticControllerProvider =
    StateNotifierProvider<NetworkDiagnosticController, NetworkDiagnosticState>(
      (ref) => NetworkDiagnosticController(ref),
    );
