import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/agent_preset.dart';
import '../models/chat.dart';
import '../models/chat_context_options.dart';
import '../services/chat_service.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider(this._service);

  final ChatService _service;

  List<ChatRoom> _rooms = const [];
  List<AgentPreset> _agents = const [];
  List<ChatParticipant> _participants = const [];
  List<ChatMessage> _messages = const [];
  String? _selectedRoomId;
  bool _isLoadingWorkspace = false;
  bool _isLoadingMessages = false;
  bool _isSending = false;
  bool _hasPendingTasks = false;
  bool _isMutatingParticipants = false;
  String? _error;
  String? _lastUserId;

  List<ChatRoom> get rooms => _rooms;
  List<AgentPreset> get agents => _agents;
  List<ChatParticipant> get participants => _participants;
  List<ChatMessage> get messages => _messages;
  String? get selectedRoomId => _selectedRoomId;
  bool get isLoadingWorkspace => _isLoadingWorkspace;
  bool get isLoadingMessages => _isLoadingMessages;
  bool get isSending => _isSending;
  bool get hasPendingTasks => _hasPendingTasks;
  bool get isMutatingParticipants => _isMutatingParticipants;
  String? get error => _error;

  ChatRoom? get selectedRoom {
    for (final room in _rooms) {
      if (room.roomId == _selectedRoomId) {
        return room;
      }
    }
    return null;
  }

  List<ChatParticipant> get activeAgentParticipants {
    return _participants
        .where((participant) => participant.isAgent && participant.isActive)
        .toList();
  }

  Set<String> get activeAgentIds {
    return activeAgentParticipants
        .map((participant) => participant.agentId)
        .whereType<String>()
        .toSet();
  }

  Future<void> loadWorkspace(String userId) async {
    _lastUserId = userId;
    _isLoadingWorkspace = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.listRooms(ownerUserId: userId),
        _service.listAgents(ownerUserId: userId),
      ]);

      _rooms = (results[0] as List<ChatRoom>)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _agents = results[1] as List<AgentPreset>;
      _isLoadingWorkspace = false;
      notifyListeners();

      if (_selectedRoomId == null && _rooms.isNotEmpty) {
        await selectRoom(_rooms.first.roomId, userId);
      } else if (_selectedRoomId != null) {
        await selectRoom(_selectedRoomId!, userId);
      }
    } catch (error, stackTrace) {
      debugPrint('[ChatProvider.loadWorkspace] $error');
      debugPrint('$stackTrace');
      _isLoadingWorkspace = false;
      _error = 'Unable to load the workspace.';
      notifyListeners();
    }
  }

  Future<void> selectRoom(String roomId, String userId) async {
    if (_selectedRoomId != roomId) {
      _hasPendingTasks = false;
    }
    _selectedRoomId = roomId;
    _lastUserId = userId;
    _isLoadingMessages = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.getRoom(roomId),
        _service.listMessages(roomId: roomId, viewerUserId: userId),
      ]);
      final details = results[0] as ChatRoomDetails;
      _participants = details.participants;
      _messages = results[1] as List<ChatMessage>;
      _replaceRoom(details.room);
      _isLoadingMessages = false;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[ChatProvider.selectRoom] $error');
      debugPrint('$stackTrace');
      _isLoadingMessages = false;
      _error = 'Unable to open the room.';
      notifyListeners();
    }
  }

  Future<void> createRoom({
    required String userId,
    required String title,
    required String mode,
    required List<String> initialAgentIds,
  }) async {
    _isLoadingWorkspace = true;
    _error = null;
    notifyListeners();

    try {
      final details = await _service.createRoom(
        userId: userId,
        title: title,
        mode: mode,
        initialAgentIds: initialAgentIds,
      );
      _replaceRoom(details.room);
      _participants = details.participants;
      _messages = const [];
      _selectedRoomId = details.room.roomId;
      _isLoadingWorkspace = false;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[ChatProvider.createRoom] $error');
      debugPrint('$stackTrace');
      _isLoadingWorkspace = false;
      _error = 'Unable to create the room.';
      notifyListeners();
    }
  }

  Future<MessageSendResult?> sendMessage({
    required String userId,
    required String text,
    required bool whisper,
    required List<String> recipientAgentIds,
    required bool oneShot,
    ChatContextOptions? contextOptions,
  }) async {
    final roomId = _selectedRoomId;
    if (roomId == null || text.trim().isEmpty) {
      return null;
    }

    _lastUserId = userId;
    _isSending = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.sendMessage(
        roomId: roomId,
        userId: userId,
        text: text.trim(),
        visibility: whisper ? 'whisper' : 'room',
        recipientAgentIds: whisper ? recipientAgentIds : const [],
        deliveryMode: oneShot ? 'one_shot' : 'append_history',
        contextOptions: contextOptions,
      );
      _messages = [..._messages, result.message];
      _touchSelectedRoom(result.message.createdAt);
      _isSending = false;
      if (result.createdTasks.isNotEmpty) {
        _hasPendingTasks = true;
      }
      notifyListeners();
      if (result.createdTasks.isNotEmpty) {
        unawaited(_pollAgentResponses(roomId, _messages.length, result.createdTasks.length));
      }
      return result;
    } catch (error, stackTrace) {
      debugPrint('[ChatProvider.sendMessage] $error');
      debugPrint('$stackTrace');
      _isSending = false;
      _error = 'Unable to send the message.';
      notifyListeners();
      return null;
    }
  }

  Future<void> _pollAgentResponses(String roomId, int countAfterSend, [int expectedCount = 1]) async {
    for (var i = 0; i < 8; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!_hasPendingTasks) return;
      if (roomId != _selectedRoomId) return;

      final userId = _lastUserId;
      if (userId == null || userId.isEmpty) break;

      try {
        final messages = await _service.listMessages(
          roomId: roomId,
          viewerUserId: userId,
        );
        _messages = messages;
        final newCount = messages.length - countAfterSend;
        if (newCount >= (expectedCount > 0 ? expectedCount : 1)) {
          _hasPendingTasks = false;
        }
        notifyListeners();
      } catch (error, stackTrace) {
        debugPrint('[ChatProvider._pollAgentResponses] $error');
        debugPrint('$stackTrace');
      }

      if (!_hasPendingTasks) return;
    }

    if (_hasPendingTasks) {
      _hasPendingTasks = false;
      notifyListeners();
    }
  }

  Future<void> inviteAgent({
    required String userId,
    required String agentId,
  }) async {
    final roomId = _selectedRoomId;
    if (roomId == null) {
      return;
    }

    _isMutatingParticipants = true;
    _error = null;
    notifyListeners();

    try {
      final participant = await _service.inviteAgent(
        roomId: roomId,
        agentId: agentId,
        invitedByUserId: userId,
      );
      _upsertParticipant(participant);
      _isMutatingParticipants = false;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[ChatProvider.inviteAgent] $error');
      debugPrint('$stackTrace');
      _isMutatingParticipants = false;
      _error = 'Unable to invite the agent.';
      notifyListeners();
    }
  }

  Future<void> removeAgent({
    required String userId,
    required String agentId,
  }) async {
    final roomId = _selectedRoomId;
    if (roomId == null) {
      return;
    }

    _isMutatingParticipants = true;
    _error = null;
    notifyListeners();

    try {
      final participant = await _service.removeAgent(
        roomId: roomId,
        agentId: agentId,
        removedByUserId: userId,
      );
      _upsertParticipant(participant);
      _isMutatingParticipants = false;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[ChatProvider.removeAgent] $error');
      debugPrint('$stackTrace');
      _isMutatingParticipants = false;
      _error = 'Unable to remove the agent.';
      notifyListeners();
    }
  }

  void _replaceRoom(ChatRoom room) {
    final rooms = [..._rooms];
    final index = rooms.indexWhere((item) => item.roomId == room.roomId);
    if (index == -1) {
      rooms.insert(0, room);
    } else {
      rooms[index] = room;
    }
    rooms.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _rooms = rooms;
  }

  void _touchSelectedRoom(String updatedAt) {
    final selected = selectedRoom;
    if (selected == null) {
      return;
    }
    _replaceRoom(
      ChatRoom(
        roomId: selected.roomId,
        title: selected.title,
        mode: selected.mode,
        status: selected.status,
        ownerUserId: selected.ownerUserId,
        activeHistoryMode: selected.activeHistoryMode,
        baseSummaryMessageId: selected.baseSummaryMessageId,
        createdAt: selected.createdAt,
        updatedAt: updatedAt,
        archivedAt: selected.archivedAt,
      ),
    );
  }

  void _upsertParticipant(ChatParticipant participant) {
    final participants = [..._participants];
    final index = participants.indexWhere(
      (item) => item.participantId == participant.participantId,
    );
    if (index == -1) {
      participants.add(participant);
    } else {
      participants[index] = participant;
    }
    _participants = participants;
  }
}
