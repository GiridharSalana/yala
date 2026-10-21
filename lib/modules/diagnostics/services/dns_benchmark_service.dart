// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../../../services/interfaces/api_service_interface.dart';
import '../models/dns_benchmark_models.dart';
import 'dns_packet_codec.dart';

/// Abstract contract for DNS latency benchmarking.
abstract class IDnsBenchmarkService {
  /// Measures latency for a specific DNS resolver endpoint.
  Future<DnsBenchmarkResult> benchmarkProvider({
    required DnsProviderMetadata provider,
    required DnsVantagePoint vantagePoint,
    required DnsProtocol protocol,
    int sampleCount = 3,
    Duration timeout = const Duration(milliseconds: 2500),
    String? routerIp,
    String? routerSysauth,
    bool routerUseHttps = false,
  });

  /// Cancels any currently executing benchmark run.
  void cancel();
}

/// Production implementation of [IDnsBenchmarkService] supporting RFC 1035 UDP queries
/// and router-originated RPC nslookup queries.
class DnsBenchmarkService implements IDnsBenchmarkService {
  final IApiService? api;
  final List<String> testDomains;
  final Random _random = Random();
  bool _isCancelled = false;
  RawDatagramSocket? _activeSocket;

  DnsBenchmarkService({this.api, List<String>? testDomains})
    : testDomains =
          testDomains ??
          const ['cloudflare.com', 'google.com', 'wikipedia.org'];

  @override
  void cancel() {
    _isCancelled = true;
    try {
      _activeSocket?.close();
      _activeSocket = null;
    } catch (_) {}
  }

  @override
  Future<DnsBenchmarkResult> benchmarkProvider({
    required DnsProviderMetadata provider,
    required DnsVantagePoint vantagePoint,
    required DnsProtocol protocol,
    int sampleCount = 3,
    Duration timeout = const Duration(milliseconds: 2500),
    String? routerIp,
    String? routerSysauth,
    bool routerUseHttps = false,
  }) async {
    _isCancelled = false;

    if (vantagePoint == DnsVantagePoint.router) {
      return _benchmarkViaRouterRpc(
        provider: provider,
        sampleCount: sampleCount,
        timeout: timeout,
        routerIp: routerIp,
        routerSysauth: routerSysauth,
        routerUseHttps: routerUseHttps,
      );
    }

    // Default: Client-side UDP Port 53 queries
    return _benchmarkViaClientUdp(
      provider: provider,
      sampleCount: sampleCount,
      timeout: timeout,
    );
  }

  /// Executes RFC 1035 UDP DNS queries from the local device to [provider.primaryServer]:53.
  Future<DnsBenchmarkResult> _benchmarkViaClientUdp({
    required DnsProviderMetadata provider,
    required int sampleCount,
    required Duration timeout,
  }) async {
    final serverIp = provider.primaryServer.trim();
    InternetAddress targetAddress;
    try {
      targetAddress = InternetAddress(serverIp);
    } catch (e) {
      return DnsBenchmarkResult(
        provider: provider,
        status: DnsBenchmarkStatus.unreachable,
        testedEndpoint: '$serverIp:53',
        protocol: DnsProtocol.udpPort53,
        vantagePoint: DnsVantagePoint.clientDevice,
        errorMessage: 'Invalid resolver IP address: $e',
        timestamp: DateTime.now(),
      );
    }

    final successfulSamples = <double>[];
    int failedCount = 0;
    String? lastError;
    DnsBenchmarkStatus status = DnsBenchmarkStatus.success;

    for (int i = 0; i < sampleCount; i++) {
      if (_isCancelled) {
        return DnsBenchmarkResult(
          provider: provider,
          status: DnsBenchmarkStatus.untested,
          testedEndpoint: '$serverIp:53',
          protocol: DnsProtocol.udpPort53,
          vantagePoint: DnsVantagePoint.clientDevice,
          errorMessage: 'Benchmark cancelled by user',
          timestamp: DateTime.now(),
        );
      }

      final domain = testDomains[i % testDomains.length];
      final queryId = _random.nextInt(0xffff);
      final queryPacket = DnsPacketCodec.buildQuery(domain, queryId);

      RawDatagramSocket? socket;
      try {
        socket = await RawDatagramSocket.bind(
          targetAddress.type == InternetAddressType.IPv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4,
          0,
        );
        _activeSocket = socket;

        final completer = Completer<double>();
        final sw = Stopwatch()..start();

        final sub = socket.listen(
          (event) {
            if (event == RawSocketEvent.read) {
              final datagram = socket?.receive();
              if (datagram != null && datagram.data.length >= 12) {
                final resp = DnsPacketCodec.parseResponse(
                  datagram.data,
                  queryId,
                );
                if (resp.queryId == queryId) {
                  sw.stop();
                  if (resp.isSuccessfulResponse) {
                    final ms = sw.elapsedMicroseconds / 1000.0;
                    if (!completer.isCompleted) completer.complete(ms);
                  } else if (resp.rcode == 2) {
                    if (!completer.isCompleted) {
                      completer.completeError('Server Failure (RCODE 2)');
                    }
                  } else {
                    final ms = sw.elapsedMicroseconds / 1000.0;
                    if (!completer.isCompleted) completer.complete(ms);
                  }
                }
              }
            }
          },
          onError: (err) {
            if (!completer.isCompleted) completer.completeError(err);
          },
        );

        socket.send(queryPacket, targetAddress, 53);

        final sampleMs = await completer.future.timeout(
          timeout,
          onTimeout: () => throw TimeoutException('Query timed out'),
        );

        await sub.cancel();
        successfulSamples.add(sampleMs);
      } on TimeoutException {
        failedCount++;
        lastError = 'Query timed out after ${timeout.inMilliseconds}ms';
      } on SocketException catch (se) {
        failedCount++;
        lastError = 'Socket error: ${se.message}';
        if (se.osError?.errorCode == 111 ||
            se.message.toLowerCase().contains('refused')) {
          status = DnsBenchmarkStatus.refused;
        }
      } catch (e) {
        failedCount++;
        lastError = e.toString();
        if (e.toString().contains('Server Failure')) {
          status = DnsBenchmarkStatus.serverError;
        }
      } finally {
        try {
          socket?.close();
        } catch (_) {}
        if (_activeSocket == socket) _activeSocket = null;
      }
    }

    if (successfulSamples.isEmpty) {
      if (lastError != null && lastError.contains('timed out')) {
        status = DnsBenchmarkStatus.timeout;
      } else if (status == DnsBenchmarkStatus.success) {
        status = DnsBenchmarkStatus.unreachable;
      }

      return DnsBenchmarkResult(
        provider: provider,
        status: status,
        totalQueries: sampleCount,
        successfulQueries: 0,
        failedQueries: failedCount,
        testedEndpoint: '$serverIp:53',
        protocol: DnsProtocol.udpPort53,
        vantagePoint: DnsVantagePoint.clientDevice,
        errorMessage: lastError ?? 'All queries failed',
        timestamp: DateTime.now(),
      );
    }

    final finalStatus = failedCount > 0
        ? DnsBenchmarkStatus.partial
        : DnsBenchmarkStatus.success;

    final sorted = List<double>.from(successfulSamples)..sort();
    final median = calculateMedian(sorted);
    final min = sorted.first;
    final max = sorted.last;
    final avg = sorted.reduce((a, b) => a + b) / sorted.length;

    return DnsBenchmarkResult(
      provider: provider,
      status: finalStatus,
      medianLatencyMs: median,
      minLatencyMs: min,
      maxLatencyMs: max,
      avgLatencyMs: avg,
      samples: successfulSamples,
      totalQueries: sampleCount,
      successfulQueries: successfulSamples.length,
      failedQueries: failedCount,
      testedEndpoint: '$serverIp:53',
      protocol: DnsProtocol.udpPort53,
      vantagePoint: DnsVantagePoint.clientDevice,
      errorMessage: failedCount > 0 ? lastError : null,
      timestamp: DateTime.now(),
    );
  }

  /// Executes DNS queries directly from the OpenWrt router via RPC nslookup.
  Future<DnsBenchmarkResult> _benchmarkViaRouterRpc({
    required DnsProviderMetadata provider,
    required int sampleCount,
    required Duration timeout,
    String? routerIp,
    String? routerSysauth,
    bool routerUseHttps = false,
  }) async {
    final effectiveApi = api;
    if (effectiveApi == null || routerIp == null || routerSysauth == null) {
      return DnsBenchmarkResult(
        provider: provider,
        status: DnsBenchmarkStatus.unsupported,
        testedEndpoint: provider.primaryServer,
        protocol: DnsProtocol.routerNslookup,
        vantagePoint: DnsVantagePoint.router,
        errorMessage: 'Router API unavailable or router not connected',
        timestamp: DateTime.now(),
      );
    }

    final successfulSamples = <double>[];
    int failedCount = 0;
    String? lastError;

    for (int i = 0; i < sampleCount; i++) {
      if (_isCancelled) {
        return DnsBenchmarkResult(
          provider: provider,
          status: DnsBenchmarkStatus.untested,
          testedEndpoint: provider.primaryServer,
          protocol: DnsProtocol.routerNslookup,
          vantagePoint: DnsVantagePoint.router,
          errorMessage: 'Benchmark cancelled by user',
          timestamp: DateTime.now(),
        );
      }

      final domain = testDomains[i % testDomains.length];
      final targetServer = provider.isRouterDns ? null : provider.primaryServer;

      try {
        final sw = Stopwatch()..start();
        final lookupResult = await effectiveApi
            .executeDnsLookup(
              routerIp,
              routerSysauth,
              routerUseHttps,
              host: domain,
              server: targetServer,
            )
            .timeout(timeout);
        sw.stop();

        if (lookupResult.isSuccess) {
          final ms = sw.elapsedMicroseconds / 1000.0;
          successfulSamples.add(ms);
        } else {
          failedCount++;
          lastError = lookupResult.errorMessage ?? 'Router nslookup failed';
        }
      } on TimeoutException {
        failedCount++;
        lastError = 'Router nslookup timed out';
      } catch (e) {
        failedCount++;
        lastError = e.toString();
      }
    }

    if (successfulSamples.isEmpty) {
      return DnsBenchmarkResult(
        provider: provider,
        status: DnsBenchmarkStatus.timeout,
        totalQueries: sampleCount,
        successfulQueries: 0,
        failedQueries: failedCount,
        testedEndpoint: provider.primaryServer,
        protocol: DnsProtocol.routerNslookup,
        vantagePoint: DnsVantagePoint.router,
        errorMessage: lastError ?? 'All router DNS lookups failed',
        timestamp: DateTime.now(),
      );
    }

    final sorted = List<double>.from(successfulSamples)..sort();
    final median = calculateMedian(sorted);
    final min = sorted.first;
    final max = sorted.last;
    final avg = sorted.reduce((a, b) => a + b) / sorted.length;

    return DnsBenchmarkResult(
      provider: provider,
      status: failedCount > 0
          ? DnsBenchmarkStatus.partial
          : DnsBenchmarkStatus.success,
      medianLatencyMs: median,
      minLatencyMs: min,
      maxLatencyMs: max,
      avgLatencyMs: avg,
      samples: successfulSamples,
      totalQueries: sampleCount,
      successfulQueries: successfulSamples.length,
      failedQueries: failedCount,
      testedEndpoint: provider.primaryServer,
      protocol: DnsProtocol.routerNslookup,
      vantagePoint: DnsVantagePoint.router,
      errorMessage: failedCount > 0 ? lastError : null,
      timestamp: DateTime.now(),
    );
  }

  /// Calculates the robust median of an already sorted list of numbers.
  static double calculateMedian(List<double> sorted) {
    if (sorted.isEmpty) return 0.0;
    final middle = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[middle];
    } else {
      return (sorted[middle - 1] + sorted[middle]) / 2.0;
    }
  }
}
