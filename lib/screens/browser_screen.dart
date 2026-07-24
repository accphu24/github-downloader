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
    // Nếu được mở từ danh sách repo (đã có sẵn owner/repo), tự động load luôn
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
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: _logout)],
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
                    decoration: const InputDecoration(labelText: 'Owner', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _repoController,
                    decoration: const InputDecoration(labelText: 'Repo', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _loadRepo, child: const Text('Mở')),
              ],
            ),
          ),
          if (_currentPath.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(alignment: Alignment.centerLeft, child: Text('📁 /$_currentPath')),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final file = _files[index];
                final isDir = file.type == 'dir';
                return ListTile(
                  leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file),
                  title: Text(file.name),
                  trailing: isDir
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () => _downloadFile(file),
                        ),
                  onTap: isDir ? () => _openFolder(file.path) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
