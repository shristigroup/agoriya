import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../../../data/models/user_model.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneKey = GlobalKey<FormFieldState>();
  final _otpKey = GlobalKey<FormFieldState>();
  final _profileFormKey = GlobalKey<FormState>();

  // ── Step flags ─────────────────────────────────────────────────────────────
  bool _otpSent = false;       // OTP has been dispatched
  bool _otpConfirmed = false;  // OTP has been verified
  String? _selectedManagerId;
  List<UserModel> _allUsers = [];

  @override
  void initState() {
    super.initState();
    // _loadUsers() is intentionally NOT called here — the user is unauthenticated
    // at this point and Firestore rules will block the read. It is called after
    // OTP verification when Firebase Auth has established a session.
  }

  Future<void> _loadUsers() async {
    try {
      final users = await FirestoreRepository().getAllUsers();
      if (mounted) setState(() => _allUsers = users);
    } catch (_) {}
  }

  Future<void> _prefillExistingUser() async {
    try {
      final existing = await FirestoreRepository()
          .getUserByPhone('+91${_phoneController.text}');
      if (existing != null && mounted) {
        setState(() {
          _firstNameController.text = existing.firstName;
          _lastNameController.text = existing.lastName;
          _selectedManagerId = existing.managerId;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _sendOtp(BuildContext context) {
    if (!(_phoneKey.currentState?.validate() ?? false)) return;
    context.read<AuthBloc>().add(SendOtpEvent('+91${_phoneController.text}'));
  }

  void _confirmOtp(BuildContext context) {
    if (!(_otpKey.currentState?.validate() ?? false)) return;
    context.read<AuthBloc>().add(VerifyOtpEvent(_otpController.text));
  }

  void _submit(BuildContext context) {
    if (!(_profileFormKey.currentState?.validate() ?? false)) return;
    context.read<AuthBloc>().add(CompleteProfileEvent(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      managerId: _selectedManagerId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is OtpSent) {
            setState(() => _otpSent = true);
          } else if (state is OtpVerified) {
            setState(() => _otpConfirmed = true);
            _prefillExistingUser();
            _loadUsers(); // user is now authenticated — Firestore read will succeed
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.error,
            ));
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthLoading;
          final sendingOtp  = isLoading && !_otpSent;
          final confirmingOtp = isLoading && _otpSent && !_otpConfirmed;
          final submitting    = isLoading && _otpConfirmed;

          return SafeArea(
            child: Column(
              children: [
                // ── Header ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Agoriya',
                        style: AppTheme.sora(40, weight: FontWeight.w800, color: Colors.white, letterSpacing: -1),
                      ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2),
                      const SizedBox(height: 4),
                      Text('Field Force Tracker',
                        style: AppTheme.sora(16, color: Colors.white.withValues(alpha: 0.7)),
                      ).animate().fadeIn(delay: 200.ms),
                    ],
                  ),
                ),

                // ── Form card ─────────────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),

                          // ── Step 1: Phone ────────────────────────────────
                          _sectionTitle('Phone Number'),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  key: _phoneKey,
                                  controller: _phoneController,
                                  enabled: !_otpSent,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration: const InputDecoration(
                                    prefixText: '+91 ',
                                    prefixStyle: TextStyle(
                                      fontFamily: 'Sora',
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    hintText: '9876543210',
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Required';
                                    if (v.length < 10) return 'Enter valid number';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              _ActionButton(
                                label: 'Get OTP',
                                loading: sendingOtp,
                                done: _otpSent,
                                onPressed: _otpSent ? null : () => _sendOtp(context),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // ── Step 2: OTP ──────────────────────────────────
                          _sectionTitle('OTP'),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  key: _otpKey,
                                  controller: _otpController,
                                  enabled: _otpSent && !_otpConfirmed,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  maxLength: 6,
                                  decoration: const InputDecoration(
                                    hintText: '6-digit OTP',
                                    counterText: '',
                                  ),
                                  validator: (v) {
                                    if (v == null || v.length != 6) {
                                      return 'Enter 6-digit OTP';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              _ActionButton(
                                label: 'Confirm OTP',
                                loading: confirmingOtp,
                                done: _otpConfirmed,
                                onPressed: (!_otpSent || _otpConfirmed)
                                    ? null
                                    : () => _confirmOtp(context),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // ── Step 3: Profile ──────────────────────────────
                          Form(
                            key: _profileFormKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _sectionTitle('Your Name'),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _firstNameController,
                                        enabled: _otpConfirmed && !submitting,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        decoration: const InputDecoration(
                                            hintText: 'First name'),
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty)
                                                ? 'Required'
                                                : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _lastNameController,
                                        enabled: _otpConfirmed && !submitting,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        decoration: const InputDecoration(
                                            hintText: 'Last name'),
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty)
                                                ? 'Required'
                                                : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _sectionTitle('Manager (Optional)'),
                                const SizedBox(height: 12),
                                _buildManagerDropdown(submitting),
                                const SizedBox(height: 28),
                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: (!_otpConfirmed || submitting)
                                        ? null
                                        : () => _submit(context),
                                    child: submitting
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Submit'),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) =>
      Text(title, style: AppTheme.sora(13, weight: FontWeight.w600, color: AppTheme.textSecondary, letterSpacing: 0.5));

  Widget _buildManagerDropdown(bool submitting) {
    final filtered = _allUsers
        .where((u) => u.phoneNumber != '+91${_phoneController.text}')
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return DropdownButtonFormField<String>(
      key: ValueKey(_selectedManagerId),
      initialValue: _selectedManagerId,
      isExpanded: true,
      decoration: const InputDecoration(hintText: 'Select manager'),
      items: [
        const DropdownMenuItem(value: null, child: Text('No manager')),
        ...filtered.map((u) => DropdownMenuItem(
              value: u.id,
              child: Text(u.fullName, overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: (_otpConfirmed && !submitting)
          ? (val) => setState(() => _selectedManagerId = val)
          : null,
    );
  }
}

// ── Reusable inline action button ─────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool done;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.loading,
    required this.done,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: (loading || done) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          backgroundColor: done ? AppTheme.primaryLight : null,
          disabledBackgroundColor:
              done ? AppTheme.primaryLight : null,
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : done
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(label),
      ),
    );
  }
}
