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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BrowserScreen()),
    );
  }

  Color _permissionColor(GithubRepo repo) {
    if (repo.canAdmin) return Colors.deepPurple;
    if (repo.canPush) return Colors.green;
    if (repo.canPull) return Colors.blueGrey;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_username != null ? 'Repo của $_username' : 'Repo của tôi'),
        actions: [
          IconButton(icon: const Icon(Icons.edit), tooltip: 'Nhập owner/repo thủ công', onPressed: _openManualEntry),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRepos),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
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
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadRepos, child: const Text('Thử lại')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRepos,
                  child: ListView.builder(
                    itemCount: _repos.length,
                    itemBuilder: (context, index) {
                      final repo = _repos[index];
                      return ListTile(
                        leading: Icon(repo.private ? Icons.lock : Icons.public),
                        title: Text(repo.fullName),
                        subtitle: repo.description != null && repo.description!.isNotEmpty
                            ? Text(repo.description!, maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        trailing: Chip(
                          label: Text(
                            repo.permissionLabel,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          backgroundColor: _permissionColor(repo),
                        ),
                        onTap: () => _openRepo(repo),
                      );
                    },
                  ),
                ),
    );
  }
}
