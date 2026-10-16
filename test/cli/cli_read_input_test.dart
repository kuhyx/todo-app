import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_runner.dart';

void main() {
  group('readInput', () {
    test('returns empty for an interactive terminal', () async {
      expect(await readInput(const Stream.empty(), hasTerminal: true), '');
    });

    test('decodes the whole stream and trims trailing whitespace', () async {
      final input = Stream<List<int>>.fromIterable([
        utf8.encode('ab'),
        utf8.encode('c\n\n'),
      ]);
      expect(await readInput(input, hasTerminal: false), 'abc');
    });
  });
}
