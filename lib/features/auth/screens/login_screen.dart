import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/org_code_model.dart';

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
  final _codeController = TextEditingController();
  final _phoneKey = GlobalKey<FormFieldState>();
  final _otpKey = GlobalKey<FormFieldState>();
  final _profileFormKey = GlobalKey<FormState>();

  bool _otpSent = false;
  bool _otpConfirmed = false;

  _CodeState _codeState = _CodeState.idle;
  String? _codeError;
  OrgCodeModel? _orgCodeDoc;
  List<UserModel> _orgMembers = [];

  String? _selectedManagerId;
  String? _selfId; // current user's doc ID — excluded from manager dropdown
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _prefillExistingUser() async {
    try {
      final existing = await FirestoreRepository()
          .getUserByPhone('+91${_phoneController.text}');
      if (existing != null && mounted) {
        setState(() {
          _firstNameController.text = existing.firstName;
          _lastNameController.text = existing.lastName;
          _selfId = existing.id;
        });
        if (existing.code != null && existing.code!.isNotEmpty) {
          _codeController.text = existing.code!;
          await _getPeople(preSelectManagerId: existing.managerId);
        }
      }
    } catch (_) {
      // proceed without prefill
    }
  }

  Future<void> _getPeople({String? preSelectManagerId}) async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() { _codeError = 'Enter a 6-character code'; _codeState = _CodeState.idle; });
      return;
    }
    setState(() { _codeState = _CodeState.loading; _codeError = null; });
    try {
      final repo = FirestoreRepository();
      final orgCode = await repo.getOrgCode(code);
      if (orgCode == null) {
        if (mounted) setState(() { _codeState = _CodeState.idle; _codeError = 'Code not found'; });
        return;
      }
      if (orgCode.isFull) {
        if (mounted) setState(() { _codeState = _CodeState.idle; _codeError = 'Organisation is full (${orgCode.currentUserCount}/${orgCode.totalUserCount} seats)'; });
        return;
      }
      final members = await repo.getOrgMembers(code);
      members.sort((a, b) => a.fullName.compareTo(b.fullName));
      if (mounted) {
        setState(() {
          _orgCodeDoc = orgCode;
          _orgMembers = members;
          _selectedManagerId = preSelectManagerId != null &&
                  members.any((m) => m.id == preSelectManagerId)
              ? preSelectManagerId
              : null;
          _codeState = _CodeState.loaded;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _codeState = _CodeState.idle; _codeError = 'Could not reach server'; });
    }
  }

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

    final codeText = _codeController.text.trim().toUpperCase();

    // Code entered but not yet verified — user must click Get People first.
    if (codeText.isNotEmpty && _codeState != _CodeState.loaded) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Click "Get People" to verify the organisation code'),
        backgroundColor: AppTheme.error,
      ));
      return;
    }

    context.read<AuthBloc>().add(CompleteProfileEvent(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      managerId: _selectedManagerId,
      orgCode: _codeState == _CodeState.loaded ? codeText : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is OtpSent) {
            setState(() => _otpSent = true);
          } else if (state is OtpVerified) {
            setState(() => _otpConfirmed = true);
            _prefillExistingUser();
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.error,
            ));
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthLoading;
          final sendingOtp = isLoading && !_otpSent;
          final confirmingOtp = isLoading && _otpSent && !_otpConfirmed;
          final submitting = isLoading && _otpConfirmed;

          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/logo/tf-logo.png',
                        height: 100,
                        width: 100,
                      ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.85, 0.85)),
                      const SizedBox(height: 16),
                      Text.rich(
                        TextSpan(
                          text: 'TrackFolks',
                          style: AppTheme.sora(36, weight: FontWeight.w800, color: AppTheme.primary, letterSpacing: -1),
                          children: _appVersion.isNotEmpty
                              ? [
                                  WidgetSpan(
                                    child: Transform.translate(
                                      offset: const Offset(3, -14),
                                      child: Text(
                                        'v$_appVersion',
                                        style: AppTheme.sora(11, color: AppTheme.primary.withValues(alpha: 0.75)),
                                      ),
                                    ),
                                  ),
                                ]
                              : [],
                        ),
                      ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2),
                      const SizedBox(height: 4),
                      Text('Field Force Tracker',
                        style: AppTheme.sora(15, color: AppTheme.primary.withValues(alpha: 0.75)),
                      ).animate().fadeIn(delay: 200.ms),
                    ],
                  ),
                ),

                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                                        textCapitalization: TextCapitalization.words,
                                        decoration: const InputDecoration(hintText: 'First name'),
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _lastNameController,
                                        enabled: _otpConfirmed && !submitting,
                                        textCapitalization: TextCapitalization.words,
                                        decoration: const InputDecoration(hintText: 'Last name'),
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                                      ),
                                    ),
                                  ],
                                ),

                                // ── Organisation code ───────────────────────
                                if (_otpConfirmed) ...[
                                  const SizedBox(height: 20),
                                  _sectionTitle('Organisation Code (Optional)'),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Skip to create your own organisation',
                                    style: AppTheme.sora(11, color: AppTheme.textHint),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _codeController,
                                          enabled: _otpConfirmed && !submitting,
                                          textCapitalization: TextCapitalization.characters,
                                          maxLength: 6,
                                          decoration: InputDecoration(
                                            hintText: 'e.g. AB3X7K',
                                            counterText: '',
                                            errorText: _codeError,
                                          ),
                                          onChanged: (_) {
                                            if (_codeState != _CodeState.idle) {
                                              setState(() {
                                                _codeState = _CodeState.idle;
                                                _orgCodeDoc = null;
                                                _orgMembers = [];
                                                _selectedManagerId = null;
                                                _codeError = null;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _ActionButton(
                                        label: 'Get People',
                                        loading: _codeState == _CodeState.loading,
                                        done: _codeState == _CodeState.loaded,
                                        onPressed: (!_otpConfirmed ||
                                                submitting ||
                                                _codeState == _CodeState.loading ||
                                                _codeState == _CodeState.loaded)
                                            ? null
                                            : _getPeople,
                                      ),
                                    ],
                                  ),

                                  // Org info + manager picker shown after successful code lookup
                                  if (_codeState == _CodeState.loaded && _orgCodeDoc != null) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppTheme.primary.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.group_outlined,
                                                  size: 16, color: AppTheme.primary),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${_orgCodeDoc!.currentUserCount} / ${_orgCodeDoc!.totalUserCount} members',
                                                style: AppTheme.sora(12,
                                                    weight: FontWeight.w600,
                                                    color: AppTheme.primary),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Text('Select your manager *',
                                              style: AppTheme.sora(12,
                                                  weight: FontWeight.w600,
                                                  color: AppTheme.textSecondary)),
                                          const SizedBox(height: 6),
                                          DropdownButtonFormField<String?>(
                                            key: ValueKey(_selectedManagerId),
                                            value: _selectedManagerId,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                                hintText: 'No Manager'),
                                            items: [
                                              const DropdownMenuItem<String?>(
                                                value: null,
                                                child: Text('No Manager'),
                                              ),
                                              ..._orgMembers
                                                  .where((u) => u.id != _selfId)
                                                  .map((u) => DropdownMenuItem<String?>(
                                                        value: u.id,
                                                        child: Text(u.fullName,
                                                            overflow: TextOverflow.ellipsis),
                                                      )),
                                            ],
                                            onChanged: (!_otpConfirmed || submitting)
                                                ? null
                                                : (val) => setState(() => _selectedManagerId = val),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],

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

  Widget _sectionTitle(String title) => Text(title,
      style: AppTheme.sora(13,
          weight: FontWeight.w600,
          color: AppTheme.textSecondary,
          letterSpacing: 0.5));
}

enum _CodeState { idle, loading, loaded }

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
          disabledBackgroundColor: done ? AppTheme.primaryLight : null,
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
