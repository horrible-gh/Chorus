import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_context_options.dart';
import '../services/file_upload_service.dart';

class ChatContextSelector extends StatefulWidget {
  const ChatContextSelector({
    super.key,
    required this.options,
    required this.onChanged,
    required this.userId,
    required this.fileUploadService,
    this.pinnedMessagePreview,
  });

  final ChatContextOptions options;
  final ValueChanged<ChatContextOptions> onChanged;
  final String userId;
  final FileUploadService fileUploadService;
  /// Preview text of the currently pinned message (shown when pinned mode is active).
  final String? pinnedMessagePreview;

  @override
  State<ChatContextSelector> createState() => _ChatContextSelectorState();
}

class _ChatContextSelectorState extends State<ChatContextSelector> {
  late final TextEditingController _rotationNController;
  late final TextEditingController _filePathController;
  bool _uploading = false;
  String? _uploadedFileId;

  @override
  void initState() {
    super.initState();
    _rotationNController =
        TextEditingController(text: widget.options.rotationN.toString());
    _filePathController = TextEditingController();
  }

  @override
  void dispose() {
    _rotationNController.dispose();
    _filePathController.dispose();
    super.dispose();
  }

  void _onModeSelected(ChatContextMode mode) {
    widget.onChanged(widget.options.copyWith(mode: mode));
  }

  void _onClearPinned() {
    widget.onChanged(
      ChatContextOptions(
        mode: widget.options.mode,
        rotationN: widget.options.rotationN,
        uploadedFileId: widget.options.uploadedFileId,
      ),
    );
  }

  void _onRotationNChanged(String value) {
    final n = int.tryParse(value);
    if (n != null && n >= 1 && n <= 9999) {
      widget.onChanged(widget.options.copyWith(rotationN: n));
    }
  }

  Future<void> _uploadFile() async {
    final path = _filePathController.text.trim();
    if (path.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final result = await widget.fileUploadService.uploadFile(
        ownerUserId: widget.userId,
        filePath: path,
      );
      setState(() {
        _uploadedFileId = result.fileId;
        _uploading = false;
      });
      widget.onChanged(widget.options.copyWith(uploadedFileId: result.fileId));
    } catch (_) {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Context',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('None'),
                selected: widget.options.mode == ChatContextMode.none,
                onSelected: (_) => _onModeSelected(ChatContextMode.none),
              ),
              ChoiceChip(
                label: const Text('Pinned'),
                selected: widget.options.mode == ChatContextMode.pinned,
                onSelected: (_) => _onModeSelected(ChatContextMode.pinned),
              ),
              ChoiceChip(
                label: const Text('Rotation'),
                selected: widget.options.mode == ChatContextMode.rotation,
                onSelected: (_) => _onModeSelected(ChatContextMode.rotation),
              ),
            ],
          ),
          if (widget.options.mode == ChatContextMode.pinned) ...[
            const SizedBox(height: 8),
            _PinnedMessageInfo(
              pinnedMessageId: widget.options.pinnedMessageId,
              pinnedMessagePreview: widget.pinnedMessagePreview,
              onClear:
                  widget.options.pinnedMessageId != null ? _onClearPinned : null,
            ),
          ],
          if (widget.options.mode == ChatContextMode.rotation) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _rotationNController,
                decoration: const InputDecoration(
                  labelText: 'Message count (N)',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: _onRotationNChanged,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filePathController,
                  decoration: InputDecoration(
                    labelText: 'File path',
                    isDense: true,
                    suffixText: _uploadedFileId != null ? '✓ uploaded' : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _uploading
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.upload_file_outlined, size: 20),
                      tooltip: 'Upload file',
                      onPressed: _uploadFile,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinnedMessageInfo extends StatelessWidget {
  const _PinnedMessageInfo({
    required this.pinnedMessageId,
    required this.pinnedMessagePreview,
    required this.onClear,
  });

  final String? pinnedMessageId;
  final String? pinnedMessagePreview;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (pinnedMessageId == null) {
      return Row(
        children: [
          Icon(Icons.push_pin_outlined, size: 16, color: colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Long-press a message to pin it, or use the Pin option when sending.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ),
        ],
      );
    }

    final preview = (pinnedMessagePreview?.isNotEmpty == true)
        ? pinnedMessagePreview!
        : pinnedMessageId!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.push_pin,
            size: 16,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Icon(
                Icons.close,
                size: 16,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
        ],
      ),
    );
  }
}
