import 'package:flutter_test/flutter_test.dart';
import 'package:yala/services/throughput_service.dart';
import 'package:yala/state/controllers/throughput_controller.dart';

void main() {
  final dump = {
    'interface': [
      {'interface': 'loopback', 'device': 'lo', 'l3_device': 'lo'},
      {'interface': 'lan', 'proto': 'static', 'l3_device': 'br-lan'},
      {
        'interface': 'wwan',
        'proto': 'dhcp',
        'device': 'phy0-sta0',
        'l3_device': 'phy0-sta0',
        'route': [
          {'target': '0.0.0.0', 'mask': 0},
        ],
      },
    ],
  };

  test('wwan STA uplink is resolved as WAN', () {
    expect(ThroughputController.resolveThroughputDeviceNames(dump), {
      'phy0-sta0',
    });
  });

  test(
    'unmatched resolved names fall back to STA device instead of zero',
    () async {
      final svc = ThroughputService();
      Map<String, dynamic> snap(int rx) => {
        'phy0-sta0': {
          'stats': {'rx_bytes': rx, 'tx_bytes': rx},
        },
        'br-lan': {
          'stats': {'rx_bytes': 5, 'tx_bytes': 5},
        },
      };
      svc.updateThroughput(snap(1000), {'nonexistent0'});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      svc.updateThroughput(snap(1000 + 30000), {'nonexistent0'});
      expect(svc.currentRxRate, greaterThan(0));
    },
  );
}
