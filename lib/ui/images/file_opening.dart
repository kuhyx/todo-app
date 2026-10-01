/// Opening an attached file outside the app.
///
/// Android hands the cached file to whichever app handles its type (the
/// system chooser when there is no default), through `open_file`'s
/// FileProvider. The desktop page opens the wrapper's copy in a new browser
/// tab, which shows PDFs, text and media and downloads anything else (see
/// `wrapper_attachment_serving.dart`).
library;

import 'package:open_file/open_file.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [source], the file called [name]; returns why it could not, or null.
Future<String?> openAttachedFile(ImageSource source, String name) async {
  switch (source) {
    case LocalImageSource(:final path):
      final result = await OpenFile.open(path);
      return switch (result.type) {
        ResultType.done => null,
        ResultType.noAppToOpen => 'No app on this phone opens $name',
        _ => 'Could not open $name: ${result.message}',
      };
    case NetworkImageSource(:final url):
      final uri = Uri.parse(url);
      final named = uri.replace(
        queryParameters: {...uri.queryParameters, 'name': name},
      );
      final opened = await launchUrl(named, webOnlyWindowName: '_blank');
      return opened ? null : 'Could not open $name';
    case MissingImageSource():
      return '$name is not on this device yet';
  }
}
