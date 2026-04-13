import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../data/models/visit_model.dart';
import '../../../../data/local/local_storage_service.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../visits/visit_detail_screen.dart';
import '../visits/visit_edit_screen.dart';

class VisitsTab extends StatelessWidget {
  final List<VisitModel> visits;
  final List<VisitModel> filteredVisits;
  final String? filterClient;
  final List<String> clientNames;
  final String targetUserId;
  final bool isReadOnly;
  final bool isPunchedOut;

  const VisitsTab({
    super.key,
    required this.visits,
    required this.filteredVisits,
    this.filterClient,
    required this.clientNames,
    required this.targetUserId,
    this.isReadOnly = false,
    this.isPunchedOut = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isPunchedOut) _PunchedOutBanner(),
        if (clientNames.isNotEmpty) _buildFilterBar(context),
        Expanded(
          child: filteredVisits.isEmpty
              ? _buildEmptyState()
              : _buildVisitList(context),
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.filter_list_rounded, size: 18,
              color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: filterClient,
              hint: Text('All clients',
                  style: AppTheme.sora(13, color: AppTheme.textSecondary)),
              isExpanded: true,
              underline: const SizedBox(),
              items: [
                DropdownMenuItem(
                    value: null,
                    child: Text('All clients', style: AppTheme.sora(13))),
                ...clientNames.map((name) => DropdownMenuItem(
                    value: name,
                    child: Text(name, style: AppTheme.sora(13)))),
              ],
              onChanged: (val) =>
                  context.read<HomeBloc>().add(FilterVisitsByClientEvent(val)),
            ),
          ),
          if (filterClient != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 18,
                  color: AppTheme.textSecondary),
              onPressed: () => context
                  .read<HomeBloc>()
                  .add(FilterVisitsByClientEvent(null)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final icon = isPunchedOut
        ? Icons.lock_clock_rounded
        : Icons.storefront_outlined;
    final message = filterClient != null
        ? 'No visits for $filterClient'
        : isPunchedOut
            ? 'No visits recorded today'
            : 'No customer visits yet';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppTheme.textHint),
          const SizedBox(height: 16),
          Text(message,
              style: AppTheme.sora(15, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildVisitList(BuildContext context) {
    final grouped = <String, List<VisitModel>>{};
    for (final v in filteredVisits) {
      grouped.putIfAbsent(AppUtils.formatDate(v.checkinTimestamp), () => [])
          .add(v);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: sortedDates.length,
      itemBuilder: (context, i) {
        final date = sortedDates[i];
        final dayVisits = grouped[date]!;
        final dt = DateTime.parse(date);
        final displayDate = AppUtils.isSameDay(dt, DateTime.now())
            ? 'Today'
            : AppUtils.isSameDay(dt, DateTime.now().subtract(const Duration(days: 1)))
                ? 'Yesterday'
                : AppUtils.formatDateDisplay(dt);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(displayDate,
                  style: AppTheme.sora(12,
                      weight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.5)),
            ),
            ...dayVisits.map((v) => _VisitCard(
                  visit: v,
                  targetUserId: targetUserId,
                  isReadOnly: isReadOnly,
                )),
          ],
        );
      },
    );
  }
}

class _PunchedOutBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        color: AppTheme.punchOut.withOpacity(0.1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_clock_rounded,
                size: 16, color: AppTheme.punchOut.withOpacity(0.8)),
            const SizedBox(width: 8),
            Text('Punched Out — day is complete',
                style: AppTheme.sora(13,
                    weight: FontWeight.w600,
                    color: AppTheme.punchOut.withOpacity(0.8))),
          ],
        ),
      );
}

class _VisitCard extends StatelessWidget {
  final VisitModel visit;
  final String targetUserId;
  final bool isReadOnly;
  const _VisitCard(
      {required this.visit,
      required this.targetUserId,
      required this.isReadOnly});

  void _onTap(BuildContext context) {
    if (isReadOnly) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<HomeBloc>(),
          child: VisitDetailScreen(
              visit: visit, targetUserId: targetUserId, isReadOnly: true),
        ),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BlocProvider.value(
        value: context.read<HomeBloc>(),
        child: visit.isCheckedOut
            ? VisitDetailScreen(visit: visit, targetUserId: targetUserId)
            : VisitEditScreen(
                visit: visit, targetUserId: targetUserId, isEditMode: false),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isActive = !visit.isCheckedOut;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onTap(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.accent.withOpacity(0.12)
                        : AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isActive
                        ? Icons.radio_button_checked
                        : Icons.check_circle_rounded,
                    color: isActive ? AppTheme.accent : AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(visit.clientName,
                          style: AppTheme.sora(14, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(visit.location,
                          style: AppTheme.sora(12, color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.login_rounded, size: 12,
                              color: AppTheme.textHint),
                          const SizedBox(width: 4),
                          Text(AppUtils.formatTime(visit.checkinTimestamp),
                              style: AppTheme.sora(11, color: AppTheme.textHint)),
                          if (visit.checkoutTimestamp != null) ...[
                            Text(' → ',
                                style: AppTheme.sora(11,
                                    color: AppTheme.textHint)),
                            Text(
                                AppUtils.formatTime(visit.checkoutTimestamp!),
                                style: AppTheme.sora(11,
                                    color: AppTheme.textHint)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (visit.expenseAmount != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        '₹${visit.expenseAmount!.toStringAsFixed(0)}',
                        style: AppTheme.sora(12,
                            weight: FontWeight.w700, color: AppTheme.primary)),
                  ),
                ],
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: AppTheme.textHint, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
