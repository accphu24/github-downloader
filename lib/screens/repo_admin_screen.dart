import 'package:flutter/material.dart';
import '../services/github_service.dart';
import '../l10n/strings.dart';
import '../widgets/top_notification.dart';

/// Màn hình quản lý phần "admin" của repo: ai có quyền truy cập (collaborators)
/// và webhook đang cấu hình. Chỉ nên điều hướng tới màn này khi
/// GithubRepo.canAdmin == true, vì mọi API ở đây đều cần quyền admin trên repo.
class RepoAdminScreen extends StatefulWidget {
  final String owner;
  final String repo;
  final GithubService githubService;

  const RepoAdminScreen({super.key, required this.owner, required this.repo, required this.githubService});

  @override
  State<RepoAdminScreen> createState() => _RepoAdminScreenState();
}

class _RepoAdminScreenState extends State<RepoAdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<Collaborator> _collaborators = [];
  List<GithubWebhook> _webhooks = [];
  bool _loading = true;
  String? _error;

  static const _permissions = ['pull', 'triage', 'push', 'maintain', 'admin'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.githubService.listCollaborators(widget.owner, widget.repo),
        widget.githubService.listWebhooks(widget.owner, widget.repo),
      ]);
      setState(() {
        _collaborators = results[0] as List<Collaborator>;
        _webhooks = results[1] as List<GithubWebhook>;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // ---------------- Collaborators ----------------

  Future<void> _showAddCollaboratorDialog() async {
    final controller = TextEditingController();
    String permission = 'push';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t('admin.add_collaborator_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(labelText: t('admin.username_label'), border: const OutlineInputBorder()),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: permission,
                decoration: InputDecoration(labelText: t('admin.permission_label'), border: const OutlineInputBorder()),
                items: _permissions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) => setDialogState(() => permission = v ?? permission),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('admin.add_button'))),
          ],
        ),
      ),
    );

    final username = controller.text.trim();
    if (result != true || username.isEmpty || !mounted) return;

    try {
      await widget.githubService.addCollaborator(widget.owner, widget.repo, username, permission: permission);
      if (mounted) showTopNotification(context, t('admin.add_collaborator_success', {'username': username}));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmRemoveCollaborator(Collaborator c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('admin.remove_collaborator_confirm', {'username': c.login})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('admin.remove_button')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.githubService.removeCollaborator(widget.owner, widget.repo, c.login);
      if (mounted) showTopNotification(context, t('admin.remove_collaborator_success', {'username': c.login}));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // ---------------- Webhooks ----------------

  Future<void> _showAddWebhookDialog() async {
    final urlController = TextEditingController();
    final secretController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('admin.add_webhook_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: InputDecoration(labelText: t('admin.webhook_url_label'), border: const OutlineInputBorder()),
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secretController,
              decoration: InputDecoration(labelText: t('admin.webhook_secret_label'), border: const OutlineInputBorder()),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('admin.add_button'))),
        ],
      ),
    );

    final url = urlController.text.trim();
    if (result != true || url.isEmpty || !mounted) return;

    try {
      await widget.githubService.createWebhook(widget.owner, widget.repo, url, secret: secretController.text.trim());
      if (mounted) showTopNotification(context, t('admin.add_webhook_success'));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggleWebhook(GithubWebhook hook) async {
    try {
      await widget.githubService.toggleWebhookActive(widget.owner, widget.repo, hook.id, !hook.active);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmDeleteWebhook(GithubWebhook hook) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('admin.delete_webhook_confirm')),
        content: Text(hook.url, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('admin.remove_button')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.githubService.deleteWebhook(widget.owner, widget.repo, hook.id);
      if (mounted) showTopNotification(context, t('admin.delete_webhook_success'));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('admin.title', {'owner': widget.owner, 'repo': widget.repo})),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t('admin.tab_collaborators')),
            Tab(text: t('admin.tab_webhooks')),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _tabController.index == 0 ? _showAddCollaboratorDialog() : _showAddWebhookDialog(),
        child: const Icon(Icons.add_rounded),
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
                        FilledButton(onPressed: _load, child: Text(t('common.retry'))),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // ---- Tab collaborators ----
                    _collaborators.isEmpty
                        ? Center(child: Text(t('admin.no_collaborators'), style: TextStyle(color: scheme.outline)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: _collaborators.length,
                              itemBuilder: (context, index) {
                                final c = _collaborators[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    leading: CircleAvatar(backgroundImage: NetworkImage(c.avatarUrl)),
                                    title: Text(c.login, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(c.permission),
                                    trailing: IconButton(
                                      icon: Icon(Icons.person_remove_rounded, color: scheme.error),
                                      tooltip: t('admin.remove_button'),
                                      onPressed: () => _confirmRemoveCollaborator(c),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                    // ---- Tab webhooks ----
                    _webhooks.isEmpty
                        ? Center(child: Text(t('admin.no_webhooks'), style: TextStyle(color: scheme.outline)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: _webhooks.length,
                              itemBuilder: (context, index) {
                                final hook = _webhooks[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    leading: Icon(
                                      Icons.webhook_rounded,
                                      color: hook.active ? scheme.primary : scheme.outline,
                                    ),
                                    title: Text(hook.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(hook.events.join(', ')),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Switch(value: hook.active, onChanged: (_) => _toggleWebhook(hook)),
                                        IconButton(
                                          icon: Icon(Icons.delete_rounded, color: scheme.error),
                                          onPressed: () => _confirmDeleteWebhook(hook),
                                        ),
                                      ],
                                    ),
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
