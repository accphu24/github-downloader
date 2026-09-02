import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../l10n/strings.dart';

/// Tìm kiếm code trên TOÀN GITHUB (khác với ô tìm kiếm trong browser_screen,
/// vốn chỉ tìm trong tên file của 1 repo đang mở). Hỗ trợ cú pháp qualifier
/// giống hệt github.com, ví dụ "TODO language:dart" hoặc "useState repo:facebook/react".
class CodeSearchScreen extends StatefulWidget {
  final GithubService githubService;

  const CodeSearchScreen({super.key, required this.githubService});

  @override
  State<CodeSearchScreen> createState() => _CodeSearchScreenState();
}

class _CodeSearchScreenState extends State<CodeSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<CodeSearchResult> _results = [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    // Debounce 700ms: GitHub Search API giới hạn RẤT chặt (10 request/phút),
    // gọi theo mỗi ký tự gõ sẽ vượt giới hạn gần như ngay lập tức.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () => _runSearch(value));
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final results = await widget.githubService.searchCodeGlobal(trimmed);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: t('codesearch.hint'),
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
          onSubmitted: _runSearch,
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: !_searched
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        t('codesearch.hint_qualifiers'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.outline),
                      ),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : _results.isEmpty && !_loading
                        ? Center(child: Text(t('codesearch.no_results'), style: TextStyle(color: scheme.outline)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final r = _results[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  leading: const Icon(Icons.insert_drive_file_rounded),
                                  title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                  subtitle: Text(
                                    '${r.repoFullName} · ${r.path}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                                  onTap: () {
                                    if (r.htmlUrl.isNotEmpty) {
                                      launchUrl(Uri.parse(r.htmlUrl), mode: LaunchMode.externalApplication);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
