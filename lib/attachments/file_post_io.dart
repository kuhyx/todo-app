/// Off the web nothing posts files to the wrapper: Android stores them
/// itself.
library;

import 'package:todo/attachments/image_store_api.dart';

/// Always throws; only the desktop page posts files.
Future<({int status, String body})> postFile(Uri url, XFile file) =>
    throw UnsupportedError('Only the desktop page posts files');
