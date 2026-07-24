import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/auth_service.dart';
import '../services/github_service.dart';

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

  GithubService? _githubService;
  List<GithubFile> _files = [];
  String _currentPath = '';
  bool _loading = false;
  String? _username;

  @override
  void initState() {
    super.initState();
    _init();
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

  Future<void> _loadRepo() async {
    if (_ownerController.text.isEmpty || _repoController.text.isEmpty) return;
    setState(() {
      _loading = true;
      _currentPath = '';
    });
    try {
      final files = await _githubService!.listContents(
        _ownerController.text.trim(),
        _repoController.text.trim(),
      );
      setState(() => _files = files);
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _openFolder(String path) async {
    setState(() => _loading = true);
    try {
      final files = await _githubService!.listContents(
        _ownerController.text.trim(),
        _repoController.text.trim(),
        path: path,
      );
      setState(() {
        _files = files;
        _currentPath = path;
      });
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _downloadFile(GithubFile file) async {
    if (file.downloadUrl == null) return;
    setState(() => _loading = true);
    try {
      final bytes = await _githubService!.downloadFile(file.downloadUrl!);
      final dir = await getExternalStorageDirectory();
      final savePath = '${dir!.path}/${file.name}';
      await File(savePath).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã lưu: $savePath')),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Nhấn giữ vào 1 thư mục -> hỏi xác nhận -> tải toàn bộ (kể cả thư mục con)
  /// và nén thành 1 file .zip duy nhất.
  Future<void> _handleFolderLongPress(GithubFile folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Tải "${folder.name}" dạng ZIP?'),
        content: const Text('Toàn bộ file và thư mục con bên trong sẽ được nén lại thành 1 file .zip.'),
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

    try {
      final zipBytes = await _githubService!.downloadFolderAsZip(
        _ownerController.text.trim(),
        _repoController.text.trim(),
        folder.path,
        onProgress: (done, total) => progressNotifier.value = 'Đã tải $done/$total file...',
      );

      final dir = await getExternalStorageDirectory();
      final savePath = '${dir!.path}/${folder.name}.zip';
      await File(savePath).writeAsBytes(zipBytes);

      if (mounted) {
        Navigator.pop(context); // đóng dialog tiến trình
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã lưu: $savePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError(e.toString());
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_username != null ? 'Xin chào, $_username' : 'Duyệt repo'),
        actions: [IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _logout)],
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
          if (_currentPath.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '📁 /$_currentPath',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (!_loading && _files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mẹo: nhấn giữ vào thư mục để tải cả thư mục dạng .zip',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _files.isEmpty && !_loading
                ? Center(
                    child: Text(
                      'Nhập owner/repo rồi bấm "Mở"\nđể bắt đầu duyệt file.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final isDir = file.type == 'dir';
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          leading: CircleAvatar(
                            backgroundColor: isDir
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.secondaryContainer,
                            child: Icon(
                              isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                              color: isDir
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSecondaryContainer,
                              size: 20,
                            ),
                          ),
                          title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          trailing: isDir
                              ? const Icon(Icons.chevron_right_rounded)
                              : IconButton(
                                  icon: const Icon(Icons.download_rounded),
                                  onPressed: () => _downloadFile(file),
                                ),
                          onTap: isDir ? () => _openFolder(file.path) : null,
                          onLongPress: isDir ? () => _handleFolderLongPress(file) : null,
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
