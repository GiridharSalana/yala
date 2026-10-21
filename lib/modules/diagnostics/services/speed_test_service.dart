// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import '../../../services/api_service.dart';
import '../../../services/interfaces/api_service_interface.dart';
import '../models/speed_test_models.dart';

/// Abstract contract for Internet Speed Test execution.
abstract class ISpeedTestService {
  /// Stream reporting real-time progress events during test execution.
  Stream<SpeedTestProgress> get progressStream;

  /// Runs the full internet speed test pipeline (latency -> download -> upload).
  Future<SpeedTestResult> runTest({
    int downloadByteTarget = 15000000, // 15 MB
    int uploadByteTarget = 4000000, // 4 MB
    int latencyProbes = 5,
    Duration timeout = const Duration(seconds: 25),
  });

  /// Runs speed test directly from the OpenWrt router (WAN speed test via LuCI RPC).
  Future<SpeedTestResult> runRouterSpeedTest({
    required IApiService api,
    required String routerIp,
    required String sysauth,
    bool useHttps = false,
    String? wanInterface,
    Duration timeout = const Duration(seconds: 30),
  });

  /// Immediately cancels any ongoing speed test and aborts open network connections.
  void cancel();

  /// Detects the client device network transport (Wi-Fi, Cellular, Ethernet, VPN, Unknown).
  Future<String> detectTransportType();
}

/// Production implementation of [ISpeedTestService] utilizing Cloudflare Anycast speed test infrastructure.
class SpeedTestService implements ISpeedTestService {
  final String serverUrl;
  final String serverName;
  final HttpClient Function()? clientFactory;

  final StreamController<SpeedTestProgress> _progressController =
      StreamController<SpeedTestProgress>.broadcast();

  HttpClient? _activeClient;
  bool _isCancelled = false;

  SpeedTestService({
    this.serverUrl = 'https://speed.cloudflare.com',
    this.serverName = 'Cloudflare Anycast (speed.cloudflare.com)',
    this.clientFactory,
  });

  @override
  Stream<SpeedTestProgress> get progressStream => _progressController.stream;

  @override
  void cancel() {
    _isCancelled = true;
    try {
      _activeClient?.close(force: true);
      _activeClient = null;
    } catch (_) {}
    _emitProgress(
      const SpeedTestProgress(
        stage: SpeedTestStage.cancelled,
        statusMessage: 'Speed test cancelled by user',
      ),
    );
  }

  void _emitProgress(SpeedTestProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  @override
  Future<String> detectTransportType() async {
    // In Flutter test environment, avoid OS network interface queries that block FakeAsync
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return 'Wi-Fi';
    }
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: false,
      ).timeout(const Duration(seconds: 1), onTimeout: () => []);
      for (final iface in ifaces) {
        final name = iface.name.toLowerCase();
        if (name.startsWith('wlan') ||
            name.startsWith('wl') ||
            name.startsWith('wifi')) {
          return 'Wi-Fi';
        }
        if (name.startsWith('rmnet') ||
            name.startsWith('ccmni') ||
            name.startsWith('pdp') ||
            name.startsWith('cellular')) {
          return 'Cellular';
        }
        if (name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('wg') ||
            name.startsWith('ppp')) {
          return 'VPN';
        }
        if (name.startsWith('eth') || name.startsWith('en')) {
          return 'Ethernet';
        }
      }
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Future<SpeedTestResult> runTest({
    int downloadByteTarget = 15000000,
    int uploadByteTarget = 4000000,
    int latencyProbes = 5,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    _isCancelled = false;
    final transport = await detectTransportType();
    final client = clientFactory != null ? clientFactory!() : HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);
    _activeClient = client;

    final latencySamples = <double>[];
    double? medianLatencyMs;
    double? jitterMs;
    double? loadedLatencyMs;
    double? downloadSpeedMbps;
    double? uploadSpeedMbps;
    int totalDownloadBytes = 0;
    int totalUploadBytes = 0;
    int downloadDurationMs = 0;
    int uploadDurationMs = 0;
    String? errorMessage;

    try {
      // ----------------------------------------------------
      // PHASE 1: Idle Latency and Jitter
      // ----------------------------------------------------
      _emitProgress(
        const SpeedTestProgress(
          stage: SpeedTestStage.measuringLatency,
          statusMessage: 'Measuring idle latency and jitter...',
        ),
      );

      for (int i = 0; i < latencyProbes; i++) {
        if (_isCancelled) throw const _SpeedTestCancelledException();

        final sw = Stopwatch()..start();
        final uri = Uri.parse('$serverUrl/__down?bytes=0');
        final req = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 4));
        final resp = await req.close().timeout(const Duration(seconds: 4));
        await resp.drain().timeout(const Duration(seconds: 4));
        sw.stop();

        final sample = sw.elapsedMicroseconds / 1000.0;
        latencySamples.add(sample);

        final curSorted = List<double>.from(latencySamples)..sort();
        final curMedian = calculateMedian(curSorted);
        final curJitter = calculateJitter(latencySamples);

        _emitProgress(
          SpeedTestProgress(
            stage: SpeedTestStage.measuringLatency,
            progressPercent: (i + 1) / latencyProbes,
            currentLatencyMs: curMedian,
            currentJitterMs: curJitter,
            statusMessage:
                'Collected probe ${i + 1}/$latencyProbes: ${sample.toStringAsFixed(1)} ms',
          ),
        );
      }

      if (latencySamples.isNotEmpty) {
        final sorted = List<double>.from(latencySamples)..sort();
        medianLatencyMs = calculateMedian(sorted);
        jitterMs = calculateJitter(latencySamples);
      }

      // ----------------------------------------------------
      // PHASE 2: Download Throughput
      // ----------------------------------------------------
      if (_isCancelled) throw const _SpeedTestCancelledException();

      _emitProgress(
        SpeedTestProgress(
          stage: SpeedTestStage.measuringDownload,
          currentLatencyMs: medianLatencyMs,
          currentJitterMs: jitterMs,
          statusMessage: 'Testing download throughput...',
        ),
      );

      final downloadSw = Stopwatch();
      final downloadUri = Uri.parse(
        '$serverUrl/__down?bytes=$downloadByteTarget',
      );
      final dReq = await client
          .getUrl(downloadUri)
          .timeout(const Duration(seconds: 6));
      final dResp = await dReq.close().timeout(const Duration(seconds: 6));

      if (dResp.statusCode != 200) {
        throw HttpException(
          'Download server returned status ${dResp.statusCode}',
        );
      }

      downloadSw.start();
      int dBytesRecv = 0;
      DateTime lastEmitTime = DateTime.now();

      await for (final chunk in dResp) {
        if (_isCancelled) throw const _SpeedTestCancelledException();
        dBytesRecv += chunk.length;

        final now = DateTime.now();
        if (now.difference(lastEmitTime).inMilliseconds >= 100 ||
            dBytesRecv >= downloadByteTarget) {
          lastEmitTime = now;
          final sec = downloadSw.elapsedMicroseconds / 1000000.0;
          final curMbps = sec > 0.05
              ? calculateThroughputMbps(dBytesRecv, sec)
              : 0.0;
          _emitProgress(
            SpeedTestProgress(
              stage: SpeedTestStage.measuringDownload,
              currentSpeedMbps: curMbps,
              progressPercent: (dBytesRecv / downloadByteTarget).clamp(
                0.0,
                1.0,
              ),
              transferredBytes: dBytesRecv,
              totalExpectedBytes: downloadByteTarget,
              currentLatencyMs: medianLatencyMs,
              currentJitterMs: jitterMs,
              statusMessage: 'Downloading: ${curMbps.toStringAsFixed(1)} Mbps',
            ),
          );
        }
      }
      downloadSw.stop();

      final totalDownloadSec = downloadSw.elapsedMicroseconds / 1000000.0;
      totalDownloadBytes = dBytesRecv;
      downloadDurationMs = downloadSw.elapsedMilliseconds;

      if (totalDownloadSec > 0.1 && totalDownloadBytes > 50000) {
        downloadSpeedMbps = calculateThroughputMbps(
          totalDownloadBytes,
          totalDownloadSec,
        );
      } else {
        errorMessage =
            'Insufficient transfer bytes to measure download speed reliably';
      }

      // Optional loaded latency probe during transition
      try {
        final lSw = Stopwatch()..start();
        final lReq = await client
            .getUrl(Uri.parse('$serverUrl/__down?bytes=0'))
            .timeout(const Duration(seconds: 2));
        final lResp = await lReq.close().timeout(const Duration(seconds: 2));
        await lResp.drain().timeout(const Duration(seconds: 2));
        lSw.stop();
        loadedLatencyMs = lSw.elapsedMicroseconds / 1000.0;
      } catch (_) {
        loadedLatencyMs = null;
      }

      // ----------------------------------------------------
      // PHASE 3: Upload Throughput
      // ----------------------------------------------------
      if (_isCancelled) throw const _SpeedTestCancelledException();

      _emitProgress(
        SpeedTestProgress(
          stage: SpeedTestStage.measuringUpload,
          currentSpeedMbps: downloadSpeedMbps,
          currentLatencyMs: medianLatencyMs,
          currentJitterMs: jitterMs,
          statusMessage: 'Testing upload throughput...',
        ),
      );

      final uploadSw = Stopwatch();
      final uploadUri = Uri.parse('$serverUrl/__up');
      final uReq = await client
          .postUrl(uploadUri)
          .timeout(const Duration(seconds: 6));
      uReq.headers.set('Content-Type', 'application/octet-stream');
      uReq.contentLength = uploadByteTarget;

      // Stream bounded chunks reusing buffer without excessive memory allocation
      const chunkSize = 64 * 1024; // 64 KB
      final chunkBuffer = List<int>.filled(chunkSize, 0xaa);
      int uBytesSent = 0;
      DateTime lastUploadEmit = DateTime.now();

      uploadSw.start();
      while (uBytesSent < uploadByteTarget) {
        if (_isCancelled) throw const _SpeedTestCancelledException();
        final remaining = uploadByteTarget - uBytesSent;
        final toSend = remaining > chunkSize ? chunkSize : remaining;
        uReq.add(
          toSend == chunkSize ? chunkBuffer : chunkBuffer.sublist(0, toSend),
        );
        uBytesSent += toSend;

        final now = DateTime.now();
        if (now.difference(lastUploadEmit).inMilliseconds >= 100 ||
            uBytesSent >= uploadByteTarget) {
          lastUploadEmit = now;
          final sec = uploadSw.elapsedMicroseconds / 1000000.0;
          final curMbps = sec > 0.05
              ? calculateThroughputMbps(uBytesSent, sec)
              : 0.0;
          _emitProgress(
            SpeedTestProgress(
              stage: SpeedTestStage.measuringUpload,
              currentSpeedMbps: curMbps,
              progressPercent: (uBytesSent / uploadByteTarget).clamp(0.0, 1.0),
              transferredBytes: uBytesSent,
              totalExpectedBytes: uploadByteTarget,
              currentLatencyMs: medianLatencyMs,
              currentJitterMs: jitterMs,
              statusMessage: 'Uploading: ${curMbps.toStringAsFixed(1)} Mbps',
            ),
          );
        }
      }

      final uResp = await uReq.close().timeout(const Duration(seconds: 6));
      await uResp.drain().timeout(const Duration(seconds: 6));
      uploadSw.stop();

      if (uResp.statusCode != 200) {
        throw HttpException(
          'Upload server returned status ${uResp.statusCode}',
        );
      }

      final totalUploadSec = uploadSw.elapsedMicroseconds / 1000000.0;
      totalUploadBytes = uBytesSent;
      uploadDurationMs = uploadSw.elapsedMilliseconds;

      if (totalUploadSec > 0.1 && totalUploadBytes > 50000) {
        uploadSpeedMbps = calculateThroughputMbps(
          totalUploadBytes,
          totalUploadSec,
        );
      }

      final finalResult = SpeedTestResult(
        downloadSpeedMbps: downloadSpeedMbps,
        uploadSpeedMbps: uploadSpeedMbps,
        idleLatencyMs: medianLatencyMs,
        jitterMs: jitterMs,
        loadedLatencyMs: loadedLatencyMs,
        connectionType: transport,
        serverName: serverName,
        timestamp: DateTime.now(),
        downloadBytes: totalDownloadBytes,
        uploadBytes: totalUploadBytes,
        downloadDurationMs: downloadDurationMs,
        uploadDurationMs: uploadDurationMs,
        latencySamples: latencySamples,
        stage: SpeedTestStage.completed,
        errorMessage: errorMessage,
      );

      _emitProgress(
        SpeedTestProgress(
          stage: SpeedTestStage.completed,
          currentSpeedMbps: downloadSpeedMbps,
          progressPercent: 1.0,
          currentLatencyMs: medianLatencyMs,
          currentJitterMs: jitterMs,
          statusMessage: 'Speed test completed successfully',
        ),
      );

      return finalResult;
    } on _SpeedTestCancelledException {
      return SpeedTestResult(
        downloadSpeedMbps: downloadSpeedMbps,
        uploadSpeedMbps: uploadSpeedMbps,
        idleLatencyMs: medianLatencyMs,
        jitterMs: jitterMs,
        connectionType: transport,
        serverName: serverName,
        timestamp: DateTime.now(),
        downloadBytes: totalDownloadBytes,
        uploadBytes: totalUploadBytes,
        downloadDurationMs: downloadDurationMs,
        uploadDurationMs: uploadDurationMs,
        latencySamples: latencySamples,
        stage: SpeedTestStage.cancelled,
        errorMessage: 'Test cancelled by user',
      );
    } catch (e) {
      final errStr = e.toString();
      _emitProgress(
        SpeedTestProgress(
          stage: SpeedTestStage.failed,
          statusMessage: 'Speed test failed: $errStr',
        ),
      );

      return SpeedTestResult(
        downloadSpeedMbps: downloadSpeedMbps,
        uploadSpeedMbps: uploadSpeedMbps,
        idleLatencyMs: medianLatencyMs,
        jitterMs: jitterMs,
        loadedLatencyMs: loadedLatencyMs,
        connectionType: transport,
        serverName: serverName,
        timestamp: DateTime.now(),
        downloadBytes: totalDownloadBytes,
        uploadBytes: totalUploadBytes,
        downloadDurationMs: downloadDurationMs,
        uploadDurationMs: uploadDurationMs,
        latencySamples: latencySamples,
        stage: SpeedTestStage.failed,
        errorMessage: errStr,
      );
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
      if (_activeClient == client) _activeClient = null;
    }
  }

  @override
  Future<SpeedTestResult> runRouterSpeedTest({
    required IApiService api,
    required String routerIp,
    required String sysauth,
    bool useHttps = false,
    String? wanInterface,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    _isCancelled = false;

    double? medianLatencyMs;
    double? jitterMs;
    double? loadedLatencyMs;
    double? downloadSpeedMbps;
    double? uploadSpeedMbps;
    double? packetLossPercent;
    int totalDownloadBytes = 0;
    int totalUploadBytes = 0;
    int downloadDurationMs = 0;
    int uploadDurationMs = 0;
    List<double> latencySamples = [];
    String? errorMessage;

    try {
      // -----------------------------------------------------------------
      // 1. Idle Latency & Jitter via router ping probes
      // -----------------------------------------------------------------
      _emitProgress(
        const SpeedTestProgress(
          stage: SpeedTestStage.measuringLatency,
          progressPercent: 0.05,
          statusMessage: 'Measuring idle latency & jitter from router WAN...',
        ),
      );

      try {
        final pingRes = await api.executePing(
          routerIp,
          sysauth,
          useHttps,
          target: '1.1.1.1',
          count: 5,
          timeoutSec: 3,
        );

        if (pingRes.isSuccess && pingRes.replies.isNotEmpty) {
          latencySamples = pingRes.replies.map((r) => r.timeMs).toList();
          final sorted = List<double>.from(latencySamples)..sort();
          medianLatencyMs = calculateMedian(sorted);
          jitterMs = calculateJitter(latencySamples);
          packetLossPercent = pingRes.packetLossPercent;
        } else {
          medianLatencyMs = pingRes.avgRttMs ?? pingRes.minRttMs;
          packetLossPercent = pingRes.packetLossPercent;
        }
      } catch (_) {}

      if (_isCancelled) {
        return SpeedTestResult(
          vantagePoint: 'Router Internet Speed Test (WAN)',
          connectionType: 'Router WAN (${wanInterface ?? 'wan'})',
          serverName: serverName,
          timestamp: DateTime.now(),
          stage: SpeedTestStage.cancelled,
          errorMessage: 'Test cancelled by user',
        );
      }

      // -----------------------------------------------------------------
      // 2. Download Throughput (Multi-stage: Warmup -> Progressive Sustained)
      // -----------------------------------------------------------------
      _emitProgress(
        SpeedTestProgress(
          stage: SpeedTestStage.measuringDownload,
          progressPercent: 0.15,
          currentLatencyMs: medianLatencyMs,
          currentJitterMs: jitterMs,
          statusMessage: 'Warming up TCP window buffer (10 MB)...',
        ),
      );

      final downloadSamples = <_TransferSample>[];

      // Pass 1: Warmup & TCP slow-start (10 MB)
      final warmupSample = await _executeRouterDownload(
        api,
        routerIp,
        sysauth,
        useHttps,
        10000000,
      );

      if (_isCancelled) {
        return SpeedTestResult(
          idleLatencyMs: medianLatencyMs,
          jitterMs: jitterMs,
          vantagePoint: 'Router Internet Speed Test (WAN)',
          connectionType: 'Router WAN (${wanInterface ?? 'wan'})',
          serverName: serverName,
          timestamp: DateTime.now(),
          stage: SpeedTestStage.cancelled,
          errorMessage: 'Test cancelled by user',
        );
      }

      if (warmupSample != null && warmupSample.speedMbps > 0) {
        downloadSamples.add(warmupSample);

        final warmupSpeed = warmupSample.speedMbps;

        // Adaptive chunk sizing based on initial line throughput
        int chunk1Bytes = 25000000; // 25 MB
        int chunk2Bytes = 25000000; // 25 MB
        int chunk3Bytes = 50000000; // 50 MB

        if (warmupSpeed >= 120.0) {
          chunk1Bytes = 25000000; // 25 MB
          chunk2Bytes = 25000000; // 25 MB
          chunk3Bytes = 50000000; // 50 MB
        } else if (warmupSpeed >= 35.0) {
          chunk1Bytes = 15000000; // 15 MB
          chunk2Bytes = 25000000; // 25 MB
          chunk3Bytes = 35000000; // 35 MB
        } else {
          chunk1Bytes = 8000000; // 8 MB
          chunk2Bytes = 12000000; // 12 MB
          chunk3Bytes = 15000000; // 15 MB
        }

        // Pass 2: Steady-state sample 1
        _emitProgress(
          SpeedTestProgress(
            stage: SpeedTestStage.measuringDownload,
            progressPercent: 0.30,
            currentSpeedMbps: warmupSample.speedMbps,
            transferredBytes: warmupSample.bytes,
            totalExpectedBytes:
                warmupSample.bytes + chunk1Bytes + chunk2Bytes + chunk3Bytes,
            currentLatencyMs: medianLatencyMs,
            currentJitterMs: jitterMs,
            statusMessage:
                'TCP window primed (${warmupSample.speedMbps.toStringAsFixed(1)} Mbps). Testing sustained download (Stage 1/3)...',
          ),
        );

        final chunk1Sample = await _executeRouterDownload(
          api,
          routerIp,
          sysauth,
          useHttps,
          chunk1Bytes,
        );

        if (_isCancelled) {
          return SpeedTestResult(
            downloadSpeedMbps: warmupSample.speedMbps,
            idleLatencyMs: medianLatencyMs,
            jitterMs: jitterMs,
            vantagePoint: 'Router Internet Speed Test (WAN)',
            connectionType: 'Router WAN (${wanInterface ?? 'wan'})',
            serverName: serverName,
            timestamp: DateTime.now(),
            stage: SpeedTestStage.cancelled,
            errorMessage: 'Test cancelled by user',
          );
        }

        if (chunk1Sample != null && chunk1Sample.speedMbps > 0) {
          downloadSamples.add(chunk1Sample);
          final currentBest = [
            warmupSample.speedMbps,
            chunk1Sample.speedMbps,
          ].reduce((a, b) => a > b ? a : b);

          _emitProgress(
            SpeedTestProgress(
              stage: SpeedTestStage.measuringDownload,
              progressPercent: 0.45,
              currentSpeedMbps: currentBest,
              transferredBytes: warmupSample.bytes + chunk1Sample.bytes,
              totalExpectedBytes:
                  warmupSample.bytes + chunk1Bytes + chunk2Bytes + chunk3Bytes,
              currentLatencyMs: medianLatencyMs,
              currentJitterMs: jitterMs,
              statusMessage:
                  'Measuring steady-state throughput: ${currentBest.toStringAsFixed(1)} Mbps (Stage 2/3)...',
            ),
          );

          // Pass 3: Steady-state sample 2 (only if chunk 1 did not take excessive time > 6s)
          if (chunk1Sample.durationSec < 6.0) {
            final chunk2Sample = await _executeRouterDownload(
              api,
              routerIp,
              sysauth,
              useHttps,
              chunk2Bytes,
            );

            if (_isCancelled) {
              return SpeedTestResult(
                downloadSpeedMbps: currentBest,
                idleLatencyMs: medianLatencyMs,
                jitterMs: jitterMs,
                vantagePoint: 'Router Internet Speed Test (WAN)',
                connectionType: 'Router WAN (${wanInterface ?? 'wan'})',
                serverName: serverName,
                timestamp: DateTime.now(),
                stage: SpeedTestStage.cancelled,
                errorMessage: 'Test cancelled by user',
              );
            }

            if (chunk2Sample != null && chunk2Sample.speedMbps > 0) {
              downloadSamples.add(chunk2Sample);
              final updatedBest = [
                currentBest,
                chunk2Sample.speedMbps,
              ].reduce((a, b) => a > b ? a : b);

              _emitProgress(
                SpeedTestProgress(
                  stage: SpeedTestStage.measuringDownload,
                  progressPercent: 0.58,
                  currentSpeedMbps: updatedBest,
                  transferredBytes:
                      warmupSample.bytes +
                      chunk1Sample.bytes +
                      chunk2Sample.bytes,
                  totalExpectedBytes:
                      warmupSample.bytes +
                      chunk1Bytes +
                      chunk2Bytes +
                      chunk3Bytes,
                  currentLatencyMs: medianLatencyMs,
                  currentJitterMs: jitterMs,
                  statusMessage:
                      'Measuring peak saturation download: ${updatedBest.toStringAsFixed(1)} Mbps (Stage 3/3)...',
                ),
              );

              // Pass 4: Maximum saturation sample 3 (only if chunk 2 took < 5s)
              if (chunk2Sample.durationSec < 5.0) {
                final chunk3Sample = await _executeRouterDownload(
                  api,
                  routerIp,
                  sysauth,
                  useHttps,
                  chunk3Bytes,
                );
                if (chunk3Sample != null && chunk3Sample.speedMbps > 0) {
                  downloadSamples.add(chunk3Sample);
                }
              }
            }
          }
        }
      } else {
        // Warmup failed, fallback single probe
        final fallbackSample = await _executeRouterDownload(
          api,
          routerIp,
          sysauth,
          useHttps,
          15000000,
        );
        if (fallbackSample != null && fallbackSample.speedMbps > 0) {
          downloadSamples.add(fallbackSample);
        } else {
          errorMessage = 'Router download measurement failed';
        }
      }

      if (_isCancelled) {
        return SpeedTestResult(
          idleLatencyMs: medianLatencyMs,
          jitterMs: jitterMs,
          vantagePoint: 'Router Internet Speed Test (WAN)',
          connectionType: 'Router WAN (${wanInterface ?? 'wan'})',
          serverName: serverName,
          timestamp: DateTime.now(),
          stage: SpeedTestStage.cancelled,
          errorMessage: 'Test cancelled by user',
        );
      }

      // Calculate final sustained download speed (90th percentile standard)
      if (downloadSamples.isNotEmpty) {
        totalDownloadBytes = downloadSamples
            .map((s) => s.bytes)
            .reduce((a, b) => a + b);
        final totalSec = downloadSamples
            .map((s) => s.durationSec)
            .reduce((a, b) => a + b);
        downloadDurationMs = (totalSec * 1000).toInt();

        final speeds = downloadSamples.map((s) => s.speedMbps).toList();
        downloadSpeedMbps = calculatePercentile(speeds, 0.90);
      }

      // Optional loaded ping probe during network activity
      try {
        final lPing = await api.executePing(
          routerIp,
          sysauth,
          useHttps,
          target: '1.1.1.1',
          count: 2,
          timeoutSec: 2,
        );
        if (lPing.isSuccess) {
          loadedLatencyMs = lPing.avgRttMs ?? lPing.minRttMs;
        }
      } catch (_) {}

      // -----------------------------------------------------------------
      // 3. Upload Throughput (Multi-stage: Warmup -> Progressive Sustained)
      // -----------------------------------------------------------------
      _emitProgress(
        SpeedTestProgress(
          stage: SpeedTestStage.measuringUpload,
          progressPercent: 0.68,
          currentSpeedMbps: downloadSpeedMbps,
          currentLatencyMs: medianLatencyMs,
          currentJitterMs: jitterMs,
          statusMessage: 'Warming up upload stream (10 MB)...',
        ),
      );

      final uploadSamples = <_TransferSample>[];

      // Upload Pass 1: Warmup (10 MB = 10,485,760 bytes)
      final uploadWarmup = await _executeRouterUpload(
        api,
        routerIp,
        sysauth,
        useHttps,
        10485760,
      );

      if (_isCancelled) {
        return SpeedTestResult(
          downloadSpeedMbps: downloadSpeedMbps,
          idleLatencyMs: medianLatencyMs,
          jitterMs: jitterMs,
          loadedLatencyMs: loadedLatencyMs,
          vantagePoint: 'Router Internet Speed Test (WAN)',
          connectionType: 'Router WAN (${wanInterface ?? 'wan'})',
          serverName: serverName,
          timestamp: DateTime.now(),
          stage: SpeedTestStage.cancelled,
          errorMessage: 'Test cancelled by user',
        );
      }

      if (uploadWarmup != null && uploadWarmup.speedMbps > 0) {
        uploadSamples.add(uploadWarmup);

        _emitProgress(
          SpeedTestProgress(
            stage: SpeedTestStage.measuringUpload,
            progressPercent: 0.78,
            currentSpeedMbps: uploadWarmup.speedMbps,
            transferredBytes: uploadWarmup.bytes,
            totalExpectedBytes: 60000000,
            currentLatencyMs: medianLatencyMs,
            currentJitterMs: jitterMs,
            statusMessage:
                'Upload stream primed (${uploadWarmup.speedMbps.toStringAsFixed(1)} Mbps). Testing sustained upload (Stage 1/2)...',
          ),
        );

        // Adaptive upload chunk size
        int upload2Bytes = 20971520; // 20 MB
        int upload3Bytes = 31457280; // 30 MB
        if (uploadWarmup.speedMbps < 25.0) {
          upload2Bytes = 5242880; // 5 MB
          upload3Bytes = 10485760; // 10 MB
        } else if (uploadWarmup.speedMbps < 60.0) {
          upload2Bytes = 15728640; // 15 MB
          upload3Bytes = 20971520; // 20 MB
        }

        // Upload Pass 2: Steady-state sample 1
        final uploadChunk1 = await _executeRouterUpload(
          api,
          routerIp,
          sysauth,
          useHttps,
          upload2Bytes,
        );

        if (_isCancelled) {
          return SpeedTestResult(
            downloadSpeedMbps: downloadSpeedMbps,
            uploadSpeedMbps: uploadWarmup.speedMbps,
            idleLatencyMs: medianLatencyMs,
            jitterMs: jitterMs,
            loadedLatencyMs: loadedLatencyMs,
            vantagePoint: 'Router Internet Speed Test (WAN)',
            connectionType: 'Router WAN (${wanInterface ?? 'wan'})',
            serverName: serverName,
            timestamp: DateTime.now(),
            stage: SpeedTestStage.cancelled,
            errorMessage: 'Test cancelled by user',
          );
        }

        if (uploadChunk1 != null && uploadChunk1.speedMbps > 0) {
          uploadSamples.add(uploadChunk1);
          final currentUpBest = [
            uploadWarmup.speedMbps,
            uploadChunk1.speedMbps,
          ].reduce((a, b) => a > b ? a : b);

          _emitProgress(
            SpeedTestProgress(
              stage: SpeedTestStage.measuringUpload,
              progressPercent: 0.88,
              currentSpeedMbps: currentUpBest,
              transferredBytes: uploadWarmup.bytes + uploadChunk1.bytes,
              totalExpectedBytes:
                  uploadWarmup.bytes + upload2Bytes + upload3Bytes,
              currentLatencyMs: medianLatencyMs,
              currentJitterMs: jitterMs,
              statusMessage:
                  'Measuring peak sustained upload: ${currentUpBest.toStringAsFixed(1)} Mbps (Stage 2/2)...',
            ),
          );

          if (uploadChunk1.durationSec < 6.0) {
            final uploadChunk2 = await _executeRouterUpload(
              api,
              routerIp,
              sysauth,
              useHttps,
              upload3Bytes,
            );
            if (uploadChunk2 != null && uploadChunk2.speedMbps > 0) {
              uploadSamples.add(uploadChunk2);
            }
          }
        }
      }

      if (uploadSamples.isNotEmpty) {
        totalUploadBytes = uploadSamples
            .map((s) => s.bytes)
            .reduce((a, b) => a + b);
        final totalUpSec = uploadSamples
            .map((s) => s.durationSec)
            .reduce((a, b) => a + b);
        uploadDurationMs = (totalUpSec * 1000).toInt();

        final upSpeeds = uploadSamples.map((s) => s.speedMbps).toList();
        uploadSpeedMbps = calculatePercentile(upSpeeds, 0.90);
      }

      // -----------------------------------------------------------------
      // 4. Completed Result
      // -----------------------------------------------------------------
      final finalResult = SpeedTestResult(
        downloadSpeedMbps: downloadSpeedMbps,
        uploadSpeedMbps: uploadSpeedMbps,
        idleLatencyMs: medianLatencyMs,
        jitterMs: jitterMs,
        loadedLatencyMs: loadedLatencyMs,
        packetLossPercent: packetLossPercent,
        connectionType: 'Router WAN (${wanInterface ?? 'wan'})',
        vantagePoint: 'Router Internet Speed Test (WAN)',
        serverName: serverName,
        timestamp: DateTime.now(),
        downloadBytes: totalDownloadBytes,
        uploadBytes: totalUploadBytes,
        downloadDurationMs: downloadDurationMs,
        uploadDurationMs: uploadDurationMs,
        latencySamples: latencySamples,
        stage: downloadSpeedMbps != null
            ? SpeedTestStage.completed
            : SpeedTestStage.failed,
        errorMessage: errorMessage,
      );

      _emitProgress(
        SpeedTestProgress(
          stage: finalResult.stage,
          currentSpeedMbps: downloadSpeedMbps,
          progressPercent: 1.0,
          currentLatencyMs: medianLatencyMs,
          currentJitterMs: jitterMs,
          statusMessage: finalResult.stage == SpeedTestStage.completed
              ? 'Router speed test completed successfully'
              : (errorMessage ?? 'Router speed test failed'),
        ),
      );

      return finalResult;
    } finally {
      // Ensure any temporary test buffer in OpenWrt RAM /tmp is cleaned up
      try {
        await _callFileExec(api, routerIp, sysauth, useHttps, '/bin/sh', [
          '-c',
          'rm -f /tmp/speed_up.bin',
        ]);
      } catch (_) {}
    }
  }

  Future<_TransferSample?> _executeRouterDownload(
    IApiService api,
    String routerIp,
    String sysauth,
    bool useHttps,
    int targetBytes,
  ) async {
    final httpUrl = serverUrl.startsWith('https://')
        ? 'http://${serverUrl.substring(8)}/__down?bytes=$targetBytes'
        : '$serverUrl/__down?bytes=$targetBytes';
    final httpsUrl = serverUrl.startsWith('http://')
        ? 'https://${serverUrl.substring(7)}/__down?bytes=$targetBytes'
        : '$serverUrl/__down?bytes=$targetBytes';

    // 1. Try curl with HTTP first (avoids software AES crypto overhead on embedded router CPUs)
    for (final url in [httpUrl, httpsUrl]) {
      try {
        final curlExec = await _callFileExec(
          api,
          routerIp,
          sysauth,
          useHttps,
          '/bin/sh',
          [
            '-c',
            'curl --insecure -s -w "%{time_total} %{time_starttransfer} %{size_download} %{speed_download} %{http_code}" -o /dev/null "$url"',
          ],
        );

        if (curlExec != null && curlExec['code'] == 0) {
          final stdout = (curlExec['stdout'] as String? ?? '').trim();
          final parts = stdout.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final timeTotalSec = double.tryParse(parts[0]) ?? 0.0;
            final timeStartTransferSec = double.tryParse(parts[1]) ?? 0.0;
            final sizeDownload = int.tryParse(parts[2]) ?? targetBytes;
            final speedBytesSec = double.tryParse(parts[3]) ?? 0.0;
            final httpCode = parts.length >= 5
                ? int.tryParse(parts[4]) ?? 200
                : 200;

            if (httpCode == 200 &&
                timeTotalSec > 0.05 &&
                (sizeDownload > 0 || speedBytesSec > 0)) {
              final wireDuration = timeTotalSec - timeStartTransferSec;
              final mbps = wireDuration > 0.02 && sizeDownload > 0
                  ? (sizeDownload * 8.0) / (wireDuration * 1000000.0)
                  : (speedBytesSec * 8.0) / 1000000.0;

              return _TransferSample(
                bytes: sizeDownload > 0 ? sizeDownload : targetBytes,
                durationSec: wireDuration > 0.02 ? wireDuration : timeTotalSec,
                speedMbps: mbps,
              );
            }
          }
        }
      } catch (_) {}
    }

    // 2. Fallback to wget if curl is unavailable or failed
    for (final url in [httpUrl, httpsUrl]) {
      try {
        final sw = Stopwatch()..start();
        final wgetExec = await _callFileExec(
          api,
          routerIp,
          sysauth,
          useHttps,
          '/bin/sh',
          ['-c', 'wget --no-check-certificate -q -O /dev/null "$url"'],
        );
        sw.stop();

        if (wgetExec != null && wgetExec['code'] == 0) {
          final sec = sw.elapsedMicroseconds / 1000000.0;
          if (sec > 0.05) {
            final mbps = calculateThroughputMbps(targetBytes, sec);
            return _TransferSample(
              bytes: targetBytes,
              durationSec: sec,
              speedMbps: mbps,
            );
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<_TransferSample?> _executeRouterUpload(
    IApiService api,
    String routerIp,
    String sysauth,
    bool useHttps,
    int targetBytes,
  ) async {
    final httpUpUrl = serverUrl.startsWith('https://')
        ? 'http://${serverUrl.substring(8)}/__up'
        : '$serverUrl/__up';
    final httpsUpUrl = serverUrl.startsWith('http://')
        ? 'https://${serverUrl.substring(7)}/__up'
        : '$serverUrl/__up';

    int sizeMb = (targetBytes / (1024 * 1024)).round();
    if (sizeMb < 1) sizeMb = 1;

    // 1. Try RAM tmpfs buffer upload with curl (fastest, zero pipe context-switching, known Content-Length)
    for (final url in [httpUpUrl, httpsUpUrl]) {
      try {
        final uploadExec = await _callFileExec(
          api,
          routerIp,
          sysauth,
          useHttps,
          '/bin/sh',
          [
            '-c',
            'dd if=/dev/zero of=/tmp/speed_up.bin bs=1M count=$sizeMb 2>/dev/null && curl --insecure -s -w "%{time_total} %{time_starttransfer} %{size_upload} %{speed_upload} %{http_code}" -X POST -H "Content-Type: application/octet-stream" --data-binary @/tmp/speed_up.bin -o /dev/null "$url" && rm -f /tmp/speed_up.bin',
          ],
        );

        if (uploadExec != null && uploadExec['code'] == 0) {
          final stdout = (uploadExec['stdout'] as String? ?? '').trim();
          final parts = stdout.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final timeTotalSec = double.tryParse(parts[0]) ?? 0.0;
            final timeStartTransferSec = double.tryParse(parts[1]) ?? 0.0;
            final sizeUpload = int.tryParse(parts[2]) ?? (sizeMb * 1024 * 1024);
            final speedBytesSec = double.tryParse(parts[3]) ?? 0.0;
            final httpCode = parts.length >= 5
                ? int.tryParse(parts[4]) ?? 200
                : 200;

            if (httpCode == 200 &&
                timeTotalSec > 0.05 &&
                (sizeUpload > 0 || speedBytesSec > 0)) {
              final wireDuration = timeTotalSec - timeStartTransferSec;
              final mbps = wireDuration > 0.02 && sizeUpload > 0
                  ? (sizeUpload * 8.0) / (wireDuration * 1000000.0)
                  : (speedBytesSec * 8.0) / 1000000.0;

              return _TransferSample(
                bytes: sizeUpload,
                durationSec: wireDuration > 0.02 ? wireDuration : timeTotalSec,
                speedMbps: mbps,
              );
            }
          }
        }
      } catch (_) {}
    }

    // 2. Fallback to piped streaming if RAM buffer creation failed
    final count64k = (targetBytes / (64 * 1024)).round().clamp(16, 512);
    try {
      final uploadExec = await _callFileExec(
        api,
        routerIp,
        sysauth,
        useHttps,
        '/bin/sh',
        [
          '-c',
          'dd if=/dev/zero bs=64k count=$count64k 2>/dev/null | curl --insecure -s -w "%{time_total} %{time_starttransfer} %{size_upload} %{speed_upload} %{http_code}" --data-binary @- -o /dev/null "$httpUpUrl"',
        ],
      );

      if (uploadExec != null && uploadExec['code'] == 0) {
        final stdout = (uploadExec['stdout'] as String? ?? '').trim();
        final parts = stdout.split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final timeTotalSec = double.tryParse(parts[0]) ?? 0.0;
          final timeStartTransferSec = double.tryParse(parts[1]) ?? 0.0;
          final sizeUpload = int.tryParse(parts[2]) ?? (count64k * 64 * 1024);
          final speedBytesSec = double.tryParse(parts[3]) ?? 0.0;
          final httpCode = parts.length >= 5
              ? int.tryParse(parts[4]) ?? 200
              : 200;

          if (httpCode == 200 &&
              timeTotalSec > 0.05 &&
              (sizeUpload > 0 || speedBytesSec > 0)) {
            final wireDuration = timeTotalSec - timeStartTransferSec;
            final mbps = wireDuration > 0.02 && sizeUpload > 0
                ? (sizeUpload * 8.0) / (wireDuration * 1000000.0)
                : (speedBytesSec * 8.0) / 1000000.0;

            return _TransferSample(
              bytes: sizeUpload,
              durationSec: wireDuration > 0.02 ? wireDuration : timeTotalSec,
              speedMbps: mbps,
            );
          }
        }
      }
    } catch (_) {}

    return null;
  }

  Future<Map<String, dynamic>?> _callFileExec(
    IApiService api,
    String routerIp,
    String sysauth,
    bool useHttps,
    String command,
    List<String> args,
  ) async {
    try {
      final res = await api.call(
        routerIp,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: RealApiService.fileExecParams(command, args),
      );
      if (res is List && res.length > 1 && res[0] == 0 && res[1] is Map) {
        return Map<String, dynamic>.from(res[1] as Map);
      }
    } catch (_) {}

    try {
      final res = await api.call(
        routerIp,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: RealApiService.fileExecArgs(command, args),
      );
      if (res is List && res.length > 1 && res[0] == 0 && res[1] is Map) {
        return Map<String, dynamic>.from(res[1] as Map);
      }
    } catch (_) {}

    return null;
  }

  /// Calculates throughput in Megabits per second (decimal bits / 1,000,000).
  static double calculateThroughputMbps(int bytes, double durationSeconds) {
    if (durationSeconds <= 0) return 0.0;
    return (bytes * 8.0) / (durationSeconds * 1000000.0);
  }

  /// Robust median calculation for sorted sample list.
  static double calculateMedian(List<double> sorted) {
    if (sorted.isEmpty) return 0.0;
    final middle = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[middle];
    } else {
      return (sorted[middle - 1] + sorted[middle]) / 2.0;
    }
  }

  /// Calculates the given percentile (e.g., 0.90 for 90th percentile) from a sample list.
  static double calculatePercentile(List<double> samples, double percentile) {
    if (samples.isEmpty) return 0.0;
    final sorted = List<double>.from(samples)..sort();
    if (sorted.length == 1) return sorted.first;
    final rank = (sorted.length - 1) * percentile.clamp(0.0, 1.0);
    final lower = rank.floor();
    final upper = rank.ceil();
    if (lower == upper) return sorted[lower];
    final weight = rank - lower;
    return sorted[lower] * (1.0 - weight) + sorted[upper] * weight;
  }

  /// Calculates RFC-standard latency jitter: sum(|sample[i] - sample[i-1]|) / (N - 1).
  static double calculateJitter(List<double> samples) {
    if (samples.length < 2) return 0.0;
    double diffSum = 0.0;
    for (int i = 1; i < samples.length; i++) {
      diffSum += (samples[i] - samples[i - 1]).abs();
    }
    return diffSum / (samples.length - 1);
  }
}

class _SpeedTestCancelledException implements Exception {
  const _SpeedTestCancelledException();
}

class _TransferSample {
  final int bytes;
  final double durationSec;
  final double speedMbps;

  const _TransferSample({
    required this.bytes,
    required this.durationSec,
    required this.speedMbps,
  });
}
