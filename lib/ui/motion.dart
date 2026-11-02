/// Reduced-motion handling shared by every animated surface.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

/// [token] unless the OS "remove animations" setting is on, in which case
/// [AppDuration.instant]. Haptics are not motion and never go through this.
Duration motionDuration(BuildContext context, Duration token) =>
    MediaQuery.disableAnimationsOf(context) ? AppDuration.instant : token;
