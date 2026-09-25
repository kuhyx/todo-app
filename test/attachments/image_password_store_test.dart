import 'package:flutter_test/flutter_test.dart';
import 'package:todo/attachments/image_password_store.dart';

import '../fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = ImagePasswordStore();

  test('write, read, login and delete', () async {
    installFakeSecureStorage();
    expect(await store.read(), '');
    expect(await store.login(), isNull);
    expect(await store.write('pw'), isTrue);
    expect(await store.read(), 'pw');
    final login = (await store.login())!;
    expect((login.user, login.password), (kDufsImagesUser, 'pw'));
    expect(await store.write(''), isTrue);
    expect(await store.read(), '');
  });

  test('a missing keystore reads as no password and refuses writes', () async {
    installFakeSecureStorage(throwing: true);
    expect(await store.read(), '');
    expect(await store.write('pw'), isFalse);
  });
}
