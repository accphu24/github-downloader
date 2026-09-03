import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../services/pinned_repos_service.dart';
import '../l10n/strings.dart';

/// Tìm kiếm GỘP trên toàn bộ repo đã ghim (nhóm C #1), 2 tab:
/// - Code: dùng GitHub Code Search API với "repo:a OR repo:b" gộp trong 1 request.
/// - File/Thư mục: dùng Git Trees API, chạy song song từng repo vì API này
///   không bị giới hạn chặt như Code Search (10 request/phút).
/// Kết quả luôn nhóm theo repo (accordion) để dễ phân biệt.
class PinnedSearchScreen extends StatefulWidget {
  final GithubService githubService;

  const PinnedSearchScreen({super.key, required this.githubService});

  @override
  State<PinnedSearchScreen> createState() => _PinnedSearchScreenState();
}

class _PinnedSearchScreenState extends State<PinnedSearchScreen> with SingleTickerProviderStateMixin {
  final _pinnedService = PinnedReposService();
  late final TabController _tabController;

  Set<String> _pinned = {};
  bool _loadingPinned = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPinned();
  }

  Future<void> _loadPinned() async {
    final pinned = await _pinnedService.getPinned();
    if (mounted) setState(() {
      _pinned = pinned;
      _loadingPinned = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('pinnedsearch.title')),
        bottom: _loadingPinned || _pinned.isEmpty
            ? null
            : TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: t('pinnedsearch.tab_code')),
                  Tab(text: t('pinnedsearch.tab_files')),
                ],
              ),
      ),
      body: _loadingPinned
          ? const Center(child: CircularProgressIndicator())
          : _pinned.isEmpty
              ? _buildNoPinnedState(context)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _PinnedCodeSearchTab(githubService: widget.githubService, pinned: _pinned),
                    _PinnedFileSearchTab(githubService: widget.githubService, pinned: _pinned),
                  ],
                ),
    );
  }

  Widget _buildNoPinnedState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border_rounded, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              t('pinnedsearch.no_pinned_title'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              t('pinnedsearch.no_pinned_body'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

// ================== Tab: tìm code ==================

class _PinnedCodeSearchTab extends StatefulWidget {
  final GithubService githubService;
  final Set<String> pinned;

  const _PinnedCodeSearchTab({required this.githubService, required this.pinned});

  @override
  State<_PinnedCodeSearchTab> createState() => _PinnedCodeSearchTabState();
}

class _PinnedCodeSearchTabState extends State<_PinnedCodeSearchTab> with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  Timer? _debounce;

  Map<String, List<CodeSearchResult>> _grouped = {};
  bool _loading = false;
  String? _error;
  bool _searched = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    // Debounce 700ms: GitHub Search API giới hạn RẤT chặt (10 request/phút).
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () => _runSearch(value));
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _grouped = {};
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
      final results = await widget.githubService.searchCodeAcrossRepos(trimmed, widget.pinned);
      final grouped = <String, List<CodeSearchResult>>{};
      for (final r in results) {
        grouped.putIfAbsent(r.repoFullName, () => []).add(r);
      }
      if (mounted) setState(() => _grouped = grouped);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: t('pinnedsearch.code_hint'),
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
            ),
            onChanged: _onQueryChanged,
            onSubmitted: _runSearch,
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: !_searched
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      t('pinnedsearch.code_hint_qualifiers', {'count': '${widget.pinned.length}'}),
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
                  : _grouped.isEmpty && !_loading
                      ? Center(child: Text(t('pinnedsearch.no_results'), style: TextStyle(color: scheme.outline)))
                      : _buildGroupedList(scheme),
        ),
      ],
    );
  }

  Widget _buildGroupedList(ColorScheme scheme) {
    final repoNames = _grouped.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: repoNames.length,
      itemBuilder: (context, index) {
        final repo = repoNames[index];
        final items = _grouped[repo]!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: ExpansionTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            initiallyExpanded: repoNames.length <= 3,
            title: Text(repo, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(t('pinnedsearch.result_count', {'count': '${items.length}', 'repo': repo})),
            children: items
                .map((r) => ListTile(
                      leading: const Icon(Icons.insert_drive_file_rounded),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(r.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () {
                        if (r.htmlUrl.isNotEmpty) {
                          launchUrl(Uri.parse(r.htmlUrl), mode: LaunchMode.externalApplication);
                        }
                      },
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

// ================== Tab: tìm file/thư mục ==================

class _PinnedFileSearchTab extends StatefulWidget {
  final GithubService githubService;
  final Set<String> pinned;

  const _PinnedFileSearchTab({required this.githubService, required this.pinned});

  @override
  State<_PinnedFileSearchTab> createState() => _PinnedFileSearchTabState();
}

class _PinnedFileSearchTabState extends State<_PinnedFileSearchTab> with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();

  Map<String, List<GithubFile>> _grouped = {};
  bool _loading = false;
  bool _searched = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _grouped = {};
        _searched = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _searched = true;
    });
    // Git Trees API không bị giới hạn chặt như Code Search nên chạy song song
    // từng repo được, không cần debounce - chỉ tìm khi bấm Enter.
    final grouped = await widget.githubService.searchFilesAcrossRepos(trimmed, widget.pinned);
    if (mounted) {
      setState(() {
        _grouped = grouped;
        _loading = false;
      });
    }
  }

  Future<void> _openResult(String repoFullName, GithubFile file) async {
    final parts = repoFullName.split('/');
    if (parts.length != 2) return;
    try {
      final branch = await widget.githubService.getDefaultBranch(parts[0], parts[1]);
      final url = 'https://github.com/$repoFullName/blob/$branch/${file.path}';
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Bỏ qua nếu không lấy được default branch - không chặn thao tác khác của người dùng.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: t('pinnedsearch.files_hint'),
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
            ),
            onSubmitted: _runSearch,
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: !_searched
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      t('pinnedsearch.files_hint_empty', {'count': '${widget.pinned.length}'}),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline),
                    ),
                  ),
                )
              : _grouped.isEmpty && !_loading
                  ? Center(child: Text(t('pinnedsearch.no_results'), style: TextStyle(color: scheme.outline)))
                  : _buildGroupedList(scheme),
        ),
      ],
    );
  }

  Widget _buildGroupedList(ColorScheme scheme) {
    final repoNames = _grouped.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: repoNames.length,
      itemBuilder: (context, index) {
        final repo = repoNames[index];
        final items = _grouped[repo]!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: ExpansionTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            initiallyExpanded: repoNames.length <= 3,
            title: Text(repo, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(t('pinnedsearch.result_count', {'count': '${items.length}', 'repo': repo})),
            children: items
                .map((f) => ListTile(
                      leading: Icon(f.type == 'dir' ? Icons.folder_rounded : Icons.insert_drive_file_rounded),
                      title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => _openResult(repo, f),
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}
