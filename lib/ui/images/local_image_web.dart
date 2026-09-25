import 'package:flutter/widgets.dart';

/// Never reached on the web: the web store only returns network sources.
Widget localImage(
  String path, {
  required BoxFit fit,
  required ImageErrorWidgetBuilder errorBuilder,
}) => const SizedBox.shrink();
