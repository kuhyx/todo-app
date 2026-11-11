/// Framework strings the app paints without asking for them.
///
/// Material's own buttons (the app bar back arrow, a dialog's close, the
/// drawer, the overflow menu) carry tooltips from [MaterialLocalizations],
/// and a tooltip is painted on long-press and hover. kuhy's textgate rule
/// says nothing he sees has words he did not ask for, so these tooltips are
/// blanked: an empty tooltip is not built at all. Screen readers still get
/// the button's semantics from the icon itself.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// English Material strings with every button tooltip blanked.
class TextFreeMaterialLocalizations extends DefaultMaterialLocalizations {
  /// Creates the localizations.
  const TextFreeMaterialLocalizations();

  @override
  String get backButtonTooltip => '';

  @override
  String get closeButtonTooltip => '';

  @override
  String get openAppDrawerTooltip => '';

  @override
  String get showMenuTooltip => '';

  @override
  String get moreButtonTooltip => '';

  @override
  String get deleteButtonTooltip => '';
}

class _Delegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture(const TextFreeMaterialLocalizations());

  @override
  bool shouldReload(_Delegate old) => false;
}

/// Pass as `MaterialApp.localizationsDelegates`.
const List<LocalizationsDelegate<dynamic>> kTextFreeLocalizations = [
  _Delegate(),
];
