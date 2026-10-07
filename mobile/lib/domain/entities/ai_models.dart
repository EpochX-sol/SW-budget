/// Representation of a message in an AI Financial Coach thread
class AiMessage {
  final String id;
  final String threadId;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime createdAt;
  final AiProposal? proposal;
  final bool isStreaming;

  const AiMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.proposal,
    this.isStreaming = false,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  AiMessage copyWith({
    String? content,
    AiProposal? proposal,
    bool? isStreaming,
  }) {
    return AiMessage(
      id: id,
      threadId: threadId,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      proposal: proposal ?? this.proposal,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}

/// Representation of an interactive financial action proposed by the AI coach
class AiProposal {
  final String id;
  final String tool; // e.g. "create_limit", "create_saving_plan", "categorize_transaction"
  final Map<String, dynamic> payload;
  final String status; // 'pending', 'accepted', 'rejected'
  final DateTime? createdAt;

  const AiProposal({
    required this.id,
    required this.tool,
    required this.payload,
    this.status = 'pending',
    this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';

  factory AiProposal.fromMap(Map<String, dynamic> map) {
    return AiProposal(
      id: map['id'] as String? ?? '',
      tool: map['tool'] as String? ?? '',
      payload: map['payload'] as Map<String, dynamic>? ?? {},
      status: map['status'] as String? ?? 'pending',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
    );
  }

  AiProposal copyWith({String? status}) {
    return AiProposal(
      id: id,
      tool: tool,
      payload: payload,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}

/// Representation of an episodic vector memory item stored by the AI
class AiMemoryItem {
  final String id;
  final String kind; // 'preference', 'goal', 'habit', 'fact', 'decision'
  final String content;
  final int importance; // 1 to 5
  final bool pinned;
  final DateTime createdAt;

  const AiMemoryItem({
    required this.id,
    required this.kind,
    required this.content,
    required this.importance,
    required this.pinned,
    required this.createdAt,
  });

  factory AiMemoryItem.fromMap(Map<String, dynamic> map) {
    return AiMemoryItem(
      id: map['id'] as String? ?? '',
      kind: map['kind'] as String? ?? 'fact',
      content: map['content'] as String? ?? '',
      importance: (map['importance'] as num?)?.toInt() ?? 3,
      pinned: map['pinned'] == true || map['pinned'] == 1,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

/// Event types emitted during Server-Sent Events (SSE) streaming
enum AiStreamEventType { token, proposal, done, error }

class AiStreamEvent {
  final AiStreamEventType type;
  final String? token;
  final AiProposal? proposal;
  final Map<String, dynamic>? usage;
  final String? error;

  const AiStreamEvent({
    required this.type,
    this.token,
    this.proposal,
    this.usage,
    this.error,
  });
}
