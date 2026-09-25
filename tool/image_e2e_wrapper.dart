// A throwaway desktop wrapper for end-to-end runs of the web build, on a
// port and HOME of its own, so a test page can never write the real
// BACKLOG.md, note-log copy or image cache (the page talks only to the
// wrapper that served it; see servingWrapperOrigin).
//
//   HOME=$(mktemp -d) dart run tool/image_e2e_wrapper.dart \
//       --port 8731 --web-root build/web
//
// Images use $HOME/.local/share/todo-desktop/images and the login in
// $HOME/.config/dufs/logins/todo.env, exactly like the real wrapper.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:todo/desktop/wrapper_server.dart';

Future<void> main(List<String> args) async {
  String arg(String name, String fallback) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final home = Platform.environment['HOME']!;
  final port = int.parse(arg('--port', '8731'));
  final server = WrapperServer(
    webRoot: p.absolute(arg('--web-root', 'build/web')),
    // The real wrapper's layout, under the throwaway HOME.
    backlogPath: defaultBacklogPath(home),
    logPath: p.join(home, '.local', 'share', 'todo-desktop', 'todo_notes.json'),
  );
  await server.start(port);
  stdout.writeln('e2e wrapper on http://localhost:$port (HOME=$home)');
}
