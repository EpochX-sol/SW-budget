import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/entities/ai_models.dart';
import 'ai_chat_providers.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    ref.read(aiChatProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(aiChatProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: AppColors.secondaryLight, size: 20),
            ),
            const SizedBox(width: 10),
            Text('AI Financial Coach', style: AppTypography.titleLarge),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_outlined, color: AppColors.textPrimary),
            tooltip: 'What the AI Knows',
            onPressed: () => context.push('/ai-memory'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Messages List
            Expanded(
              child: chatState.messages.isEmpty
                  ? _EmptyChatWelcome(
                      onSelectPrompt: (prompt) {
                        _inputController.text = prompt;
                        _handleSend();
                      },
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: chatState.messages.length,
                      itemBuilder: (context, index) {
                        final msg = chatState.messages[index];
                        return _MessageBubble(
                          message: msg,
                          onDecideProposal: (propId, decision) {
                            ref.read(aiChatProvider.notifier).decideProposal(propId, decision);
                          },
                        );
                      },
                    ),
            ),

            // Error Banner
            if (chatState.errorMessage != null) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.expenseSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  chatState.errorMessage!,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.expenseLight),
                ),
              ),
            ],

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: AppTypography.bodyMedium,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ask about spending, limits, or safe burn...',
                        hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: chatState.isStreaming ? null : _handleSend,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      foregroundColor: AppColors.textInverse,
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: chatState.isStreaming
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChatWelcome extends StatelessWidget {
  final ValueChanged<String> onSelectPrompt;

  const _EmptyChatWelcome({required this.onSelectPrompt});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.secondaryLight, AppColors.secondaryDark],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.smart_toy_rounded, size: 40, color: Colors.black),
          ),
          const SizedBox(height: 20),
          Text(
            'Grounded Financial Guidance',
            style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '"Numbers from code, words from AI." I analyze your verified CBE & Telebirr ledger and provide exact math.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          Text('Suggested Questions', style: AppTypography.labelLarge.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          _PromptCard(
            text: 'Can I afford to spend 2,000 ETB on dinner tonight?',
            onTap: () => onSelectPrompt('Can I afford to spend 2,000 ETB on dinner tonight given my food budget?'),
          ),
          const SizedBox(height: 8),
          _PromptCard(
            text: 'How much am I saving compared to my goals?',
            onTap: () => onSelectPrompt('How much am I saving compared to my saving plans this month?'),
          ),
          const SizedBox(height: 8),
          _PromptCard(
            text: 'Analyze my bank tariff fees across CBE & Telebirr',
            onTap: () => onSelectPrompt('How much did I pay in ATM and bank tariff fees this month?'),
          ),
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _PromptCard({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: AppColors.primaryLight),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTypography.bodySmall)),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AiMessage message;
  final void Function(String proposalId, String decision) onDecideProposal;

  const _MessageBubble({
    required this.message,
    required this.onDecideProposal,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(18).copyWith(bottomRight: Radius.zero),
          ),
          child: Text(
            message.content,
            style: AppTypography.bodyMedium.copyWith(color: Colors.white),
          ),
        ),
      );
    }

    // Assistant Message
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, right: 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18).copyWith(bottomLeft: Radius.zero),
                border: Border.all(color: AppColors.border),
              ),
              child: message.isStreaming && message.content.isEmpty
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondaryLight),
                        ),
                        SizedBox(width: 8),
                        Text('Thinking with verified ledger math...'),
                      ],
                    )
                  : MarkdownBody(
                      data: message.content,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary, height: 1.5),
                        strong: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ),
            ),

            // Inline Interactive Proposal Action Card
            if (message.proposal != null) ...[
              const SizedBox(height: 8),
              _ProposalCard(
                proposal: message.proposal!,
                onDecide: (decision) => onDecideProposal(message.proposal!.id, decision),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final AiProposal proposal;
  final ValueChanged<String> onDecide;

  const _ProposalCard({required this.proposal, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    final tool = proposal.tool;
    final payload = proposal.payload;

    String actionTitle = 'Financial Action Proposal';
    if (tool == 'create_limit') {
      actionTitle = 'Proposal: Set ${payload['amount']} ETB Budget Limit';
    } else if (tool == 'create_saving_plan') {
      actionTitle = 'Proposal: Create Saving Goal Jar';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondaryLight.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppColors.secondaryLight, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  actionTitle,
                  style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Details: $payload',
            style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),

          if (proposal.isPending) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => onDecide('rejected'),
                  child: const Text('Dismiss', style: TextStyle(color: AppColors.textMuted)),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => onDecide('accepted'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    foregroundColor: AppColors.textInverse,
                  ),
                  child: const Text('Accept Action', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ] else if (proposal.isAccepted) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.incomeLight, size: 16),
                const SizedBox(width: 4),
                Text('Action Approved & Recorded in Ledger',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.incomeLight)),
              ],
            ),
          ] else ...[
            Text('Proposal Dismissed',
                style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}
