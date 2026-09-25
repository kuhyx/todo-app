import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:todo/desktop/dufs_login_env.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dufs_env'));
  tearDown(() => dir.deleteSync(recursive: true));

  File env(String body) =>
      File(p.join(dir.path, 'todo.env'))..writeAsStringSync(body);

  test('default path is ~/.config/dufs/logins/todo.env', () {
    expect(defaultDufsLoginEnvPath('/h'), '/h/.config/dufs/logins/todo.env');
  });

  test('reads the login add_dufs_login.sh writes', () {
    final login = readDufsLoginEnv(
      env(
        '# written by add_dufs_login.sh\n'
        'DUFS_URL=https://kuhy-cloud.duckdns.org/\n'
        'DUFS_USER=todo\nDUFS_PASSWORD=a=b\nDUFS_PATH=/todo-images\nnoise\n',
      ),
    )!;
    expect(login.user, 'todo');
    expect(login.password, 'a=b', reason: 'only the first = splits');
    expect(login.baseUrl, 'https://kuhy-cloud.duckdns.org');
  });

  test('keeps a url without a trailing slash as is', () {
    final login = readDufsLoginEnv(
      env('DUFS_URL=http://x\nDUFS_USER=u\nDUFS_PASSWORD=p\n'),
    )!;
    expect(login.baseUrl, 'http://x');
  });

  test('absent or incomplete files give no login', () {
    expect(readDufsLoginEnv(File(p.join(dir.path, 'nope.env'))), isNull);
    expect(readDufsLoginEnv(env('DUFS_USER=u\nDUFS_PASSWORD=p\n')), isNull);
    expect(readDufsLoginEnv(env('DUFS_URL=x\nDUFS_USER=u\n')), isNull);
    expect(readDufsLoginEnv(env('DUFS_URL=x\nDUFS_PASSWORD=p\n')), isNull);
  });
}
