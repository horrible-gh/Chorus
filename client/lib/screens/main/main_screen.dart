import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../models/agent_preset.dart';
import '../../models/chat.dart';
import '../../models/chat_context_options.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/chat_push_service.dart';
import '../../services/chat_service.dart';
import '../../services/file_upload_service.dart';
import '../../widgets/chat_context_selector.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  ChatProvider? _chatProvider;
  String? _loadedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    _chatProvider ??= ChatProvider(
      ChatService(auth.dio),
      getToken: () => auth.accessToken ?? '',
    );

    final userId = auth.user?.userId;
    if (userId != null && userId.isNotEmpty && _loadedUserId != userId) {
      _loadedUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _chatProvider?.loadWorkspace(userId);
        }
      });
    }
  }

  @override
  void dispose() {
    _chatProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chatProvider = _chatProvider ??= ChatProvider(ChatService(auth.dio));
    final userId = auth.user?.userId ?? '';
    final displayName = auth.user?.displayName ?? 'User';

    return ChangeNotifierProvider<ChatProvider>.value(
      value: chatProvider,
      child: _MainShell(
        userId: userId,
        displayName: displayName,
      ),
    );
  }
}

class _MainShell extends StatelessWidget {
  const _MainShell({
    required this.userId,
    required this.displayName,
  });

  final String userId;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final showAgentPanel = constraints.maxWidth >= 1120;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: compact ? 0 : null,
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.graphic_eq),
                SizedBox(width: 8),
                Text('Chorus'),
              ],
            ),
            actions: [
              Consumer<ChatProvider>(
                builder: (context, chat, child) {
                  return IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: userId.isEmpty || chat.isLoadingWorkspace
                        ? null
                        : () => chat.loadWorkspace(userId),
                  );
                },
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push(AppRoutes.settings),
              ),
              IconButton(
                tooltip: 'Agent presets',
                icon: const Icon(Icons.smart_toy_outlined),
                onPressed: () => context.push(AppRoutes.agentPresets),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 96 : 180),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              Consumer<AuthProvider>(
                builder: (context, auth, child) {
                  return IconButton(
                    tooltip: 'Sign out',
                    icon: const Icon(Icons.logout),
                    onPressed: auth.isLoading
                        ? null
                        : () async {
                            await context.read<AuthProvider>().logout();
                            if (context.mounted) {
                              context.go(AppRoutes.login);
                            }
                          },
                  );
                },
              ),
            ],
          ),
          drawer: compact
              ? Drawer(
                  child: SafeArea(
                    child: _RoomSidebar(
                      userId: userId,
                      inDrawer: true,
                    ),
                  ),
                )
              : null,
          body: compact
              ? _ChatPane(
                  userId: userId,
                  showAgentPanelButton: true,
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 304,
                      child: _RoomSidebar(userId: userId),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _ChatPane(
                        userId: userId,
                        showAgentPanelButton: !showAgentPanel,
                      ),
                    ),
                    if (showAgentPanel) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 320,
                        child: _AgentPanel(userId: userId),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _RoomSidebar extends StatelessWidget {
  const _RoomSidebar({
    required this.userId,
    this.inDrawer = false,
  });

  final String userId;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<ChatProvider>(
      builder: (context, chat, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Rooms',
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'New room',
                      icon: const Icon(Icons.add),
                      onPressed: userId.isEmpty || chat.isLoadingWorkspace
                          ? null
                          : () => _showCreateRoomDialog(context, userId),
                    ),
                  ],
                ),
              ),
              if (chat.isLoadingWorkspace) const LinearProgressIndicator(),
              if (chat.error != null)
                _InlineError(
                  message: chat.error!,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                ),
              Expanded(
                child: chat.rooms.isEmpty
                    ? _EmptyRooms(
                        loading: chat.isLoadingWorkspace,
                        onCreate: userId.isEmpty
                            ? null
                            : () => _showCreateRoomDialog(context, userId),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                        itemCount: chat.rooms.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final room = chat.rooms[index];
                          return _RoomTile(
                            room: room,
                            selected: room.roomId == chat.selectedRoomId,
                            onTap: () async {
                              if (inDrawer) {
                                Navigator.of(context).pop();
                              }
                              await context
                                  .read<ChatProvider>()
                                  .selectRoom(room.roomId, userId);
                            },
                            onDelete: () async {
                              await context
                                  .read<ChatProvider>()
                                  .deleteRoom(room.roomId, userId);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateRoomDialog(
    BuildContext context,
    String userId,
  ) async {
    final chat = context.read<ChatProvider>();
    final draft = await showDialog<_NewRoomDraft>(
      context: context,
      builder: (context) => _CreateRoomDialog(agents: chat.agents),
    );
    if (draft == null || !context.mounted) {
      return;
    }

    await context.read<ChatProvider>().createRoom(
          userId: userId,
          title: draft.title,
          mode: draft.mode,
          initialAgentIds: draft.agentIds,
        );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final ChatRoom room;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
          room.mode == 'one_shot'
              ? Icons.flash_on_outlined
              : Icons.forum_outlined,
        ),
        title: Text(
          room.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_modeLabel(room.mode)} · ${_shortDate(room.updatedAt)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: selected
            ? IconButton(
                tooltip: 'Delete room',
                icon: Icon(
                  Icons.delete_outline,
                  color: colorScheme.error,
                ),
                onPressed: () => _confirmDelete(context),
              )
            : null,
        selected: selected,
        onTap: onTap,
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Room'),
        content: const Text('Are you sure you want to delete this room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({
    required this.loading,
    required this.onCreate,
  });

  final bool loading;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No rooms yet',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create room'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPane extends StatefulWidget {
  const _ChatPane({
    required this.userId,
    required this.showAgentPanelButton,
  });

  final String userId;
  final bool showAgentPanelButton;

  @override
  State<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<_ChatPane> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _selectedAgentIds = {};
  bool _whisper = false;
  bool _oneShot = false;
  bool _pinOnSend = false;
  int _lastMessageCount = 0;
  bool _lastHadPendingTasks = false;
  GenerationState _lastGenerationState = GenerationState.idle;
  ChatContextOptions _contextOptions = const ChatContextOptions();
  FileUploadService? _fileUploadService;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _fileUploadService ??= FileUploadService(context.read<AuthProvider>().dio);
    return Consumer<ChatProvider>(
      builder: (context, chat, child) {
        final room = chat.selectedRoom;
        final activeAgentIds = chat.activeAgentIds;
        _selectedAgentIds
            .removeWhere((agentId) => !activeAgentIds.contains(agentId));
        if (_whisper && activeAgentIds.isEmpty) {
          _whisper = false;
        }

        if (_lastMessageCount != chat.messages.length) {
          _lastMessageCount = chat.messages.length;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
        }

        if (_lastHadPendingTasks != chat.hasPendingTasks) {
          _lastHadPendingTasks = chat.hasPendingTasks;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
        }

        if (_lastGenerationState != chat.generationState) {
          final prevState = _lastGenerationState;
          _lastGenerationState = chat.generationState;
          if (prevState == GenerationState.cancelRequested &&
              chat.generationState == GenerationState.generating) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cancel failed. Try again.'),
                  ),
                );
              }
            });
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
        }

        if (room == null) {
          return _NoRoomSelected(
            onCreate: widget.userId.isEmpty
                ? null
                : () => _showCreateRoomDialog(context, widget.userId),
          );
        }

        final pinnedMessageId = _contextOptions.pinnedMessageId;
        String? pinnedMessagePreview;
        if (pinnedMessageId != null) {
          for (final msg in chat.messages) {
            if (msg.messageId == pinnedMessageId) {
              final t = msg.text;
              pinnedMessagePreview = t.length > 80 ? '${t.substring(0, 80)}…' : t;
              break;
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChatHeader(
              userId: widget.userId,
              room: room,
              showAgentPanelButton: widget.showAgentPanelButton,
            ),
            if (chat.pushStatus == ChatPushStatus.pushFallback ||
                chat.pushStatus == ChatPushStatus.pushFailed)
              const _PushFallbackBanner(),
            Expanded(
              child: Stack(
                children: [
                  chat.messages.isEmpty
                      ? _EmptyMessages(loading: chat.isLoadingMessages)
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          itemCount: chat.messages.length +
                              (_showStatusBubble(chat) ? 1 : 0),
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            if (index == chat.messages.length &&
                                _showStatusBubble(chat)) {
                              if (chat.hasPendingTasks) {
                                return _AgentThinkingBubble(
                                  completed: chat.pendingTasksCompleted,
                                  total: chat.pendingTasksTotal,
                                );
                              } else if (chat.generationState ==
                                  GenerationState.cancelled) {
                                return const _CancelledGenerationBubble();
                              } else if (chat.generationState ==
                                  GenerationState.failed) {
                                return const _FailedGenerationBubble();
                              } else {
                                return const _TimeoutGenerationBubble();
                              }
                            }
                            final message = chat.messages[index];
                            final alreadyPinned =
                                message.messageId == pinnedMessageId;
                            return _MessageBubble(
                              message: message,
                              senderName: _senderName(message, chat),
                              isPinned: alreadyPinned,
                              isCancelled: message.isCancelled,
                              onPinRequested: alreadyPinned
                                  ? null
                                  : () => _onPinMessage(message.messageId),
                              onUnpinRequested:
                                  alreadyPinned ? _onUnpinMessage : null,
                            );
                          },
                        ),
                  if (chat.isLoadingMessages && chat.messages.isNotEmpty)
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
            _Composer(
              controller: _messageController,
              activeAgents: chat.activeAgentParticipants,
              selectedAgentIds: _selectedAgentIds,
              whisper: _whisper,
              oneShot: _oneShot,
              pinOnSend: _pinOnSend,
              sending: chat.isSending,
              isOneShotRoom: room.mode == 'one_shot',
              contextOptions: _contextOptions,
              pinnedMessagePreview: pinnedMessagePreview,
              userId: widget.userId,
              fileUploadService: _fileUploadService!,
              showCancelButton: chat.hasPendingTasks,
              isCancelRequested:
                  chat.generationState == GenerationState.cancelRequested,
              onCancel: chat.hasPendingTasks
                  ? () => context
                        .read<ChatProvider>()
                        .cancelGeneration(widget.userId)
                  : null,
              onWhisperChanged: (value) {
                setState(() {
                  _whisper = value;
                  if (!_whisper) {
                    _selectedAgentIds.clear();
                  }
                });
              },
              onOneShotChanged: (value) {
                setState(() {
                  _oneShot = value;
                });
              },
              onPinOnSendChanged: (value) {
                setState(() => _pinOnSend = value);
              },
              onAgentToggled: (agentId, selected) {
                setState(() {
                  if (selected) {
                    _selectedAgentIds.add(agentId);
                  } else {
                    _selectedAgentIds.remove(agentId);
                  }
                });
              },
              onContextChanged: (opts) {
                setState(() => _contextOptions = opts);
              },
              onSend: () => _sendMessage(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateRoomDialog(
    BuildContext context,
    String userId,
  ) async {
    final chat = context.read<ChatProvider>();
    final draft = await showDialog<_NewRoomDraft>(
      context: context,
      builder: (context) => _CreateRoomDialog(agents: chat.agents),
    );
    if (draft == null || !context.mounted) {
      return;
    }
    await context.read<ChatProvider>().createRoom(
          userId: userId,
          title: draft.title,
          mode: draft.mode,
          initialAgentIds: draft.agentIds,
        );
  }

  Future<void> _sendMessage(BuildContext context) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final shouldPin = _pinOnSend;
    final messenger = ScaffoldMessenger.of(context);
    final chat = context.read<ChatProvider>();
    final result = await chat.sendMessage(
      userId: widget.userId,
      text: text,
      whisper: _whisper,
      recipientAgentIds: _selectedAgentIds.toList(),
      oneShot: _oneShot,
      contextOptions: _contextOptions,
    );
    if (!mounted || result == null) {
      return;
    }

    _messageController.clear();
    _scrollToEnd();
    if (shouldPin) {
      setState(() {
        _contextOptions = _contextOptions.copyWith(
          pinnedMessageId: result.message.messageId,
        );
        _pinOnSend = false;
      });
    }
    if (result.createdTasks.isNotEmpty) {
      messenger.showMaterialBanner(
        MaterialBanner(
          content: Text('${result.createdTasks.length} agent task(s) queued.'),
          actions: [
            TextButton(
              onPressed: () => messenger.hideCurrentMaterialBanner(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (context.mounted) messenger.hideCurrentMaterialBanner();
      });
    }
  }

  void _onPinMessage(String messageId) {
    setState(() {
      _contextOptions = _contextOptions.copyWith(pinnedMessageId: messageId);
    });
  }

  void _onUnpinMessage() {
    setState(() {
      _contextOptions = ChatContextOptions(
        mode: _contextOptions.mode,
        rotationN: _contextOptions.rotationN,
        uploadedFileId: _contextOptions.uploadedFileId,
      );
    });
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  bool _showStatusBubble(ChatProvider chat) {
    return chat.hasPendingTasks ||
        chat.generationState == GenerationState.cancelled ||
        chat.generationState == GenerationState.failed ||
        chat.generationState == GenerationState.timeout;
  }

  String _senderName(ChatMessage message, ChatProvider chat) {
    if (message.isFromUser) {
      return 'You';
    }
    if (message.isFromAgent) {
      for (final participant in chat.participants) {
        if (participant.isAgent && participant.agentId == message.senderAgentId) {
          return participant.displayName;
        }
      }
      for (final agent in chat.agents) {
        if (agent.agentId == message.senderAgentId) {
          return agent.displayName;
        }
      }
      return message.senderAgentId ?? 'Agent';
    }
    return 'System';
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.userId,
    required this.room,
    required this.showAgentPanelButton,
  });

  final String userId;
  final ChatRoom room;
  final bool showAgentPanelButton;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<ChatProvider>(
      builder: (context, chat, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(
              children: [
                Icon(
                  room.mode == 'one_shot'
                      ? Icons.flash_on_outlined
                      : Icons.forum_outlined,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        room.title,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _SmallChip(
                            icon: Icons.history,
                            label: _modeLabel(room.mode),
                          ),
                          for (final participant
                              in chat.activeAgentParticipants.take(3))
                            _SmallChip(
                              icon: Icons.smart_toy_outlined,
                              label: participant.displayName,
                            ),
                          if (chat.activeAgentParticipants.length > 3)
                            _SmallChip(
                              icon: Icons.more_horiz,
                              label:
                                  '+${chat.activeAgentParticipants.length - 3}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Reload messages',
                  icon: const Icon(Icons.sync),
                  onPressed: chat.isLoadingMessages
                      ? null
                      : () => chat.selectRoom(room.roomId, userId),
                ),
                if (showAgentPanelButton)
                  IconButton(
                    tooltip: 'Agents',
                    icon: const Icon(Icons.smart_toy_outlined),
                    onPressed: () => _showAgents(context, userId),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAgents(BuildContext context, String userId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 520,
            child: _AgentPanel(userId: userId),
          ),
        );
      },
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.activeAgents,
    required this.selectedAgentIds,
    required this.whisper,
    required this.oneShot,
    required this.pinOnSend,
    required this.sending,
    required this.isOneShotRoom,
    required this.contextOptions,
    required this.userId,
    required this.fileUploadService,
    required this.onWhisperChanged,
    required this.onOneShotChanged,
    required this.onPinOnSendChanged,
    required this.onAgentToggled,
    required this.onContextChanged,
    required this.onSend,
    required this.showCancelButton,
    required this.isCancelRequested,
    this.onCancel,
    this.pinnedMessagePreview,
  });

  final TextEditingController controller;
  final List<ChatParticipant> activeAgents;
  final Set<String> selectedAgentIds;
  final bool whisper;
  final bool oneShot;
  final bool pinOnSend;
  final bool sending;
  final bool isOneShotRoom;
  final ChatContextOptions contextOptions;
  final String? pinnedMessagePreview;
  final String userId;
  final FileUploadService fileUploadService;
  final ValueChanged<bool> onWhisperChanged;
  final ValueChanged<bool> onOneShotChanged;
  final ValueChanged<bool> onPinOnSendChanged;
  final void Function(String agentId, bool selected) onAgentToggled;
  final ValueChanged<ChatContextOptions> onContextChanged;
  final VoidCallback onSend;
  final bool showCancelButton;
  final bool isCancelRequested;
  final VoidCallback? onCancel;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed) {
      final canSend = !widget.sending &&
          widget.controller.text.trim().isNotEmpty &&
          (!widget.whisper || widget.selectedAgentIds.isNotEmpty);

      if (canSend) {
        widget.onSend();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  selected: widget.whisper,
                  avatar: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Whisper'),
                  onSelected: widget.activeAgents.isEmpty ? null : widget.onWhisperChanged,
                ),
                FilterChip(
                  selected: widget.oneShot,
                  avatar: const Icon(Icons.flash_on_outlined, size: 18),
                  label: const Text('One shot'),
                  onSelected: widget.onOneShotChanged,
                ),
                FilterChip(
                  selected: widget.pinOnSend,
                  avatar: const Icon(Icons.push_pin_outlined, size: 18),
                  label: const Text('Pin'),
                  onSelected: widget.onPinOnSendChanged,
                ),
              ],
            ),
            if (widget.whisper) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final agent in widget.activeAgents)
                    FilterChip(
                      selected: widget.selectedAgentIds.contains(agent.agentId),
                      avatar: const Icon(Icons.smart_toy_outlined, size: 18),
                      label: Text(agent.displayName),
                      onSelected: agent.agentId == null
                          ? null
                          : (selected) =>
                              widget.onAgentToggled(agent.agentId!, selected),
                    ),
                ],
              ),
            ],
            if (widget.isOneShotRoom) ...[
              const SizedBox(height: 8),
              ChatContextSelector(
                options: widget.contextOptions,
                onChanged: widget.onContextChanged,
                userId: widget.userId,
                fileUploadService: widget.fileUploadService,
                pinnedMessagePreview: widget.pinnedMessagePreview,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    focusNode: _focusNode,
                    onKeyEvent: _handleKeyEvent,
                    child: TextField(
                      controller: widget.controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        prefixIcon: Icon(Icons.chat_bubble_outline),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (widget.showCancelButton) ...[
                  widget.isCancelRequested
                      ? IconButton.filled(
                          onPressed: null,
                          icon: const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          tooltip: 'Cancel...',
                        )
                      : IconButton.filled(
                          onPressed: widget.onCancel,
                          icon: const Icon(Icons.stop),
                          tooltip: 'Stop',
                        ),
                  const SizedBox(width: 8),
                ],
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, child) {
                    final canSend = !widget.sending &&
                        !widget.isCancelRequested &&
                        value.text.trim().isNotEmpty &&
                        (!widget.whisper || widget.selectedAgentIds.isNotEmpty);
                    return IconButton.filled(
                      tooltip: 'Send',
                      icon: widget.sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      onPressed: canSend ? widget.onSend : null,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.senderName,
    this.isPinned = false,
    this.isCancelled = false,
    this.onPinRequested,
    this.onUnpinRequested,
  });

  final ChatMessage message;
  final String senderName;
  final bool isPinned;
  final bool isCancelled;
  final VoidCallback? onPinRequested;
  final VoidCallback? onUnpinRequested;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final alignRight = message.isFromUser;
    final bubbleColor = message.isFromUser
        ? colorScheme.primaryContainer
        : message.isFromAgent
            ? colorScheme.surfaceContainerHighest
            : colorScheme.tertiaryContainer;
    final textColor = message.isFromUser
        ? colorScheme.onPrimaryContainer
        : message.isFromAgent
            ? colorScheme.onSurfaceVariant
            : colorScheme.onTertiaryContainer;

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: GestureDetector(
          onLongPressStart: (onPinRequested == null && onUnpinRequested == null)
              ? null
              : (details) => _showContextMenu(context, details.globalPosition),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: alignRight
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        senderName,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      Text(
                        _timeOfDay(message.createdAt),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: textColor,
                            ),
                      ),
                      if (message.isWhisper)
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: textColor,
                        ),
                      if (message.isOneShot)
                        Icon(
                          Icons.flash_on_outlined,
                          size: 14,
                          color: textColor,
                        ),
                      if (isPinned)
                        Icon(
                          Icons.push_pin,
                          size: 14,
                          color: textColor,
                        ),
                      if (isCancelled)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Cancelled',
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (message.isStreaming)
                    _StreamingText(text: message.text, textColor: textColor)
                  else
                    SelectableText(
                      message.text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: textColor,
                          ),
                    ),
                  if (message.isFromAgent && message.contextUsage != null)
                    _ContextMeterBar(
                      contextUsage: message.contextUsage!,
                      textColor: textColor,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        if (isPinned)
          PopupMenuItem<void>(
            onTap: onUnpinRequested,
            child: const Row(
              children: [
                Icon(Icons.push_pin_outlined, size: 18),
                SizedBox(width: 8),
                Text('Unpin'),
              ],
            ),
          )
        else
          PopupMenuItem<void>(
            onTap: onPinRequested,
            child: const Row(
              children: [
                Icon(Icons.push_pin_outlined, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text('Pin', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Displays text with an animated blinking cursor to indicate active streaming.
class _StreamingText extends StatefulWidget {
  const _StreamingText({required this.text, required this.textColor});

  final String text;
  final Color textColor;

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final showCursor = _controller.value > 0.5;
        return Text(
          '${widget.text}${showCursor ? '▍' : ''}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: widget.textColor,
              ),
        );
      },
    );
  }
}

class _ContextMeterBar extends StatelessWidget {
  const _ContextMeterBar({
    required this.contextUsage,
    required this.textColor,
  });

  final ContextUsage contextUsage;
  final Color textColor;

  Color _barColor() {
    final r = contextUsage.displayRatio;
    if (r >= 0.95) return Colors.red;
    if (r >= 0.80) return Colors.orange;
    if (r >= 0.60) return Colors.amber;
    return Colors.green;
  }

  String _label() {
    final pct = (contextUsage.displayRatio * 100).round();
    return contextUsage.hasActual ? '$pct%' : '~$pct% est.';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: contextUsage.displayRatio.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: textColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(_barColor()),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _label(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: textColor.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
          ),
        ],
      ),
    );
  }
}

class _AgentPanel extends StatelessWidget {
  const _AgentPanel({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<ChatProvider>(
      builder: (context, chat, child) {
        return DecoratedBox(
          decoration: BoxDecoration(color: colorScheme.surface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Agents',
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh),
                      onPressed: chat.isLoadingWorkspace
                          ? null
                          : () => chat.loadWorkspace(userId),
                    ),
                  ],
                ),
              ),
              if (chat.isMutatingParticipants) const LinearProgressIndicator(),
              if (chat.selectedRoom == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Select a room to manage agents.'),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final participant in chat.activeAgentParticipants)
                        _SmallChip(
                          icon: Icons.check_circle_outline,
                          label: participant.displayName,
                        ),
                      if (chat.activeAgentParticipants.isEmpty)
                        const _SmallChip(
                          icon: Icons.info_outline,
                          label: 'No active agents',
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: chat.agents.isEmpty && chat.isLoadingWorkspace
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                        itemCount: chat.agents.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final agent = chat.agents[index];
                          final active = chat.activeAgentIds.contains(
                            agent.agentId,
                          );
                          return _AgentTile(
                            agent: agent,
                            active: active,
                            disabled: chat.selectedRoom == null ||
                                chat.isMutatingParticipants,
                            onPressed: active
                                ? () => chat.removeAgent(
                                      userId: userId,
                                      agentId: agent.agentId,
                                    )
                                : () => chat.inviteAgent(
                                      userId: userId,
                                      agentId: agent.agentId,
                                    ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AgentTile extends StatelessWidget {
  const _AgentTile({
    required this.agent,
    required this.active,
    required this.disabled,
    required this.onPressed,
  });

  final AgentPreset agent;
  final bool active;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: active ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: CircleAvatar(
          backgroundColor: active
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          foregroundColor:
              active ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          child: const Icon(Icons.smart_toy_outlined, size: 20),
        ),
        title: Text(
          agent.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${agent.roleName} · ${agent.defaultModel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: active ? 'Remove from room' : 'Invite to room',
          icon: Icon(active ? Icons.remove_circle_outline : Icons.add_circle),
          onPressed: disabled ? null : onPressed,
        ),
      ),
    );
  }
}

class _NoRoomSelected extends StatelessWidget {
  const _NoRoomSelected({required this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Select or create a room',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create room'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentThinkingBubble extends StatelessWidget {
  const _AgentThinkingBubble({
    this.completed = 0,
    this.total = 0,
  });

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = total > 1
        ? 'Agents are responding… ($completed/$total)'
        : 'Agent is responding…';
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CancelledGenerationBubble extends StatelessWidget {
  const _CancelledGenerationBubble();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cancel_outlined,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  'Generation cancelled.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FailedGenerationBubble extends StatelessWidget {
  const _FailedGenerationBubble();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 14,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Text(
                  'An error occurred during generation.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeoutGenerationBubble extends StatelessWidget {
  const _TimeoutGenerationBubble();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_off_outlined,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  '응답 시간이 초과되었습니다',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 42,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 168),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({
    required this.message,
    required this.padding,
  });

  final String message;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: padding,
      child: Text(
        message,
        style: TextStyle(
          color: colorScheme.error,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({required this.agents});

  final List<AgentPreset> agents;

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final _titleController = TextEditingController(text: 'New conversation');
  final Set<String> _selectedAgentIds = {};
  String _mode = 'append_history';

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _titleController.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('New room'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(Icons.title),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'append_history',
                  icon: Icon(Icons.history),
                  label: Text('History'),
                ),
                ButtonSegment(
                  value: 'one_shot',
                  icon: Icon(Icons.flash_on_outlined),
                  label: Text('One shot'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.first;
                });
              },
            ),
            if (widget.agents.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Invite agents',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 280,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.agents.map((agent) {
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _selectedAgentIds.contains(agent.agentId),
                        title: Text(
                          agent.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          agent.roleName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedAgentIds.add(agent.agentId);
                            } else {
                              _selectedAgentIds.remove(agent.agentId);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: canCreate
              ? () {
                  Navigator.of(context).pop(
                    _NewRoomDraft(
                      title: _titleController.text.trim(),
                      mode: _mode,
                      agentIds: _selectedAgentIds.toList(),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.add),
          label: const Text('Create'),
        ),
      ],
    );
  }

  void _onTitleChanged() {
    setState(() {});
  }
}

class _NewRoomDraft {
  const _NewRoomDraft({
    required this.title,
    required this.mode,
    required this.agentIds,
  });

  final String title;
  final String mode;
  final List<String> agentIds;
}

String _modeLabel(String mode) {
  switch (mode) {
    case 'one_shot':
      return 'One shot';
    case 'append_history':
    default:
      return 'History';
  }
}

String _shortDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value.isEmpty ? 'Updated now' : value;
  }
  return DateFormat('MMM d, HH:mm').format(parsed.toLocal());
}

String _timeOfDay(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }
  return DateFormat('HH:mm').format(parsed.toLocal());
}

/// Status badge displayed below the chat header in push_fallback/push_failed state.
class _PushFallbackBanner extends StatelessWidget {
  const _PushFallbackBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 14,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 6),
          Text(
            'Live updates disconnected · Auto-refreshing',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
          ),
        ],
      ),
    );
  }
}
