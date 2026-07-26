import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/github_service.dart';
import 'browser_screen.dart';
import 'login_screen.dart';

/// Cache đơn giản trong bộ nhớ, tồn tại trong suốt phiên chạy app.
/// Giúp mở lại danh sách repo tức thì thay vì gọi API mỗi lần vào màn hình.
class _RepoCache {
  static List<GithubRepo>? repos;
}

class RepoListScreen extends StatefulWidget {
  const RepoListScreen({super.key});

  @override
  State<RepoListScreen> createState() => _RepoListScreenState();
}

class _RepoListScreenState extends State<RepoListScreen> {
  final _authService = AuthService();
  final _searchController = TextEditingController();
  GithubService? _githubService;
  List<GithubRepo> _allRepos = [];
  List<GithubRepo> _filteredRepos = [];
  bool _loading = true;
  String? _error;
  String? _username;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
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
    _githubService = GithubService(token: token);
    _username = username;

    // Có cache -> hiện ngay lập tức, rồi âm thầm làm mới ở nền
    if (_RepoCache.repos != null) {
      setState(() {
        _allRepos = _RepoCache.repos!;
        _filteredRepos = _allRepos;
        _loading = false;
      });
      _loadRepos(silent: true);
    } else {
      await _loadRepos();
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredRepos = query.isEmpty
          ? _allRepos
          : _allRepos.where((r) => r.fullName.toLowerCase().contains(query)).toList();
    });
  }

  Future<void> _loadRepos({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repos = await _githubService!.listUserRepos();
      _RepoCache.repos = repos;
      setState(() {
        _allRepos = repos;
        _applyFilter();
      });
    } on GithubUnauthorizedException {
      await _forceLogout();
    } catch (e) {
      if (!silent) setState(() => _error = e.toString());
    } finally {
      if (!silent) setState(() => _loading = false);
    }
  }

  Future<void> _forceLogout() async {
    await _authService.logout();
    _RepoCache.repos = null;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    _RepoCache.repos = null;
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openRepo(GithubRepo repo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrowserScreen(initialOwner: repo.owner, initialRepo: repo.name),
      ),
    );
  }

  void _openManualEntry() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BrowserScreen()));
  }

  Color _permissionColor(BuildContext context, GithubRepo repo) {
    final scheme = Theme.of(context).colorScheme;
    if (repo.canAdmin) return scheme.primary;
    if (repo.canPush) return Colors.teal;
    if (repo.canPull) return scheme.outline;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_username != null ? 'Repo của $_username' : 'Repo của tôi'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_rounded), tooltip: 'Nhập owner/repo thủ công', onPressed: _openManualEntry),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => _loadRepos()),
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _logout),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm repo theo tên...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: _searchController.clear)
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: () => _loadRepos(), child: const Text('Thử lại')),
                            ],
                          ),
                        ),
                      )
                    : _filteredRepos.isEmpty
                        ? Center(
                            child: Text(
                              _allRepos.isEmpty ? 'Không tìm thấy repo nào.' : 'Không có repo nào khớp tìm kiếm.',
                              style: TextStyle(color: scheme.outline),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadRepos(),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: _filteredRepos.length,
                              itemBuilder: (context, index) {
                                final repo = _filteredRepos[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    leading: CircleAvatar(
                                      backgroundColor: repo.private ? scheme.errorContainer : scheme.primaryContainer,
                                      child: Icon(
                                        repo.private ? Icons.lock_rounded : Icons.public_rounded,
                                        size: 18,
                                        color: repo.private ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                                      ),
                                    ),
                                    title: Text(repo.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: repo.description != null && repo.description!.isNotEmpty
                                        ? Text(repo.description!, maxLines: 1, overflow: TextOverflow.ellipsis)
                                        : null,
                                    trailing: Chip(
                                      label: Text(
                                        repo.permissionLabel,
                                        style: const TextStyle(color: Colors.white, fontSize: 11),
                                      ),
                                      backgroundColor: _permissionColor(context, repo),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                    ),
                                    onTap: () => _openRepo(repo),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
