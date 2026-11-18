import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_exceptions.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_cards.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_inputs.dart';
import '../../../../core/widgets/app_layout.dart';
import '../../../connectivity/app_features_provider.dart';
import '../../../environments/presentation/providers/environment_providers.dart';
import '../../../sync/presentation/sync_widgets.dart';
import '../../data/models/employee_record.dart';
import '../providers/employee_providers.dart';
import '../widgets/employee_list_widgets.dart';

enum _ViewMode { table, grid }

/// Unified employee list.
///
/// * Records registered on this device and not yet on the server are pinned
///   above the server results (first page), each with its sync status.
/// * Server records use server-side paging, search and source filtering.
///   Records this device registered are matched by server id, so nothing
///   appears twice.
/// * Offline (or when the server fails), the same query is answered from
///   server records cached on the device, labelled with the last refresh.
class EmployeeListScreen extends ConsumerStatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  ConsumerState<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends ConsumerState<EmployeeListScreen> {
  late final TextEditingController _search = TextEditingController(text: ref.read(employeeQueryProvider).query);
  final _scroll = ScrollController();
  Timer? _debounce;
  _ViewMode _mode = _ViewMode.table;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppConstants.searchDebounce, () => _applySearch(value));
  }

  void _applySearch(String value) {
    _debounce?.cancel();
    ref.read(employeeQueryProvider.notifier).setSearch(value);
  }

  void _goToPage(int page) {
    ref.read(employeeQueryProvider.notifier).goToPage(page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _refresh() async {
    ref.read(employeeRefresherProvider)();
    try {
      await ref.read(serverPageProvider.future);
    } catch (_) {
      // shown by the error state
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeEnvironmentProvider, (_, _) {
      _debounce?.cancel();
      _search.clear();
    });

    final features = ref.watch(appFeaturesProvider);
    final query = ref.watch(employeeQueryProvider);
    final listing = ref.watch(employeeListingProvider);
    final linked = ref.watch(linkedLocalByServerIdProvider);
    final counts = ref.watch(localCountsProvider);
    final serverTotal = ref.watch(serverOverviewProvider).valueOrNull?.total;
    final server = listing.server;
    final serverData = server.valueOrNull;
    final loading = server.isLoading;
    final env = ref.watch(activeEnvironmentProvider);
    final desktop = context.isDesktop;
    final mode = desktop ? _mode : _ViewMode.grid;
    final pad = context.pagePadding;

    final subtitleParts = [
      if (serverTotal != null) '${Fmt.number(serverTotal)} on server',
      if (counts.awaiting > 0) '${counts.awaiting} waiting to sync',
      if (features.environmentIndicator) env.environmentName,
    ];
    final header = AppPageHeader(
      title: desktop ? 'Employee Management' : 'Employees',
      subtitle: subtitleParts.isEmpty ? 'Employee records' : subtitleParts.join(' · '),
      actions: [
        if (desktop)
          SegmentedButton<_ViewMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _ViewMode.table, icon: Icon(Icons.table_rows_outlined), tooltip: 'Table view'),
              ButtonSegment(value: _ViewMode.grid, icon: Icon(Icons.grid_view_rounded), tooltip: 'Card view'),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        AppIconButton(
          key: const Key('employees-refresh'),
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh',
          onPressed: loading ? null : _refresh,
        ),
        if (!context.isMobile) ...[
          if (counts.awaiting > 0) const SyncNowButton(),
          AppPrimaryButton(
            label: 'Register employee',
            icon: Icons.add_rounded,
            expand: false,
            height: 46,
            onPressed: () => context.go(Routes.enroll),
          ),
        ] else if (counts.awaiting > 0)
          AppIconButton(
            icon: Icons.sync_rounded,
            tooltip: 'Sync now',
            background: AppColors.peach,
            foreground: Colors.white,
            onPressed: () => runSyncNow(context, ref),
          ),
      ],
    );

    final searchBar = AppSearchBar(
      fieldKey: const Key('employee-search'),
      controller: _search,
      hint: 'Search number, name, designation or template ID',
      onChanged: _onSearchChanged,
      onSubmitted: _applySearch,
    );
    final sourceChips = SourceFilterChips(
      selected: query.source,
      onChanged: ref.read(employeeQueryProvider.notifier).setSource,
    );
    final statusChips = RecordFilterChips(
      selected: listing.filter,
      onChanged: (f) {
        ref.read(recordFilterProvider.notifier).set(f);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      },
      counts: {
        RecordFilter.all: serverTotal == null ? null : serverTotal + counts.awaiting,
        RecordFilter.onServer: serverTotal,
        RecordFilter.localOnly: counts.localOnly,
        RecordFilter.pending: counts.pending + counts.syncing,
        RecordFilter.failed: counts.failed,
      },
    );
    final controls = context.isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchBar,
              const SizedBox(height: Space.sm),
              statusChips,
              const SizedBox(height: Space.xs),
              sourceChips,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(flex: 5, child: searchBar),
                  const SizedBox(width: Space.md),
                  Flexible(flex: 4, child: sourceChips),
                ],
              ),
              const SizedBox(height: Space.sm),
              statusChips,
            ],
          );

    final local = listing.localRecords;
    final serverRecords = listing.serverRecords(linked);
    final filtered = query.query.trim().isNotEmpty || query.source != null || listing.filter != RecordFilter.all;

    final slivers = <Widget>[
      SliverToBoxAdapter(child: header),
      SliverToBoxAdapter(child: controls),
      SliverToBoxAdapter(
        child: SizedBox(
          height: Space.lg,
          child: Center(
            child: loading && serverData != null
                ? const LinearProgressIndicator(key: Key('list-reloading'), minHeight: 2)
                : null,
          ),
        ),
      ),
      if (serverData != null && serverData.fromCache)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: AppBanner(
              key: const Key('stale-banner'),
              type: SnackType.info,
              title: 'Showing saved server records',
              message: [
                switch (serverData.error) {
                  final ApiException e when !e.isNetwork => 'The server returned an error: ${e.message}',
                  _ => 'The server can\'t be reached.',
                },
                serverData.lastRefresh == null
                    ? 'No server records have been saved on this device yet.'
                    : 'Server records are from ${Fmt.dateTime(serverData.lastRefresh)} and may be out of date.',
              ].join(' '),
              action: TextButton(onPressed: _refresh, child: const Text('Retry')),
            ),
          ),
        ),
      if (local.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: AppSectionHeader(title: 'On this device', subtitle: '${local.length} not yet on the server'),
        ),
        ..._records(context, local, mode, keyPrefix: 'local'),
        const SliverToBoxAdapter(child: SizedBox(height: Space.lg)),
      ],
      if (!listing.filter.isLocal) ...[
        if (local.isNotEmpty && serverRecords.isNotEmpty)
          SliverToBoxAdapter(
            child: AppSectionHeader(title: 'On server', subtitle: serverData?.fromCache == true ? 'Saved copy' : null),
          ),
        ..._serverContent(context, server, serverRecords, local.isEmpty, filtered, mode),
        if (serverData != null && serverData.page.totalPages > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: Space.lg),
              child: PaginationBar(page: serverData.page, onPage: _goToPage, compact: !desktop, busy: loading),
            ),
          ),
      ] else if (local.isEmpty)
        SliverToBoxAdapter(
          child: AppEmptyState(
            icon: Icons.cloud_done_outlined,
            title: 'Nothing here',
            message: 'No employees on this device match "${listing.filter.label}".',
            actionLabel: 'Show all employees',
            onAction: () => ref.read(recordFilterProvider.notifier).set(RecordFilter.all),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.peach,
          onRefresh: _refresh,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      context.isMobile ? Space.md : Space.xl,
                      pad,
                      context.useSidebar ? Space.xl : 120,
                    ),
                    sliver: SliverMainAxisGroup(slivers: slivers),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _serverContent(
    BuildContext context,
    AsyncValue<ServerListing?> server,
    List<EmployeeRecord> records,
    bool nothingLocal,
    bool filtered,
    _ViewMode mode,
  ) {
    final data = server.valueOrNull;
    if (data == null) {
      if (server.hasError) {
        final e = server.error!;
        return [
          SliverToBoxAdapter(
            child: AppEmptyState(
              icon: e is ApiException && e.isNetwork ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
              title: 'Could not load employees',
              message: friendlyError(e),
              actionLabel: 'Try again',
              onAction: _refresh,
            ),
          ),
        ];
      }
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: AppLoadingIndicator(message: 'Loading employees…'),
          ),
        ),
      ];
    }
    if (records.isEmpty) {
      if (!nothingLocal) return const [];
      return [
        SliverToBoxAdapter(
          child: filtered
              ? AppEmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'No matching employees',
                  message: 'Try a different search term or filter.',
                  actionLabel: 'Clear filters',
                  onAction: () {
                    _search.clear();
                    ref.read(employeeQueryProvider.notifier).reset();
                    ref.read(recordFilterProvider.notifier).set(RecordFilter.all);
                  },
                )
              : AppEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: data.fromCache ? 'No saved records' : 'No employees yet',
                  message: data.fromCache
                      ? 'Connect to the server to load employee records. You can still register employees.'
                      : 'Registered employees will appear here.',
                  actionLabel: 'Register an employee',
                  onAction: () => context.go(Routes.enroll),
                ),
        ),
      ];
    }
    return _records(context, records, mode, keyPrefix: 'server');
  }

  List<Widget> _records(BuildContext context, List<EmployeeRecord> items, _ViewMode mode, {required String keyPrefix}) {
    if (mode == _ViewMode.table) {
      return [
        SliverToBoxAdapter(
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(
              children: [
                const EmployeeTableHeader(),
                Divider(color: context.palette.border, height: 1),
                for (var i = 0; i < items.length; i++)
                  animatedListItem(
                    context,
                    i,
                    EmployeeTableRow(key: ValueKey('$keyPrefix-${items[i].key}'), record: items[i]),
                  ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverLayoutBuilder(
        builder: (context, c) {
          final w = c.crossAxisExtent;
          final cols = w >= 1100 ? 3 : (w >= 640 ? 2 : 1);
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: Space.md,
              crossAxisSpacing: Space.md,
              // Room for name, designation and up to two rows of tags
              // (sync status, source, dates) on narrow cards.
              mainAxisExtent: 180,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => animatedListItem(
              context,
              i,
              EmployeeCard(key: ValueKey('$keyPrefix-${items[i].key}'), record: items[i]),
            ),
          );
        },
      ),
    ];
  }
}
