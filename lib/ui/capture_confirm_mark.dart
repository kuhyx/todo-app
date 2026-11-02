/// The checkmark confirming a capture; static under "remove animations".
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Plays once each time [captured] changes value.
class CaptureConfirmMark extends StatefulWidget {
  /// Creates the mark.
  const CaptureConfirmMark({required this.captured, super.key});

  /// Key of the checkmark icon while it is visible.
  static const ValueKey<String> iconKey = ValueKey('capture-confirm-icon');

  /// Width always reserved, so the counter beside it never moves.
  static const double slotWidth = 24;

  /// Fade in, hold and fade out: three [AppDuration.base] thirds.
  static final Duration duration = AppDuration.base * 3;

  /// Counts captures; each change plays the confirmation.
  final ValueListenable<int> captured;

  @override
  State<CaptureConfirmMark> createState() => _CaptureConfirmMarkState();
}

class _CaptureConfirmMarkState extends State<CaptureConfirmMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CaptureConfirmMark.duration,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void initState() {
    super.initState();
    widget.captured.addListener(_play);
  }

  @override
  void dispose() {
    widget.captured.removeListener(_play);
    _controller.dispose();
    super.dispose();
  }

  void _play() => _controller.forward(from: 0);

  double _opacity({required bool reduced}) {
    final t = _controller.value;
    if (reduced || (t >= 1 / 3 && t < 2 / 3)) return 1;
    if (t < 1 / 3) return AppCurve.decelerate.transform(t * 3);
    return 1 - AppCurve.accelerate.transform((t - 2 / 3) * 3);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: CaptureConfirmMark.slotWidth,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (!_controller.isAnimating) return const SizedBox.shrink();
          return Opacity(
            opacity: _opacity(reduced: reduced),
            child: const _CheckIcon(),
          );
        },
      ),
    );
  }
}

class _CheckIcon extends StatelessWidget {
  const _CheckIcon();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Icon(
      Icons.check_circle,
      key: CaptureConfirmMark.iconKey,
      size: 18,
      color: color,
    );
  }
}
