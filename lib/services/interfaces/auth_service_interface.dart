// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

abstract class IAuthService {
  Future<void> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> tryAutoLogin(
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps, {
    bool force = false,
    BuildContext? context,
  });
  Future<void> logout();
  Future<bool> checkRouterAvailability(
    String ipAddress,
    bool useHttps, {
    BuildContext? context,
  });

  String? get sysauth;
  String? get ipAddress;
  bool get useHttps;
  bool get isAuthenticated;

  /// Authoritative generation counter for active session invalidation.
  int get authEpoch;

  /// Starts a password transition critical section: advances authEpoch and suppresses transparent renewal.
  int startPasswordTransition();

  /// Completes a password transition: sets verified new session token and advances authEpoch.
  void completePasswordTransition({
    required String newToken,
    required String newPassword,
    required String ipAddress,
    required bool useHttps,
  });

  /// Cancels a password transition critical section: advances authEpoch and unblocks renewal.
  void cancelPasswordTransition();

  /// Directly updates the in-memory session token without clearing saved router credentials.
  void updateSessionToken(String? token);
}
