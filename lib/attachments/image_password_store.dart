/// The phone's copy of the `todo` dufs login password, in the OS keystore.
///
/// Created on the PC by `add_dufs_login.sh todo /todo-images rw` and pasted
/// into Settings → Cloud images. The desktop never uses this: its wrapper
/// reads `~/.config/dufs/logins/todo.env` instead.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:todo/images/dufs_image_client.dart';

/// The login name `add_dufs_login.sh` was run with.
const kDufsImagesUser = 'todo';

/// Reads and writes the password; failures read as "no password".
class ImagePasswordStore {
  /// Creates a store over [storage] (injectable for tests).
  const ImagePasswordStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'dufsImagesPassword';

  /// The saved password, or '' when none is set or the keystore is
  /// unavailable.
  Future<String> read() async {
    try {
      return await _storage.read(key: _key) ?? '';
    } on Exception {
      return '';
    }
  }

  /// Saves [password] (an empty one deletes it); false if the keystore is
  /// unavailable.
  Future<bool> write(String password) async {
    try {
      if (password.isEmpty) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: password);
      }
      return true;
    } on Exception {
      return false;
    }
  }

  /// The full login, or null when no password is saved.
  Future<DufsLogin?> login() async {
    final password = await read();
    if (password.isEmpty) return null;
    return DufsLogin(user: kDufsImagesUser, password: password);
  }
}
