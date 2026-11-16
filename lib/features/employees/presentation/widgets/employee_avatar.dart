import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/models/employee_record.dart';
import '../providers/employee_providers.dart';

/// Employee photograph with an initials fallback.
///
/// * Employees registered on this device show the photo stored on the
///   device — available offline and before they reach the server.
/// * Server employees load `photoUrl` from the active backend (resolved
///   against the active environment), decoded at display size and cached.
/// * On the web, if the backend sends no CORS headers for photos, the
///   browser falls back to a plain `<img>` element.
class EmployeeAvatar extends ConsumerWidget {
  const EmployeeAvatar({
    super.key,
    required this.record,
    this.size = 52,
    this.radius,
    this.heroTag,
  });

  final EmployeeRecord record;
  final double size;
  final double? radius;
  final Object? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = BorderRadius.circular(radius ?? size * 0.32);
    final fallback = InitialsAvatar(name: record.name, size: size);
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    Widget content;
    final photoRef = record.localPhotoRef;
    if (photoRef != null) {
      final bytes = ref.watch(localPhotoProvider(photoRef)).valueOrNull;
      content = bytes == null
          ? fallback
          : Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: px,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
            );
    } else {
      final repo = ref.watch(employeeRepositoryProvider);
      final url = repo.resolvePhotoUrl(record.view.photoUrl);
      if (url == null) {
        content = fallback;
      } else {
        final headers = repo.photoHeaders;
        content = Image.network(
          url,
          key: ValueKey(url),
          headers: headers.isEmpty ? null : headers,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: px,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          frameBuilder: (_, child, frame, syncLoaded) => syncLoaded || frame != null ? child : fallback,
          errorBuilder: (_, _, _) => fallback,
        );
      }
    }
    content = ClipRRect(borderRadius: r, child: SizedBox(width: size, height: size, child: content));
    if (heroTag != null) content = Hero(tag: heroTag!, child: content);
    return Semantics(image: true, label: 'Photo of ${record.name}', child: content);
  }
}

/// Coloured tile with the person's initials.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hue = name.codeUnits.fold<int>(0, (a, b) => a + b) % 4;
    final accent = const [AppColors.peach, AppColors.success, AppColors.info, AppColors.warning][hue];
    return Container(
      width: size,
      height: size,
      color: Color.alphaBlend(accent.withValues(alpha: context.isDark ? 0.22 : 0.16), p.card),
      alignment: Alignment.center,
      child: Text(
        Fmt.initials(name),
        style: TextStyle(color: context.onTint(accent), fontWeight: FontWeight.w700, fontSize: size * 0.36),
      ),
    );
  }
}
