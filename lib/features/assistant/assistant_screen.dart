import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/local_storage_service.dart';
import 'assistant_actions.dart';
import 'assistant_config.dart';
import 'assistant_controller.dart';
import 'assistant_data.dart';
import 'assistant_models.dart';
import 'credit_store.dart';
import 'llm_client.dart';

/// The owner's AI assistant: a chat that can manage shifts and look at the
/// team. Reads run at once; every change shows a card to confirm.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  AssistantController? _c;
  String? _error;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _ticker;
  DateTime? _busySince;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final user = LocalStorageService.getUser();
    if (user == null || (user.code ?? '').isEmpty) {
      setState(() => _error = 'The assistant needs an organisation.');
      return;
    }
    final config = await AssistantConfig.load();
    if (!config.enabled) {
      if (mounted) setState(() => _error = 'The assistant is switched off for now.');
      return;
    }
    final controller = AssistantController(
      llm: FirebaseAiClient(),
      credits: FirestoreCreditStore(user.id),
      config: config,
      actions: buildAssistantActions(FirestoreAssistantData(user)),
    );
    await controller.init();
    controller.addListener(_onChange);
    if (mounted) setState(() => _c = controller);
  }

  void _onChange() {
    final c = _c;
    if (c == null || !mounted) return;
    if (c.busy && _ticker == null) {
      _busySince = DateTime.now();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else if (!c.busy) {
      _ticker?.cancel();
      _ticker = null;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _c?.removeListener(_onChange);
    _c?.stop();
    _c?.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _c?.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('AI assist'),
        actions: [
          if (c?.creditsLeft != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('${c!.creditsLeft} credits',
                    style: AppTheme.sora(12, color: Colors.white70)),
              ),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center,
                  style: AppTheme.sora(14, color: AppTheme.textSecondary))))
          : c == null
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        itemCount: c.messages.length,
                        itemBuilder: (_, i) => _bubble(c, c.messages[i]),
                      ),
                    ),
                    if (c.busy) _workingBar(c),
                    _inputBar(c),
                  ],
                ),
    );
  }

  Widget _workingBar(AssistantController c) {
    final secs = _busySince == null ? 0 : DateTime.now().difference(_busySince!).inSeconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
          const SizedBox(width: 8),
          Text('Working… ${secs}s',
              style: AppTheme.sora(12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _inputBar(AssistantController c) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Ask or tell me what to do',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                c.busy
                    ? IconButton.filled(
                        onPressed: c.stop,
                        tooltip: 'Stop',
                        style: IconButton.styleFrom(backgroundColor: AppTheme.error),
                        icon: const Icon(Icons.stop_rounded),
                      )
                    : IconButton.filled(
                        onPressed: _send,
                        tooltip: 'Send',
                        icon: const Icon(Icons.send_rounded),
                      ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('AI can make mistakes. Check each card before you confirm.',
                  style: AppTheme.sora(10, color: AppTheme.textHint)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(AssistantController c, ChatMessage m) {
    if (m.proposal != null) return _proposalCard(c, m.proposal!);
    if (m.role == ChatRole.note) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(m.text, style: AppTheme.sora(11, color: AppTheme.textHint)),
        ),
      );
    }
    final mine = m.role == ChatRole.user;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: mine ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          m.text,
          style: AppTheme.sora(14, color: mine ? Colors.white : AppTheme.textPrimary),
        ),
      ),
    );
  }

  Widget _proposalCard(AssistantController c, Proposal p) {
    final done = p.state == ProposalState.done;
    final failed = p.state == ProposalState.failed;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: failed ? AppTheme.error : (done ? AppTheme.punchIn : AppTheme.primary.withOpacity(0.4))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.title, style: AppTheme.sora(14, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final line in p.lines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(line, style: AppTheme.sora(12, color: AppTheme.textSecondary)),
              ),
            const SizedBox(height: 10),
            switch (p.state) {
              ProposalState.pending => Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => c.cancelProposal(p), child: const Text('Cancel')),
                    const SizedBox(width: 6),
                    ElevatedButton(onPressed: () => c.confirm(p), child: const Text('Confirm')),
                  ],
                ),
              ProposalState.running => const LinearProgressIndicator(color: AppTheme.primary),
              ProposalState.done => Text('Done. ${p.result ?? ''}',
                  style: AppTheme.sora(12, weight: FontWeight.w600, color: AppTheme.punchIn)),
              ProposalState.cancelled =>
                Text('Cancelled', style: AppTheme.sora(12, color: AppTheme.textHint)),
              ProposalState.failed => Text('Failed: ${p.result ?? ''}',
                  style: AppTheme.sora(12, weight: FontWeight.w600, color: AppTheme.error)),
            },
          ],
        ),
      ),
    );
  }
}
