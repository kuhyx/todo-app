import 'dart:io';

import 'package:flutter/widgets.dart';

/// A cached image file on this device.
Widget localImage(
  String path, {
  required BoxFit fit,
  required ImageErrorWidgetBuilder errorBuilder,
}) => Image.file(File(path), fit: fit, errorBuilder: errorBuilder);
