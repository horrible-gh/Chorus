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
    this.senderUserId,
    this.senderAgentId,
    this.sourceTaskId,
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
  final String createdAt;

  bool get isFromUser => senderType == 'user';
  bool get isFromAgent => senderType == 'agent';
  bool get isWhisper => visibility == 'whisper';
  bool get isOneShot => deliveryMode == 'one_shot';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawRecipients = json['recipient_agent_ids'];
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
