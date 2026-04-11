import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
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
  final _formKey = GlobalKey<FormState>();

  bool _otpSent = false;
  bool _otpVerified = false;
  List<UserModel> _allUsers = [];
  String? _selectedManagerId;
  bool _loadingUsers = false;
  bool _isExistingUser = false; // pre-filled from Firestore

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final users = await FirestoreRepository().getAllUsers();
      setState(() => _allUsers = users);
    } catch (_) {}
    setState(() => _loadingUsers = false);
  }

  Future<void> _prefillExistingUser() async {
    try {
      final phone = '+91${_phoneController.text}';
      final existing = await FirestoreRepository().getUserByPhone(phone);
      if (existing != null && mounted) {
        setState(() {
          _firstNameController.text = existing.firstName;
          _lastNameController.text = existing.lastName;
          _selectedManagerId = existing.managerId;
          _isExistingUser = true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is OtpSent) {
            setState(() => _otpSent = true);
          } else if (state is OtpVerified) {
            setState(() => _otpVerified = true);
            // Pre-fill if existing user
            _prefillExistingUser();
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.error,
              ),
            );
          }
        },
        builder: (context, state) {
          return SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Agoriya',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2),
                      const SizedBox(height: 4),
                      Text(
                        'Field Force Tracker',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.7),
                          fontWeight: FontWeight.w400,
                        ),
                      ).animate().fadeIn(delay: 200.ms),
                    ],
                  ),
                ),
                // Form card
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            _buildSectionTitle('Phone Number'),
                            const SizedBox(height: 12),
                            _buildPhoneField(state),
                            if (_otpSent) ...[
                              const SizedBox(height: 20),
                              _buildSectionTitle('OTP'),
                              const SizedBox(height: 12),
                              _buildOtpField(state),
                            ],
                            if (_otpVerified) ...[
                              const SizedBox(height: 20),
                              _buildSectionTitle('Your Name'),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _buildFirstNameField()),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildLastNameField()),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _buildSectionTitle('Manager (Optional)'),
                              const SizedBox(height: 12),
                              _buildManagerDropdown(state),
                            ],
                            const SizedBox(height: 28),
                            _buildActionButton(context, state),
                            const SizedBox(height: 24),
                          ],
                        ),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Sora',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildPhoneField(AuthState state) {
    return TextFormField(
      controller: _phoneController,
      enabled: !_otpSent,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
        if (v == null || v.isEmpty) return 'Enter phone number';
        if (v.length < 10) return 'Enter valid phone number';
        return null;
      },
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildOtpField(AuthState state) {
    return TextFormField(
      controller: _otpController,
      enabled: !_otpVerified,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 6,
      decoration: const InputDecoration(
        hintText: '6-digit OTP',
        counterText: '',
      ),
      validator: (v) {
        if (v == null || v.length != 6) return 'Enter 6-digit OTP';
        return null;
      },
    ).animate().fadeIn().slideX(begin: 0.1);
  }

  Widget _buildFirstNameField() {
    return TextFormField(
      controller: _firstNameController,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(hintText: 'First name'),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _buildLastNameField() {
    return TextFormField(
      controller: _lastNameController,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(hintText: 'Last name'),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
    ).animate().fadeIn().slideX(begin: 0.1);
  }

  Widget _buildManagerDropdown(AuthState state) {
    // Filter out current user (by phone)
    final filtered = _allUsers
        .where((u) => u.phoneNumber != '+91${_phoneController.text}')
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return DropdownButtonFormField<String>(
      value: _selectedManagerId,
      isExpanded: true,
      decoration: const InputDecoration(hintText: 'Select manager'),
      items: [
        const DropdownMenuItem(value: null, child: Text('No manager')),
        ...filtered.map(
          (u) => DropdownMenuItem(
            value: u.id,
            child: Text(u.fullName, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (val) => setState(() => _selectedManagerId = val),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildActionButton(BuildContext context, AuthState state) {
    final isLoading = state is AuthLoading;

    String label = 'Send OTP';
    VoidCallback? onPressed;

    if (!_otpSent) {
      label = 'Send OTP';
      onPressed = isLoading
          ? null
          : () {
              if (_formKey.currentState?.validate() ?? false) {
                context.read<AuthBloc>().add(
                      SendOtpEvent('+91${_phoneController.text}'),
                    );
              }
            };
    } else if (!_otpVerified) {
      label = 'Verify OTP';
      onPressed = isLoading
          ? null
          : () {
              if (_formKey.currentState?.validate() ?? false) {
                context.read<AuthBloc>().add(
                      VerifyOtpEvent(_otpController.text),
                    );
              }
            };
    } else {
      label = 'Continue';
      onPressed = isLoading
          ? null
          : () {
              if (_formKey.currentState?.validate() ?? false) {
                context.read<AuthBloc>().add(
                      CompleteProfileEvent(
                        firstName: _firstNameController.text.trim(),
                        lastName: _lastNameController.text.trim(),
                        managerId: _selectedManagerId,
                      ),
                    );
              }
            };
    }

    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    ).animate().fadeIn(delay: 400.ms);
  }
}
