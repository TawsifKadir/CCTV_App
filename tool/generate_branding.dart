// Generates the launcher-icon source images from the supplied branding photo.
//
//   dart run tool/generate_branding.dart
//   dart run flutter_launcher_icons
//
// Inputs:  assets/branding/source_photo.jpg   (original, never modified)
// Outputs: assets/branding/app_icon.png               square crop, 1024 px
//          assets/branding/adaptive_background.png    wider crop for Android
//                                                      adaptive icons (the OS
//                                                      masks the outer third)
//          assets/branding/adaptive_foreground.png    transparent layer
//          assets/branding/app_logo.png               256 px in-app logo
//
// The crop windows are tuned for the supplied portrait so the face sits in
// the centre of every icon mask. Adjust [_iconCrop] / [_adaptiveCrop] if the
// source photo is replaced.
import 'dart:io';

import 'package:image/image.dart' as img;

/// (left, top, side) in source pixels.
const _iconCrop = (168, 48, 564);
const _adaptiveCrop = (92, 20, 640);
const _size = 1024;

void main() {
  final src = File('assets/branding/source_photo.jpg');
  if (!src.existsSync()) {
    stderr.writeln('Missing ${src.path}');
    exit(1);
  }
  final decoded = img.decodeImage(src.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode ${src.path}');
    exit(1);
  }
  final photo = img.bakeOrientation(decoded);

  img.Image crop((int, int, int) c) {
    final (x, y, side) = c;
    final s = [side, photo.width - x, photo.height - y].reduce((a, b) => a < b ? a : b);
    final square = img.copyCrop(photo, x: x, y: y, width: s, height: s);
    return img.copyResize(square, width: _size, height: _size, interpolation: img.Interpolation.cubic);
  }

  final icon = crop(_iconCrop);
  File('assets/branding/app_icon.png').writeAsBytesSync(img.encodePng(icon));
  final logo = img.copyResize(icon, width: 256, height: 256, interpolation: img.Interpolation.cubic);
  File('assets/branding/app_logo.png').writeAsBytesSync(img.encodePng(logo));
  File('assets/branding/adaptive_background.png').writeAsBytesSync(img.encodePng(crop(_adaptiveCrop)));
  final clear = img.Image(width: _size, height: _size, numChannels: 4);
  File('assets/branding/adaptive_foreground.png').writeAsBytesSync(img.encodePng(clear));
  stdout.writeln('Branding images written to assets/branding/');
}
