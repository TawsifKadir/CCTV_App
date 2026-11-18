// Generates launcher-icon sources from the official SNOWTEX logo.
//
//   dart run tool/generate_branding.dart
//   dart run flutter_launcher_icons
//
// Input:  assets/branding/snowtex_logo.jpg (original, never modified)
// Output: assets/branding/app_icon.png             1024 px, full logo (iOS, web, macOS, legacy Android)
//         assets/branding/adaptive_foreground.png  logo inside the Android adaptive-icon safe zone
//         assets/branding/app_logo.png             256 px in-app logo
// It also prints the logo's background blue, used as the Android adaptive
// icon background colour in pubspec.yaml.
//
// NOTE: the supplied logo is 200x200 px, so the 1024 px icon is upscaled.
// Replace snowtex_logo.jpg with a high-resolution or vector original when
// available and re-run both commands.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final logo = img.decodeImage(File('assets/branding/snowtex_logo.jpg').readAsBytesSync())!;
  final bg = logo.getPixel(4, 4);
  final hex = [bg.r, bg.g, bg.b].map((v) => v.toInt().toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  img.Image scaled(int size) => img.copyResize(logo, width: size, height: size, interpolation: img.Interpolation.cubic);

  File('assets/branding/app_icon.png').writeAsBytesSync(img.encodePng(scaled(1024)));
  File('assets/branding/app_logo.png').writeAsBytesSync(img.encodePng(scaled(256)));

  // Adaptive icons are masked to as little as the central ~66%: put the
  // logo at 62% on a transparent layer over a matching blue background.
  final fg = img.Image(width: 1024, height: 1024, numChannels: 4);
  const inner = 634;
  img.compositeImage(fg, scaled(inner), dstX: (1024 - inner) ~/ 2, dstY: (1024 - inner) ~/ 2);
  File('assets/branding/adaptive_foreground.png').writeAsBytesSync(img.encodePng(fg));
  stdout.writeln('Logo background colour: #$hex');
}
