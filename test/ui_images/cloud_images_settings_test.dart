import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/ui/cloud_images_settings.dart';

import '../fake_image_store.dart';
import '../fake_secure_storage.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    ImageStore? store,
    http.Client? client,
    bool field = true,
  }) async {
    final app = MaterialApp(
      home: CloudImagesScreen(httpClient: client, showPasswordField: field),
    );
    await tester.pumpWidget(
      store == null ? app : ImageStoreScope(store: store, child: app),
    );
    await tester.pump();
  }

  MockClient answer(int code) =>
      MockClient((_) async => http.Response('', code));

  Future<void> saveWith(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Save & test'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the settings tile opens the screen', (tester) async {
    installFakeSecureStorage();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CloudImagesTile())),
    );
    await tester.tap(find.text('Cloud images'));
    await tester.pumpAndSettle();
    expect(find.byType(CloudImagesScreen), findsOneWidget);
  });

  testWidgets('loads the saved password and the store status', (tester) async {
    installFakeSecureStorage(initial: {'dufsImagesPassword': 'saved'});
    await pump(tester, store: FakeImageStore());
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'saved',
    );
    expect(find.text('Login: configured'), findsOneWidget);
    expect(find.text('Waiting to upload: 0'), findsOneWidget);
  });

  testWidgets('an accepted password is saved and the queue uploads', (
    tester,
  ) async {
    installFakeSecureStorage();
    final store = FakeImageStore();
    await pump(tester, store: store, client: answer(207));
    await saveWith(tester, ' pw ');
    expect(find.text('Saved — dufs accepted the login'), findsOneWidget);
    expect(store.reconciles.single, isEmpty);
  });

  testWidgets('a rejected password says so and uploads nothing', (
    tester,
  ) async {
    installFakeSecureStorage();
    final store = FakeImageStore();
    await pump(tester, store: store, client: answer(401));
    await saveWith(tester, 'bad');
    expect(find.text('Saved, but dufs rejected the password'), findsOneWidget);
    expect(store.reconciles, isEmpty);
  });

  testWidgets('an unreachable dufs is reported', (tester) async {
    installFakeSecureStorage();
    await pump(
      tester,
      store: FakeImageStore(),
      client: MockClient((_) => throw const SocketException('down')),
    );
    await saveWith(tester, 'pw');
    expect(find.text('Saved — dufs is unreachable right now'), findsOneWidget);
  });

  testWidgets('no keystore means nothing is saved', (tester) async {
    installFakeSecureStorage(throwing: true);
    await pump(tester, store: FakeImageStore(), client: answer(207));
    await saveWith(tester, 'pw');
    expect(
      find.text('Could not save: the keystore is unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('the desktop shows status only, with the setup command', (
    tester,
  ) async {
    await pump(tester, field: false);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('Login: missing — create it on the PC with'),
      findsOneWidget,
    );
    expect(find.text(kAddLoginCommand), findsOneWidget);
  });

  testWidgets('closing the screen mid-test is harmless', (tester) async {
    installFakeSecureStorage();
    final reply = Completer<http.Response>();
    final store = FakeImageStore();
    await pump(tester, store: store, client: MockClient((_) => reply.future));
    await tester.enterText(find.byType(TextField), 'pw');
    await tester.tap(find.text('Save & test'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    reply.complete(http.Response('', 207));
    await tester.pump();
    expect(store.reconciles, isEmpty);
  });
}
