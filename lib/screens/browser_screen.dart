import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/auth_service.dart';
import '../services/github_service.dart';
import 'login_screen.dart';

const int _bigFolderWarningThreshold = 200;

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.')),
        );
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
    });
    final files = await _guard(() => _githubService!.listContents(
          _ownerController.text.trim(),
          _repoController.text.trim(),
        ));
    if (files != null) setState(() => _files = files);
    setState(() => _loading = false);
  }

  Future<void> _openFolder(String path) async {
    setState(() => _loading = true);
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

  Future<void> _downloadFile(GithubFile file) async {
    if (file.downloadUrl == null) return;
    setState(() => _loading = true);
    final bytes = await _guard(() => _githubService!.downloadFile(file.downloadUrl!));
    if (bytes != null) {
      final dir = await getExternalStorageDirectory();
      final savePath = '${dir!.path}/${file.name}';
      await File(savePath).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu: $savePath')));
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _previewFile(GithubFile file) async {
    if (file.downloadUrl == null) return;
    showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(content: SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))),
    );
    final bytes = await _guard(() => _githubService!.downloadFile(file.downloadUrl!));
    if (mounted) Navigator.pop(context); // đóng dialog loading

    if (bytes == null || !mounted) return;

    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = '(Không thể hiển thị - có thể là file nhị phân)';
    }
    const maxChars = 8000;
    final truncated = content.length > maxChars;
    if (truncated) content = '${content.substring(0, maxChars)}\n\n... (đã cắt bớt, tải file để xem đầy đủ)';

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text(file.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  IconButton(
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _downloadFile(file);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: SelectableText(content, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nhấn giữ vào 1 thư mục -> đếm số file trước, cảnh báo nếu quá nhiều,
  /// rồi mới tải toàn bộ (kể cả thư mục con) và nén thành 1 file .zip.
  Future<void> _handleFolderLongPress(GithubFile folder) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: SizedBox(
          height: 60,
          child: Row(children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 16),
            Text('Đang kiểm tra số lượng file...'),
          ]),
        ),
      ),
    );

    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    final files = await _guard(() => _githubService!.listAllFilesRecursive(owner, repo, folder.path));
    if (mounted) Navigator.pop(context); // đóng dialog đếm file
    if (files == null || !mounted) return;

    if (files.isEmpty) {
      _showError('Thư mục này không có file nào.');
      return;
    }

    final isBig = files.length > _bigFolderWarningThreshold;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Tải "${folder.name}" dạng ZIP?'),
        content: Text(
          isBig
              ? 'Thư mục này có ${files.length} file, khá nhiều nên có thể mất vài phút và dễ chạm giới hạn API của GitHub. Vẫn muốn tiếp tục?'
              : 'Thư mục này có ${files.length} file. Toàn bộ sẽ được nén thành 1 file .zip.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tải ZIP')),
        ],
      ),
    );
    if (confirm != true) return;

    final progressNotifier = ValueNotifier<String>('Đang chuẩn bị...');
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: ValueListenableBuilder<String>(
          valueListenable: progressNotifier,
          builder: (context, value, _) => Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 16),
              Expanded(child: Text(value)),
            ],
          ),
        ),
      ),
    );

    final zipBytes = await _guard(() => _githubService!.zipFiles(
          files,
          folder.path,
          onProgress: (done, total) => progressNotifier.value = 'Đã tải $done/$total file...',
        ));

    if (mounted) Navigator.pop(context); // đóng dialog tiến trình
    if (zipBytes == null) return;

    final dir = await getExternalStorageDirectory();
    final savePath = '${dir!.path}/${folder.name}.zip';
    await File(savePath).writeAsBytes(zipBytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu: $savePath')));
    }
  }

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
      await _downloadFile(meta);
    }
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
        title: Text(_username != null ? 'Xin chào, $_username' : 'Duyệt repo'),
        actions: [
          if (repoIsOpen)
            IconButton(
              icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
              tooltip: 'Tìm file trong toàn repo',
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchController.clear();
                  _searchResults = [];
                }
              }),
            ),
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _logout),
        ],
      ),
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
                      labelText: 'Owner',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _repoController,
                    decoration: InputDecoration(
                      labelText: 'Repo',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _loadRepo, child: const Text('Mở')),
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
                  hintText: 'Tìm file theo tên/đường dẫn trong toàn repo...',
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mẹo: nhấn giữ vào thư mục để tải cả thư mục dạng .zip',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
            ),
          if (_loading || _searchLoading) const LinearProgressIndicator(),
          Expanded(
            child: _searching
                ? _buildSearchResults(scheme)
                : _files.isEmpty && !_loading
                    ? Center(
                        child: Text(
                          'Nhập owner/repo rồi bấm "Mở"\nđể bắt đầu duyệt file.',
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
          _searchController.text.isEmpty ? 'Nhập từ khoá rồi nhấn Enter để tìm.' : 'Không tìm thấy file nào khớp.',
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
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isDir = file.type == 'dir';
        final canPreview = !isDir && isPreviewable(file.name);
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
}
