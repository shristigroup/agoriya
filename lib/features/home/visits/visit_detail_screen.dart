import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/visit_model.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/repositories/firestore_repository.dart';
import 'visit_edit_screen.dart';

class VisitDetailScreen extends StatefulWidget {
  final VisitModel visit;
  final String targetUserId;
  final bool isReadOnly;

  const VisitDetailScreen({
    super.key,
    required this.visit,
    required this.targetUserId,
    this.isReadOnly = false,
  });

  @override
  State<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  late VisitModel _visit;
  List<VisitComment> _comments = [];
  bool _loadingComments = false;
  final _commentController = TextEditingController();
  bool _submittingComment = false;

  @override
  void initState() {
    super.initState();
    _visit = widget.visit;
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    try {
      final comments = await FirestoreRepository()
          .getComments(widget.targetUserId, _visit.id);
      setState(() => _comments = comments);
    } catch (_) {}
    setState(() => _loadingComments = false);
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final user = LocalStorageService.getUser();
    if (user == null) return;
    setState(() => _submittingComment = true);
    try {
      await FirestoreRepository().addComment(
        widget.targetUserId,
        _visit.id,
        VisitComment(
          id: '', userId: user.id, userName: user.fullName,
          text: text, timestamp: DateTime.now(),
        ),
      );
      _commentController.clear();
      await _loadComments();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
      );
    }
    setState(() => _submittingComment = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(_visit.clientName),
        actions: [
          if (!widget.isReadOnly)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () async {
                final updated = await Navigator.of(context).push<VisitModel>(
                  MaterialPageRoute(
                    builder: (_) => VisitEditScreen(
                      visit: _visit,
                      targetUserId: widget.targetUserId,
                      isEditMode: true,
                    ),
                  ),
                );
                if (updated != null) setState(() => _visit = updated);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(),
                  if (_visit.visitNotes?.isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    _buildNotesCard(),
                  ],
                  if (_visit.expenseAmount != null) ...[
                    const SizedBox(height: 16),
                    _buildExpenseCard(),
                  ],
                  const SizedBox(height: 16),
                  _buildCommentsSection(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconBox(icon: Icons.storefront_rounded, color: AppTheme.checkIn),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_visit.clientName,
                          style: AppTheme.sora(17, weight: FontWeight.w700)),
                      Text(_visit.location,
                          style: AppTheme.sora(13, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _TimeRow(Icons.login_rounded, 'Check In',
                AppUtils.formatDateTime(_visit.checkinTimestamp), AppTheme.checkIn),
            if (_visit.checkoutTimestamp != null) ...[
              const SizedBox(height: 12),
              _TimeRow(Icons.logout_rounded, 'Check Out',
                  AppUtils.formatDateTime(_visit.checkoutTimestamp!), AppTheme.checkOut),
              const SizedBox(height: 12),
              _TimeRow(Icons.timer_rounded, 'Duration',
                  AppUtils.formatDuration(_visit.visitDuration), AppTheme.primary),
            ] else ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Currently visiting',
                    style: AppTheme.sora(12, weight: FontWeight.w600,
                        color: AppTheme.accent)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.notes_rounded, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text('Visit Notes',
                  style: AppTheme.sora(13, weight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
            ]),
            const SizedBox(height: 10),
            Text(_visit.visitNotes!,
                style: AppTheme.sora(14, color: AppTheme.textPrimary, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_rounded, size: 16,
                    color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text('Expense',
                    style: AppTheme.sora(13, weight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                const Spacer(),
                Text('₹${_visit.expenseAmount!.toStringAsFixed(0)}',
                    style: AppTheme.sora(18, weight: FontWeight.w700,
                        color: AppTheme.primary)),
              ],
            ),
            if (_visit.billCopy != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: _visit.billCopy!,
                  height: 180, width: double.infinity, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    height: 180, color: AppTheme.divider,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 60, color: AppTheme.divider,
                    child: const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comments', style: AppTheme.sora(15, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (_loadingComments)
          const Center(child: Padding(padding: EdgeInsets.all(16),
              child: CircularProgressIndicator()))
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No comments yet',
                style: AppTheme.sora(13, color: AppTheme.textHint)),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _comments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _CommentTile(
              comment: _comments[i],
              isMe: LocalStorageService.getUser()?.id == _comments[i].userId,
            ),
          ),
      ],
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                filled: true,
                fillColor: AppTheme.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          _submittingComment
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: _submitComment,
                  icon: const Icon(Icons.send_rounded),
                  color: AppTheme.primary,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Shared small widgets ───────────────────────────────────────────────────────

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _IconBox({required this.icon, required this.color, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: size * 0.52),
      );
}

class _TimeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _TimeRow(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: AppTheme.sora(13, color: AppTheme.textSecondary)),
          const Spacer(),
          Text(value,
              style: AppTheme.sora(13, weight: FontWeight.w600, color: color)),
        ],
      );
}

class _CommentTile extends StatelessWidget {
  final VisitComment comment;
  final bool isMe;
  const _CommentTile({required this.comment, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: isMe ? AppTheme.primary : AppTheme.checkIn,
          child: Text(AppUtils.getInitials(comment.userName),
              style: const TextStyle(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? AppTheme.primary.withOpacity(0.06) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.userName,
                        style: AppTheme.sora(12, weight: FontWeight.w700)),
                    const Spacer(),
                    Text(AppUtils.formatDateTime(comment.timestamp),
                        style: AppTheme.sora(10, color: AppTheme.textHint)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(comment.text,
                    style: AppTheme.sora(13, color: AppTheme.textPrimary,
                        height: 1.4)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
