import 'package:flutter/foundation.dart';

import '../../../core/config/api_endpoints.dart';

enum PhotoFormat {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png');

  const PhotoFormat(this.mimeType, this.extension);
  final String mimeType;
  final String extension;
}

/// A photograph ready to be sent as the multipart `photo` part.
@immutable
class EmployeePhoto {
  const EmployeePhoto._(this.bytes, this.format, this.origin);

  final Uint8List bytes;
  final PhotoFormat format;

  /// Whether the operator captured or uploaded it (shown in the UI only;
  /// the backend records its own enrollment source).
  final PhotoOrigin origin;

  int get sizeBytes => bytes.lengthInBytes;
  String get filename => 'photo.${format.extension}';

  /// Validates [bytes] and wraps them. Throws [PhotoValidationException].
  factory EmployeePhoto.fromBytes(Uint8List bytes, {required PhotoOrigin origin}) {
    final error = PhotoValidator.validate(bytes);
    if (error != null) throw PhotoValidationException(error);
    return EmployeePhoto._(bytes, PhotoValidator.detectFormat(bytes)!, origin);
  }
}

enum PhotoOrigin { camera, upload }

class PhotoValidationException implements Exception {
  const PhotoValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Mirrors the backend's `EmployeeForm.photoBytes()` rules: a JPEG or PNG
/// photo of at most 10 MB.
class PhotoValidator {
  PhotoValidator._();

  static const maxBytes = ApiEndpoints.maxPhotoBytes;

  /// Detects JPEG/PNG from the file signature (not the file name).
  static PhotoFormat? detectFormat(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return PhotoFormat.jpeg;
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (b.length >= png.length) {
      for (var i = 0; i < png.length; i++) {
        if (b[i] != png[i]) return null;
      }
      return PhotoFormat.png;
    }
    return null;
  }

  /// `null` when valid, otherwise a user-facing message.
  static String? validate(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return 'Add a photograph of the employee.';
    if (bytes.lengthInBytes > maxBytes) {
      final mb = (bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1);
      return 'This photo is $mb MB. Upload a JPEG or PNG photo up to 10 MB.';
    }
    if (detectFormat(bytes) == null) return 'Only JPEG and PNG photos are supported.';
    return null;
  }
}
