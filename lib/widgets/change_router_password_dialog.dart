// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/state/app_state.dart';
import 'package:yala/state/controllers/session_controller.dart';
import 'package:yala/widgets/luci_guardrail.dart';
import 'package:yala/widgets/luci_toast.dart';
import 'package:yala/widgets/password_strength_meter.dart';

/// Modal dialog for securely updating the router admin/root password.
///
/// Implements transactional multi-step workflow:
/// 1. Prechecks and confirmation guardrail
/// 2. Progress reporting across ubus RPC, reauth, and verification
/// 3. In-memory retention and storage retry on Keystore/storage failures
/// 4. Ambiguous recovery messaging with zero credential exposure
class ChangeRouterPasswordDialog extends StatefulWidget {
  const ChangeRouterPasswordDialog({super.key});

  /// Displays the [ChangeRouterPasswordDialog] modally.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const ChangeRouterPasswordDialog(),
    );
  }

  @override
  State<ChangeRouterPasswordDialog> createState() =>
      _ChangeRouterPasswordDialogState();
}

class _ChangeRouterPasswordDialogState
    extends State<ChangeRouterPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _allowWeakPassword = false;

  ChangePasswordStatus _status = ChangePasswordStatus.idle;
  String? _errorMessage;
  bool _isStorageWarning = false;
  bool _isAmbiguous = false;
  String? _storageWarningMessage;
  String? _ambiguousMessage;
  bool _isRetryingStorage = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onPasswordChanged);
    _currentPasswordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _newPasswordController.removeListener(_onPasswordChanged);
    _confirmPasswordController.removeListener(_onPasswordChanged);
    _currentPasswordController.removeListener(_onPasswordChanged);

    // Memory hygiene: clear plaintext before disposal
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();

    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _isProcessing =>
      _status == ChangePasswordStatus.validating ||
      _status == ChangePasswordStatus.requesting ||
      _status == ChangePasswordStatus.reauthenticating ||
      _status == ChangePasswordStatus.verifying ||
      _status == ChangePasswordStatus.savingStorage;

  bool get _isWeak =>
      _newPasswordController.text.isNotEmpty &&
      _newPasswordController.text.length < 8;

  bool get _canSubmit {
    if (_isProcessing || _isStorageWarning || _isAmbiguous) return false;
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) return false;
    if (newPass != confirm) return false;
    if (newPass == current) return false;
    if (_isWeak && !_allowWeakPassword) return false;

    return true;
  }

  Future<void> _handleSubmit() async {
    final l10n = AppLocalizations.of(context);
    final appState = AppState.instance;

    // 1. Critical Confirmation Guardrail
    final confirmed = await LuciGuardrail.confirmCriticalOperation(
      context,
      title: l10n?.changePasswordCriticalDialogTitle ??
          'Critical: Change Router Password',
      description: l10n?.changePasswordCriticalDialogDesc ??
          'Changing the router\'s root/admin password will terminate active sessions. If you lose or forget the new password, a physical router factory reset will be required.',
      hazardDetails: const [
        'Terminates active sessions across all devices',
        'Cannot be undone without physical access if forgotten',
      ],
      confirmLabel: 'Proceed with Change',
      cancelLabel: 'Cancel',
      acknowledgementLabel: l10n?.changePasswordCriticalDialogAcknowledge ??
          'I understand the risks and want to proceed',
      requireAcknowledgement: true,
      isDestructive: true,
    );

    if (!confirmed || !mounted) return;

    setState(() {
      _status = ChangePasswordStatus.validating;
      _errorMessage = null;
      _isStorageWarning = false;
      _isAmbiguous = false;
    });

    final result = await appState.changeRouterPassword(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
      onProgress: (status) {
        if (mounted) {
          setState(() => _status = status);
        }
      },
    );

    if (!mounted) return;

    if (result.isSuccess && result.status == ChangePasswordStatus.success) {
      context.showToastSuccess(
        l10n?.changePasswordSuccess ?? 'Router password updated successfully',
      );
      Navigator.of(context).pop(true);
    } else if (result.status == ChangePasswordStatus.storageWarning) {
      setState(() {
        _status = ChangePasswordStatus.storageWarning;
        _isStorageWarning = true;
        _storageWarningMessage = result.errorMessage;
      });
    } else if (result.status == ChangePasswordStatus.ambiguous) {
      setState(() {
        _status = ChangePasswordStatus.ambiguous;
        _isAmbiguous = true;
        _ambiguousMessage = result.errorMessage;
      });
    } else {
      setState(() {
        _status = ChangePasswordStatus.failed;
        _errorMessage = result.errorMessage ?? 'Password change failed';
      });
    }
  }

  Future<void> _handleRetryStorage() async {
    final l10n = AppLocalizations.of(context);
    final appState = AppState.instance;
    final router = appState.selectedRouter;
    if (router == null) return;

    setState(() => _isRetryingStorage = true);
    final success = await appState.retrySaveRouterPassword(router);
    if (!mounted) return;

    setState(() => _isRetryingStorage = false);
    if (success) {
      context.showToastSuccess(
        l10n?.changePasswordSuccess ?? 'Router password updated successfully',
      );
      Navigator.of(context).pop(true);
    } else {
      context.showToastError(
        'Saving to secure storage failed again. Please note your password.',
      );
    }
  }

  String _getStatusMessage(AppLocalizations? l10n) {
    switch (_status) {
      case ChangePasswordStatus.requesting:
        return l10n?.changePasswordStatusRequesting ??
            'Updating password on router...';
      case ChangePasswordStatus.reauthenticating:
        return l10n?.changePasswordStatusReauth ??
            'Re-authenticating with new password...';
      case ChangePasswordStatus.verifying:
        return l10n?.changePasswordStatusVerifying ??
            'Verifying router access...';
      case ChangePasswordStatus.savingStorage:
        return l10n?.changePasswordStatusSaving ??
            'Saving credentials to secure storage...';
      default:
        return 'Processing password change...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // If in Ambiguous failure mode, render dedicated recovery content
    if (_isAmbiguous) {
      return AlertDialog(
        icon: const Icon(
          Icons.help_outline_rounded,
          color: Colors.orangeAccent,
          size: 40,
        ),
        title: Text(
          l10n?.changePasswordAmbiguousTitle ??
              'Password Verification Inconclusive',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _ambiguousMessage ??
                    l10n?.changePasswordAmbiguousDesc ??
                    'The password change request was sent, but YALA could not verify whether it took effect. Stored credentials were not modified.',
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              const Text(
                '• To protect your access, your saved credentials have NOT been altered.\n'
                '• Do NOT repeatedly retry changing the password.\n'
                '• Please verify your router connection via the LuCI web interface or SSH before attempting again.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Dismiss'),
          ),
        ],
      );
    }

    // If in Storage Warning mode, render persistence recovery view
    if (_isStorageWarning) {
      return AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.amber,
          size: 40,
        ),
        title: Text(
          l10n?.changePasswordStorageWarningTitle ??
              'Router Password Changed (Storage Warning)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n?.changePasswordStorageWarningDesc ??
                    'The router\'s password was changed successfully, but saving it to device storage failed. Take note of your new password.',
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _storageWarningMessage ??
                      'Local device storage write error occurred.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: _isRetryingStorage ? null : _handleRetryStorage,
            icon: _isRetryingStorage
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              l10n?.changePasswordRetryStorage ?? 'Retry Saving to Storage',
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      icon: const Icon(Icons.password_rounded, size: 36),
      title: Text(
        l10n?.changePasswordTitle ?? 'Change Router Password',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Current Password Field
              TextFormField(
                controller: _currentPasswordController,
                obscureText: _obscureCurrent,
                enabled: !_isProcessing,
                decoration: InputDecoration(
                  labelText: l10n?.changePasswordCurrentLabel ??
                      'Current Password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureCurrent
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() => _obscureCurrent = !_obscureCurrent);
                    },
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),

              // New Password Field
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNew,
                enabled: !_isProcessing,
                decoration: InputDecoration(
                  labelText: l10n?.changePasswordNewLabel ?? 'New Password',
                  prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() => _obscureNew = !_obscureNew);
                    },
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),

              // Password Strength Meter
              if (_newPasswordController.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                PasswordStrengthMeter(
                  password: _newPasswordController.text,
                ),
              ],

              // Same password warning
              if (_newPasswordController.text.isNotEmpty &&
                  _newPasswordController.text ==
                      _currentPasswordController.text) ...[
                const SizedBox(height: 4),
                Text(
                  l10n?.changePasswordSameAsCurrent ??
                      'New password must be different from current password',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 11.5,
                  ),
                ),
              ],

              // Weak password guidance banner & acknowledgement
              if (_isWeak) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.changePasswordWeakWarning ??
                            'This password is short or weak. A password of at least 8 characters is recommended.',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Checkbox(
                            value: _allowWeakPassword,
                            onChanged: _isProcessing
                                ? null
                                : (v) {
                                    setState(
                                      () => _allowWeakPassword = v ?? false,
                                    );
                                  },
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          Expanded(
                            child: Text(
                              l10n?.changePasswordWeakAcknowledge ??
                                  'Proceed with weak password anyway',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Confirm New Password Field
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                enabled: !_isProcessing,
                decoration: InputDecoration(
                  labelText: l10n?.changePasswordConfirmLabel ??
                      'Confirm New Password',
                  prefixIcon: const Icon(Icons.check_circle_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() => _obscureConfirm = !_obscureConfirm);
                    },
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),

              // Mismatch warning
              if (_confirmPasswordController.text.isNotEmpty &&
                  _newPasswordController.text !=
                      _confirmPasswordController.text) ...[
                const SizedBox(height: 4),
                Text(
                  l10n?.changePasswordMismatch ?? 'Passwords do not match',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 11.5,
                  ),
                ),
              ],

              // Processing Stepper
              if (_isProcessing) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _getStatusMessage(l10n),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        OutlinedButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _handleSubmit : null,
          child: const Text('Change Password'),
        ),
      ],
    );
  }
}
