import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/github_service.dart';
import '../services/downloads_service.dart';
import '../services/download_manager.dart';
import '../l10n/strings.dart';
import '../widgets/top_notification.dart';
import '../main.dart' show navigatorKey;
import 'login_screen.dart';
import 'actions_screen.dart';
import 'commits_screen.dart';
import '../widgets/file_editor_sheet.dart';

const int _bigFolderWarningThreshold = 200;
const int _bigDateSortWarningThreshold = 50;

enum SortOption { nameAsc, nameDesc, sizeAsc, sizeDesc, dateNewest, dateOldest }

String _sortLabel(SortOption option) {
  switch (option) {
    case SortOption.nameAsc:
      return t('browser.sort.name_asc');
    case SortOption.nameDesc:
      return t('browser.sort.name_desc');
    case SortOption.sizeAsc:
      return t('browser.sort.size_asc');
    case SortOption.sizeDesc:
      return t('browser.sort.size_desc');
    case SortOption.dateNewest:
      return t('browser.sort.date_newest');
    case SortOption.dateOldest:
      return t('browser.sort.date_oldest');
  }
}

String _formatSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class BrowserScreen extends StatefulWidget {
  final String? initialOwner;
  final String? initialRepo;

  const BrowserScreen({super.key, this.initialOwner, this.initialRepo});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _authService = AuthService();
  late final _ownerController = TextEditingController(text: widget.initialOwner ?? '');
  late final _repoController = TextEditingController(text: widget.initialRepo ?? '');
  final _searchController = TextEditingController();

  GithubService? _githubService;
  List<GithubFile> _files = [];
  String _currentPath = '';
  bool _loading = false;
  String? _username;

  bool _searching = false;
  List<GithubFile> _searchResults = [];
  bool _searchLoading = false;

  SortOption _sortOption = SortOption.nameAsc;
  final Map<String, DateTime> _fileDates = {};
  bool _loadingDates = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final token = await _authService.getToken();
    final username = await _authService.getUsername();
    setState(() {
      _githubService = GithubService(token: token);
      _username = username;
    });
    if (widget.initialOwner != null && widget.initialRepo != null) {
      await _loadRepo();
    }
  }

  /// Bắt lỗi chung: nếu token hết hạn/bị thu hồi thì tự đăng xuất về màn hình login.
  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on GithubUnauthorizedException {
      await _authService.logout();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('login.session_expired'))));
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
      return null;
    } catch (e) {
      _showError(e.toString());
      return null;
    }
  }

  Future<void> _loadRepo() async {
    if (_ownerController.text.isEmpty || _repoController.text.isEmpty) return;
    setState(() {
      _loading = true;
      _currentPath = '';
      _fileDates.clear();
    });
    final files = await _guard(() => _githubService!.listContents(
          _ownerController.text.trim(),
          _repoController.text.trim(),
        ));
    if (files != null) setState(() => _files = files);
    setState(() => _loading = false);
  }

  Future<void> _openFolder(String path) async {
    setState(() {
      _loading = true;
      _fileDates.clear();
    });
    final files = await _guard(() => _githubService!.listContents(
          _ownerController.text.trim(),
          _repoController.text.trim(),
          path: path,
        ));
    if (files != null) {
      setState(() {
        _files = files;
        _currentPath = path;
      });
    }
    setState(() => _loading = false);
  }

  void _downloadFile(GithubFile file) {
    if (file.downloadUrl == null) return;
    DownloadManager.instance.runDownload(
      label: file.name,
      navigatorKey: navigatorKey,
      fetch: (onProgress) => _githubService!.downloadFile(file.downloadUrl!),
      save: (bytes) => DownloadsService.saveBytes(file.name, bytes),
      onSuccess: (ctx, savedPath) => showTopNotification(ctx, t('common.saved_at', {'path': savedPath})),
      onError: (ctx, error) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(error))),
    );
  }

  Future<void> _previewFile(GithubFile file) async {
    if (file.downloadUrl == null) return;
    final saved = await FileEditorSheet.show(
      context,
      owner: _ownerController.text.trim(),
      repo: _repoController.text.trim(),
      file: file,
      githubService: _githubService!,
      canEdit: true, // GitHub sẽ tự từ chối (403) nếu tài khoản không có quyền ghi
    );
    if (saved == true && mounted) {
      if (_currentPath.isEmpty) {
        await _loadRepo();
      } else {
        await _openFolder(_currentPath);
      }
    }
  }

  /// Logic dùng chung để tải 1 thư mục (hoặc cả repo, khi path rỗng) dạng .zip.
  /// Bước đếm file + xác nhận vẫn ở màn hình hiện tại (nhanh), nhưng bước tải
  /// + nén thực sự chạy nền qua DownloadManager để không chặn màn hình.
  Future<void> _downloadAsZip({required String path, required String displayName}) async {
    setState(() => _loading = true);
    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    final files = await _guard(() => _githubService!.listAllFilesRecursive(owner, repo, path));
    if (mounted) setState(() => _loading = false);
    if (files == null || !mounted) return;

    if (files.isEmpty) {
      _showError(t('browser.zip_no_files'));
      return;
    }

    final isBig = files.length > _bigFolderWarningThreshold;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('browser.zip_confirm_title', {'name': displayName})),
        content: Text(
          isBig
              ? t('browser.zip_confirm_big', {'count': files.length.toString()})
              : t('browser.zip_confirm_normal', {'count': files.length.toString()}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('browser.zip_download_button'))),
        ],
      ),
    );
    if (confirm != true) return;

    DownloadManager.instance.runDownload(
      label: '$displayName.zip',
      navigatorKey: navigatorKey,
      fetch: (onProgress) => _githubService!.zipFiles(
        files,
        path,
        onProgress: (done, total) => onProgress(total > 0 ? done / total : null),
      ),
      save: (bytes) => DownloadsService.saveBytes('$displayName.zip', bytes),
      onSuccess: (ctx, savedPath) => showTopNotification(ctx, t('common.saved_at', {'path': savedPath})),
      onError: (ctx, error) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(error))),
    );
  }

  Future<void> _handleFolderLongPress(GithubFile folder) =>
      _downloadAsZip(path: folder.path, displayName: folder.name);

  Future<void> _downloadWholeRepoAsZip() =>
      _downloadAsZip(path: '', displayName: _repoController.text.trim());

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searchLoading = true);
    final results = await _guard(() => _githubService!.searchFilesInRepo(
          _ownerController.text.trim(),
          _repoController.text.trim(),
          query.trim(),
        ));
    if (results != null) setState(() => _searchResults = results);
    setState(() => _searchLoading = false);
  }

  Future<void> _openSearchResult(GithubFile result, {required bool preview}) async {
    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    final meta = await _guard(() => _githubService!.getFileMeta(owner, repo, result.path));
    if (meta == null) return;
    if (preview) {
      await _previewFile(meta);
    } else {
      _downloadFile(meta);
    }
  }

  /// Chọn kiểu sắp xếp. Nếu chọn theo ngày mà chưa có dữ liệu ngày, sẽ tự tải trước.
  Future<void> _selectSort(SortOption option) async {
    setState(() => _sortOption = option);

    final needsDate = option == SortOption.dateNewest || option == SortOption.dateOldest;
    if (!needsDate) return;

    final filesNeedingDate = _files.where((f) => f.type == 'file' && !_fileDates.containsKey(f.path)).toList();
    if (filesNeedingDate.isEmpty) return;

    if (filesNeedingDate.length > _bigDateSortWarningThreshold) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t('browser.date_sort_warning_title')),
          content: Text(t('browser.date_sort_warning_body', {'count': filesNeedingDate.length.toString()})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('common.continue'))),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _loadingDates = true);
    for (final file in filesNeedingDate) {
      final date = await _guard(() => _githubService!.getLastCommitDate(
            _ownerController.text.trim(),
            _repoController.text.trim(),
            file.path,
          ));
      if (date != null) _fileDates[file.path] = date;
    }
    if (mounted) setState(() => _loadingDates = false);
  }

  /// Luôn đưa thư mục lên trước, sau đó sắp xếp file theo tiêu chí đang chọn.
  List<GithubFile> get _sortedFiles {
    final dirs = _files.where((f) => f.type == 'dir').toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = _files.where((f) => f.type == 'file').toList();

    switch (_sortOption) {
      case SortOption.nameAsc:
        files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case SortOption.nameDesc:
        files.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case SortOption.sizeAsc:
        files.sort((a, b) => (a.size ?? 0).compareTo(b.size ?? 0));
        break;
      case SortOption.sizeDesc:
        files.sort((a, b) => (b.size ?? 0).compareTo(a.size ?? 0));
        break;
      case SortOption.dateNewest:
        files.sort((a, b) =>
            (_fileDates[b.path] ?? DateTime(0)).compareTo(_fileDates[a.path] ?? DateTime(0)));
        break;
      case SortOption.dateOldest:
        files.sort((a, b) =>
            (_fileDates[a.path] ?? DateTime(0)).compareTo(_fileDates[b.path] ?? DateTime(0)));
        break;
    }

    return [...dirs, ...files];
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repoIsOpen = _ownerController.text.isNotEmpty && _repoController.text.isNotEmpty && _files.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_username != null ? t('browser.title_named', {'username': _username!}) : t('browser.title_generic')),
        actions: [
          if (repoIsOpen) ...[
            IconButton(
              icon: const Icon(Icons.play_circle_outline_rounded),
              tooltip: t('browser.actions_tooltip'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ActionsScreen(
                    owner: _ownerController.text.trim(),
                    repo: _repoController.text.trim(),
                    githubService: _githubService!,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: t('browser.commits_tooltip'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommitsScreen(
                    owner: _ownerController.text.trim(),
                    repo: _repoController.text.trim(),
                    githubService: _githubService!,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
              tooltip: t('browser.search_tooltip'),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchController.clear();
                  _searchResults = [];
                }
              }),
            ),
          ],
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _logout),
        ],
      ),
      floatingActionButton: repoIsOpen && !_searching
          ? FloatingActionButton.extended(
              onPressed: _downloadWholeRepoAsZip,
              icon: const Icon(Icons.folder_zip_rounded),
              label: Text(t('browser.download_whole_repo')),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ownerController,
                    decoration: InputDecoration(
                      labelText: t('browser.owner_label'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _repoController,
                    decoration: InputDecoration(
                      labelText: t('browser.repo_label'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _loadRepo, child: Text(t('browser.open_button'))),
              ],
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: t('browser.search_hint'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: _runSearch,
              ),
            ),
          if (_currentPath.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '📁 /$_currentPath',
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (!_loading && _files.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('browser.hint_long_press_zip'),
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
                  PopupMenuButton<SortOption>(
                    tooltip: t('browser.sort_tooltip'),
                    onSelected: _selectSort,
                    icon: Icon(Icons.sort_rounded, size: 20, color: scheme.primary),
                    itemBuilder: (ctx) => SortOption.values
                        .map((o) => PopupMenuItem(
                              value: o,
                              child: Row(
                                children: [
                                  if (_sortOption == o) Icon(Icons.check_rounded, size: 16, color: scheme.primary),
                                  if (_sortOption == o) const SizedBox(width: 6),
                                  Text(_sortLabel(o)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          if (_loading || _searchLoading || _loadingDates) const LinearProgressIndicator(),
          Expanded(
            child: _searching
                ? _buildSearchResults(scheme)
                : _files.isEmpty && !_loading
                    ? Center(
                        child: Text(
                          t('browser.empty_state'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.outline),
                        ),
                      )
                    : _buildFileList(scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme scheme) {
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.isEmpty ? t('browser.search_hint_empty') : t('browser.search_no_match'),
          style: TextStyle(color: scheme.outline),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        final canPreview = isPreviewable(result.name);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.insert_drive_file_rounded),
            title: Text(result.name, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(result.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canPreview)
                  IconButton(
                    icon: const Icon(Icons.visibility_rounded),
                    onPressed: () => _openSearchResult(result, preview: true),
                  ),
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () => _openSearchResult(result, preview: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileList(ColorScheme scheme) {
    final sorted = _sortedFiles;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final file = sorted[index];
        final isDir = file.type == 'dir';
        final canPreview = !isDir && isPreviewable(file.name);
        final dateStr = _fileDates.containsKey(file.path) ? _formatSizeOrDate(file) : null;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: 0,
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: CircleAvatar(
              backgroundColor: isDir ? scheme.primaryContainer : scheme.secondaryContainer,
              child: Icon(
                isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                color: isDir ? scheme.onPrimaryContainer : scheme.onSecondaryContainer,
                size: 20,
              ),
            ),
            title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: !isDir
                ? Text(
                    dateStr ?? _formatSize(file.size),
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  )
                : null,
            trailing: isDir
                ? const Icon(Icons.chevron_right_rounded)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canPreview)
                        IconButton(icon: const Icon(Icons.visibility_rounded), onPressed: () => _previewFile(file)),
                      IconButton(icon: const Icon(Icons.download_rounded), onPressed: () => _downloadFile(file)),
                    ],
                  ),
            onTap: isDir ? () => _openFolder(file.path) : (canPreview ? () => _previewFile(file) : null),
            onLongPress: isDir ? () => _handleFolderLongPress(file) : null,
          ),
        );
      },
    );
  }

  String _formatSizeOrDate(GithubFile file) {
    final date = _fileDates[file.path];
    if (date == null) return _formatSize(file.size);
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · ${_formatSize(file.size)}';
  }
}
