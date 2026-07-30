import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/github_service.dart';
import '../services/pinned_repos_service.dart';
import '../l10n/strings.dart';
import 'browser_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

/// Cache đơn giản trong bộ nhớ, tồn tại trong suốt phiên chạy app.
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
  final _pinnedService = PinnedReposService();
  final _searchController = TextEditingController();
  GithubService? _githubService;
  List<GithubRepo> _allRepos = [];
  List<GithubRepo> _filteredRepos = [];
  Set<String> _pinned = {};
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
    _pinned = await _pinnedService.getPinned();

    if (_RepoCache.repos != null) {
      setState(() {
        _allRepos = _RepoCache.repos!;
        _applyFilter();
        _loading = false;
      });
      _loadRepos(silent: true);
    } else {
      await _loadRepos();
    }
  }

  List<GithubRepo> _sortWithPinnedFirst(List<GithubRepo> repos) {
    final pinnedRepos = repos.where((r) => _pinned.contains(r.fullName)).toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    final rest = repos.where((r) => !_pinned.contains(r.fullName)).toList();
    return [...pinnedRepos, ...rest];
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    final base = query.isEmpty
        ? _allRepos
        : _allRepos.where((r) => r.fullName.toLowerCase().contains(query)).toList();
    setState(() => _filteredRepos = _sortWithPinnedFirst(base));
  }

  Future<void> _togglePin(GithubRepo repo) async {
    final updated = await _pinnedService.togglePin(repo.fullName);
    setState(() {
      _pinned = updated;
      _applyFilter();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('login.session_expired'))));
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

  void _openSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Color _permissionColor(BuildContext context, GithubRepo repo) {
    final scheme = Theme.of(context).colorScheme;
    if (repo.canAdmin) return scheme.primary;
    if (repo.canPush) return Colors.teal;
    if (repo.canPull) return scheme.outline;
    return Colors.grey;
  }

  String _permissionLabel(GithubRepo repo) {
    if (repo.canAdmin) return t('repolist.perm_admin');
    if (repo.canPush) return t('repolist.perm_write');
    if (repo.canPull) return t('repolist.perm_read');
    return t('repolist.perm_unknown');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_username != null ? t('repolist.title_named', {'username': _username!}) : t('repolist.title_generic')),
        actions: [
          IconButton(icon: const Icon(Icons.edit_rounded), tooltip: t('repolist.manual_entry_tooltip'), onPressed: _openManualEntry),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => _loadRepos()),
          IconButton(icon: const Icon(Icons.settings_rounded), tooltip: t('repolist.settings_tooltip'), onPressed: _openSettings),
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
                hintText: t('repolist.search_hint'),
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
                              FilledButton(onPressed: () => _loadRepos(), child: Text(t('common.retry'))),
                            ],
                          ),
                        ),
                      )
                    : _filteredRepos.isEmpty
                        ? Center(
                            child: Text(
                              _allRepos.isEmpty ? t('repolist.empty') : t('repolist.empty_filtered'),
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
                                final isPinned = _pinned.contains(repo.fullName);
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  color: isPinned
                                      ? scheme.primaryContainer.withValues(alpha: 0.35)
                                      : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
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
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Chip(
                                          label: Text(
                                            _permissionLabel(repo),
                                            style: const TextStyle(color: Colors.white, fontSize: 11),
                                          ),
                                          backgroundColor: _permissionColor(context, repo),
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            isPinned ? Icons.star_rounded : Icons.star_border_rounded,
                                            color: isPinned ? Colors.amber : scheme.outline,
                                          ),
                                          tooltip: isPinned ? t('repolist.unpin_tooltip') : t('repolist.pin_tooltip'),
                                          onPressed: () => _togglePin(repo),
                                        ),
                                      ],
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
