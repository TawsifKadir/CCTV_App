import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/motion.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_cards.dart';
import '../../data/models/employee.dart';
import '../../data/models/employee_page.dart';
import '../../../authentication/domain/permissions.dart';
import '../../data/models/employee_record.dart';
import '../../../sync/presentation/sync_widgets.dart';
import 'employee_avatar.dart';

void openEmployee(BuildContext context, EmployeeRecord r) => context.push(Routes.employee(r.key), extra: r);

/// Tag for the enrollment source.
class SourcePill extends StatelessWidget {
  const SourcePill({super.key, required this.employee, this.dense = true, this.short = false});
  final Employee employee;
  final bool dense;

  /// "Photo" / "Capture" for narrow table columns.
  final bool short;

  @override
  Widget build(BuildContext context) {
    final s = employee.enrollmentSource;
    final (Color color, IconData icon) = switch (s) {
      EnrollmentSource.capture => (AppColors.info, Icons.videocam_outlined),
      EnrollmentSource.photo => (AppColors.primary, Icons.photo_outlined),
      null => (AppColors.muted, Icons.help_outline_rounded),
    };
    final label = !short
        ? employee.sourceLabel
        : switch (s) {
            EnrollmentSource.capture => 'Capture',
            EnrollmentSource.photo => 'Photo',
            null => employee.sourceLabel,
          };
    return AppPill(label: label, color: color, icon: icon, dense: dense);
  }
}

/// Rounded employee card (phones, and the desktop grid view).
class EmployeeCard extends StatelessWidget {
  const EmployeeCard({super.key, required this.record});
  final EmployeeRecord record;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final e = record.view;
    return AppCard(
      onTap: () => openEmployee(context, record),
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EmployeeAvatar(record: record, size: 64, heroTag: 'emp-${record.key}'),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (e.employeeNo != null)
                      Text(Fmt.employeeNo(e.employeeNo), style: t.labelMedium?.copyWith(color: context.palette.accent)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  e.designation ?? '—',
                  style: t.bodyMedium?.copyWith(color: p.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SyncStatusBadge(record: record),
                    if (record.isOnServer) SourcePill(employee: e),
                    _Meta(icon: Icons.cake_outlined, text: Fmt.date(e.dateOfBirth)),
                    _Meta(icon: Icons.event_available_outlined, text: Fmt.date(e.enrolledAt)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: muted),
        const SizedBox(width: 3),
        Text(text, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// Desktop table header.
class EmployeeTableHeader extends StatelessWidget {
  const EmployeeTableHeader({super.key, this.showActions = false});

  /// Admin-only actions column.
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget head(String s, int flex) => Expanded(
      flex: flex,
      child: Text(
        s.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.labelSmall?.copyWith(letterSpacing: 0.6),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm + 2),
      child: Row(
        children: [
          const SizedBox(width: _photoCol),
          head('Emp. No', 2),
          head('Name', 4),
          head('Designation', 4),
          head('Date of birth', 3),
          head('Enrolled', 3),
          head('Source', 3),
          head('Status', 3),
          SizedBox(
            width: showActions ? _actionsCol : _chevronCol,
            child: showActions ? Text('ACTIONS', maxLines: 1, style: t.labelSmall?.copyWith(letterSpacing: 0.6)) : null,
          ),
        ],
      ),
    );
  }
}

const double _photoCol = 56;
const double _actionsCol = 88;
const double _chevronCol = 32;

/// One row of the desktop table. Hover is a cheap colour change only.
class EmployeeTableRow extends ConsumerStatefulWidget {
  const EmployeeTableRow({super.key, required this.record});
  final EmployeeRecord record;

  @override
  ConsumerState<EmployeeTableRow> createState() => _EmployeeTableRowState();
}

class _EmployeeTableRowState extends ConsumerState<EmployeeTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final rec = widget.record;
    final e = rec.view;
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final perms = ref.watch(permissionsProvider);
    final showActions = perms.canEditEmployees || perms.canDeleteEmployees;
    Widget cell(int flex, Widget child) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: Space.sm),
        child: child,
      ),
    );
    Text one(String s, TextStyle? style) => Text(s, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: 'Open ${e.name}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openEmployee(context, rec),
          child: ColoredBox(
            color: _hover ? p.backgroundAlt.withValues(alpha: 0.55) : Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: _photoCol,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: EmployeeAvatar(record: rec, size: 42, heroTag: 'emp-${rec.key}'),
                    ),
                  ),
                  cell(2, one(Fmt.employeeNo(e.employeeNo), t.labelLarge)),
                  cell(4, one(e.name, t.titleSmall)),
                  cell(4, one(e.designation ?? '—', t.bodyMedium)),
                  cell(3, one(Fmt.date(e.dateOfBirth), t.bodyMedium)),
                  cell(3, one(Fmt.date(e.enrolledAt), t.bodyMedium)),
                  cell(
                    3,
                    rec.isOnServer
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: SourcePill(employee: e, short: true),
                          )
                        : one('Pending', t.bodySmall),
                  ),
                  cell(
                    3,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SyncStatusBadge(record: rec, short: true),
                    ),
                  ),
                  if (showActions)
                    SizedBox(
                      width: _actionsCol,
                      child: rec.isOnServer
                          ? Row(
                              children: [
                                IconButton(
                                  key: Key('row-edit-${rec.key}'),
                                  tooltip: 'Edit',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () => requestEditEmployee(context, perms),
                                ),
                                IconButton(
                                  key: Key('row-delete-${rec.key}'),
                                  tooltip: 'Delete',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                                  onPressed: () => requestDeleteEmployee(context, perms),
                                ),
                              ],
                            )
                          : null,
                    )
                  else
                    SizedBox(
                      width: _chevronCol,
                      child: Icon(Icons.chevron_right_rounded, color: _hover ? AppColors.primary : p.textMuted),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// All / Photo Upload / Camera Capture.
class SourceFilterChips extends StatelessWidget {
  const SourceFilterChips({super.key, required this.selected, required this.onChanged});

  final EnrollmentSource? selected;
  final ValueChanged<EnrollmentSource?> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <(EnrollmentSource?, String, IconData)>[
      (null, 'All', Icons.groups_2_outlined),
      (EnrollmentSource.photo, 'Photo Upload', Icons.photo_outlined),
      (EnrollmentSource.capture, 'Camera Capture', Icons.videocam_outlined),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: _FilterChip(
                key: Key('source-${o.$1?.apiValue ?? 'all'}'),
                label: o.$2,
                icon: o.$3,
                selected: selected == o.$1,
                onTap: () => onChanged(o.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({super.key, required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final fg = selected ? Colors.white : p.text;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? p.nav : p.card,
        shape: StadiumBorder(side: BorderSide(color: selected ? p.nav : p.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: selected ? AppColors.primary : p.textMuted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: t.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Server-side pagination controls. Compact on phones; numbered on desktop.
class PaginationBar extends StatelessWidget {
  const PaginationBar({super.key, required this.page, required this.onPage, this.compact = false, this.busy = false});

  final EmployeePage page;
  final ValueChanged<int> onPage;
  final bool compact;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final current = page.page;
    final total = page.totalPages;
    final summary = page.totalElements == 0
        ? 'No employees'
        : '${page.firstItemNumber}–${page.lastItemNumber} of ${page.totalElements}';
    final prev = AppIconButton(
      key: const Key('page-prev'),
      icon: Icons.chevron_left_rounded,
      tooltip: 'Previous page',
      onPressed: page.hasPrevious && !busy ? () => onPage(current - 1) : null,
    );
    final next = AppIconButton(
      key: const Key('page-next'),
      icon: Icons.chevron_right_rounded,
      tooltip: 'Next page',
      onPressed: page.hasNext && !busy ? () => onPage(current + 1) : null,
    );
    final pageLabel = Text(
      total == 0 ? 'Page 0 of 0' : 'Page ${current + 1} of $total',
      key: const Key('page-label'),
      style: t.labelLarge,
    );

    if (compact) {
      return Row(
        children: [
          Expanded(child: Text(summary, style: t.bodySmall)),
          prev,
          const SizedBox(width: Space.xs),
          pageLabel,
          const SizedBox(width: Space.xs),
          next,
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text('Showing $summary employees', style: t.bodyMedium?.copyWith(color: p.textMuted)),
        ),
        DefaultTextStyle.merge(
          style: TextStyle(color: p.textMuted),
          child: pageLabel,
        ),
        const SizedBox(width: Space.md),
        prev,
        const SizedBox(width: Space.xs),
        for (final i in _windowed(current, total)) ...[
          if (i == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('…', style: t.labelLarge),
            )
          else
            _PageNumber(index: i, selected: i == current, onTap: busy ? null : () => onPage(i)),
          const SizedBox(width: 4),
        ],
        const SizedBox(width: Space.xs - 4),
        next,
      ],
    );
  }

  /// Page indexes to show, with `null` for gaps: 1 … 4 5 6 … 20.
  static List<int?> _windowed(int current, int total) {
    if (total <= 7) return [for (var i = 0; i < total; i++) i];
    final out = <int?>[0];
    final start = (current - 1).clamp(1, total - 4);
    final end = (current + 1).clamp(3, total - 2);
    if (start > 1) out.add(null);
    for (var i = start; i <= end; i++) {
      out.add(i);
    }
    if (end < total - 2) out.add(null);
    out.add(total - 1);
    return out;
  }
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({required this.index, required this.selected, required this.onTap});
  final int index;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: Radii.smAll,
      child: InkWell(
        borderRadius: Radii.smAll,
        onTap: selected ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 38),
          height: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('${index + 1}', style: t.labelLarge?.copyWith(color: selected ? Colors.white : p.text)),
        ),
      ),
    );
  }
}

/// Compact row used on the dashboard for recent records.
class EmployeeListTile extends StatelessWidget {
  const EmployeeListTile({super.key, required this.record});
  final EmployeeRecord record;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = record.view;
    return InkWell(
      borderRadius: Radii.mdAll,
      onTap: () => openEmployee(context, record),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs + 2, horizontal: Space.xs),
        child: Row(
          children: [
            EmployeeAvatar(record: record, size: 44),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: t.titleSmall, overflow: TextOverflow.ellipsis),
                  Text(
                    [if (e.employeeNo != null) Fmt.employeeNo(e.employeeNo), e.designation ?? '—'].join(' · '),
                    style: t.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.xs),
            SyncStatusBadge(record: record),
          ],
        ),
      ),
    );
  }
}

/// Grid/list item with a bounded entrance animation.
Widget animatedListItem(BuildContext context, int index, Widget child) =>
    child.entrance(context, index: index, maxAnimated: 8);

/// All / On server / Local only / Pending sync / Failed sync, with counts.
class RecordFilterChips extends StatelessWidget {
  const RecordFilterChips({super.key, required this.selected, required this.onChanged, required this.counts});

  final RecordFilter selected;
  final ValueChanged<RecordFilter> onChanged;

  /// `null` count = unknown (e.g. server total while never online).
  final Map<RecordFilter, int?> counts;

  @override
  Widget build(BuildContext context) {
    const icons = {
      RecordFilter.all: Icons.groups_2_outlined,
      RecordFilter.onServer: Icons.cloud_done_outlined,
      RecordFilter.localOnly: Icons.smartphone_rounded,
      RecordFilter.pending: Icons.cloud_upload_outlined,
      RecordFilter.failed: Icons.error_outline_rounded,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in RecordFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: _FilterChip(
                key: Key('filter-${f.name}'),
                label: counts[f] == null ? f.label : '${f.label}  ${counts[f]}',
                icon: icons[f]!,
                selected: selected == f,
                onTap: () => onChanged(f),
              ),
            ),
        ],
      ),
    );
  }
}
