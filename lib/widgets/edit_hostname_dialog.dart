// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/network_actions_controller.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

/// Interactive dialog for changing the OpenWrt router system hostname.
///
/// Implements RFC 1123 / RFC 952 validation, real-time error feedback,
/// loading states, and state synchronization across router profiles and dashboard info.
class EditHostnameDialog extends StatefulWidget {
  final String currentHostname;
  final VoidCallback? onSaved;

  const EditHostnameDialog({
    super.key,
    required this.currentHostname,
    this.onSaved,
  });

  /// Displays the [EditHostnameDialog] modally.
  static Future<bool?> show(
    BuildContext context, {
    String? currentHostname,
    VoidCallback? onSaved,
  }) {
    final appState = AppState.instance;
    final effectiveCurrent = (currentHostname != null && currentHostname.trim().isNotEmpty)
        ? currentHostname.trim()
        : (appState.dashboardData?['boardInfo']?['hostname']?.toString() ??
            appState.selectedRouter?.lastKnownHostname ??
            'OpenWrt');

    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => EditHostnameDialog(
        currentHostname: effectiveCurrent,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<EditHostnameDialog> createState() => _EditHostnameDialogState();
}

class _EditHostnameDialogState extends State<EditHostnameDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _validationErrorReason;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentHostname);
    _validationErrorReason = NetworkActionsController.validateHostname(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate(String value) {
    final errorReason = NetworkActionsController.validateHostname(value);
    if (_validationErrorReason != errorReason) {
      setState(() {
        _validationErrorReason = errorReason;
      });
    }
  }

  String? _getLocalizedError(AppLocalizations? l10n) {
    if (_validationErrorReason == null) return null;
    switch (_validationErrorReason) {
      case 'empty':
        return l10n?.hostnameValidationEmpty ?? 'Hostname cannot be empty';
      case 'too_long':
        return l10n?.hostnameValidationLength ?? 'Hostname must be between 1 and 63 characters';
      case 'hyphen_edge':
        return l10n?.hostnameValidationHyphen ?? 'Hostname cannot start or end with a hyphen';
      case 'invalid_characters':
      default:
        return l10n?.hostnameValidationInvalid ?? 'Only letters (a-z), numbers (0-9), and hyphens (-) allowed';
    }
  }

  bool get _isValid => _validationErrorReason == null && _controller.text.trim().isNotEmpty;
  bool get _isUnchanged => _controller.text.trim() == widget.currentHostname.trim();

  Future<void> _handleSave() async {
    final trimmed = _controller.text.trim();
    final l10n = AppLocalizations.of(context);

    if (!_isValid) return;

    if (_isUnchanged) {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.selection));
      Navigator.of(context).pop(false);
      context.showToastInfo(
        l10n?.hostnameUnchanged ?? 'Hostname is unchanged',
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));

    final parentContext = Navigator.of(context).context;

    try {
      final appState = AppState.instance;
      final success = await appState.updateRouterHostname(
        trimmed,
        context: parentContext.mounted ? parentContext : null,
      );

      if (!mounted) return;

      if (success) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
        widget.onSaved?.call();
        Navigator.of(context).pop(true);
        if (parentContext.mounted) {
          parentContext.showToastSuccess(
            l10n?.hostnameSavedSuccess ?? 'Router hostname updated successfully',
          );
        }
      } else {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        setState(() {
          _isSaving = false;
        });
        if (parentContext.mounted) {
          parentContext.showToastError(
            l10n?.hostnameSavedFailure ?? 'Failed to update router hostname',
          );
        }
      }
    } catch (e, stack) {
      Logger.exception('Error saving hostname from dialog', e, stack);
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        context.showToastError(
          l10n?.hostnameSavedFailure ?? 'Failed to update router hostname',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.badge_outlined,
              color: colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              l10n?.dialogEditHostnameTitle ?? 'Edit Router Hostname',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n?.dialogEditHostnameDescription ??
                    'Change the system hostname of your OpenWrt router.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // Current hostname chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.router_outlined,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${l10n?.hostname ?? "Hostname"}: ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.currentHostname,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Hostname input field
              TextFormField(
                controller: _controller,
                autofocus: true,
                enabled: !_isSaving,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleSave(),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(63),
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
                ],
                onChanged: _validate,
                decoration: InputDecoration(
                  labelText: l10n?.hostnameInputLabel ?? 'Hostname',
                  hintText: l10n?.hostnameInputHint ?? 'e.g. OpenWrt, home-router',
                  prefixIcon: const Icon(Icons.dns_outlined, size: 20),
                  errorText: _getLocalizedError(l10n),
                  errorMaxLines: 2,
                  helperText: 'RFC 1123 (1-63 chars, letters, numbers, hyphens)',
                  helperMaxLines: 2,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: _isSaving
                              ? null
                              : () {
                                  _controller.clear();
                                  _validate('');
                                },
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
        ElevatedButton(
          onPressed: (_isValid && !_isSaving) ? _handleSave : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isSaving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                  ),
                )
              : Text(
                  l10n?.actionSave ?? 'Save',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}
