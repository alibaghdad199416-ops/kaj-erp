import 'package:flutter/animation.dart';

/// Motion rules for a restrained, premium enterprise experience.
abstract final class KajMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration emphasized = Duration(milliseconds: 260);
  static const Duration page = Duration(milliseconds: 320);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;
  static const Curve entranceCurve = Curves.easeOutQuart;
}
