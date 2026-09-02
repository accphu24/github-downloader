import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../utils/time_ago.dart';
import '../l10n/strings.dart';
import '../widgets/top_notification.dart';
import 'user_profile_screen.dart';

/// Quản lý gist của tài khoản đang đăng nhập, kèm ô tìm kiếm nhanh để mở hồ
/// sơ (và theo dõi) 1 tài khoản GitHub bất kỳ theo username.
class GistsScreen extends StatefulWidget {
  final GithubService githubService;

  const GistsScreen({super.key, required this.githubService});

  @override
  State<GistsScreen> createState() => _GistsScreenState();
}

class _GistsScreenState extends State<GistsScreen> {
  final _profileSearchController = TextEditingController();
  List<GithubGist> _gists = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _profileSearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gists = await widget.githubService.listMyGists();
      setState(() => _gists = gists);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openProfileSearch() {
    final username = _profileSearchController.text.trim();
    if (username.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfileScreen(username: username, githubService: widget.githubService)),
    );
    _profileSearchController.clear();
  }

  Future<void> _showCreateGistDialog() async {
    final fileNameController = TextEditingController(text: 'file.txt');
    final contentController = TextEditingController();
    final descController = TextEditingController();
    bool public = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t('gists.create_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fileNameController,
                  decoration: InputDecoration(labelText: t('gists.filename_label'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(labelText: t('gists.description_label'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  decoration: InputDecoration(labelText: t('gists.content_label'), border: const OutlineInputBorder()),
                  maxLines: 6,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('gists.public_label')),
                  value: public,
                  onChanged: (v) => setDialogState(() => public = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('gists.create_button'))),
          ],
        ),
      ),
    );

    final fileName = fileNameController.text.trim();
    final content = contentController.text;
    if (confirmed != true || fileName.isEmpty || content.isEmpty || !mounted) return;

    try {
      await widget.githubService.createGist(
        {fileName: content},
        description: descController.text.trim(),
        public: public,
      );
      if (mounted) showTopNotification(context, t('gists.create_success'));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmDeleteGist(GithubGist gist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('gists.delete_confirm')),
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
      await widget.githubService.deleteGist(gist.id);
      if (mounted) showTopNotification(context, t('gists.delete_success'));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(t('gists.title'))),
      floatingActionButton: FloatingActionButton(onPressed: _showCreateGistDialog, child: const Icon(Icons.add_rounded)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _profileSearchController,
              decoration: InputDecoration(
                hintText: t('gists.find_profile_hint'),
                prefixIcon: const Icon(Icons.person_search_rounded),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _openProfileSearch),
              ),
              onSubmitted: (_) => _openProfileSearch(),
            ),
          ),
          const Divider(height: 1),
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
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: _load, child: Text(t('common.retry'))),
                            ],
                          ),
                        ),
                      )
                    : _gists.isEmpty
                        ? Center(child: Text(t('gists.empty'), style: TextStyle(color: scheme.outline)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: _gists.length,
                              itemBuilder: (context, index) {
                                final gist = _gists[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    leading: Icon(gist.public ? Icons.public_rounded : Icons.lock_rounded),
                                    title: Text(
                                      gist.description?.isNotEmpty == true ? gist.description! : gist.fileNames.join(', '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text('${gist.fileNames.join(', ')} · ${timeAgo(gist.updatedAt)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                          onPressed: () => launchUrl(Uri.parse(gist.htmlUrl), mode: LaunchMode.externalApplication),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete_rounded, size: 18, color: scheme.error),
                                          onPressed: () => _confirmDeleteGist(gist),
                                        ),
                                      ],
                                    ),
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
