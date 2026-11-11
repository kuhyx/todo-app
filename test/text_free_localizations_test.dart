import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/text_free_localizations.dart';

void main() {
  test('every button tooltip is blank', () {
    const l = TextFreeMaterialLocalizations();
    expect([
      l.backButtonTooltip,
      l.closeButtonTooltip,
      l.openAppDrawerTooltip,
      l.showMenuTooltip,
      l.moreButtonTooltip,
      l.deleteButtonTooltip,
    ], everyElement(isEmpty));
    // Everything else is still the default English.
    expect(l.okButtonLabel, const DefaultMaterialLocalizations().okButtonLabel);
  });

  test('the delegate loads them for English only, once', () async {
    final delegate = kTextFreeLocalizations.single;
    expect(delegate.isSupported(const Locale('en')), isTrue);
    expect(delegate.isSupported(const Locale('pl')), isFalse);
    expect(
      await delegate.load(const Locale('en')),
      isA<TextFreeMaterialLocalizations>(),
    );
    expect(delegate.shouldReload(delegate), isFalse);
  });
}
