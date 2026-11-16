import 'package:flutter/material.dart';

/// 4/8-point spacing scale.
class Space {
  Space._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Corner radii.
class Radii {
  Radii._();
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
}

/// Standard animation durations. Use [Motion.of] to honour reduced motion.
class Motion {
  Motion._();
  static const fast = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 500);
  static const curve = Curves.easeOutCubic;
}
