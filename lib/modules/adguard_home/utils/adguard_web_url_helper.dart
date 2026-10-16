// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/widgets/luci_toast.dart';

/// Helper utility for resolving, constructing, and launching AdGuard Home Web UI URLs.
class AdGuardWebUrlHelper {
  AdGuardWebUrlHelper._();

  /// Formats host address correctly for URLs (e.g., IPv6 bracket notation).
  static String formatHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return '127.0.0.1';
    // If it contains colons and is not already bracketed, wrap in brackets for IPv6.
    if (trimmed.contains(':') && !trimmed.startsWith('[')) {
      return '[$trimmed]';
    }
    return trimmed;
  }

  /// Builds a complete Web UI URL given [host], [port], and optional [useHttps].
  static String buildWebUrl({
    required String host,
    required int port,
    bool useHttps = false,
  }) {
    final formattedHost = formatHost(host);
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$formattedHost:$port';
  }

  /// Launches the AdGuard Home Web UI in an external browser.
  ///
  /// In Reviewer Mode ([isReviewerMode] is true), external browser launches
  /// are strictly suppressed to guarantee sandbox isolation, and an informative
  /// localized toast is presented instead.
  static Future<bool> launchWebInterface({
    required BuildContext context,
    required bool isReviewerMode,
    required String host,
    required int port,
    bool useHttps = false,
  }) async {
    final l10n = AppLocalizations.of(context);

    if (isReviewerMode) {
      if (context.mounted) {
        context.showToastInfo(
          l10n?.aghWebInterfaceDisabledReviewer ??
              'Web interface launch disabled in Reviewer Mode',
        );
      }
      return false;
    }

    final urlString = buildWebUrl(host: host, port: port, useHttps: useHttps);
    final uri = Uri.tryParse(urlString);
    if (uri != null && await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
