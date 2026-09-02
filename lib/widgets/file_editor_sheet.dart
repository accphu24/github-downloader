import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import '../services/github_service.dart';
import '../services/downloads_service.dart';
import '../utils/syntax_lang.dart';
import '../l10n/strings.dart';
import 'top_notification.dart';
import 'diff_preview_sheet.dart';

/// Bottom sheet xem và sửa nội dung 1 file text, có thể lưu (commit) thẳng lên GitHub.
/// Trả về true qua Navigator nếu đã lưu thành công (để màn hình cha có thể tự làm mới).
class FileEditorSheet extends StatefulWidget {
  final String owner;
  final String repo;
  final GithubFile file;
  final GithubService githubService;
  final bool canEdit;
  final String? branch;

  const FileEditorSheet({
    super.key,
    required this.owner,
    required this.repo,
    required this.file,
    required this.githubService,
    required this.canEdit,
    this.branch,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String owner,
    required String repo,
    required GithubFile file,
    required GithubService githubService,
    required bool canEdit,
    String? branch,
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
        branch: branch,
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
      final meta = await widget.githubService.getFileMeta(widget.owner, widget.repo, widget.file.path, ref: widget.branch);
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
    final savedPath = await DownloadsService.saveBytes(widget.file.name, utf8.encode(_controller.text));
    if (mounted && savedPath != null) {
      showTopNotification(context, t('common.saved_at', {'path': savedPath}));
    }
  }

  Future<void> _saveToGithub() async {
    if (_currentSha == null) return;
    final defaultMessage = 'Update ${widget.file.name} via GitHub Repo Downloader';

    final commitMessage = await DiffPreviewSheet.show(
      context,
      fileName: widget.file.name,
      oldContent: _originalContent,
      newContent: _controller.text,
      initialCommitMessage: defaultMessage,
    );
    if (commitMessage == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.githubService.updateFile(
        widget.owner,
        widget.repo,
        widget.file.path,
        _controller.text,
        _currentSha!,
        commitMessage: commitMessage.isEmpty ? defaultMessage : commitMessage,
        branch: widget.branch,
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

  bool get _isMarkdown {
    final lower = widget.file.name.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  /// Chế độ xem (không sửa): file Markdown -> render đẹp (bold/heading/list...);
  /// file code có ngôn ngữ nhận diện được -> tô màu cú pháp; còn lại -> text thường.
  Widget _buildViewer(BuildContext context, ScrollController scrollController) {
    if (_isMarkdown) {
      return Markdown(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        data: _controller.text,
        selectable: true,
      );
    }

    final lang = highlightLanguageForFile(widget.file.name);
    if (lang != null) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: HighlightView(
            _controller.text,
            language: lang,
            theme: isDark ? atomOneDarkTheme : githubTheme,
            textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _controller.text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
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
                    // Trước đây chỉ khoá khi _loading -> nếu tải nội dung file bị lỗi
                    // (_error != null), nút này vẫn bấm được và âm thầm lưu ra 1 file
                    // RỖNG (vì _controller.text chưa từng được gán nội dung thật).
                    onPressed: (_loading || _error != null) ? null : _downloadToDevice,
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
                          : _buildViewer(context, scrollController),
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
