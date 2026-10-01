import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/images/attachment_ref.dart';
import 'package:todo/ui/images/attachment_strip.dart';
import 'package:todo/ui/images/file_embed.dart';
import 'package:todo/ui/images/image_embed.dart';

import '../fake_image_store.dart';

void main() {
  final pdf = AttachmentRef.forFile('n1', 'a.pdf');
  final attachment = Attachment(ref: pdf, name: 'Raport.pdf', isImage: false);
  late FakeImageStore store;
  late List<(ImageSource, String)> opened;
  String? failure;

  setUp(() {
    store = FakeImageStore();
    opened = [];
    failure = null;
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ImageStoreScope(
        store: store,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
  }

  FileEmbed embed({bool compact = false}) => FileEmbed(
    attachment: attachment,
    compact: compact,
    opening: (source, name) async {
      opened.add((source, name));
      return failure;
    },
  );

  testWidgets('a row shows the name and size and opens on tap', (tester) async {
    await pump(tester, embed());
    expect(find.text('Raport.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    await tester.tap(find.text('Raport.pdf'));
    await tester.pump();
    expect(opened.single.$2, 'Raport.pdf');
    expect(opened.single.$1, isA<LocalImageSource>());
  });

  testWidgets('a failed open is reported', (tester) async {
    failure = 'No app on this phone opens Raport.pdf';
    await pump(tester, embed());
    await tester.tap(find.text('Raport.pdf'));
    await tester.pump();
    expect(find.text(failure!), findsOneWidget);
  });

  testWidgets('a file not here yet says so and does not open', (tester) async {
    store.missing.add(pdf);
    await pump(tester, embed());
    expect(find.text(kImageNotDownloaded), findsOneWidget);
    await tester.tap(find.text('Raport.pdf'));
    await tester.pump();
    expect(opened, isEmpty);
  });

  testWidgets('a queued file carries the upload badge, in both shapes', (
    tester,
  ) async {
    store.pending.add(pdf);
    await pump(tester, embed());
    expect(find.byTooltip(kImageWaitingToUpload), findsOneWidget);
    await pump(tester, embed(compact: true));
    expect(find.byTooltip(kImageWaitingToUpload), findsOneWidget);
  });

  testWidgets('the size is asked again when the store changes', (tester) async {
    store.missing.add(pdf);
    await pump(tester, embed());
    expect(find.text(kImageNotDownloaded), findsOneWidget);
    store
      ..missing.clear()
      ..changed();
    await tester.pump();
    await tester.pump();
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  testWidgets('the strip shows a compact tile for a file', (tester) async {
    final image = AttachmentRef.create('n1');
    await pump(
      tester,
      AttachmentStrip(
        text: '${image.imageMarkdown}\n${pdf.fileMarkdown('Raport.pdf')}',
      ),
    );
    expect(find.byType(ImageEmbed), findsOneWidget);
    final tile = tester.widget<FileEmbed>(find.byType(FileEmbed));
    expect(tile.compact, isTrue);
    expect(find.text('2.0 KB'), findsNothing, reason: 'no room for a size');
  });

  test('formatBytes picks a readable unit', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(10 * 1024), '10 KB');
    expect(formatBytes(34 * 1024 * 1024), '34 MB');
    expect(formatBytes(2254857830), '2.1 GB');
    expect(formatBytes(5000 * 1024 * 1024 * 1024 * 1024), '5000 TB');
  });

  test('fileIconFor groups types by kind', () {
    expect(fileIconFor('pdf'), Icons.picture_as_pdf_outlined);
    expect(fileIconFor('mkv'), Icons.movie_outlined);
    expect(fileIconFor('flac'), Icons.audiotrack_outlined);
    expect(fileIconFor('md'), Icons.description_outlined);
    expect(fileIconFor('7z'), Icons.folder_zip_outlined);
    expect(fileIconFor('psd'), Icons.image_outlined);
    expect(fileIconFor('bin'), Icons.insert_drive_file_outlined);
  });
}
