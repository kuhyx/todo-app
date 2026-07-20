// coverage:ignore-file
// App bootstrap: opens the platform's note store and calls runApp. Exercised
// end-to-end by running the app, not unit tests.
import 'package:flutter/material.dart';

import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repository_factory.dart';
import 'package:todo/frame_stats.dart';
import 'package:todo/ui/capture_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installFrameStats();

  // Where the log lives, and whether a legacy sqlite DB needs importing, is
  // platform-specific and resolved by a conditional import: `dart:io` cannot be
  // imported at all in a web compile, and the desktop app is now a web build.
  final repository = await openRepository();

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
