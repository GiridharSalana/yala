// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:yala/models/router.dart';
import 'package:yala/modules/adguard_home/models/adguard_models.dart';
import '../utils/logger.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  static const String _routersKey = 'routers';
  static const String _selectedRouterKey = 'selectedRouterId';
  static const String _adGuardProfilesKey = 'agh_instance_profiles';

  Future<void> saveCredentials({
    required String ipAddress,
    required String username,
    required String password,
    required bool useHttps,
  }) async {
    try {
      await _storage.write(key: 'ipAddress', value: ipAddress);
      await _storage.write(key: 'username', value: username);
      await _storage.write(key: 'password', value: password);
      await _storage.write(key: 'useHttps', value: useHttps.toString());
    } catch (e, stack) {
      Logger.exception('Failed to save credentials', e, stack);
      rethrow;
    }
  }

  static bool _isMockRouter(Router r) {
    return r.id == 'reviewer-mock-router' ||
        r.id.startsWith('reviewer://') ||
        r.lastKnownHostname == 'OpenWrt-Reviewer' ||
        (r.id == 'http://192.168.1.1-root' &&
            r.lastKnownHostname == 'OpenWrt-Reviewer');
  }

  Future<Map<String, String?>> getCredentials() async {
    try {
      final all = await _storage.readAll();
      final routers = await getRouters();
      if (routers.isNotEmpty) {
        // Prefer the explicitly selected router; fall back to first in list
        final selectedId = all[_selectedRouterKey];
        final router = selectedId != null
            ? routers.firstWhere(
                (r) => r.id == selectedId,
                orElse: () => routers.first,
              )
            : routers.first;
        if (_isMockRouter(router)) {
          return {
            'ipAddress': null,
            'username': null,
            'password': null,
            'useHttps': null,
          };
        }
        return {
          'ipAddress': router.ipAddress,
          'username': router.username,
          'password': router.password,
          'useHttps': router.useHttps.toString(),
        };
      }

      final ipAddress = all['ipAddress'];
      final username = all['username'];
      final password = all['password'];
      final useHttps = all['useHttps'];
      if (ipAddress == '192.168.1.1' &&
          username == 'root' &&
          (password == '' || password == null) &&
          (all[_selectedRouterKey] == 'reviewer-mock-router' ||
              all[_selectedRouterKey]?.startsWith('reviewer://') == true)) {
        return {
          'ipAddress': null,
          'username': null,
          'password': null,
          'useHttps': null,
        };
      }
      if (ipAddress != null &&
          ipAddress.isNotEmpty &&
          username != null &&
          password != null) {
        return {
          'ipAddress': ipAddress,
          'username': username,
          'password': password,
          'useHttps': useHttps,
        };
      }
      return {
        'ipAddress': null,
        'username': null,
        'password': null,
        'useHttps': null,
      };
    } catch (e, stack) {
      Logger.exception('Failed to get credentials', e, stack);
      return {
        'ipAddress': null,
        'username': null,
        'password': null,
        'useHttps': null,
      };
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: 'ipAddress');
      await _storage.delete(key: 'username');
      await _storage.delete(key: 'password');
      await _storage.delete(key: 'useHttps');
    } catch (e, stack) {
      Logger.exception('Failed to clear credentials', e, stack);
      // Don't rethrow as this is often called during cleanup
    }
  }

  Future<String?> readValue(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e, stack) {
      Logger.exception('Failed to read value for key: $key', e, stack);
      return null;
    }
  }

  Future<void> writeValue(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e, stack) {
      Logger.exception('Failed to write value for key: $key', e, stack);
      rethrow;
    }
  }

  Future<void> deleteValue(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e, stack) {
      Logger.exception('Failed to delete value for key: $key', e, stack);
      rethrow;
    }
  }

  /// Purges stored AdGuard credentials for a specific router ID.
  Future<void> deleteAdGuardCredentials(String routerId) async {
    try {
      await _storage.delete(key: 'agh_creds_$routerId');
      await _storage.delete(key: 'agh_creds_local_$routerId');
    } catch (e, stack) {
      Logger.exception(
        'Failed to delete AdGuard credentials for router: $routerId',
        e,
        stack,
      );
    }
  }

  /// Retrieves stored AdGuard instance profiles.
  Future<List<AdGuardInstanceProfile>> getAdGuardProfiles() async {
    try {
      final jsonString = await _storage.read(key: _adGuardProfilesKey);
      if (jsonString == null || jsonString.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .whereType<Map>()
          .map((e) => AdGuardInstanceProfile.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, stack) {
      Logger.exception('Failed to get AdGuard instance profiles', e, stack);
      return [];
    }
  }

  /// Saves a list of AdGuard instance profiles.
  Future<void> saveAdGuardProfiles(List<AdGuardInstanceProfile> profiles) async {
    try {
      final jsonList = profiles.map((p) => p.toJson()).toList();
      await _storage.write(key: _adGuardProfilesKey, value: jsonEncode(jsonList));
    } catch (e, stack) {
      Logger.exception('Failed to save AdGuard instance profiles', e, stack);
      rethrow;
    }
  }

  /// Saves or updates a single AdGuard instance profile.
  Future<void> saveAdGuardProfile(AdGuardInstanceProfile profile) async {
    try {
      final profiles = await getAdGuardProfiles();
      final updated = [
        for (final p in profiles)
          if (p.id != profile.id) p,
        profile,
      ];
      await saveAdGuardProfiles(updated);
    } catch (e, stack) {
      Logger.exception(
        'Failed to save AdGuard instance profile: ${profile.id}',
        e,
        stack,
      );
      rethrow;
    }
  }

  /// Deletes an AdGuard instance profile and its credentials.
  Future<void> deleteAdGuardProfile(String profileId) async {
    try {
      final profiles = await getAdGuardProfiles();
      final updated = profiles.where((p) => p.id != profileId).toList();
      await saveAdGuardProfiles(updated);
      await _storage.delete(key: 'agh_creds_$profileId');
    } catch (e, stack) {
      Logger.exception(
        'Failed to delete AdGuard instance profile: $profileId',
        e,
        stack,
      );
      rethrow;
    }
  }

  /// Saves instance-scoped AdGuard credentials.
  Future<void> saveAdGuardCredentialsForInstance(
    String instanceId,
    String username,
    String password,
  ) async {
    try {
      await _storage.write(
        key: 'agh_creds_$instanceId',
        value: jsonEncode({'username': username, 'password': password}),
      );
    } catch (e, stack) {
      Logger.exception(
        'Failed to save AdGuard credentials for instance: $instanceId',
        e,
        stack,
      );
      rethrow;
    }
  }

  /// Retrieves the active AdGuard profile ID for the specified router context.
  Future<String?> getActiveAdGuardProfileId(String routerId) async {
    try {
      return await _storage.read(key: 'agh_active_profile_$routerId');
    } catch (e, stack) {
      Logger.exception(
        'Failed to get active AdGuard profile ID for router: $routerId',
        e,
        stack,
      );
      return null;
    }
  }

  /// Persists the active AdGuard profile ID for the specified router context.
  Future<void> saveActiveAdGuardProfileId(
    String routerId,
    String profileId,
  ) async {
    try {
      await _storage.write(
        key: 'agh_active_profile_$routerId',
        value: profileId,
      );
    } catch (e, stack) {
      Logger.exception(
        'Failed to save active AdGuard profile ID for router: $routerId',
        e,
        stack,
      );
      rethrow;
    }
  }

  /// Clears the active AdGuard profile ID for the specified router context.
  Future<void> clearActiveAdGuardProfileId(String routerId) async {
    try {
      await _storage.delete(key: 'agh_active_profile_$routerId');
    } catch (e, stack) {
      Logger.exception(
        'Failed to clear active AdGuard profile ID for router: $routerId',
        e,
        stack,
      );
    }
  }

  Future<void> saveRouters(List<Router> routers) async {
    try {
      final cleanList = routers.where((r) => !_isMockRouter(r)).toList();
      final jsonList = cleanList.map((r) => r.toJson()).toList();
      await _storage.write(key: _routersKey, value: jsonEncode(jsonList));
    } catch (e, stack) {
      Logger.exception('Failed to save routers', e, stack);
      rethrow;
    }
  }

  Future<List<Router>> getRouters() async {
    try {
      final jsonString = await _storage.read(key: _routersKey);
      if (jsonString == null || jsonString.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .whereType<Map>()
          .map((e) => Router.fromJson(Map<String, dynamic>.from(e)))
          .where(
            (r) =>
                r.id.isNotEmpty &&
                r.ipAddress.isNotEmpty &&
                !_isMockRouter(r),
          )
          .toList();
    } catch (e, stack) {
      Logger.exception('Failed to get routers', e, stack);
      return [];
    }
  }

  Future<void> deleteRouter(String id) async {
    try {
      final routers = await getRouters();
      final updated = routers.where((r) => r.id != id).toList();
      await saveRouters(updated);
      await deleteAdGuardCredentials(id);
      await clearActiveAdGuardProfileId(id);
      // Remove local AdGuard profiles associated with this router; preserve external profiles!
      final profiles = await getAdGuardProfiles();
      final keptProfiles = profiles.where((p) => p.routerId != id).toList();
      if (keptProfiles.length != profiles.length) {
        await saveAdGuardProfiles(keptProfiles);
      }
    } catch (e, stack) {
      Logger.exception('Failed to delete router: $id', e, stack);
      rethrow;
    }
  }

  Future<void> updateRouter(Router router, {String? oldId}) async {
    try {
      final targetId = oldId ?? router.id;
      final routers = await getRouters();
      final updated = [
        for (final r in routers)
          if (r.id == targetId) router else r,
      ];
      await saveRouters(updated);

      if (oldId != null && oldId != router.id) {
        final profiles = await getAdGuardProfiles();
        final updatedProfiles = profiles.map((p) {
          if (p.routerId == oldId) {
            return p.copyWith(routerId: router.id);
          }
          return p;
        }).toList();
        if (updatedProfiles != profiles) {
          await saveAdGuardProfiles(updatedProfiles);
        }
      }
    } catch (e, stack) {
      Logger.exception('Failed to update router: ${router.id}', e, stack);
      rethrow;
    }
  }

  Future<void> saveSelectedRouterId(String? id) async {
    try {
      if (id == null ||
          id == 'reviewer-mock-router' ||
          id.startsWith('reviewer://')) {
        await _storage.delete(key: _selectedRouterKey);
      } else {
        await _storage.write(key: _selectedRouterKey, value: id);
      }
    } catch (e, stack) {
      Logger.exception('Failed to save selected router ID', e, stack);
      rethrow;
    }
  }

  Future<String?> getSelectedRouterId() async {
    try {
      return await _storage.read(key: _selectedRouterKey);
    } catch (e, stack) {
      Logger.exception('Failed to get selected router ID', e, stack);
      return null;
    }
  }
}
