import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/github_service.dart';
import 'browser_screen.dart';

class RepoListScreen extends StatefulWidget {
  const RepoListScreen({super.key});

  @override
  State<RepoListScreen> createState() => _RepoListScreenState();
}

class _RepoListScreenState extends State<RepoListScreen> {
  final _authService = AuthService();
  GithubService? _githubService;
  List<GithubRepo> _repos = [];
  bool _loading = true;
  String? _error;
  String? _username;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final token = await _authService.getToken();
    final username = await _authService.getUsername();
    _githubService = GithubService(token: token);
    _username = username;
    await _loadRepos();
  }

  Future<void> _loadRepos() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repos = await _githubService!.listUserRepos();
      setState(() => _repos = repos);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
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
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadRepos),
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _logout),
        ],
      ),
      body: _loading
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
                        FilledButton(onPressed: _loadRepos, child: const Text('Thử lại')),
                      ],
                    ),
                  ),
                )
              : _repos.isEmpty
                  ? Center(
                      child: Text(
                        'Không tìm thấy repo nào.',
                        style: TextStyle(color: scheme.outline),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadRepos,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _repos.length,
                        itemBuilder: (context, index) {
                          final repo = _repos[index];
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
    );
  }
}
