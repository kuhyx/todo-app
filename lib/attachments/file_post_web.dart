/// POSTs a picked or dropped file to the desktop wrapper with `fetch`.
///
/// `package:http`'s browser client buffers a request body whole, and
/// `XFile.readAsBytes` copies the file into Dart: either would put a
/// multi-gigabyte attachment in the page's memory. Handing the file's own
/// Blob to `fetch` lets the browser stream it from disk instead.
library;

import 'dart:js_interop';

import 'package:todo/attachments/image_store_api.dart';
import 'package:web/web.dart' as web;

/// POSTs [file] to [url]. [file]'s path is the object URL that file_selector
/// or the drop listener created for it.
Future<({int status, String body})> postFile(Uri url, XFile file) async {
  final source = await web.window.fetch(file.path.toJS).toDart;
  final blob = await source.blob().toDart;
  final response = await web.window
      .fetch(url.toString().toJS, web.RequestInit(method: 'POST', body: blob))
      .toDart;
  return (status: response.status, body: (await response.text().toDart).toDart);
}
