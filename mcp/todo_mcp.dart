import 'dart:async';
import 'dart:io';

import 'package:todo/mcp/mcp_main.dart';

Future<void> main() async {
  final stop = await startTodoMcp(Platform.environment, stderr);
  if (stop == null) exit(1);
  await Future.any([
    ProcessSignal.sigterm.watch().first,
    ProcessSignal.sigint.watch().first,
  ]);
  await stop();
  exit(0);
}
