// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yala/l10n/app_localizations.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_api_models.dart';

/// Dialog for collecting AdGuard Home HTTP basic authentication credentials.
///
/// Dispatches credentials directly to [AdGuardController.setCredentials],
/// ensuring zero direct manipulation of secure storage keys in the UI layer.
class AdGuardCredentialsDialog extends StatefulWidget {
  final AdGuardController controller;

  const AdGuardCredentialsDialog({super.key, required this.controller});

  static Future<bool?> show(
    BuildContext context, {
    required AdGuardController controller,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AdGuardCredentialsDialog(controller: controller),
    );
  }

  @override
  State<AdGuardCredentialsDialog> createState() =>
      _AdGuardCredentialsDialogState();
}

class _AdGuardCredentialsDialogState extends State<AdGuardCredentialsDialog> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Username cannot be empty';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final creds = AdGuardCredentials(username: username, password: password);
      final success = await widget.controller.setCredentials(creds);
      if (!mounted) return;
      if (!success) {
        setState(() {
          _isSubmitting = false;
          _errorMessage =
              'Authentication failed. Invalid username or password.';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n?.aghCredentialsTitle ?? 'AdGuard Home Credentials'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n?.aghCredentialsSubtitle ??
                  'Enter HTTP credentials for AdGuard Home',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('agh_credentials_username_field'),
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: l10n?.aghUsername ?? 'Username',
                prefixIcon: const Icon(Icons.person_outline),
                border: const OutlineInputBorder(),
              ),
              enabled: !_isSubmitting,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('agh_credentials_password_field'),
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: l10n?.aghPassword ?? 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: const OutlineInputBorder(),
              ),
              obscureText: _obscurePassword,
              enabled: !_isSubmitting,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
        FilledButton(
          key: const Key('agh_credentials_submit_button'),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n?.aghSaveCredentials ?? 'Save & Connect'),
        ),
      ],
    );
  }
}
