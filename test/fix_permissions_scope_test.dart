// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/services/api_service.dart';

void main() {
  group('Comprehensive Fix Permissions Scope Tests', () {
    test('fullAclJson contains valid JSON with all required scopes', () {
      final jsonMap =
          jsonDecode(ApiService.fullAclJson) as Map<String, dynamic>;
      expect(jsonMap.containsKey('yet-another-luci-app'), isTrue);

      final acl = jsonMap['yet-another-luci-app'] as Map<String, dynamic>;
      expect(acl['description'], 'Yet Another LuCI App Permissions');

      // Check 'read' section
      final read = acl['read'] as Map<String, dynamic>;
      expect(read.containsKey('uci'), isTrue);
      expect(read.containsKey('ubus'), isTrue);
      expect(read.containsKey('file'), isTrue);
      expect(read.containsKey('cgi-io'), isTrue);

      final readUci = (read['uci'] as List).cast<String>();
      expect(
        readUci.contains('*'),
        isTrue,
        reason: 'Wildcard UCI must be present',
      );
      expect(
        readUci.contains('sqm'),
        isTrue,
        reason: 'SQM config must be present',
      );
      expect(
        readUci.contains('ddns'),
        isTrue,
        reason: 'DDNS config must be present',
      );
      expect(readUci.contains('firewall'), isTrue);
      expect(readUci.contains('wireless'), isTrue);
      expect(readUci.contains('network'), isTrue);
      expect(readUci.contains('dhcp'), isTrue);
      expect(readUci.contains('system'), isTrue);
      expect(readUci.contains('tailscale'), isTrue);
      expect(readUci.contains('nextdns'), isTrue);
      expect(readUci.contains('cloudflared'), isTrue);
      expect(readUci.contains('mwan3'), isTrue);
      expect(readUci.contains('adblock'), isTrue);

      final readUbus = read['ubus'] as Map<String, dynamic>;
      expect(readUbus.containsKey('*'), isTrue);
      expect(readUbus.containsKey('luci'), isTrue);
      expect(readUbus.containsKey('luci-rpc'), isTrue);
      expect(readUbus.containsKey('network'), isTrue);
      expect(readUbus.containsKey('system'), isTrue);
      expect(readUbus.containsKey('uci'), isTrue);
      expect(readUbus.containsKey('file'), isTrue);
      expect(readUbus.containsKey('rc'), isTrue);
      expect(readUbus.containsKey('iwinfo'), isTrue);
      expect(readUbus.containsKey('luci.temp-status'), isTrue);

      final readFile = read['file'] as Map<String, dynamic>;
      expect(readFile.containsKey('/bin/*'), isTrue);
      expect(readFile.containsKey('/sbin/*'), isTrue);
      expect(readFile.containsKey('/usr/bin/*'), isTrue);
      expect(readFile.containsKey('/usr/sbin/*'), isTrue);
      expect(readFile.containsKey('/bin/sh'), isTrue);
      expect(readFile.containsKey('/etc/config/*'), isTrue);
      expect(readFile.containsKey('/proc/*'), isTrue);
      expect(readFile.containsKey('/sys/*'), isTrue);
      expect(readFile.containsKey('/tmp/*'), isTrue);

      // Check 'write' section
      final write = acl['write'] as Map<String, dynamic>;
      expect(write.containsKey('uci'), isTrue);
      expect(write.containsKey('ubus'), isTrue);
      expect(write.containsKey('file'), isTrue);
      expect(write.containsKey('cgi-io'), isTrue);

      final writeUci = (write['uci'] as List).cast<String>();
      expect(writeUci.contains('*'), isTrue);
      expect(writeUci.contains('sqm'), isTrue);
      expect(writeUci.contains('ddns'), isTrue);
      expect(writeUci.contains('firewall'), isTrue);

      final writeFile = write['file'] as Map<String, dynamic>;
      expect(writeFile.containsKey('/etc/crontabs/root'), isTrue);
      expect(writeFile.containsKey('/etc/config/*'), isTrue);
      expect(writeFile.containsKey('/tmp/*'), isTrue);
    });

    test(
      'getPermissionsFixScript includes read-only filesystem guard and rpcd reload',
      () {
        final script = ApiService.getPermissionsFixScript();

        // Verify read-only fallback logic
        expect(script.contains('.write_test'), isTrue);
        expect(
          script.contains('mount -t tmpfs tmpfs /usr/share/rpcd/acl.d'),
          isTrue,
        );

        // Verify target file path
        expect(
          script.contains('/usr/share/rpcd/acl.d/yet-another-luci-app.json'),
          isTrue,
        );

        // Verify embedded ACL contains SQM and wildcard
        expect(script.contains('"sqm"'), isTrue);
        expect(script.contains('"*"'), isTrue);

        // Verify non-fatal package manager invocation
        expect(script.contains('apk update || true'), isTrue);
        expect(script.contains('opkg update || true'), isTrue);

        // Verify daemon reload
        expect(script.contains('/etc/init.d/rpcd restart'), isTrue);
      },
    );
  });
}
