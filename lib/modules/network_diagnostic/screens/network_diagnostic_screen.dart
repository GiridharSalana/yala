// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/luci_design_system.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../../widgets/luci_app_bar.dart';
import '../controllers/network_diagnostic_controller.dart';
import '../models/diagnostic_confidence.dart';
import '../models/diagnostic_status.dart';
import '../models/diagnostic_test_result.dart';
import '../models/root_cause_finding.dart';

typedef NetworkDiagnosticView = NetworkDiagnosticScreen;

class NetworkDiagnosticScreen extends ConsumerWidget {
  final bool showAppBar;

  const NetworkDiagnosticScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(networkDiagnosticControllerProvider);
    final controller = ref.read(networkDiagnosticControllerProvider.notifier);
    final appState = ref.watch(appStateProvider);

    final routerName =
        appState.selectedRouter?.name ??
        (appState.reviewerModeEnabled
            ? 'Demo Router (Reviewer Mode)'
            : 'Router');
    final routerIp =
        appState.selectedRouter?.ipAddress ??
        (appState.reviewerModeEnabled ? '192.168.1.1' : 'Unknown IP');

    final displayResults = state.showOnlyIssues
        ? state.liveResults.where((r) => r.status.isProblem).toList()
        : state.liveResults;

    final issueCount = state.liveResults
        .where((r) => r.status.isProblem)
        .length;

    final content = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Hero Assessment & Action Card
          _buildHeroAssessmentCard(
            context,
            state: state,
            controller: controller,
            routerName: routerName,
            routerIp: routerIp,
          ),
          const SizedBox(height: LuciSpacing.md),

          // 2. Active Root Cause Findings (if any)
          if (state.report?.findings.isNotEmpty == true) ...[
            _buildSectionHeader(
              context,
              title:
                  l10n?.netDiagSectionFindings ??
                  'Root-Cause Findings & Evidence',
              icon: Icons.lightbulb_outline_rounded,
            ),
            const SizedBox(height: LuciSpacing.xs),
            ...state.report!.findings.map(
              (finding) => _buildFindingCard(context, finding),
            ),
            const SizedBox(height: LuciSpacing.md),
          ],

          // 3. Test Results Breakdown
          if (state.liveResults.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader(
                  context,
                  title:
                      l10n?.netDiagSectionResults ?? 'Diagnostic Test Results',
                  icon: Icons.checklist_rounded,
                ),
                if (issueCount > 0)
                  FilterChip(
                    label: Text(
                      l10n?.netDiagFilterShowIssuesOnly(issueCount) ??
                          'Show Issues Only ($issueCount)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: state.showOnlyIssues
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    selected: state.showOnlyIssues,
                    onSelected: (_) => controller.toggleShowOnlyIssues(),
                  ),
              ],
            ),
            const SizedBox(height: LuciSpacing.xs),
            ...displayResults.map(
              (test) => _buildTestResultCard(context, test),
            ),
            const SizedBox(height: LuciSpacing.md),
          ],

          // 4. Limitations & Unverified Domains Disclosure
          if (state.report?.unverifiedAreas.isNotEmpty == true) ...[
            _buildUnverifiedAreasCard(context, state.report!.unverifiedAreas),
            const SizedBox(height: LuciSpacing.lg),
          ],
        ],
      ),
    );

    if (!showAppBar) {
      return content;
    }

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n?.netDiagTitle ?? 'Network Diagnostic',
        actions: [
          if (state.report != null && !state.isAnalyzing)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n?.netDiagBtnRerun ?? 'Rerun Diagnostics',
              onPressed: controller.runDiagnostics,
            ),
        ],
      ),
      body: content,
    );
  }

  // ---------------------------------------------------------------------------
  // 1. HERO ASSESSMENT & ACTION CARD
  // ---------------------------------------------------------------------------
  Widget _buildHeroAssessmentCard(
    BuildContext context, {
    required NetworkDiagnosticState state,
    required NetworkDiagnosticController controller,
    required String routerName,
    required String routerIp,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = state.report;
    final isAnalyzing = state.isAnalyzing;

    Color headerBg;
    Color headerBorder;
    Color iconColor;
    IconData statusIcon;
    String statusTitle;
    String statusSummary;

    if (isAnalyzing) {
      headerBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.3);
      headerBorder = theme.colorScheme.primary.withValues(alpha: 0.4);
      iconColor = theme.colorScheme.primary;
      statusIcon = Icons.sync_rounded;
      statusTitle =
          l10n?.netDiagRunningTitle ?? 'Running Network Diagnostics...';
      statusSummary =
          state.currentStepTitle ??
          (l10n?.netDiagRunningSummary ??
              'Gathering configuration and probing network paths...');
    } else if (report == null) {
      headerBg = theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.4,
      );
      headerBorder = theme.colorScheme.outlineVariant.withValues(alpha: 0.3);
      iconColor = theme.colorScheme.primary;
      statusIcon = Icons.troubleshoot_rounded;
      statusTitle = l10n?.netDiagReadyTitle ?? 'Network Diagnostic Ready';
      statusSummary =
          l10n?.netDiagSubtitleReady ??
          'Perform automated, evidence-based root-cause analysis on router uplink, DNS resolution, default routes, IPv4, IPv6, and external reachability.';
    } else {
      switch (report.overallStatus) {
        case DiagnosticStatus.healthy:
          headerBg = LuciStatusColors.connected.withValues(alpha: 0.12);
          headerBorder = LuciStatusColors.connected.withValues(alpha: 0.35);
          iconColor = LuciStatusColors.connected;
          statusIcon = Icons.check_circle_rounded;
          statusTitle = l10n?.netDiagHealthyTitle ?? 'Network Healthy';
          statusSummary = report.overallSummary;
          break;
        case DiagnosticStatus.degraded:
        case DiagnosticStatus.suspected:
          headerBg = LuciStatusColors.warning.withValues(alpha: 0.12);
          headerBorder = LuciStatusColors.warning.withValues(alpha: 0.35);
          iconColor = LuciStatusColors.warning;
          statusIcon = Icons.warning_amber_rounded;
          statusTitle = report.overallStatus == DiagnosticStatus.degraded
              ? (l10n?.netDiagDegradedTitle ?? 'Connectivity Degraded')
              : (l10n?.netDiagSuspectedTitle ?? 'Suspected Issue');
          statusSummary = report.overallSummary;
          break;
        case DiagnosticStatus.failureConfirmed:
          headerBg = LuciStatusColors.error.withValues(alpha: 0.12);
          headerBorder = LuciStatusColors.error.withValues(alpha: 0.35);
          iconColor = LuciStatusColors.error;
          statusIcon = Icons.error_outline_rounded;
          statusTitle =
              l10n?.netDiagIssueDetectedTitle ?? 'Connectivity Issue Detected';
          statusSummary = report.overallSummary;
          break;
        case DiagnosticStatus.inconclusive:
        case DiagnosticStatus.notTested:
        case DiagnosticStatus.unsupported:
        case DiagnosticStatus.notApplicable:
          headerBg = LuciStatusColors.inactive.withValues(alpha: 0.12);
          headerBorder = LuciStatusColors.inactive.withValues(alpha: 0.35);
          iconColor = LuciStatusColors.inactive;
          statusIcon = Icons.help_outline_rounded;
          statusTitle = _getLocalizedStatusLabel(report.overallStatus, l10n);
          statusSummary = report.overallSummary;
          break;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(color: headerBorder),
      ),
      padding: const EdgeInsets.all(LuciSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: iconColor, size: 28),
              ),
              const SizedBox(width: LuciSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n?.netDiagTargetRouter(routerName, routerIp) ??
                          'Target: $routerName ($routerIp)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LuciSpacing.md),
          Text(
            statusSummary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.4,
            ),
          ),
          if (isAnalyzing) ...[
            const SizedBox(height: LuciSpacing.md),
            LinearProgressIndicator(
              value: state.currentProgress > 0 ? state.currentProgress : null,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
          if (report != null && !isAnalyzing) ...[
            const SizedBox(height: LuciSpacing.sm),
            Text(
              l10n?.netDiagCollectedAt(
                    _formatTime(report.timestamp),
                    report.sessionId,
                  ) ??
                  'Collected at: ${_formatTime(report.timestamp)} • Session ID: ${report.sessionId}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: LuciSpacing.md),
          Row(
            children: [
              if (isAnalyzing)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(l10n?.netDiagBtnCancel ?? 'Cancel Analysis'),
                    onPressed: controller.cancel,
                  ),
                )
              else
                Expanded(
                  child: FilledButton.icon(
                    icon: Icon(
                      report == null
                          ? Icons.play_arrow_rounded
                          : Icons.refresh_rounded,
                      size: 20,
                    ),
                    label: Text(
                      report == null
                          ? (l10n?.netDiagBtnRun ?? 'Run Diagnostics')
                          : (l10n?.netDiagBtnRerun ?? 'Rerun Diagnostics'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: controller.runDiagnostics,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. ROOT CAUSE FINDING CARDS
  // ---------------------------------------------------------------------------
  Widget _buildFindingCard(BuildContext context, RootCauseFinding finding) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    Color badgeColor;
    IconData findingIcon;
    switch (finding.status) {
      case DiagnosticStatus.healthy:
        badgeColor = LuciStatusColors.connected;
        findingIcon = Icons.check_circle_outline_rounded;
        break;
      case DiagnosticStatus.degraded:
      case DiagnosticStatus.suspected:
        badgeColor = LuciStatusColors.warning;
        findingIcon = Icons.warning_amber_rounded;
        break;
      case DiagnosticStatus.failureConfirmed:
        badgeColor = LuciStatusColors.error;
        findingIcon = Icons.error_outline_rounded;
        break;
      default:
        badgeColor = LuciStatusColors.inactive;
        findingIcon = Icons.info_outline_rounded;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: LuciSpacing.sm),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
        side: BorderSide(color: badgeColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LuciSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(findingIcon, color: badgeColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    finding.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _getLocalizedConfidenceLabel(finding.confidence, l10n),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              finding.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (finding.supportingEvidence.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                l10n?.netDiagSupportingEvidence ?? 'Supporting Observations:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              ...finding.supportingEvidence.map(
                (ev) => Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: badgeColor)),
                      Expanded(
                        child: Text(
                          ev,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (finding.contradictoryEvidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n?.netDiagConflictingEvidence ??
                    'Conflicting / Mitigating Observations:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: LuciStatusColors.warning,
                ),
              ),
              const SizedBox(height: 4),
              ...finding.contradictoryEvidence.map(
                (ev) => Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('⚠ ', style: TextStyle(fontSize: 11)),
                      Expanded(
                        child: Text(
                          ev,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (finding.recommendedSteps.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_circle_right_outlined,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n?.netDiagRecommendedActions ??
                              'Recommended Next Steps:',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...finding.recommendedSteps.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${e.key + 1}. ${e.value}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. TEST RESULT ITEM CARDS
  // ---------------------------------------------------------------------------
  Widget _buildTestResultCard(BuildContext context, DiagnosticTestResult test) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    Color statusColor;
    IconData statusIcon;

    switch (test.status) {
      case DiagnosticStatus.healthy:
        statusColor = LuciStatusColors.connected;
        statusIcon = Icons.check_circle_rounded;
        break;
      case DiagnosticStatus.degraded:
      case DiagnosticStatus.suspected:
        statusColor = LuciStatusColors.warning;
        statusIcon = Icons.warning_amber_rounded;
        break;
      case DiagnosticStatus.failureConfirmed:
        statusColor = LuciStatusColors.error;
        statusIcon = Icons.cancel_rounded;
        break;
      case DiagnosticStatus.unsupported:
        statusColor = Colors.purple.shade400;
        statusIcon = Icons.block_flipped;
        break;
      case DiagnosticStatus.notApplicable:
        statusColor = LuciStatusColors.inactive;
        statusIcon = Icons.remove_circle_outline_rounded;
        break;
      case DiagnosticStatus.inconclusive:
      case DiagnosticStatus.notTested:
        statusColor = LuciStatusColors.inactive;
        statusIcon = Icons.help_outline_rounded;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: LuciSpacing.xs),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Icon(statusIcon, color: statusColor, size: 22),
          title: Text(
            test.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Text(
            test.explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              _getLocalizedStatusLabel(test.status, l10n),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
          children: [
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n?.netDiagWhyItMatters ?? 'Why This Matters:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    test.whyItMatters,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (test.recommendedStep != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n?.netDiagSuggestedAction ?? 'Suggested Action:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      test.recommendedStep!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (test.evidence.facts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n?.netDiagObservedFacts ?? 'Observed Facts:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ...test.evidence.facts.map(
                      (f) => Text(
                        '• $f',
                        style: LuciTypography.monoStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (test.duration != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n?.netDiagExecutionDuration(
                            test.duration!.inMilliseconds,
                          ) ??
                          'Execution Duration: ${test.duration!.inMilliseconds} ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. LIMITATIONS & UNVERIFIED DOMAINS CARD
  // ---------------------------------------------------------------------------
  Widget _buildUnverifiedAreasCard(
    BuildContext context,
    List<String> unverified,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(LuciSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                l10n?.netDiagSectionScope ??
                    'Diagnostic Scope & Unverified Domains',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n?.netDiagUnverifiedExplanation ??
                'In accordance with strict diagnostic accuracy, tests are executed from the router itself. The following factors cannot be evaluated without on-device client probes:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          ...unverified.map(
            (u) => Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                '• $u',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String _getLocalizedStatusLabel(
    DiagnosticStatus status,
    AppLocalizations? l10n,
  ) {
    if (l10n == null) return status.label;
    switch (status) {
      case DiagnosticStatus.healthy:
        return l10n.netDiagStatusHealthy;
      case DiagnosticStatus.degraded:
        return l10n.netDiagStatusDegraded;
      case DiagnosticStatus.suspected:
        return l10n.netDiagStatusSuspected;
      case DiagnosticStatus.failureConfirmed:
        return l10n.netDiagStatusFailureConfirmed;
      case DiagnosticStatus.inconclusive:
        return l10n.netDiagStatusInconclusive;
      case DiagnosticStatus.notTested:
        return l10n.netDiagStatusNotTested;
      case DiagnosticStatus.unsupported:
        return l10n.netDiagStatusUnsupported;
      case DiagnosticStatus.notApplicable:
        return l10n.netDiagStatusNotApplicable;
    }
  }

  static String _getLocalizedConfidenceLabel(
    DiagnosticConfidence confidence,
    AppLocalizations? l10n,
  ) {
    if (l10n == null) return confidence.label;
    switch (confidence) {
      case DiagnosticConfidence.high:
        return l10n.netDiagConfidenceHigh;
      case DiagnosticConfidence.moderate:
        return l10n.netDiagConfidenceModerate;
      case DiagnosticConfidence.low:
        return l10n.netDiagConfidenceLow;
      case DiagnosticConfidence.inconclusive:
        return l10n.netDiagStatusInconclusive;
    }
  }
}
