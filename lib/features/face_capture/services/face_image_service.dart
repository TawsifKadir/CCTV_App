import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../registration/domain/employee_photo.dart';

/// Why the camera could not be used.
enum CameraIssue {
  permissionDenied,
  noCamera,
  unsupported,
  failure;

  String get title => switch (this) {
    CameraIssue.permissionDenied => 'Camera access was denied',
    CameraIssue.noCamera => 'No camera found',
    CameraIssue.unsupported => 'Camera not supported here',
    CameraIssue.failure => 'The camera could not start',
  };

  String get message => switch (this) {
    CameraIssue.permissionDenied =>
      'Allow camera access in your browser or device settings, then try again. You can also upload a photo instead.',
    CameraIssue.noCamera => 'Connect a camera or upload an existing photograph instead.',
    CameraIssue.unsupported => 'This platform does not support live capture. Please upload a photograph.',
    CameraIssue.failure => 'Something went wrong while starting the camera. Try again or upload a photo.',
  };
}

class CameraIssueException implements Exception {
  const CameraIssueException(this.issue);
  final CameraIssue issue;
}

/// Camera discovery, error mapping and photo preparation.
///
/// The app only collects and submits photographs; face detection and
/// template generation happen on the backend.
class FaceImageService {
  FaceImageService._();

  static Future<List<CameraDescription>> listCameras() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw const CameraIssueException(CameraIssue.noCamera);
      return cams;
    } on CameraIssueException {
      rethrow;
    } on CameraException catch (e) {
      throw CameraIssueException(mapCameraError(e.code));
    } on MissingPluginException {
      throw const CameraIssueException(CameraIssue.unsupported);
    } on UnimplementedError {
      throw const CameraIssueException(CameraIssue.unsupported);
    } catch (_) {
      throw const CameraIssueException(CameraIssue.failure);
    }
  }

  /// Maps plugin error codes (Android, iOS and web differ) to [CameraIssue].
  static CameraIssue mapCameraError(String code) {
    final c = code.toLowerCase();
    if (c.contains('denied') || c.contains('permission') || c.contains('restricted') || c.contains('notallowed')) {
      return CameraIssue.permissionDenied;
    }
    if (c.contains('notfound') || c.contains('nocamera') || c.contains('not_found')) {
      return CameraIssue.noCamera;
    }
    if (c.contains('notsupported') || c.contains('unsupported')) return CameraIssue.unsupported;
    return CameraIssue.failure;
  }

  /// Lets the operator choose an image file (gallery on mobile, file dialog
  /// on web/desktop). Returns the raw bytes, or `null` if cancelled.
  ///
  /// On iOS/Android a quality value is passed so the picker converts HEIC
  /// and other formats to JPEG; on the web the original file is returned so
  /// its real size and format can be validated.
  static Future<Uint8List?> pickImageFile() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: kIsWeb ? null : 95,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  /// Validates an uploaded file against the backend rules (JPEG/PNG, at most
  /// 10 MB) and prepares it for upload. Throws [PhotoValidationException].
  ///
  /// Native platforms also fix EXIF rotation and downscale in a background
  /// isolate. On the web the validated original is sent unchanged: decoding
  /// a multi-megabyte image in the browser's single thread would freeze the
  /// UI for seconds.
  static Future<EmployeePhoto> prepareUpload(Uint8List raw) async {
    final error = PhotoValidator.validate(raw);
    if (error != null) throw PhotoValidationException(error);
    if (kIsWeb) return EmployeePhoto.fromBytes(raw, origin: PhotoOrigin.upload);
    final processed = await process(raw);
    return EmployeePhoto.fromBytes(processed, origin: PhotoOrigin.upload);
  }

  /// Normalises a camera capture and wraps it for upload.
  static Future<EmployeePhoto> prepareCapture(Uint8List raw) async {
    final processed = await process(raw);
    return EmployeePhoto.fromBytes(processed, origin: PhotoOrigin.camera);
  }

  /// Fixes EXIF rotation, downsizes to [AppConstants.photoMaxEdge] and
  /// re-encodes as JPEG. Runs in a background isolate on native platforms.
  static Future<Uint8List> process(Uint8List raw) async {
    final out = kIsWeb ? _processSync(raw) : await compute(_processSync, raw);
    if (out == null) {
      throw const PhotoValidationException('That file could not be read as a photo. Use a JPEG or PNG image.');
    }
    return out;
  }

  static Uint8List? _processSync(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    var image = img.bakeOrientation(decoded);
    const maxEdge = AppConstants.photoMaxEdge;
    if (image.width > maxEdge || image.height > maxEdge) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxEdge, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxEdge, interpolation: img.Interpolation.average);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: AppConstants.photoJpegQuality));
  }
}
