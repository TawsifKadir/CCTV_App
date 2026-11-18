import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/motion.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../registration/domain/employee_photo.dart';
import '../services/face_image_service.dart';
import 'camera_capture_frame.dart';

enum _Phase { starting, live, processing, review, error }

/// Live camera capture with an oval face guide, review/retake, camera
/// switching and an upload fallback. Works on Android, iOS and the web
/// (browser webcam; the browser asks for permission when it starts).
///
/// The camera starts as soon as this widget is shown and is released when
/// a photo is being reviewed or the widget is removed.
///
/// NOTE: this only captures a photograph. Face detection and template
/// generation are done by the backend.
class FaceCaptureView extends StatefulWidget {
  const FaceCaptureView({
    super.key,
    required this.onCaptured,
    required this.onUploadInstead,
    this.onCancel,
    this.preferFrontCamera = true,
  });

  /// Called with the accepted, processed photo.
  final ValueChanged<EmployeePhoto> onCaptured;

  /// Operator prefers (or must fall back to) choosing a file.
  final VoidCallback onUploadInstead;
  final VoidCallback? onCancel;
  final bool preferFrontCamera;

  @override
  State<FaceCaptureView> createState() => _FaceCaptureViewState();
}

class _FaceCaptureViewState extends State<FaceCaptureView> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _camIndex = 0;
  _Phase _phase = _Phase.starting;
  EmployeePhoto? _photo;
  CameraIssue? _issue;
  final _flash = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_controller != null) setState(_disposeController);
    } else if (state == AppLifecycleState.resumed && _phase == _Phase.live && _controller == null) {
      _startCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flash.dispose();
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    c?.dispose();
  }

  /// Detaches the controller now but disposes it only after the viewport
  /// cross-fade finishes, because the outgoing live preview still renders it.
  Future<void> _releaseAfterTransition() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    await Future<void>.delayed(context.motion(Motion.fast) + const Duration(milliseconds: 80));
    await c.dispose();
  }

  Future<void> _startCamera() async {
    setState(() {
      _phase = _Phase.starting;
      _issue = null;
    });
    try {
      if (_cameras.isEmpty) {
        _cameras = await FaceImageService.listCameras();
        final wanted = widget.preferFrontCamera ? CameraLensDirection.front : CameraLensDirection.back;
        final idx = _cameras.indexWhere((c) => c.lensDirection == wanted);
        _camIndex = idx >= 0 ? idx : 0;
      }
      await _initController(_cameras[_camIndex]);
    } on CameraIssueException catch (e) {
      _fail(e.issue);
    }
  }

  Future<void> _initController(CameraDescription cam) async {
    final controller = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: kIsWeb ? null : ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _phase = _Phase.live);
    } on CameraException catch (e) {
      await controller.dispose();
      _fail(FaceImageService.mapCameraError(e.code));
    } catch (_) {
      await controller.dispose();
      _fail(CameraIssue.failure);
    }
  }

  void _fail(CameraIssue issue) {
    if (!mounted) return;
    setState(() {
      _issue = issue;
      _phase = _Phase.error;
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _camIndex = (_camIndex + 1) % _cameras.length;
    setState(() => _phase = _Phase.starting);
    // Many devices cannot open two cameras at once: release the old one first.
    await _releaseAfterTransition();
    if (!mounted) return;
    await _initController(_cameras[_camIndex]);
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
    _flash.value = true;
    try {
      final file = await c.takePicture();
      final raw = await file.readAsBytes();
      if (!mounted) return;
      _flash.value = false;
      setState(() => _phase = _Phase.processing);
      final photo = await FaceImageService.prepareCapture(raw);
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _phase = _Phase.review;
      });
      _releaseAfterTransition(); // Free the camera while reviewing.
    } catch (_) {
      if (!mounted) return;
      _flash.value = false;
      setState(() => _phase = _controller != null ? _Phase.live : _Phase.error);
      showAppSnack(context, 'Could not capture the photograph. Please try again.', type: SnackType.error);
    }
  }

  void _retake() {
    setState(() => _photo = null);
    _startCamera();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, c) {
        final viewportH = MediaQuery.sizeOf(context).height;
        final frameW = c.maxWidth.clamp(0.0, 560.0);
        var frameH = frameW * 4 / 3;
        if (frameH > viewportH * 0.6) frameH = (viewportH * 0.6).clamp(300.0, 900.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: frameW,
                height: frameH,
                decoration: BoxDecoration(color: p.nav, borderRadius: BorderRadius.circular(Radii.xl)),
                clipBehavior: Clip.antiAlias,
                child: AnimatedSwitcher(
                  duration: context.motion(Motion.fast),
                  child: KeyedSubtree(key: ValueKey(_phase), child: _viewport()),
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            _controls(),
          ],
        );
      },
    );
  }

  Widget _viewport() {
    final t = Theme.of(context).textTheme;
    switch (_phase) {
      case _Phase.starting:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.peach),
              const SizedBox(height: Space.md),
              Text('Starting camera…', style: t.bodyMedium?.copyWith(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Allow camera access if prompted', style: t.bodySmall?.copyWith(color: Colors.white38)),
            ],
          ),
        );
      case _Phase.processing:
        return _centerMessage(Icons.auto_fix_high_outlined, 'Preparing photo…', 'Optimising the image for upload');
      case _Phase.error:
        final issue = _issue ?? CameraIssue.failure;
        return _centerMessage(
          issue == CameraIssue.permissionDenied ? Icons.no_photography_outlined : Icons.videocam_off_outlined,
          issue.title,
          issue.message,
          color: AppColors.error,
        );
      case _Phase.live:
        return _livePreview();
      case _Phase.review:
        final photo = _photo;
        if (photo == null) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              photo.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _centerMessage(
                Icons.broken_image_outlined,
                'Image unavailable',
                'The photograph could not be displayed. Please retake it.',
                color: AppColors.error,
              ),
            ),
            const CameraCaptureFrame(active: false),
            Positioned(
              bottom: Space.md,
              left: 0,
              right: 0,
              child: Center(child: _badge(Icons.visibility_outlined, 'Review photo', AppColors.peach)),
            ),
          ],
        );
    }
  }

  Widget _livePreview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    final size = c.value.previewSize;
    // On phones the sensor reports landscape dimensions for a portrait preview.
    final portraitDevice = !kIsWeb && MediaQuery.orientationOf(context) == Orientation.portrait;
    Widget preview = CameraPreview(c);
    if (size != null) {
      preview = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: portraitDevice ? size.height : size.width,
          height: portraitDevice ? size.width : size.height,
          child: preview,
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // The camera texture repaints at the sensor frame rate; isolate it so
        // overlays and the rotating tip never force it to repaint (or v.v.).
        RepaintBoundary(child: preview),
        const CameraCaptureFrame(),
        const Positioned(
          left: Space.md,
          right: Space.md,
          bottom: Space.md,
          child: Center(child: _RotatingTip()),
        ),
        Positioned(top: Space.md, left: Space.md, child: _badge(Icons.circle, 'Live', AppColors.error)),
        // Shutter flash: listens to its own notifier, so the preview is not
        // rebuilt when it fires.
        IgnorePointer(
          child: ValueListenableBuilder<bool>(
            valueListenable: _flash,
            builder: (_, on, _) => AnimatedOpacity(
              opacity: on ? 0.85 : 0,
              duration: Duration(milliseconds: on ? 60 : 300),
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls() {
    switch (_phase) {
      case _Phase.starting:
      case _Phase.processing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.onCancel != null)
              AppSecondaryButton(label: 'Cancel', expand: false, height: 46, onPressed: widget.onCancel),
          ],
        );
      case _Phase.error:
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            AppSecondaryButton(label: 'Try again', icon: Icons.refresh_rounded, expand: false, onPressed: _startCamera),
            AppPrimaryButton(
              label: 'Upload photo',
              icon: Icons.upload_rounded,
              expand: false,
              onPressed: widget.onUploadInstead,
            ),
          ],
        );
      case _Phase.live:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIconButton(
              icon: Icons.upload_rounded,
              tooltip: 'Upload a photo instead',
              onPressed: widget.onUploadInstead,
            ),
            const SizedBox(width: Space.lg),
            _ShutterButton(onPressed: _capture),
            const SizedBox(width: Space.lg),
            AppIconButton(
              icon: _cameras.length > 1 ? Icons.cameraswitch_outlined : Icons.close_rounded,
              tooltip: _cameras.length > 1 ? 'Switch camera' : 'Close camera',
              onPressed: _cameras.length > 1 ? _switchCamera : widget.onCancel,
            ),
          ],
        );
      case _Phase.review:
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            AppSecondaryButton(label: 'Retake', icon: Icons.replay_rounded, expand: false, onPressed: _retake),
            AppPrimaryButton(
              key: const Key('confirm-photo'),
              label: 'Use this photo',
              icon: Icons.check_rounded,
              expand: false,
              onPressed: () => widget.onCaptured(_photo!),
            ),
          ],
        );
    }
  }

  Widget _centerMessage(IconData icon, String title, String message, {Color color = AppColors.peach}) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: Space.md),
            Text(
              title,
              style: t.titleMedium?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: t.bodySmall?.copyWith(color: Colors.white60),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: icon == Icons.circle ? 9 : 15, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white)),
      ],
    ),
  );
}

/// Capture tips that rotate every few seconds. Owns its timer and state so
/// only this pill rebuilds — previously the whole camera view (including
/// the preview) was rebuilt on every tick.
class _RotatingTip extends StatefulWidget {
  const _RotatingTip();

  @override
  State<_RotatingTip> createState() => _RotatingTipState();
}

class _RotatingTipState extends State<_RotatingTip> {
  static const _tips = [
    'Position the face inside the frame',
    'Look directly at the camera',
    'Ensure even, sufficient lighting',
    'Remove sunglasses, hats or masks',
  ];
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _tips.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: AnimatedSwitcher(
        duration: context.motion(Motion.fast),
        child: Text(
          _tips[_i],
          key: ValueKey(_i),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ShutterButton extends StatefulWidget {
  const _ShutterButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture photo',
      child: GestureDetector(
        key: const Key('shutter'),
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedScale(
            scale: _down ? 0.9 : 1,
            duration: context.motion(Motion.fast),
            child: Container(
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.peach, width: 4),
              ),
              child: Container(
                decoration: const BoxDecoration(color: AppColors.peach, shape: BoxShape.circle),
                child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
