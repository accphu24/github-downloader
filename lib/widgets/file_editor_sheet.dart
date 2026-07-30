import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/github_service.dart';
import '../l10n/strings.dart';

/// Bottom sheet xem và sửa nội dung 1 file text, có thể lưu (commit) thẳng lên GitHub.
/// Trả về true qua Navigator nếu đã lưu thành công (để màn hình cha có thể tự làm mới).
class FileEditorSheet extends StatefulWidget {
  final String owner;
  final String repo;
  final GithubFile file;
  final GithubService githubService;
  final bool canEdit;

  const FileEditorSheet({
    super.key,
    required this.owner,
    required this.repo,
    required this.file,
    required this.githubService,
    required this.canEdit,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String owner,
    required String repo,
    required GithubFile file,
    required GithubService githubService,
    required bool canEdit,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => FileEditorSheet(
        owner: owner,
        repo: repo,
        file: file,
        githubService: githubService,
        canEdit: canEdit,
      ),
    );
  }

  @override
  State<FileEditorSheet> createState() => _FileEditorSheetState();
}

class _FileEditorSheetState extends State<FileEditorSheet> {
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _error;
  String _originalContent = '';
  late final TextEditingController _controller;
  String? _currentSha;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final meta = await widget.githubService.getFileMeta(widget.owner, widget.repo, widget.file.path);
      _currentSha = meta.sha;
      final bytes = await widget.githubService.downloadFile(meta.downloadUrl!);
      _originalContent = utf8.decode(bytes);
      _controller.text = _originalContent;
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _downloadToDevice() async {
    final dir = await getExternalStorageDirectory();
    final savePath = '${dir!.path}/${widget.file.name}';
    await File(savePath).writeAsBytes(utf8.encode(_controller.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('common.saved_at', {'path': savePath}))));
    }
  }

  Future<void> _saveToGithub() async {
    if (_currentSha == null) return;
    final messageController = TextEditingController(text: 'Update ${widget.file.name} via GitHub Repo Downloader');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('editor.commit_confirm_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('File: ${widget.file.path}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: InputDecoration(labelText: t('editor.commit_message_label'), border: const OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Commit')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.githubService.updateFile(
        widget.owner,
        widget.repo,
        widget.file.path,
        _controller.text,
        _currentSha!,
        commitMessage: messageController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('editor.commit_success'))));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('common.error_prefix', {'error': e.toString()}))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (_controller.text == _originalContent) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('editor.discard_title')),
        content: Text(t('editor.discard_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('editor.discard_stay'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('editor.discard_confirm'))),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = _controller.text != _originalContent;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => PopScope(
        canPop: !hasChanges,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (await _confirmDiscardIfNeeded() && mounted) Navigator.pop(context);
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.file.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.canEdit && !_loading && _error == null)
                    IconButton(
                      icon: Icon(_editing ? Icons.visibility_rounded : Icons.edit_rounded),
                      tooltip: _editing ? t('editor.view_tooltip') : t('editor.edit_tooltip'),
                      onPressed: () => setState(() => _editing = !_editing),
                    ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded),
                    tooltip: t('editor.download_tooltip'),
                    onPressed: _loading ? null : _downloadToDevice,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_saving) const LinearProgressIndicator(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                      : _editing
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: TextField(
                                controller: _controller,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                decoration: const InputDecoration(border: InputBorder.none),
                                onChanged: (_) => setState(() {}),
                              ),
                            )
                          : SingleChildScrollView(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(
                                _controller.text,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                              ),
                            ),
            ),
            if (_editing && hasChanges)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _saveToGithub,
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: Text(t('editor.commit_button')),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
