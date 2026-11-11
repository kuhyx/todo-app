/// The "no words" guard: kuhy's textgate rule says nothing he sees carries
/// app-written text. This walks every painted string in the widget tree and
/// fails on any run of two letters that is not note content.
///
/// Deliberately NOT named `*_test.dart`: it is a helper with no `main()`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final RegExp _word = RegExp('[A-Za-z]{2,}');

/// Finds a node whose spoken (semantics) label contains [part] literally.
/// The old visible sentences live on as spoken labels, so tests that used
/// `find.textContaining` now look here.
Finder spoken(String part) =>
    find.bySemanticsLabel(RegExp(RegExp.escape(part)));

/// Every string the tree paints: each [RichText] (which is what [Text] builds)
/// and every non-empty [Tooltip] message, since a tooltip is shown on
/// long-press. Text being typed lives in an [EditableText] and is the user's,
/// so it is never painted through a [RichText] and is not collected.
List<String> paintedStrings(WidgetTester tester) => [
  for (final w in tester.widgetList<RichText>(find.byType(RichText)))
    w.text.toPlainText(),
  for (final t in tester.widgetList<Tooltip>(find.byType(Tooltip)))
    if ((t.message ?? '').isNotEmpty) t.message!,
];

/// Fails if any painted string still holds a word once every [content]
/// string (note text, typed values: things kuhy wrote) is removed from it.
///
/// An empty tree is a failure too: a guard that saw nothing proves nothing.
void expectNoChromeWords(
  WidgetTester tester, {
  List<String> content = const [],
}) {
  final painted = paintedStrings(tester);
  expect(painted, isNotEmpty, reason: 'guard saw no painted strings');
  final offenders = <String>[];
  for (final s in painted) {
    var rest = s;
    for (final c in content) {
      rest = rest.replaceAll(c, '');
    }
    if (_word.hasMatch(rest)) offenders.add(s);
  }
  expect(offenders, isEmpty, reason: 'app-written words are painted');
}
