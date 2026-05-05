enum ChatContextMode { none, pinned, rotation }

class ChatContextOptions {
  const ChatContextOptions({
    this.mode = ChatContextMode.none,
    this.pinnedMessageId,
    this.rotationN = 5,
    this.uploadedFileId,
  });

  final ChatContextMode mode;
  final String? pinnedMessageId;
  final int rotationN;
  final String? uploadedFileId;

  String get modeValue {
    switch (mode) {
      case ChatContextMode.pinned:
        return 'pinned';
      case ChatContextMode.rotation:
        return 'rotation';
      case ChatContextMode.none:
        return 'none';
    }
  }

  ChatContextOptions copyWith({
    ChatContextMode? mode,
    String? pinnedMessageId,
    int? rotationN,
    String? uploadedFileId,
  }) {
    return ChatContextOptions(
      mode: mode ?? this.mode,
      pinnedMessageId: pinnedMessageId ?? this.pinnedMessageId,
      rotationN: rotationN ?? this.rotationN,
      uploadedFileId: uploadedFileId ?? this.uploadedFileId,
    );
  }
}
