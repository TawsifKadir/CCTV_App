import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_layout.dart';
import '../../../dashboard/widgets/dashboard_widgets.dart';
import '../../../environments/presentation/providers/environment_providers.dart';

/// On-device activity log: registrations, sign-ins and environment changes
/// made by operators on this device. Not backend data.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  bool _currentEnvOnly = false;

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(activeEnvironmentProvider);
    final all = ref.watch(activitiesProvider);
    final items = _currentEnvOnly ? all.where((a) => a.environmentId == env.environmentId).toList() : all;
    final pad = context.pagePadding;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pad, context.isMobile ? Space.md : Space.xl, pad, 0),
                  sliver: SliverToBoxAdapter(
                    child: AppPageHeader(
                      title: 'Activity',
                      subtitle: 'What happened on this device',
                      actions: [
                        FilterChip(
                          label: Text('${env.environmentName} only'),
                          selected: _currentEnvOnly,
                          onSelected: (v) => setState(() => _currentEnvOnly = v),
                        ),
                      ],
                    ),
                  ),
                ),
                if (items.isEmpty)
                  const SliverToBoxAdapter(
                    child: AppEmptyState(
                      icon: Icons.history_rounded,
                      title: 'No activity yet',
                      message: 'Registrations, sign-ins and environment changes will appear here.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, context.useSidebar ? Space.xl : 120),
                    sliver: DecoratedSliver(
                      decoration: BoxDecoration(
                        color: context.palette.card,
                        borderRadius: BorderRadius.circular(Radii.lg),
                      ),
                      sliver: SliverPadding(
                        padding: const EdgeInsets.all(Space.lg - 4),
                        // Lazily built: the log can hold over a hundred entries.
                        sliver: SliverList.builder(
                          itemCount: items.length,
                          itemBuilder: (context, i) => ActivityTile(activity: items[i], isLast: i == items.length - 1),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
