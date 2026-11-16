// The unit mcp/install.sh installs must lift the 1024-fd soft limit: the
// 2026-11-16 outage ended with the process at 1023 of 1024 fds.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('[T-nofile] the installed unit raises LimitNOFILE', () {
    final unit = File('mcp/todo-mcp.service').readAsStringSync();
    expect(unit, matches(RegExp(r'^LimitNOFILE=65536$', multiLine: true)));
    final service = unit.split('[Service]')[1].split('[Install]').first;
    expect(service, contains('LimitNOFILE=65536'), reason: 'in [Service]');
    expect(
      File('mcp/install.sh').readAsStringSync(),
      contains(r'install -m 644 "$ROOT/mcp/$UNIT"'),
      reason: 'install.sh ships this very file',
    );
  });
}
