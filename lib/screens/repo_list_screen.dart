import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/github_service.dart';
import '../services/pinned_repos_service.dart';
import '../l10n/strings.dart';
import 'browser_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import 'gists_screen.dart';
import 'pinned_search_screen.dart';
import '../services/ci_watch_service.dart';

/// Cache đơn giản trong bộ nhớ, tồn tại trong suốt phiên chạy app.
class _RepoCache {
  static List<GithubRepo>? repos;
}

/// 1 dòng trong danh sách đã nhóm: hoặc là tiêu đề nhóm (headerLabel != null),
/// hoặc là 1 repo cụ thể (repo != null) - không bao giờ cả 2 cùng lúc.
class _RepoRow {
  final String? headerLabel;
  final GithubRepo? repo;
  _RepoRow.header(this.headerLabel) : repo = null;
  _RepoRow.item(this.repo) : headerLabel = null;
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
  int _unreadCount = 0;

  // "" đại diện cho "Tất cả" (không lọc theo owner). Mặc định lọc riêng theo
  // TÀI KHOẢN CÁ NHÂN ngay khi mở màn hình - trước đây danh sách luôn gộp
  // chung repo tổ chức/repo chỉ là collaborator lẫn với repo của riêng mình
  // (API gọi affiliation: owner,collaborator,organization_member), khiến danh
  // sách vừa dài vừa khó phân biệt đâu là repo của mình.
  static const _kAllOwners = '';
  String _selectedOwner = _kAllOwners;

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
    _selectedOwner = username ?? _kAllOwners;
    _pinned = await _pinnedService.getPinned();
    _loadUnreadCount(); // chạy ngầm, không chặn danh sách repo hiện chính

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

  /// Danh sách các owner (tài khoản cá nhân + mọi tổ chức) đang có repo, tài
  /// khoản cá nhân của người dùng luôn xếp lên đầu.
  List<String> _availableOwners() {
    final owners = _allRepos.map((r) => r.owner).toSet().toList()
      ..sort((a, b) {
        if (a == _username) return -1;
        if (b == _username) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return owners;
  }

  Map<String, int> _ownerCounts() {
    final counts = <String, int>{};
    for (final r in _allRepos) {
      counts[r.owner] = (counts[r.owner] ?? 0) + 1;
    }
    return counts;
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    final base = _allRepos.where((r) {
      // Repo đã ghim luôn hiện bất kể đang lọc theo owner nào - ghim là lối tắt
      // người dùng chủ động chọn, không nên bị bộ lọc owner che mất.
      final matchesOwner =
          _selectedOwner == _kAllOwners || r.owner == _selectedOwner || _pinned.contains(r.fullName);
      final matchesQuery = query.isEmpty || r.fullName.toLowerCase().contains(query);
      return matchesOwner && matchesQuery;
    }).toList();
    setState(() => _filteredRepos = _sortWithPinnedFirst(base));
  }

  Future<void> _togglePin(GithubRepo repo) async {
    final updated = await _pinnedService.togglePin(repo.fullName);
    setState(() {
      _pinned = updated;
      _applyFilter();
    });
    CiWatchService.instance.syncWatchedReposIfEnabled(); // repo ghim đổi -> cập nhật luôn danh sách đang theo dõi CI (nếu đang bật)
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

  void _openGists() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => GistsScreen(githubService: _githubService!)));
  }

  void _openPinnedSearch() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PinnedSearchScreen(githubService: _githubService!)));
  }

  /// Mở dialog tạo repo mới cho tài khoản cá nhân, rồi mở luôn repo vừa tạo
  /// trong BrowserScreen.
  Future<void> _showCreateRepoDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool private = true;
    // "" = không thêm file mẫu.
    String gitignoreTemplate = '';
    String licenseTemplate = '';

    const gitignoreOptions = {
      '': null,
      'Dart': 'Dart',
      'Flutter': 'Dart', // GitHub chưa có template riêng "Flutter", dùng chung "Dart"
      'Node': 'Node',
      'Python': 'Python',
      'Java': 'Java',
      'Go': 'Go',
      'Rust': 'Rust',
    };
    const licenseOptions = {
      '': null,
      'MIT': 'mit',
      'Apache 2.0': 'apache-2.0',
      'GPL 3.0': 'gpl-3.0',
      'BSD 3-Clause': 'bsd-3-clause',
      'Unlicense': 'unlicense',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t('repolist.create_repo_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: t('repolist.repo_name_label'), border: const OutlineInputBorder()),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(labelText: t('repolist.repo_desc_label'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('repolist.repo_private_label')),
                  value: private,
                  onChanged: (v) => setDialogState(() => private = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: gitignoreTemplate,
                  decoration: InputDecoration(labelText: t('repolist.gitignore_label'), border: const OutlineInputBorder()),
                  items: gitignoreOptions.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k.isEmpty ? t('repolist.template_none') : k)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => gitignoreTemplate = v ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: licenseTemplate,
                  decoration: InputDecoration(labelText: t('repolist.license_label'), border: const OutlineInputBorder()),
                  items: licenseOptions.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k.isEmpty ? t('repolist.template_none') : k)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => licenseTemplate = v ?? ''),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('repolist.create_repo_button'))),
          ],
        ),
      ),
    );

    final name = nameController.text.trim();
    if (confirmed != true || name.isEmpty || !mounted) return;

    try {
      final repo = await _githubService!.createRepo(name, description: descController.text.trim(), private: private);

      // Thêm file .gitignore/LICENSE mẫu (nếu có chọn) - làm SAU khi tạo repo
      // xong vì cần repo tồn tại trước mới upload file vào được. Lỗi ở bước
      // này (hiếm khi xảy ra) không chặn việc mở repo vừa tạo, chỉ bỏ qua.
      final gitignoreKey = gitignoreOptions[gitignoreTemplate];
      if (gitignoreKey != null) {
        try {
          final content = await _githubService!.getGitignoreTemplate(gitignoreKey);
          await _githubService!.uploadNewFile(repo.owner, repo.name, '.gitignore', utf8.encode(content), commitMessage: 'Add .gitignore');
        } catch (_) {}
      }
      final licenseKey = licenseOptions[licenseTemplate];
      if (licenseKey != null) {
        try {
          final content = await _githubService!.getLicenseTemplate(licenseKey);
          await _githubService!.uploadNewFile(repo.owner, repo.name, 'LICENSE', utf8.encode(content), commitMessage: 'Add LICENSE');
        } catch (_) {}
      }

      if (mounted) {
        _RepoCache.repos = null; // ép danh sách repo tải lại từ đầu ở lần quay về màn này
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BrowserScreen(initialOwner: repo.owner, initialRepo: repo.name)),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  /// Chỉ dùng để hiện số badge trên icon chuông - lỗi ở đây (vd token cũ chưa
  /// có scope 'notifications') bỏ qua âm thầm, màn Notifications sẽ tự báo lỗi
  /// rõ ràng hơn khi user thực sự mở vào.
  Future<void> _loadUnreadCount() async {
    try {
      final notifs = await _githubService!.listNotifications();
      if (mounted) setState(() => _unreadCount = notifs.length);
    } catch (_) {
      // im lặng bỏ qua, không làm phiền màn hình chính
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(githubService: _githubService!)));
    _loadUnreadCount(); // cập nhật lại badge sau khi quay về (có thể vừa đọc/đánh dấu bớt)
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

  /// Hàng chip lọc theo chủ sở hữu (Của tôi / Tất cả / từng tổ chức) - tự ẩn
  /// nếu tất cả repo đều cùng 1 owner (không có gì để lọc).
  Widget _buildOwnerFilterRow(ColorScheme scheme) {
    final owners = _availableOwners();
    if (owners.length <= 1) return const SizedBox.shrink();
    final counts = _ownerCounts();

    Widget chip(String key, String label, int count) {
      final selected = _selectedOwner == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text('$label ($count)'),
          selected: selected,
          onSelected: (_) => setState(() {
            _selectedOwner = key;
            _applyFilter();
          }),
        ),
      );
    }

    // Thứ tự: Của tôi -> Tất cả -> các tổ chức khác (A-Z). Đặt "Tất cả" ngay
    // vị trí 2 để luôn trong tầm tay dù bạn ở trong nhiều tổ chức (nếu để cuối
    // cùng, hàng chip dài sẽ đẩy nó ra ngoài màn hình).
    final others = owners.where((o) => o != _username).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (_username != null) chip(_username!, t('repolist.filter_mine'), counts[_username] ?? 0),
            chip(_kAllOwners, t('repolist.filter_all'), _allRepos.length),
            for (final owner in others) chip(owner, owner, counts[owner] ?? 0),
          ],
        ),
      ),
    );
  }

  /// Chỉ nhóm khi đang xem "Tất cả" VÀ không tìm kiếm - nếu đã chọn riêng 1
  /// owner qua chip thì mọi repo hiện ra vốn đã cùng 1 nhóm rồi, thêm tiêu đề
  /// lúc đó chỉ thừa; lúc đang tìm kiếm thì ưu tiên thấy ngay kết quả, khỏi
  /// phải dò qua từng nhóm.
  bool get _shouldGroupByOwner => _selectedOwner == _kAllOwners && _searchController.text.trim().isEmpty;

  /// Gộp _filteredRepos thành danh sách phẳng gồm tiêu đề + repo, để
  /// ListView.builder render đơn giản (không cần widget nhóm lồng nhau).
  /// Thứ tự: "Đã ghim" trước tiên (nếu có), rồi tới từng owner (mình lên đầu,
  /// còn lại A-Z).
  List<_RepoRow> _buildGroupedRows() {
    final rows = <_RepoRow>[];
    final pinnedRepos = _filteredRepos.where((r) => _pinned.contains(r.fullName)).toList();
    final rest = _filteredRepos.where((r) => !_pinned.contains(r.fullName)).toList();

    if (pinnedRepos.isNotEmpty) {
      rows.add(_RepoRow.header('${t('repolist.section_pinned')} (${pinnedRepos.length})'));
      rows.addAll(pinnedRepos.map((r) => _RepoRow.item(r)));
    }

    final byOwner = <String, List<GithubRepo>>{};
    for (final r in rest) {
      byOwner.putIfAbsent(r.owner, () => []).add(r);
    }
    final owners = byOwner.keys.toList()
      ..sort((a, b) {
        if (a == _username) return -1;
        if (b == _username) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    for (final owner in owners) {
      final items = byOwner[owner]!;
      final label = owner == _username ? t('repolist.filter_mine') : owner;
      rows.add(_RepoRow.header('$label (${items.length})'));
      rows.addAll(items.map((r) => _RepoRow.item(r)));
    }
    return rows;
  }

  Widget _buildSectionHeader(String label, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.outline, fontSize: 12.5, letterSpacing: 0.3),
      ),
    );
  }

  /// Card hiển thị 1 repo - tách riêng thành hàm dùng chung cho cả chế độ
  /// danh sách phẳng lẫn danh sách đã nhóm theo owner, tránh lặp code.
  Widget _buildRepoCard(GithubRepo repo, ColorScheme scheme) {
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
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_username != null ? t('repolist.title_named', {'username': _username!}) : t('repolist.title_generic')),
        actions: [
          Badge(
            label: Text('$_unreadCount'),
            isLabelVisible: _unreadCount > 0,
            child: IconButton(icon: const Icon(Icons.notifications_rounded), tooltip: t('notif.tooltip'), onPressed: _openNotifications),
          ),
          IconButton(icon: const Icon(Icons.edit_rounded), tooltip: t('repolist.manual_entry_tooltip'), onPressed: _openManualEntry),
          IconButton(icon: const Icon(Icons.manage_search_rounded), tooltip: t('pinnedsearch.tooltip'), onPressed: _openPinnedSearch),
          IconButton(icon: const Icon(Icons.code_rounded), tooltip: t('repolist.gists_tooltip'), onPressed: _openGists),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => _loadRepos()),
          IconButton(icon: const Icon(Icons.settings_rounded), tooltip: t('repolist.settings_tooltip'), onPressed: _openSettings),
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _logout),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateRepoDialog,
        icon: const Icon(Icons.add_rounded),
        label: Text(t('repolist.create_repo_button')),
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
          _buildOwnerFilterRow(scheme),
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
                            child: _shouldGroupByOwner
                                ? Builder(builder: (context) {
                                    final rows = _buildGroupedRows();
                                    return ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      itemCount: rows.length,
                                      itemBuilder: (context, index) {
                                        final row = rows[index];
                                        return row.headerLabel != null
                                            ? _buildSectionHeader(row.headerLabel!, scheme)
                                            : _buildRepoCard(row.repo!, scheme);
                                      },
                                    );
                                  })
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    itemCount: _filteredRepos.length,
                                    itemBuilder: (context, index) => _buildRepoCard(_filteredRepos[index], scheme),
                                  ),
                          ),
          ),
        ],
      ),
    );
  }
}
