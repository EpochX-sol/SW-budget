import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/entities/ai_models.dart';
import 'ai_chat_providers.dart';

class AiMemoryScreen extends ConsumerStatefulWidget {
  const AiMemoryScreen({super.key});

  @override
  ConsumerState<AiMemoryScreen> createState() => _AiMemoryScreenState();
}

class _AiMemoryScreenState extends ConsumerState<AiMemoryScreen> {
  String _selectedKind = 'ALL';

  @override
  Widget build(BuildContext context) {
    final memoriesAsync = ref.watch(aiMemoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('What the AI Knows', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Transparency Banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: AppColors.primaryLight, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Episodic Long-Term Memory. Stored as local pgvector embeddings so your coach remembers your financial preferences.',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            // Kind filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All Memories',
                    isSelected: _selectedKind == 'ALL',
                    onTap: () => setState(() => _selectedKind = 'ALL'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Preferences',
                    isSelected: _selectedKind == 'preference',
                    onTap: () => setState(() => _selectedKind = 'preference'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Financial Goals',
                    isSelected: _selectedKind == 'goal',
                    onTap: () => setState(() => _selectedKind = 'goal'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Habits',
                    isSelected: _selectedKind == 'habit',
                    onTap: () => setState(() => _selectedKind = 'habit'),
                  ),
                ],
              ),
            ),

            // Memories List
            Expanded(
              child: memoriesAsync.when(
                data: (memories) {
                  final filtered = _selectedKind == 'ALL'
                      ? memories
                      : memories.where((m) => m.kind == _selectedKind).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.psychology_outlined, size: 64, color: AppColors.textMuted.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text('No Long-Term Memories', style: AppTypography.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            'As you chat with the coach, it remembers your financial preferences here.',
                            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final mem = filtered[index];
                      return _MemoryCard(
                        memory: mem,
                        onDelete: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Memory removed from AI model context.')),
                          );
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
                error: (e, _) => Center(child: Text('Error loading memories: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primaryLight : AppColors.border),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final AiMemoryItem memory;
  final VoidCallback onDelete;

  const _MemoryCard({required this.memory, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  memory.kind.toUpperCase(),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted, size: 20),
                onPressed: onDelete,
                tooltip: 'Forget Memory',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            memory.content,
            style: AppTypography.bodyMedium.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
