// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/screens/storage_monitoring_screen.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/widgets/storage_monitoring_card.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Robust External Storage Detection - Live Router Payload Tests', () {
    test('10.0.0.1 Payload: Detects external SSD on /dev/sda2 without confusing internal flash', () {
      final payload = [
        {"device": "/dev/root", "mount": "/rom", "size": 16515072, "avail": 0, "free": 0},
        {"device": "tmpfs", "mount": "/tmp", "size": 126009344, "avail": 123916288, "free": 123916288},
        {"device": "/dev/ubi0_1", "mount": "/overlay", "size": 55664640, "avail": 18579456, "free": 21463040},
        {"device": "overlayfs:/overlay", "mount": "/", "size": 55664640, "avail": 18579456, "free": 21463040},
        {"device": "tmpfs", "mount": "/dev", "size": 524288, "avail": 524288, "free": 524288},
        {"device": "/dev/sda2", "mount": "/mnt/ssd", "size": 488992784384, "avail": 483994144768, "free": 488990511104},
      ];

      final overview = StorageOverview.fromRpcData(payload);

      // 1. External detection
      expect(overview.hasExternalStorage, isTrue);
      expect(overview.externalMounts.length, equals(1));

      final externalItem = overview.externalMounts.first;
      expect(externalItem.mountPath, equals('/mnt/ssd'));
      expect(externalItem.device, equals('/dev/sda2'));
      expect(externalItem.isExternal, isTrue);
      expect(externalItem.isInbuilt, isFalse);

      // 2. Inbuilt flash & ROM preservation
      expect(overview.rootFs, isNotNull);
      expect(overview.rootFs!.isExternal, isFalse);
      expect(overview.rootFs!.isInbuilt, isTrue);

      expect(overview.overlayFs, isNotNull);
      expect(overview.overlayFs!.isExternal, isFalse);
      expect(overview.overlayFs!.isInbuilt, isTrue);
      expect(overview.overlayFs!.mountPath, equals('/overlay'));
      expect(overview.overlayFs!.device, equals('/dev/ubi0_1'));

      // 3. Capacity breakdown
      expect(overview.externalStorageTotalBytes, equals(488992784384));
      expect(overview.inbuiltStorageTotalBytes, equals(55664640)); // ~55.6 MB internal flash
      expect(overview.totalSizeBytes, equals(55664640 + 488992784384));
    });

    test('192.168.1.1 Payload: Archer C60 on-board flash reports 0 external storage', () {
      final payload = [
        {"device": "/dev/root", "mount": "/rom", "size": 4980736, "avail": 0, "free": 0},
        {"device": "tmpfs", "mount": "/tmp", "size": 28594176, "avail": 28291072, "free": 28291072},
        {"device": "/dev/mtdblock6", "mount": "/overlay", "size": 393216, "avail": 110592, "free": 110592},
        {"device": "overlayfs:/overlay", "mount": "/", "size": 393216, "avail": 110592, "free": 110592},
        {"device": "tmpfs", "mount": "/dev", "size": 524288, "avail": 524288, "free": 524288},
      ];

      final overview = StorageOverview.fromRpcData(payload);

      expect(overview.hasExternalStorage, isFalse);
      expect(overview.externalMounts, isEmpty);
      expect(overview.externalStorageTotalBytes, equals(0));
      expect(overview.inbuiltStorageTotalBytes, equals(393216)); // 384 KB overlay
      expect(overview.totalSizeBytes, equals(393216));

      for (final m in overview.mountPoints) {
        expect(m.isExternal, isFalse);
      }
    });

    test('Detects USB drives, NVMe SSDs, network CIFS/NFS shares, and external SD cards', () {
      final testCases = [
        // USB FAT32/NTFS
        {'device': '/dev/sdb1', 'mount': '/mnt/usb', 'fs': 'vfat', 'sizeBytes': 32000000000},
        // NVMe drive
        {'device': '/dev/nvme0n1p1', 'mount': '/mnt/fast_nvme', 'fs': 'ext4', 'sizeBytes': 1000000000000},
        // CIFS network share
        {'device': '//192.168.1.100/Media', 'mount': '/mnt/media', 'fs': 'cifs', 'sizeBytes': 4000000000000},
        // NFS network share
        {'device': '192.168.1.100:/export/data', 'mount': '/mnt/nfs_data', 'fs': 'nfs', 'sizeBytes': 2000000000000},
        // External SD card slot
        {'device': '/dev/mmcblk1p1', 'mount': '/mnt/sdcard', 'fs': 'exfat', 'sizeBytes': 64000000000},
      ];

      for (final tc in testCases) {
        final item = MountPointItem.fromJson(tc);
        expect(item.isExternal, isTrue, reason: 'Failed for ${tc["device"]} at ${tc["mount"]}');
        expect(item.isInbuilt, isFalse);
      }
    });

    test('Extroot: Detects external USB drive backing /overlay as external', () {
      final extrootPayload = [
        {'device': '/dev/root', 'mount': '/rom', 'size': 16000000},
        {'device': '/dev/sda1', 'mount': '/overlay', 'size': 64000000000, 'used': 2000000000, 'avail': 62000000000},
        {'device': 'overlayfs:/overlay', 'mount': '/', 'size': 64000000000, 'used': 2000000000, 'avail': 62000000000},
      ];

      final overview = StorageOverview.fromRpcData(extrootPayload);
      expect(overview.hasExternalStorage, isTrue);
      expect(overview.externalMounts.any((m) => m.mountPath == '/overlay'), isTrue);
    });

    test('Internal eMMC: Correctly identifies on-board eMMC rootfs as inbuilt, not external', () {
      final emmcPayload = [
        {'device': '/dev/mmcblk0p1', 'mount': '/boot', 'size': 67108864},
        {'device': '/dev/mmcblk0p2', 'mount': '/', 'size': 8589934592, 'used': 1073741824, 'avail': 7516192768},
      ];

      final overview = StorageOverview.fromRpcData(emmcPayload);
      expect(overview.hasExternalStorage, isFalse);
      expect(overview.rootFs!.isInbuilt, isTrue);
      expect(overview.rootFs!.isExternal, isFalse);
    });
  });

  group('Storage Monitoring UI & Badge Rendering Tests', () {
    testWidgets('StorageMonitoringScreen displays External badge when external storage is connected', (tester) async {
      final appState = AppState.instance;
      appState.setDashboardDataForTesting({
        'mountPoints': [
          {"device": "/dev/root", "mount": "/rom", "size": 16515072, "avail": 0, "free": 0},
          {"device": "tmpfs", "mount": "/tmp", "size": 126009344, "avail": 123916288, "free": 123916288},
          {"device": "/dev/ubi0_1", "mount": "/overlay", "size": 55664640, "avail": 18579456, "free": 21463040},
          {"device": "overlayfs:/overlay", "mount": "/", "size": 55664640, "avail": 18579456, "free": 21463040},
          {"device": "/dev/sda2", "mount": "/mnt/ssd", "size": 488992784384, "avail": 483994144768, "free": 488990511104},
        ],
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: StorageMonitoringScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify "Total System Storage" is displayed
      expect(find.text('Total System Storage'), findsOneWidget);

      // Verify External badge is displayed next to Total System Storage
      expect(find.textContaining('External: 455.4'), findsWidgets);

      // Verify Inbuilt vs External capacity breakdown is rendered
      expect(find.textContaining('Inbuilt: 53.1 MB'), findsOneWidget);
      expect(find.textContaining('External: 455.4'), findsWidgets);

      // Verify External Storage Devices section is rendered
      expect(find.textContaining('External Storage Devices (1)'), findsOneWidget);
    });

    testWidgets('StorageMonitoringScreen hides External badge when no external storage is connected', (tester) async {
      final appState = AppState.instance;
      appState.setDashboardDataForTesting({
        'mountPoints': [
          {"device": "/dev/root", "mount": "/rom", "size": 4980736, "avail": 0, "free": 0},
          {"device": "tmpfs", "mount": "/tmp", "size": 28594176, "avail": 28291072, "free": 28291072},
          {"device": "/dev/mtdblock6", "mount": "/overlay", "size": 393216, "avail": 110592, "free": 110592},
          {"device": "overlayfs:/overlay", "mount": "/", "size": 393216, "avail": 110592, "free": 110592},
        ],
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: StorageMonitoringScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total System Storage'), findsOneWidget);
      // External badge and section should NOT be present
      expect(find.textContaining('External:'), findsNothing);
      expect(find.textContaining('External Storage Devices'), findsNothing);
    });

    testWidgets('StorageMonitoringCard renders External chip on dashboard when external storage is present', (tester) async {
      final appState = AppState.instance;
      appState.setDashboardDataForTesting({
        'mountPoints': [
          {"device": "/dev/root", "mount": "/rom", "size": 16515072, "avail": 0, "free": 0},
          {"device": "/dev/ubi0_1", "mount": "/overlay", "size": 55664640, "avail": 18579456, "free": 21463040},
          {"device": "/dev/sda2", "mount": "/mnt/ssd", "size": 488992784384, "avail": 483994144768, "free": 488990511104},
        ],
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: StorageMonitoringCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify External badge is displayed in the card header
      expect(find.text('External'), findsOneWidget);
      expect(find.byIcon(Icons.usb_rounded), findsOneWidget);
    });
  });
}
