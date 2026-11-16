import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/motion.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_cards.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../face_capture/services/face_image_service.dart';
import '../../../face_capture/widgets/face_capture_view.dart';
import '../../domain/employee_photo.dart';

enum _Mode { choose, camera, busy }

/// Collects the employee photograph: live camera capture or file upload,
/// with preview, retake, replace and remove.
class PhotoPickerPanel extends StatefulWidget {
  const PhotoPickerPanel({
    super.key,
    required this.photo,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
    this.preferFrontCamera = true,
  });

  final EmployeePhoto? photo;
  final ValueChanged<EmployeePhoto?> onChanged;
  final String? errorText;
  final bool enabled;
  final bool preferFrontCamera;

  @override
  State<PhotoPickerPanel> createState() => _PhotoPickerPanelState();
}

class _PhotoPickerPanelState extends State<PhotoPickerPanel> {
  _Mode _mode = _Mode.choose;
  String? _localError;

  void _openCamera() => setState(() {
        _localError = null;
        _mode = _Mode.camera;
      });

  Future<void> _upload() async {
    setState(() => _localError = null);
    try {
      final raw = await FaceImageService.pickImageFile();
      if (raw == null || !mounted) {
        if (mounted && _mode == _Mode.busy) setState(() => _mode = _Mode.choose);
        return;
      }
      setState(() => _mode = _Mode.busy);
      final photo = await FaceImageService.prepareUpload(raw);
      if (!mounted) return;
      setState(() => _mode = _Mode.choose);
      widget.onChanged(photo);
    } on PhotoValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _mode = _Mode.choose;
        _localError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mode = _Mode.choose;
        _localError = 'That file could not be opened. Choose a JPEG or PNG photo.';
      });
    }
  }

  void _captured(EmployeePhoto photo) {
    setState(() => _mode = _Mode.choose);
    widget.onChanged(photo);
  }

  @override
  Widget build(BuildContext context) {
    final error = _localError ?? widget.errorText;
    final Widget body = switch (_mode) {
      _Mode.camera => FaceCaptureView(
          key: const ValueKey('camera'),
          preferFrontCamera: widget.preferFrontCamera,
          onCaptured: _captured,
          onUploadInstead: () {
            setState(() => _mode = _Mode.choose);
            _upload();
          },
          onCancel: () => setState(() => _mode = _Mode.choose),
        ),
      _Mode.busy => const SizedBox(
          key: ValueKey('busy'),
          height: 260,
          child: AppLoadingIndicator(message: 'Preparing photo…'),
        ),
      _Mode.choose => widget.photo == null
          ? _EmptyPhoto(key: const ValueKey('empty'), enabled: widget.enabled, onCamera: _openCamera, onUpload: _upload)
          : _PhotoPreview(
              key: const ValueKey('preview'),
              photo: widget.photo!,
              enabled: widget.enabled,
              onRetake: _openCamera,
              onReplace: _upload,
              onRemove: () => widget.onChanged(null),
            ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(duration: context.motion(Motion.fast), child: body),
        if (error != null) ...[
          const SizedBox(height: Space.sm),
          Text(error, key: const Key('photo-error'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error)),
        ],
      ],
    );
  }
}

class _EmptyPhoto extends StatelessWidget {
  const _EmptyPhoto({super.key, required this.enabled, required this.onCamera, required this.onUpload});

  final bool enabled;
  final VoidCallback onCamera;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return AppCard(
      border: true,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
            child: const Icon(Icons.face_retouching_natural_rounded, size: 44, color: AppColors.peach),
          ),
          const SizedBox(height: Space.md),
          Text('Employee photograph', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A clear, front-facing photo. The server creates the face template from it.',
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: p.textMuted),
          ),
          const SizedBox(height: Space.lg),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              AppPrimaryButton(
                key: const Key('photo-camera'),
                label: 'Take photo',
                icon: Icons.photo_camera_outlined,
                expand: false,
                height: 48,
                onPressed: enabled ? onCamera : null,
              ),
              AppSecondaryButton(
                key: const Key('photo-upload'),
                label: 'Upload photo',
                icon: Icons.upload_rounded,
                expand: false,
                height: 48,
                onPressed: enabled ? onUpload : null,
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text('JPEG or PNG · up to 10 MB', style: t.labelSmall),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    super.key,
    required this.photo,
    required this.enabled,
    required this.onRetake,
    required this.onReplace,
    required this.onRemove,
  });

  final EmployeePhoto photo;
  final bool enabled;
  final VoidCallback onRetake;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return AppCard(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        children: [
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth.clamp(0.0, 360.0);
            return ClipRRect(
              borderRadius: BorderRadius.circular(Radii.lg),
              child: Image.memory(
                photo.bytes,
                key: const Key('photo-preview'),
                width: w,
                height: w * 1.15,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // Decode at preview size, not the full upload resolution.
                cacheWidth: (w * dpr).round(),
              ),
            );
          }),
          const SizedBox(height: Space.sm),
          Text(
            '${photo.origin == PhotoOrigin.camera ? 'Captured' : 'Uploaded'} · '
            '${photo.format.name.toUpperCase()} · ${Fmt.bytes(photo.sizeBytes)}',
            style: t.labelSmall,
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              AppSecondaryButton(
                label: 'Retake',
                icon: Icons.photo_camera_outlined,
                expand: false,
                height: 42,
                onPressed: enabled ? onRetake : null,
              ),
              AppSecondaryButton(
                label: 'Replace',
                icon: Icons.upload_rounded,
                expand: false,
                height: 42,
                onPressed: enabled ? onReplace : null,
              ),
              AppSecondaryButton(
                key: const Key('photo-remove'),
                label: 'Remove',
                icon: Icons.delete_outline_rounded,
                variant: AppSecondaryVariant.danger,
                expand: false,
                height: 42,
                onPressed: enabled ? onRemove : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
