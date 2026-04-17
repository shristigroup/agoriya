import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/tracking_model.dart';

class DailyTile extends StatelessWidget {
  final TrackingModel tracking;
  final VoidCallback onTap;

  const DailyTile({super.key, required this.tracking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.parse(tracking.date);
    final now = DateTime.now();
    final isToday = AppUtils.isSameDay(dt, now);
    final isYesterday =
        AppUtils.isSameDay(dt, now.subtract(const Duration(days: 1)));

    final dayLabel = isToday
        ? 'Today'
        : isYesterday
            ? 'Yesterday'
            : _weekday(dt.weekday);
    final dateLabel = AppUtils.formatDateDisplay(dt);

    final punchIn = tracking.startTime;
    final punchOut = tracking.stopTime;
    final duration = tracking.attendanceDuration;

    final statusColor =
        punchOut != null ? AppTheme.textSecondary : AppTheme.punchIn;
    final statusLabel = punchOut != null ? 'Completed' : 'Active';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Date badge
                Container(
                  width: 52,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${dt.day}',
                        style: AppTheme.sora(20, weight: FontWeight.w800,
                            color: AppTheme.primary),
                      ),
                      Text(
                        _shortMonth(dt.month),
                        style: AppTheme.sora(10, weight: FontWeight.w600,
                            color: AppTheme.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Main info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(dayLabel,
                              style: AppTheme.sora(14,
                                  weight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          Text(dateLabel,
                              style: AppTheme.sora(12,
                                  color: AppTheme.textSecondary)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(statusLabel,
                                style: AppTheme.sora(10,
                                    weight: FontWeight.w600,
                                    color: statusColor)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _pill(Icons.login_rounded, AppTheme.punchIn,
                              AppUtils.formatTime(punchIn)),
                          const SizedBox(width: 6),
                          if (punchOut != null) ...[
                            const Icon(Icons.arrow_forward,
                                size: 12, color: AppTheme.textHint),
                            const SizedBox(width: 6),
                            _pill(Icons.logout_rounded, AppTheme.punchOut,
                                AppUtils.formatTime(punchOut)),
                            const SizedBox(width: 6),
                          ],
                          _pill(Icons.access_time_rounded,
                              AppTheme.textSecondary,
                              AppUtils.formatDuration(duration)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _statLabel(Icons.route_rounded,
                              AppUtils.formatDistance(tracking.distance)),
                          const SizedBox(width: 14),
                          _statLabel(Icons.storefront_rounded,
                              '${tracking.visitCount} visits'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: AppTheme.textHint, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(text, style: AppTheme.sora(11, color: color)),
      ],
    );
  }

  Widget _statLabel(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.textHint),
        const SizedBox(width: 4),
        Text(text,
            style: AppTheme.sora(11, color: AppTheme.textSecondary)),
      ],
    );
  }

  String _weekday(int w) => const [
        '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
      ][w];

  String _shortMonth(int m) => const [
        '',
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m];
}
