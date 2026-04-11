import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../data/models/visit_model.dart';
import '../../../../data/local/local_storage_service.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../bloc/home_state.dart';
import '../visits/visit_detail_screen.dart';
import '../visits/visit_edit_screen.dart';

class VisitsTab extends StatelessWidget {
  final List<VisitModel> visits;
  final List<VisitModel> filteredVisits;
  final String? filterClient;
  final List<String> clientNames;
  final String targetUserId;
  final bool isReadOnly;

  const VisitsTab({
    super.key,
    required this.visits,
    required this.filteredVisits,
    this.filterClient,
    required this.clientNames,
    required this.targetUserId,
    this.isReadOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter bar
        if (clientNames.isNotEmpty)
          _buildFilterBar(context),
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
          const Icon(Icons.filter_list_rounded, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: filterClient,
              hint: const Text(
                'All clients',
                style: TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSecondary),
              ),
              isExpanded: true,
              underline: const SizedBox(),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All clients', style: TextStyle(fontFamily: 'Sora', fontSize: 13)),
                ),
                ...clientNames.map((name) => DropdownMenuItem(
                      value: name,
                      child: Text(name, style: const TextStyle(fontFamily: 'Sora', fontSize: 13)),
                    )),
              ],
              onChanged: (val) {
                context.read<HomeBloc>().add(FilterVisitsByClientEvent(val));
              },
            ),
          ),
          if (filterClient != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
              onPressed: () =>
                  context.read<HomeBloc>().add(FilterVisitsByClientEvent(null)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_outlined, size: 56, color: AppTheme.textHint),
          const SizedBox(height: 16),
          Text(
            filterClient != null
                ? 'No visits for $filterClient'
                : 'No customer visits yet',
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 15,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitList(BuildContext context) {
    // Group by date
    final grouped = <String, List<VisitModel>>{};
    for (final visit in filteredVisits) {
      final dateKey = AppUtils.formatDate(visit.checkinTimestamp);
      grouped.putIfAbsent(dateKey, () => []).add(visit);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: sortedDates.length,
      itemBuilder: (context, i) {
        final date = sortedDates[i];
        final dayVisits = grouped[date]!;
        final displayDate = AppUtils.isSameDay(
          DateTime.parse(date),
          DateTime.now(),
        )
            ? 'Today'
            : AppUtils.isSameDay(
                DateTime.parse(date),
                DateTime.now().subtract(const Duration(days: 1)),
              )
                ? 'Yesterday'
                : AppUtils.formatDateDisplay(DateTime.parse(date));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                displayDate,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ...dayVisits.map((v) => _buildVisitCard(context, v)),
          ],
        );
      },
    );
  }

  Widget _buildVisitCard(BuildContext context, VisitModel visit) {
    final isActive = !visit.isCheckedOut;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onCardTap(context, visit),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status indicator
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.accent.withOpacity(0.12)
                        : AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isActive ? Icons.radio_button_checked : Icons.check_circle_rounded,
                    color: isActive ? AppTheme.accent : AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        visit.clientName,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        visit.location,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.login_rounded, size: 12, color: AppTheme.textHint),
                          const SizedBox(width: 4),
                          Text(
                            AppUtils.formatTime(visit.checkinTimestamp),
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 11,
                              color: AppTheme.textHint,
                            ),
                          ),
                          if (visit.checkoutTimestamp != null) ...[
                            const Text(' → ', style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
                            Text(
                              AppUtils.formatTime(visit.checkoutTimestamp!),
                              style: const TextStyle(
                                fontFamily: 'Sora',
                                fontSize: 11,
                                color: AppTheme.textHint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Expense chip
                if (visit.expenseAmount != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '₹${visit.expenseAmount!.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AppTheme.textHint, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onCardTap(BuildContext context, VisitModel visit) {
    if (isReadOnly) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<HomeBloc>(),
          child: VisitDetailScreen(
            visit: visit,
            targetUserId: targetUserId,
            isReadOnly: true,
          ),
        ),
      ));
      return;
    }

    if (!visit.isCheckedOut) {
      // Go directly to edit/checkout screen
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<HomeBloc>(),
          child: VisitEditScreen(
            visit: visit,
            targetUserId: targetUserId,
            isEditMode: false,
          ),
        ),
      ));
    } else {
      // Go to detail screen
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<HomeBloc>(),
          child: VisitDetailScreen(
            visit: visit,
            targetUserId: targetUserId,
          ),
        ),
      ));
    }
  }
}
