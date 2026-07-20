import 'package:idb_shim/idb_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/data/desktop_backup_client.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/web_log_persistence.dart';
import 'package:todo/sync/desktop_wrapper.dart';
import 'package:uuid/uuid.dart';

/// Opens the note store in a browser (the desktop app).
///
/// There is no legacy sqlite database in a browser profile, so the migration
/// path is simply absent here rather than skipped at runtime.
Future<NoteRepository> openRepository() async {
  final database = await WebLogPersistence.openDatabase(idbFactoryBrowser);
  final persistence = WebLogPersistence(
    database: database,
    backup: DesktopBackupClient(baseUrl: desktopWrapperOrigin),
  );

  final prefs = await SharedPreferences.getInstance();
  var nodeId = prefs.getString(NoteRepository.kNodeId) ?? '';
  if (nodeId.isEmpty) {
    nodeId = const Uuid().v4();
    await prefs.setString(NoteRepository.kNodeId, nodeId);
  }
  return NoteRepository.openWith(persistence: persistence, nodeId: nodeId);
}
