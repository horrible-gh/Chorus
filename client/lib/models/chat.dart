class ChatRoom {
  const ChatRoom({
    required this.roomId,
    required this.title,
    required this.mode,
    required this.status,
    required this.ownerUserId,
    required this.activeHistoryMode,
    required this.createdAt,
    required this.updatedAt,
    this.baseSummaryMessageId,
    this.archivedAt,
  });

  final String roomId;
  final String title;
  final String mode;
  final String status;
  final String ownerUserId;
  final String activeHistoryMode;
  final String? baseSummaryMessageId;
  final String createdAt;
  final String updatedAt;
  final String? archivedAt;

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      roomId: _string(json['room_id']),
      title: _string(json['title']),
      mode: _string(json['mode']),
      status: _string(json['status']),
      ownerUserId: _string(json['owner_user_id']),
      activeHistoryMode: _string(json['active_history_mode']),
      baseSummaryMessageId: _nullableString(json['base_summary_message_id']),
      createdAt: _string(json['created_at']),
      updatedAt: _string(json['updated_at']),
      archivedAt: _nullableString(json['archived_at']),
    );
  }
}

class ChatParticipant {
  const ChatParticipant({
    required this.participantId,
    required this.roomId,
    required this.participantType,
    required this.displayName,
    required this.status,
    required this.joinedAt,
    this.userId,
    this.agentId,
    this.leftAt,
  });

  final String participantId;
  final String roomId;
  final String participantType;
  final String? userId;
  final String? agentId;
  final String displayName;
  final String status;
  final String joinedAt;
  final String? leftAt;

  bool get isActive => status == 'active';
  bool get isAgent => participantType == 'agent';

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      participantId: _string(json['participant_id']),
      roomId: _string(json['room_id']),
      participantType: _string(json['participant_type']),
      userId: _nullableString(json['user_id']),
      agentId: _nullableString(json['agent_id']),
      displayName: _string(json['display_name']),
      status: _string(json['status']),
      joinedAt: _string(json['joined_at']),
      leftAt: _nullableString(json['left_at']),
    );
  }
}

class ContextUsage {
  const ContextUsage({
    required this.estimatedInputTokens,
    required this.contextWindow,
    required this.contextRatio,
    required this.contextStatus,
    this.actualInputTokens,
    this.actualOutputTokens,
    this.totalCostUsd,
  });

  final int estimatedInputTokens;
  final int contextWindow;
  final double contextRatio;
  final String contextStatus;
  final int? actualInputTokens;
  final int? actualOutputTokens;
  final double? totalCostUsd;

  bool get hasActual => actualInputTokens != null;

  /// Compute display ratio: prefer actual tokens from API when available, fall back to estimate
  double get displayRatio {
    if (actualInputTokens != null && contextWindow > 0) {
      return actualInputTokens! / contextWindow;
    }
    return contextRatio;
  }

  factory ContextUsage.fromJson(Map<String, dynamic> json) {
    return ContextUsage(
      estimatedInputTokens: (json['estimated_input_tokens'] as num?)?.toInt() ?? 0,
      contextWindow: (json['context_window'] as num?)?.toInt() ?? 0,
      contextRatio: (json['context_ratio'] as num?)?.toDouble() ?? 0.0,
      contextStatus: json['context_status']?.toString() ?? 'OK',
      actualInputTokens: (json['actual_input_tokens'] as num?)?.toInt(),
      actualOutputTokens: (json['actual_output_tokens'] as num?)?.toInt(),
      totalCostUsd: (json['total_cost_usd'] as num?)?.toDouble(),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.roomId,
    required this.senderType,
    required this.visibility,
    required this.recipientAgentIds,
    required this.contentType,
    required this.text,
    required this.deliveryMode,
    required this.historyState,
    required this.createdAt,
    required this.isCancelled,
    this.senderUserId,
    this.senderAgentId,
    this.sourceTaskId,
    this.contextUsage,
    this.isStreaming = false,
    this.thinkingContent = '',
    this.isThinkingStreaming = false,
    this.isThinkingExpanded = false,
  });

  final String messageId;
  final String roomId;
  final String senderType;
  final String? senderUserId;
  final String? senderAgentId;
  final String visibility;
  final List<String> recipientAgentIds;
  final String contentType;
  final String text;
  final String deliveryMode;
  final String historyState;
  final String? sourceTaskId;
  final ContextUsage? contextUsage;
  final String createdAt;
  final bool isCancelled;
  /// True while this is a temporary in-progress streaming message (not yet persisted in DB).
  final bool isStreaming;
  /// Claude reasoning/thinking content during response generation.
  final String thinkingContent;
  /// True while thinking is streaming (incomplete).
  final bool isThinkingStreaming;
  /// True when thinking section is expanded; auto-collapses when thinking_completed.
  final bool isThinkingExpanded;

  bool get isFromUser => senderType == 'user';
  bool get isFromAgent => senderType == 'agent';
  bool get isWhisper => visibility == 'whisper';
  bool get isOneShot => deliveryMode == 'one_shot';

  ChatMessage copyWith({
    String? text,
    bool? isStreaming,
    String? thinkingContent,
    bool? isThinkingStreaming,
    bool? isThinkingExpanded,
  }) {
    return ChatMessage(
      messageId: messageId,
      roomId: roomId,
      senderType: senderType,
      senderUserId: senderUserId,
      senderAgentId: senderAgentId,
      visibility: visibility,
      recipientAgentIds: recipientAgentIds,
      contentType: contentType,
      text: text ?? this.text,
      deliveryMode: deliveryMode,
      historyState: historyState,
      sourceTaskId: sourceTaskId,
      createdAt: createdAt,
      isCancelled: isCancelled,
      contextUsage: contextUsage,
      isStreaming: isStreaming ?? this.isStreaming,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      isThinkingStreaming: isThinkingStreaming ?? this.isThinkingStreaming,
      isThinkingExpanded: isThinkingExpanded ?? this.isThinkingExpanded,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawRecipients = json['recipient_agent_ids'];
    final rawContextUsage = json['context_usage'];
    return ChatMessage(
      messageId: _string(json['message_id']),
      roomId: _string(json['room_id']),
      senderType: _string(json['sender_type']),
      senderUserId: _nullableString(json['sender_user_id']),
      senderAgentId: _nullableString(json['sender_agent_id']),
      visibility: _string(json['visibility']),
      recipientAgentIds: rawRecipients is List
          ? rawRecipients.map((item) => item.toString()).toList()
          : const [],
      contentType: _string(json['content_type']),
      text: _string(json['text']),
      deliveryMode: _string(json['delivery_mode']),
      historyState: _string(json['history_state']),
      sourceTaskId: _nullableString(json['source_task_id']),
      createdAt: _string(json['created_at']),
      isCancelled: json['is_cancelled'] == 1,
      contextUsage: rawContextUsage is Map<String, dynamic>
          ? ContextUsage.fromJson(rawContextUsage)
          : null,
    );
  }
}

class ChatRoomDetails {
  const ChatRoomDetails({
    required this.room,
    required this.participants,
  });

  final ChatRoom room;
  final List<ChatParticipant> participants;
}

class ChatCreatedTask {
  const ChatCreatedTask({
    required this.taskId,
    required this.agentId,
    required this.status,
    this.generationId,
  });

  final String taskId;
  final String agentId;
  final String status;
  final String? generationId;

  factory ChatCreatedTask.fromJson(Map<String, dynamic> json) {
    return ChatCreatedTask(
      taskId: _string(json['task_id']),
      agentId: _string(json['agent_id']),
      status: _string(json['status']),
      generationId: _nullableString(json['generation_id']),
    );
  }
}

class MessageSendResult {
  const MessageSendResult({
    required this.message,
    required this.createdTasks,
    this.generationId,
  });

  final ChatMessage message;
  final List<ChatCreatedTask> createdTasks;
  final String? generationId;
}

String _string(Object? value) => value?.toString() ?? '';

String? _nullableString(Object? value) {
  final stringValue = value?.toString();
  if (stringValue == null || stringValue.isEmpty) {
    return null;
  }
  return stringValue;
}
