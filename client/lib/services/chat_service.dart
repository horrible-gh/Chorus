import 'package:dio/dio.dart';

import '../models/agent_preset.dart';
import '../models/chat.dart';
import '../models/chat_context_options.dart';

class ChatService {
  const ChatService(this._dio);

  final Dio _dio;

  Future<List<ChatRoom>> listRooms({required String ownerUserId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/chat/rooms',
      queryParameters: {'owner_user_id': ownerUserId},
    );
    final rooms = _list(response.data?['rooms']);
    return rooms.map((item) => ChatRoom.fromJson(_map(item))).toList();
  }

  Future<ChatRoomDetails> createRoom({
    required String userId,
    required String title,
    required String mode,
    required List<String> initialAgentIds,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/rooms',
      data: {
        'user_id': userId,
        'title': title,
        'mode': mode,
        'initial_agent_ids': initialAgentIds,
      },
    );
    return _roomDetails(response.data);
  }

  Future<ChatRoomDetails> getRoom(String roomId) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/chat/rooms/$roomId');
    return _roomDetails(response.data);
  }

  Future<List<ChatMessage>> listMessages({
    required String roomId,
    required String viewerUserId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/chat/rooms/$roomId/messages',
      queryParameters: {'viewer_user_id': viewerUserId},
    );
    final messages = _list(response.data?['messages']);
    return messages.map((item) => ChatMessage.fromJson(_map(item))).toList();
  }

  Future<MessageSendResult> sendMessage({
    required String roomId,
    required String userId,
    required String text,
    required String visibility,
    required List<String> recipientAgentIds,
    required String deliveryMode,
    ChatContextOptions? contextOptions,
  }) async {
    final body = <String, dynamic>{
      'sender': {
        'sender_type': 'user',
        'user_id': userId,
      },
      'visibility': visibility,
      'recipient_agent_ids': recipientAgentIds,
      'content': {
        'content_type': 'text',
        'text': text,
      },
      'delivery_mode': deliveryMode,
    };
    if (contextOptions != null && deliveryMode == 'one_shot') {
      body['context_mode'] = contextOptions.modeValue;
      if (contextOptions.mode == ChatContextMode.pinned &&
          contextOptions.pinnedMessageId != null) {
        body['pinned_message_id'] = contextOptions.pinnedMessageId;
      }
      if (contextOptions.mode == ChatContextMode.rotation) {
        body['rotation_n'] = contextOptions.rotationN;
      }
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/rooms/$roomId/messages',
      data: body,
    );
    final data = response.data ?? const <String, dynamic>{};
    return MessageSendResult(
      message: ChatMessage.fromJson(_map(data['message'])),
      createdTasks: _list(data['created_tasks'])
          .map((item) => ChatCreatedTask.fromJson(_map(item)))
          .toList(),
    );
  }

  Future<List<AgentPreset>> listAgents({required String ownerUserId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/agent/presets',
      queryParameters: {'owner_user_id': ownerUserId},
    );
    final agents = _list(response.data?['agents']);
    return agents.map((item) => AgentPreset.fromJson(_map(item))).toList();
  }

  Future<ChatParticipant> inviteAgent({
    required String roomId,
    required String agentId,
    required String invitedByUserId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/rooms/$roomId/participants',
      data: {
        'agent_id': agentId,
        'invited_by_user_id': invitedByUserId,
      },
    );
    return ChatParticipant.fromJson(_map(response.data?['participant']));
  }

  Future<ChatParticipant> removeAgent({
    required String roomId,
    required String agentId,
    required String removedByUserId,
  }) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/chat/rooms/$roomId/participants/$agentId',
      data: {
        'agent_id': agentId,
        'removed_by_user_id': removedByUserId,
      },
    );
    return ChatParticipant.fromJson(_map(response.data?['participant']));
  }

  Future<void> deleteRoom(String roomId) async {
    await _dio.delete<void>('/chat/rooms/$roomId');
  }

  ChatRoomDetails _roomDetails(Map<String, dynamic>? data) {
    final payload = data ?? const <String, dynamic>{};
    final participants = _list(payload['participants'])
        .map((item) => ChatParticipant.fromJson(_map(item)))
        .toList();
    return ChatRoomDetails(
      room: ChatRoom.fromJson(_map(payload['room'])),
      participants: participants,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  static List<dynamic> _list(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }
}
