import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';

/// Shown after the user's account was deleted server-side, instead of
/// dropping them straight onto the login screen. Styled like the punch-in
/// success screen; redirects to login on its own after a short delay.
class AccountDeletedScreen extends StatefulWidget {
  const AccountDeletedScreen({super.key});

  @override
  State<AccountDeletedScreen> createState() => _AccountDeletedScreenState();
}

class _AccountDeletedScreenState extends State<AccountDeletedScreen>
    with SingleTickerProviderStateMixin {
  // Long enough to read the message, which is longer than the punch screens'.
  static const _redirectDelay = Duration(seconds: 5);

  late final AnimationController _rippleController;
  Timer? _redirectTimer;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // CheckAuthEvent finds no stored user (cleared by AccountDeletedEvent)
    // and emits AuthUnauthenticated, which shows the login screen.
    _redirectTimer = Timer(_redirectDelay, () {
      if (mounted) context.read<AuthBloc>().add(CheckAuthEvent());
    });
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Stack(
        alignment: Alignment.center,
        children: [
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
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 54),
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
                Text(
                  'Account Deleted',
                  textAlign: TextAlign.center,
                  style: AppTheme.sora(30,
                      weight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5),
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3, delay: 300.ms),
                const SizedBox(height: 16),
                Text(
                  'All your data has been permanently removed from our servers.',
                  textAlign: TextAlign.center,
                  style: AppTheme.sora(15,
                      color: Colors.white.withValues(alpha: 0.85)),
                ).animate().fadeIn(delay: 500.ms),
                const SizedBox(height: 10),
                Text(
                  'No one, including your team owner, can view it.',
                  textAlign: TextAlign.center,
                  style: AppTheme.sora(14,
                      color: Colors.white.withValues(alpha: 0.65)),
                ).animate().fadeIn(delay: 700.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
