import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/visit_model.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';

class VisitEditScreen extends StatefulWidget {
  final VisitModel visit;
  final String targetUserId;
  final bool isEditMode; // true = "Update Info", false = "Check Out"

  const VisitEditScreen({
    super.key,
    required this.visit,
    required this.targetUserId,
    this.isEditMode = false,
  });

  @override
  State<VisitEditScreen> createState() => _VisitEditScreenState();
}

class _VisitEditScreenState extends State<VisitEditScreen> {
  final _notesController = TextEditingController();
  final _expenseController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  File? _billFile;
  String? _existingBillUrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _notesController.text = widget.visit.visitNotes ?? '';
    _expenseController.text = widget.visit.expenseAmount?.toStringAsFixed(0) ?? '';
    _existingBillUrl = widget.visit.billCopy;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _expenseController.dispose();
    super.dispose();
  }

  Future<void> _pickBill() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (xFile != null) {
      setState(() => _billFile = File(xFile.path));
    }
  }

  bool get _requiresBill {
    final amount = double.tryParse(_expenseController.text.trim()) ?? 0;
    return amount > 0;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_requiresBill && _billFile == null && _existingBillUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please attach a bill copy for expense claims'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final user = LocalStorageService.getUser()!;
      String? billUrl = _existingBillUrl;

      // Upload bill if new file selected
      if (_billFile != null) {
        billUrl = await FirestoreRepository()
            .uploadBillCopy(user.id, widget.visit.id, _billFile!);
      }

      final expense = double.tryParse(_expenseController.text.trim());

      final updated = widget.visit.copyWith(
        visitNotes: _notesController.text.trim(),
        expenseAmount: expense,
        billCopy: billUrl,
        checkoutTimestamp: widget.isEditMode
            ? widget.visit.checkoutTimestamp
            : DateTime.now(),
      );

      // Update via bloc if it's the current user's own visit
      if (widget.targetUserId == user.id) {
        context.read<HomeBloc>().add(UpdateVisitEvent(updated));
      } else {
        // Manager view - direct repo call
        await FirestoreRepository().updateVisit(widget.targetUserId, updated);
      }

      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
      );
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCheckedOut = widget.visit.isCheckedOut;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Visit' : 'Check Out'),
        backgroundColor: widget.isEditMode ? AppTheme.primary : AppTheme.checkOut,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Client info (read only)
              _buildReadOnlyCard(),
              const SizedBox(height: 20),

              // Check-in / Check-out times
              _buildTimingCard(isCheckedOut),
              const SizedBox(height: 20),

              _buildLabel('Visit Notes'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Add notes about the visit...',
                ),
              ),
              const SizedBox(height: 20),

              _buildLabel('Expense Amount (₹)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _expenseController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  hintText: '0',
                  prefixText: '₹ ',
                ),
                onChanged: (_) => setState(() {}), // refresh bill requirement
              ),
              const SizedBox(height: 20),

              // Bill copy
              _buildBillSection(),
              const SizedBox(height: 32),

              // Action button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isEditMode
                        ? AppTheme.primary
                        : AppTheme.checkOut,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(widget.isEditMode
                          ? 'Update Information'
                          : 'Check Out'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.checkIn.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.storefront_rounded,
                  color: AppTheme.checkIn, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.visit.clientName,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    widget.visit.location,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimingCard(bool isCheckedOut) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _timeRow(
              Icons.login_rounded,
              'Check In',
              AppUtils.formatDateTime(widget.visit.checkinTimestamp),
              AppTheme.checkIn,
            ),
            const SizedBox(height: 12),
            _timeRow(
              Icons.logout_rounded,
              'Check Out',
              isCheckedOut
                  ? AppUtils.formatDateTime(widget.visit.checkoutTimestamp!)
                  : AppUtils.formatDateTime(DateTime.now()),
              AppTheme.checkOut,
            ),
            if (!widget.isEditMode && !isCheckedOut) ...[
              const SizedBox(height: 8),
              Text(
                'Checkout time is set to now and cannot be changed',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 11,
                  color: AppTheme.textHint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _timeRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontFamily: 'Sora')),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color, fontFamily: 'Sora')),
      ],
    );
  }

  Widget _buildBillSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildLabel('Bill Copy'),
            if (_requiresBill) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Required',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 10,
                    color: AppTheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (_billFile != null)
          _buildBillPreview(Image.file(_billFile!, fit: BoxFit.cover))
        else if (_existingBillUrl != null)
          _buildBillPreview(
            Image.network(_existingBillUrl!, fit: BoxFit.cover),
          )
        else
          GestureDetector(
            onTap: _pickBill,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _requiresBill ? AppTheme.error : AppTheme.divider,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.upload_rounded,
                        color: _requiresBill ? AppTheme.error : AppTheme.textHint,
                        size: 28),
                    const SizedBox(height: 6),
                    Text(
                      'Tap to upload bill',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 13,
                        color: _requiresBill ? AppTheme.error : AppTheme.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_billFile != null || _existingBillUrl != null)
          TextButton.icon(
            onPressed: _pickBill,
            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
            label: const Text('Change'),
          ),
      ],
    );
  }

  Widget _buildBillPreview(Widget image) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: image,
      ),
    );
  }

  Widget _buildLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          letterSpacing: 0.3,
        ),
      );
}
