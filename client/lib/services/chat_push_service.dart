import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket connection status.
enum ChatPushStatus {
  pushIdle,
  pushConnecting,
  pushConnected,
  pushReconnecting,
  pushFailed,
  pushFallback,
}

/// WebSocket-based server push subscription service.
///
/// Call [connect] when entering a room, and [disconnect] when leaving or switching rooms.
/// Register a callback on [onMessageCompleted] to be notified when a message_completed event is received;
/// the callback is invoked with the room_id as its argument.
///
/// On connection failure, reconnects with exponential backoff (up to 5 retries);
/// switches to [ChatPushStatus.pushFallback] when the maximum retries are exceeded.
class ChatPushService extends ChangeNotifier {
  ChatPushService({required String wsBaseUrl}) : _wsBaseUrl = wsBaseUrl;

  final String _wsBaseUrl;

  ChatPushStatus _status = ChatPushStatus.pushIdle;
  ChatPushStatus get status => _status;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  String? _currentRoomId;
  String? _currentToken;

  final Map<String, WebSocketChannel> _backgroundChannels = {};
  final Map<String, StreamSubscription<dynamic>> _backgroundSubscriptions = {};

  int _retryCount = 0;
  Duration _currentDelay = _kReconnectInitialDelay;
  Timer? _reconnectTimer;
  Timer? _fallbackReconnectTimer;

  String? _lastProcessedTaskId;
  DateTime? _lastTaskProcessedAt;

  bool _inFlight = false;
  bool _pendingRefresh = false;

  /// Callback invoked when a message_completed event is received.
  /// Argument: room_id
  void Function(String roomId)? onMessageCompleted;

  /// Callback invoked when a message_delta streaming event is received.
  /// Arguments: taskId, roomId, delta text chunk
  void Function(String taskId, String roomId, String delta, String? agentId)? onMessageDelta;

  /// Callback invoked when a thinking_delta streaming event is received.
  /// Arguments: taskId, roomId, delta text chunk
  void Function(String taskId, String roomId, String delta)? onThinkingDelta;

  /// Callback invoked when a thinking_completed event is received.
  /// Arguments: taskId, roomId
  void Function(String taskId, String roomId)? onThinkingCompleted;

  static const int _kReconnectMaxRetries = 5;
  static const Duration _kReconnectInitialDelay = Duration(seconds: 1);
  static const int _kReconnectMultiplier = 2;
  static const Duration _kReconnectMaxDelay = Duration(seconds: 30);
  static const Duration _kDebounceWindow = Duration(seconds: 5);
  static const Duration _kFallbackReconnectInterval = Duration(seconds: 10);

  /// Starts a WebSocket subscription for the given room_id.
  ///
  /// Does nothing if already connected to the same room.
  /// If connected to a different room, moves the existing connection to the
  /// background (kept alive) and opens a new connection for the new room.
  void connect(String roomId, String token) {
    if (_currentRoomId == roomId &&
        (_status == ChatPushStatus.pushConnected ||
            _status == ChatPushStatus.pushConnecting)) {
      return;
    }
    _cancelReconnectTimer();
    _cancelFallbackReconnectTimer();
    final prevRoomId = _currentRoomId;
    if (prevRoomId != null) {
      if (_channel != null) _backgroundChannels[prevRoomId] = _channel!;
      if (_subscription != null) _backgroundSubscriptions[prevRoomId] = _subscription!;
      _channel = null;
      _subscription = null;
    }
    _currentRoomId = roomId;
    _currentToken = token;
    _resetState();
    _setStatus(ChatPushStatus.pushConnecting);
    _connectInternal(roomId, token);
  }

  /// Terminates the current WebSocket subscription and transitions to push_idle state.
  void disconnect() {
    _cancelReconnectTimer();
    _cancelFallbackReconnectTimer();
    _closeCurrentConnection();
    _currentRoomId = null;
    _currentToken = null;
    _setStatus(ChatPushStatus.pushIdle);
  }

  /// Notifies that an in-flight listMessages request has completed.
  ///
  /// If pending_refresh is true, calls onMessageCompleted once more.
  void notifyRefreshComplete() {
    _inFlight = false;
    if (_pendingRefresh && _currentRoomId != null) {
      _executeListMessages(_currentRoomId!);
    }
  }

  void _resetState() {
    _retryCount = 0;
    _currentDelay = _kReconnectInitialDelay;
    _lastProcessedTaskId = null;
    _lastTaskProcessedAt = null;
    _inFlight = false;
    _pendingRefresh = false;
  }

  void _connectInternal(String roomId, String token) {
    final baseWsUrl = '$_wsBaseUrl/ws/rooms/$roomId/events';
    try {
      if (kIsWeb) {
        // Flutter Web: cannot send Authorization header → use ?access_token= query param
        final wsUri = Uri.parse(baseWsUrl)
            .replace(queryParameters: {'access_token': token});
        debugPrint(
          '[ChatPushService] connecting platform=web '
          'url=$baseWsUrl (access_token in query)',
        );
        _channel = WebSocketChannel.connect(wsUri);
      } else {
        debugPrint(
          '[ChatPushService] connecting platform=native url=$baseWsUrl',
        );
        _channel = IOWebSocketChannel.connect(
          Uri.parse(baseWsUrl),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint(
        '[ChatPushService] connect error platform=${kIsWeb ? "web" : "native"} '
        'url=$baseWsUrl error=$e',
      );
      _scheduleReconnect(roomId, token);
    }
  }

  void _onData(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;
      switch (type) {
        case 'subscribe_success':
          _cancelFallbackReconnectTimer();
          _setStatus(ChatPushStatus.pushConnected);
          _retryCount = 0;
          _currentDelay = _kReconnectInitialDelay;

        case 'message_completed':
          _onMessageCompletedEvent(json);

        case 'message_delta':
          _onMessageDeltaEvent(json);

        case 'thinking_delta':
          _onThinkingDeltaEvent(json);

        case 'thinking_completed':
          _onThinkingCompletedEvent(json);

        case 'heartbeat':
          // Skipping last_heartbeat_at recording (Phase 1 simple implementation)
          break;

        case 'error':
          final retryAfter = json['retry_after'] as int? ?? 0;
          if (retryAfter == -1) {
            _transitionToFallback();
          } else {
            if (_currentRoomId != null && _currentToken != null) {
              _scheduleReconnect(_currentRoomId!, _currentToken!);
            }
          }

        default:
          break;
      }
    } catch (e) {
      debugPrint('[ChatPushService] parse error: $e');
    }
  }

  void _onMessageCompletedEvent(Map<String, dynamic> event) {
    final eventRoomId = event['room_id'] as String?;
    if (eventRoomId == null || eventRoomId != _currentRoomId) return;

    final taskId = event['task_id'] as String?;
    final now = DateTime.now();

    if (taskId != null && taskId == _lastProcessedTaskId) {
      final lastAt = _lastTaskProcessedAt;
      if (lastAt != null && now.difference(lastAt) < _kDebounceWindow) {
        return; // ignore duplicate events within debounce window
      }
    }
    _lastProcessedTaskId = taskId;
    _lastTaskProcessedAt = now;

    _triggerListMessagesRefresh(eventRoomId);
  }

  void _onMessageDeltaEvent(Map<String, dynamic> event) {
    final eventRoomId = event['room_id'] as String?;
    if (eventRoomId == null || eventRoomId != _currentRoomId) return;

    final taskId = event['task_id'] as String?;
    final delta = event['delta'] as String?;
    if (taskId == null || delta == null || delta.isEmpty) return;

    final agentId = event['agent_id'] as String?;
    onMessageDelta?.call(taskId, eventRoomId, delta, agentId);
  }

  void _onThinkingDeltaEvent(Map<String, dynamic> event) {
    final eventRoomId = event['room_id'] as String?;
    if (eventRoomId == null || eventRoomId != _currentRoomId) return;

    final taskId = event['task_id'] as String?;
    final delta = event['delta'] as String?;
    if (taskId == null || delta == null || delta.isEmpty) return;

    onThinkingDelta?.call(taskId, eventRoomId, delta);
  }

  void _onThinkingCompletedEvent(Map<String, dynamic> event) {
    final eventRoomId = event['room_id'] as String?;
    if (eventRoomId == null || eventRoomId != _currentRoomId) return;

    final taskId = event['task_id'] as String?;
    if (taskId == null) return;

    onThinkingCompleted?.call(taskId, eventRoomId);
  }

  void _triggerListMessagesRefresh(String roomId) {
    if (_inFlight) {
      _pendingRefresh = true;
      return;
    }
    _executeListMessages(roomId);
  }

  void _executeListMessages(String roomId) {
    _inFlight = true;
    _pendingRefresh = false;
    onMessageCompleted?.call(roomId);
  }

  void _onError(dynamic error) {
    debugPrint(
      '[ChatPushService] stream error platform=${kIsWeb ? "web" : "native"} '
      'room=${_currentRoomId ?? "none"} error=$error',
    );
    if (_currentRoomId != null && _currentToken != null) {
      _scheduleReconnect(_currentRoomId!, _currentToken!);
    }
  }

  void _onDone() {
    if (_status == ChatPushStatus.pushConnected ||
        _status == ChatPushStatus.pushConnecting) {
      if (_currentRoomId != null && _currentToken != null) {
        _scheduleReconnect(_currentRoomId!, _currentToken!);
      }
    }
  }

  void _scheduleReconnect(String roomId, String token) {
    if (_retryCount >= _kReconnectMaxRetries) {
      _transitionToFallback();
      return;
    }
    _setStatus(ChatPushStatus.pushReconnecting);
    _reconnectTimer = Timer(_currentDelay, () {
      _retryCount++;
      final nextMs = (_currentDelay.inMilliseconds * _kReconnectMultiplier)
          .clamp(0, _kReconnectMaxDelay.inMilliseconds);
      _currentDelay = Duration(milliseconds: nextMs);
      _connectInternal(roomId, token);
    });
  }

  void _transitionToFallback() {
    _cancelFallbackReconnectTimer();
    _setStatus(ChatPushStatus.pushFailed);
    _setStatus(ChatPushStatus.pushFallback);
    _scheduleFallbackReconnect();
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleFallbackReconnect() {
    if (_currentRoomId == null || _currentToken == null) {
      return;
    }
    _fallbackReconnectTimer = Timer.periodic(_kFallbackReconnectInterval, (_) {
      if (_status == ChatPushStatus.pushFallback &&
          _currentRoomId != null &&
          _currentToken != null) {
        debugPrint(
          '[ChatPushService] attempting fallback reconnect room=${_currentRoomId ?? "none"}',
        );
        _connectInternal(_currentRoomId!, _currentToken!);
      }
    });
  }

  void _cancelFallbackReconnectTimer() {
    _fallbackReconnectTimer?.cancel();
    _fallbackReconnectTimer = null;
  }

  void _closeCurrentConnection() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close(1000);
    _channel = null;
  }

  void _setStatus(ChatPushStatus newStatus) {
    if (_status == newStatus) return;
    debugPrint('[ChatPushService] status $_status → $newStatus room=${_currentRoomId ?? "none"}');
    _status = newStatus;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelReconnectTimer();
    _cancelFallbackReconnectTimer();
    _closeCurrentConnection();
    for (final sub in _backgroundSubscriptions.values) sub.cancel();
    for (final ch in _backgroundChannels.values) ch.sink.close(1000);
    _backgroundSubscriptions.clear();
    _backgroundChannels.clear();
    super.dispose();
  }
}
