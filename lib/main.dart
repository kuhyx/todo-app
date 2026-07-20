// coverage:ignore-file
// App bootstrap: wires platform DB paths (path_provider) into the repository
// and calls runApp. Exercised end-to-end by running the app, not unit tests.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo/data/note_repository.dart';
import 'package:todo/frame_stats.dart';
import 'package:todo/ui/capture_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installFrameStats();

  // Desktop platforms need the FFI sqlite implementation initialised
  // before any database is opened; mobile uses the bundled library.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
  }

  final dir = await getApplicationSupportDirectory();
  final dbPath = p.join(dir.path, 'todo.db');
  final repository = await NoteRepository.open(dbPath);

  runApp(TodoApp(repository: repository));
}

/// Root widget. Holds the single [NoteRepository] instance and hands it
/// to the screens that need it.
class TodoApp extends StatelessWidget {
  /// Creates a [TodoApp] wrapping the given [repository].
  const TodoApp({required this.repository, super.key});

  /// The single, app-wide note store, injected into every screen.
  final NoteRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'todo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: CaptureScreen(repository: repository),
    );
  }
}
