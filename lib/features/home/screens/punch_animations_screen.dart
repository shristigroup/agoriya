import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/attendance_model.dart';

class PunchInSuccessScreen extends StatefulWidget {
  final AttendanceModel attendance;
  const PunchInSuccessScreen({super.key, required this.attendance});

  @override
  State<PunchInSuccessScreen> createState() => _PunchInSuccessScreenState();
}

class _PunchInSuccessScreenState extends State<PunchInSuccessScreen>
    with TickerProviderStateMixin {
  late AnimationController _rippleController;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // Auto dismiss after 2.5s
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final punchInTime = widget.attendance.punchInTimestamp != null
        ? AppUtils.formatTime(widget.attendance.punchInTimestamp!)
        : '';

    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple circles
          ...List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _rippleController,
              builder: (_, __) {
                final progress = (_rippleController.value + i * 0.33) % 1.0;
                return Transform.scale(
                  scale: 0.4 + progress * 1.2,
                  child: Opacity(
                    opacity: (1 - progress) * 0.4,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Check icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.15),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 54,
                ),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0, 0),
                    end: const Offset(1, 1),
                    duration: 500.ms,
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(),

              const SizedBox(height: 32),

              Text('Punched In!',
                style: AppTheme.sora(32, weight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
              )
                  .animate()
                  .fadeIn(delay: 300.ms)
                  .slideY(begin: 0.3, delay: 300.ms),

              const SizedBox(height: 8),

              Text('Started at $punchInTime',
                style: AppTheme.sora(16, color: Colors.white.withOpacity(0.75)),
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 16),

              Text('Have a great day! 🎯',
                style: AppTheme.sora(14, color: Colors.white.withOpacity(0.6)),
              ).animate().fadeIn(delay: 700.ms),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Punch Out Summary Screen ───────────────────────────────────────────────

class PunchOutSummaryScreen extends StatefulWidget {
  final AttendanceModel attendance;
  final Duration totalTime;

  const PunchOutSummaryScreen({
    super.key,
    required this.attendance,
    required this.totalTime,
  });

  @override
  State<PunchOutSummaryScreen> createState() => _PunchOutSummaryScreenState();
}

class _PunchOutSummaryScreenState extends State<PunchOutSummaryScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Moon icon
              const Icon(
                Icons.nights_stay_rounded,
                color: AppTheme.accent,
                size: 64,
              )
                  .animate()
                  .scale(
                    begin: const Offset(0, 0),
                    end: const Offset(1, 1),
                    duration: 600.ms,
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(),

              const SizedBox(height: 32),

              Text('Day Complete!',
                textAlign: TextAlign.center,
                style: AppTheme.sora(30, weight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3, delay: 400.ms),

              const SizedBox(height: 32),

              // Stats card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    _statRow(
                      Icons.access_time_rounded,
                      'Time in office',
                      AppUtils.formatDuration(widget.totalTime),
                    ),
                    const Divider(color: Colors.white12, height: 28),
                    _statRow(
                      Icons.directions_walk_rounded,
                      'Distance covered',
                      AppUtils.formatDistance(widget.attendance.distance),
                    ),
                    const Divider(color: Colors.white12, height: 28),
                    _statRow(
                      Icons.storefront_rounded,
                      'Customer visits',
                      '${widget.attendance.customerVisitCount}',
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2, delay: 600.ms),

              const SizedBox(height: 28),

              Text(
                '🌟 Your manager has been informed. Keep up the great work!',
                textAlign: TextAlign.center,
                style: AppTheme.sora(14, color: Colors.white.withOpacity(0.6), height: 1.6),
              ).animate().fadeIn(delay: 900.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: AppTheme.sora(13, color: Colors.white.withOpacity(0.6))),
        ),
        Text(value, style: AppTheme.sora(16, weight: FontWeight.w700, color: Colors.white)),
      ],
    );
  }
}
