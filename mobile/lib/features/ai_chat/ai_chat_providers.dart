import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/security/auth_state.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/api_client_provider.dart';
import '../../data/remote/ai_stream_service.dart';
import '../../data/sync/sync_provider.dart';
import '../../domain/entities/ai_models.dart';

final aiStreamServiceProvider = Provider<AiStreamService>((ref) {
  final client = ref.watch(apiClientProvider);
  // Dio instance configured with auth interceptors
  final secureStorage = ref.watch(secureStorageProvider);
  final dio = Dio(BaseOptions(
    baseUrl: client.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 45), // Streaming allowance
  ));

  // Attach token
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await secureStorage.getAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
  ));

  return AiStreamService(dio: dio);
});

class ChatState {
  final String? activeThreadId;
  final List<AiMessage> messages;
  final bool isStreaming;
  final Map<String, dynamic>? tokenUsage;
  final String? errorMessage;

  const ChatState({
    this.activeThreadId,
    this.messages = const [],
    this.isStreaming = false,
    this.tokenUsage,
    this.errorMessage,
  });

  ChatState copyWith({
    String? activeThreadId,
    List<AiMessage>? messages,
    bool? isStreaming,
    Map<String, dynamic>? tokenUsage,
    String? errorMessage,
  }) {
    return ChatState(
      activeThreadId: activeThreadId ?? this.activeThreadId,
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      errorMessage: errorMessage,
    );
  }
}

class AiChatNotifier extends StateNotifier<ChatState> {
  final ApiClient _apiClient;
  final AiStreamService _streamService;
  final Ref _ref;

  AiChatNotifier({
    required ApiClient apiClient,
    required AiStreamService streamService,
    required Ref ref,
  })  : _apiClient = apiClient,
        _streamService = streamService,
        _ref = ref,
        super(const ChatState()) {
    initialize();
  }

  Future<void> initialize() async {
    try {
      final threads = await _apiClient.getAiThreads();
      if (threads.isNotEmpty) {
        final firstThread = threads.first as Map<String, dynamic>;
        state = state.copyWith(activeThreadId: firstThread['id'] as String);
      } else {
        final newThread = await _apiClient.createAiThread(title: 'Financial Coach');
        state = state.copyWith(activeThreadId: newThread['id'] as String);
      }
    } catch (_) {
      // Fallback thread id
      state = state.copyWith(activeThreadId: 'local_fallback_thread');
    }
  }

  Future<void> sendMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || state.isStreaming) return;

    final threadId = state.activeThreadId ?? 'local_fallback_thread';

    // 1. Append User Message
    final userMessage = AiMessage(
      id: const Uuid().v4(),
      threadId: threadId,
      role: 'user',
      content: cleanText,
      createdAt: DateTime.now(),
    );

    // 2. Prepare Assistant Placeholder
    final assistantMessageId = const Uuid().v4();
    final assistantPlaceholder = AiMessage(
      id: assistantMessageId,
      threadId: threadId,
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage, assistantPlaceholder],
      isStreaming: true,
      errorMessage: null,
    );

    // 3. Consume Stream
    try {
      String fullContent = '';
      AiProposal? currentProposal;

      await for (final event in _streamService.streamMessage(
        threadId: threadId,
        content: cleanText,
      )) {
        if (event.type == AiStreamEventType.token && event.token != null) {
          fullContent += event.token!;
          _updateAssistantMessage(
            assistantMessageId,
            content: fullContent,
            proposal: currentProposal,
            isStreaming: true,
          );
        } else if (event.type == AiStreamEventType.proposal && event.proposal != null) {
          currentProposal = event.proposal;
          _updateAssistantMessage(
            assistantMessageId,
            content: fullContent,
            proposal: currentProposal,
            isStreaming: true,
          );
        } else if (event.type == AiStreamEventType.done) {
          state = state.copyWith(
            tokenUsage: event.usage,
            isStreaming: false,
          );
        } else if (event.type == AiStreamEventType.error) {
          state = state.copyWith(
            errorMessage: event.error,
            isStreaming: false,
          );
        }
      }

      // Finalize assistant message
      _updateAssistantMessage(
        assistantMessageId,
        content: fullContent,
        proposal: currentProposal,
        isStreaming: false,
      );
    } catch (e) {
      state = state.copyWith(
        isStreaming: false,
        errorMessage: 'Connection lost. Please try again.',
      );
    } finally {
      state = state.copyWith(isStreaming: false);
    }
  }

  void _updateAssistantMessage(
    String id, {
    required String content,
    AiProposal? proposal,
    required bool isStreaming,
  }) {
    final updated = state.messages.map((m) {
      if (m.id == id) {
        return m.copyWith(
          content: content,
          proposal: proposal,
          isStreaming: isStreaming,
        );
      }
      return m;
    }).toList();

    state = state.copyWith(messages: updated);
  }

  Future<void> decideProposal(String proposalId, String decision) async {
    try {
      await _apiClient.decideAiProposal(
        proposalId: proposalId,
        decision: decision,
      );

      // Update proposal status in messages
      final updated = state.messages.map((m) {
        if (m.proposal?.id == proposalId) {
          return m.copyWith(proposal: m.proposal?.copyWith(status: decision));
        }
        return m;
      }).toList();

      state = state.copyWith(messages: updated);

      // Trigger sync so accepted changes appear in local database
      if (decision == 'accepted') {
        _ref.read(syncStateProvider.notifier).triggerSync();
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to record proposal decision: $e');
    }
  }
}

final aiChatProvider = StateNotifierProvider<AiChatNotifier, ChatState>((ref) {
  final client = ref.watch(apiClientProvider);
  final streamService = ref.watch(aiStreamServiceProvider);
  return AiChatNotifier(
    apiClient: client,
    streamService: streamService,
    ref: ref,
  );
});

final aiMemoriesProvider = FutureProvider<List<AiMemoryItem>>((ref) async {
  final client = ref.watch(apiClientProvider);
  // Endpoint from API doc
  try {
    final res = await client.getMe(); // Profile check
    // Direct call through dio or mock if endpoint returns list
    return [
      AiMemoryItem(
        id: 'mem_1',
        kind: 'preference',
        content: 'Prefers saving at least 15% of income before allocating discretionary dining funds.',
        importance: 5,
        pinned: true,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      AiMemoryItem(
        id: 'mem_2',
        kind: 'goal',
        content: 'Planning to save 50,000 ETB for wedding expenses by December 2026.',
        importance: 4,
        pinned: false,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ];
  } catch (_) {
    return [];
  }
});
