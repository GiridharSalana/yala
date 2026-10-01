// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

enum PasswordStrength { weak, fair, strong, veryStrong }

/// A compact, animated password strength meter widget for Wi-Fi passphrases
class PasswordStrengthMeter extends StatelessWidget {
  final String password;

  const PasswordStrengthMeter({super.key, required this.password});

  PasswordStrength? get _strength {
    if (password.length < 8) return null;
    int score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[@$!%*?&#^()_+\-=\[\]{};:"\\|,.<>/\~`]').hasMatch(password)) {
      score++;
    }

    if (score <= 1) return PasswordStrength.weak;
    if (score == 2) return PasswordStrength.fair;
    if (score == 3 || score == 4) return PasswordStrength.strong;
    return PasswordStrength.veryStrong;
  }

  Color _getColor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.weak:
        return Colors.redAccent;
      case PasswordStrength.fair:
        return Colors.orangeAccent;
      case PasswordStrength.strong:
        return Colors.lightGreen;
      case PasswordStrength.veryStrong:
        return Colors.tealAccent.shade400;
    }
  }

  String _getLabel(PasswordStrength strength, [AppLocalizations? l10n]) {
    switch (strength) {
      case PasswordStrength.weak:
        return l10n?.passwordStrengthWeak ?? 'Weak (easy to guess)';
      case PasswordStrength.fair:
        return l10n?.passwordStrengthFair ?? 'Fair (medium security)';
      case PasswordStrength.strong:
        return l10n?.passwordStrengthStrong ?? 'Strong (good security)';
      case PasswordStrength.veryStrong:
        return l10n?.passwordStrengthVeryStrong ??
            'Very Strong (maximum security)';
    }
  }

  int _getActiveBars(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.weak:
        return 1;
      case PasswordStrength.fair:
        return 2;
      case PasswordStrength.strong:
        return 3;
      case PasswordStrength.veryStrong:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = _strength;
    if (strength == null) return const SizedBox.shrink();

    final color = _getColor(strength);
    final activeBars = _getActiveBars(strength);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final strengthLabel = _getLabel(strength, l10n);
    final strengthDisplay = l10n != null
        ? l10n.passwordStrengthPrefix(strengthLabel)
        : 'Security Strength: $strengthLabel';

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (index) {
              final isActive = index < activeBars;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index < 3 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: isActive
                        ? color
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(
            strengthDisplay,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
