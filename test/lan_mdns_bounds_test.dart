import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/lan_mdns_service.dart';

void main() {
  test('mDNS address filtering keeps at most eight LAN literals', () {
    final values = [
      '8.8.8.8',
      'example.test',
      ...List.generate(10, (index) => '192.168.1.${index + 1}'),
    ];
    final addresses = LanMdnsService.validatedAddresses(values);

    expect(addresses, hasLength(8));
    expect(addresses, everyElement(startsWith('192.168.1.')));
  });
}
