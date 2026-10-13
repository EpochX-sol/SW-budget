import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/remote/api_client_provider.dart';
import '../../../data/remote/api_endpoints.dart';
import '../../theme/app_colors.dart';

class ServerConfigSheet extends ConsumerStatefulWidget {
  const ServerConfigSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const ServerConfigSheet(),
    );
  }

  @override
  ConsumerState<ServerConfigSheet> createState() => _ServerConfigSheetState();
}

class _ServerConfigSheetState extends ConsumerState<ServerConfigSheet> {
  late final TextEditingController _urlController;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;
  int? _testLatency;

  @override
  void initState() {
    super.initState();
    final currentUrl = ref.read(serverConfigProvider);
    _urlController = TextEditingController(text: currentUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleTest() async {
    final target = _urlController.text.trim();
    if (target.isEmpty) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
      _testLatency = null;
    });

    final res = await ApiClient.testServerConnection(target);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = res['success'] == true;
        _testLatency = res['latency_ms'] as int?;
        if (_testSuccess == true) {
          _testResult = 'Online (${_testLatency}ms) · Status: ${res['status']}';
        } else {
          _testResult = res['error'] ?? 'Unreachable';
        }
      });
    }
  }

  Future<void> _handleSave() async {
    final target = _urlController.text.trim();
    if (target.isEmpty) return;

    await ref.read(serverConfigProvider.notifier).updateBaseUrl(target);
    if (!mounted) return;

    // Trigger pre-warming in background
    ref.read(apiClientProvider).prewarmServer();

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Server endpoint set to: $target'),
        backgroundColor: const Color(0xFF13221C),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _selectPreset(String url) {
    _urlController.text = url;
    _handleTest();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.dns_rounded, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backend Server Settings',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Configure API host endpoint & test latency',
                      style: TextStyle(color: AppColors.text3, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.text3, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Presets
          const Text(
            'QUICK PRESETS',
            style: TextStyle(
              color: AppColors.text3,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip('Render Cloud', 'https://sw-budget.onrender.com'),
              _buildPresetChip('Local Wi-Fi', 'http://192.168.1.5:3000'),
              _buildPresetChip('Emulator', 'http://10.0.2.2:3000'),
            ],
          ),
          const SizedBox(height: 16),
          // Custom URL Input
          TextField(
            controller: _urlController,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'API Base URL',
              labelStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
              hintText: 'https://sw-budget.onrender.com',
              hintStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface2,
              prefixIcon: const Icon(Icons.link_rounded, color: AppColors.accent, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Diagnostics output
          if (_testResult != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _testSuccess == true
                    ? AppColors.incomeBg
                    : AppColors.expenseBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _testSuccess == true
                      ? AppColors.income.withValues(alpha: 0.3)
                      : AppColors.expense.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                    color: _testSuccess == true ? AppColors.income : AppColors.expense,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testSuccess == true ? AppColors.income : AppColors.expense,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.line2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _isTesting ? null : _handleTest,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                        )
                      : const Icon(Icons.bolt_rounded, size: 16),
                  label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFF080C14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _handleSave,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Save & Apply', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () {
                ref.read(serverConfigProvider.notifier).resetToDefault();
                _urlController.text = ApiEndpoints.defaultBaseUrl;
                _handleTest();
              },
              child: const Text(
                'Reset to Default (Render Cloud)',
                style: TextStyle(color: AppColors.text3, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, String url) {
    final isSelected = _urlController.text.trim() == url;
    return InkWell(
      onTap: () => _selectPreset(url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.accent : AppColors.text2,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
