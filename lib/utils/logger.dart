// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Centralized logging utility for the application
/// Provides consistent logging across different build modes
class Logger {
  static const String _tag = 'YetAnotherLuCIApp';

  /// Log debug messages (only in debug mode)
  static void debug(String message) {
    if (kDebugMode) {
      developer.log(message, name: _tag, level: 300);
    }
  }

  /// Log info messages
  static void info(String message) {
    if (kDebugMode) {
      developer.log(message, name: _tag, level: 800);
    }
  }

  /// Log warning messages
  static void warning(String message) {
    if (kDebugMode) {
      developer.log(message, name: _tag, level: 900);
    }
  }

  /// Log error messages with optional stack trace
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      developer.log(
        message,
        name: _tag,
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Log exceptions with context
  static void exception(
    String context,
    Object exception,
    StackTrace stackTrace,
  ) {
    error('$context: $exception', exception, stackTrace);
  }
}
