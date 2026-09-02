import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../services/download_manager.dart';
import '../services/downloads_service.dart';
import '../utils/time_ago.dart';
import '../l10n/strings.dart';
import '../widgets/top_notification.dart';
import '../main.dart' show navigatorKey;

/// Xem/tạo/xoá release của repo, tải asset đính kèm. Khác với Actions
/// artifact (tồn tại tạm 90 ngày) - release + asset tồn tại vĩnh viễn cho tới
/// khi xoá thủ công, dùng để phát hành bản chính thức (vd file APK build sẵn).
class ReleasesScreen extends StatefulWidget {
  final String owner;
  final String repo;
  final String defaultBranch;
  final GithubService githubService;

  const ReleasesScreen({
    super.key,
    required this.owner,
    required this.repo,
    required this.defaultBranch,
    required this.githubService,
  });

  @override
  State<ReleasesScreen> createState() => _ReleasesScreenState();
}

class _ReleasesScreenState extends State<ReleasesScreen> {
  List<GithubRelease> _releases = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final releases = await widget.githubService.listReleases(widget.owner, widget.repo);
      setState(() => _releases = releases);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showCreateReleaseDialog() async {
    final tagController = TextEditingController();
    final nameController = TextEditingController();
    final bodyController = TextEditingController();
    bool draft = false;
    bool prerelease = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t('releases.create_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tagController,
                  decoration: InputDecoration(labelText: t('releases.tag_label'), hintText: 'v1.0.0', border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: t('releases.name_label'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  decoration: InputDecoration(labelText: t('releases.notes_label'), border: const OutlineInputBorder()),
                  maxLines: 4,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('releases.prerelease_label')),
                  value: prerelease,
                  onChanged: (v) => setDialogState(() => prerelease = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('releases.draft_label')),
                  value: draft,
                  onChanged: (v) => setDialogState(() => draft = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('releases.create_button'))),
          ],
        ),
      ),
    );

    final tag = tagController.text.trim();
    if (confirmed != true || tag.isEmpty || !mounted) return;

    try {
      await widget.githubService.createRelease(
        widget.owner,
        widget.repo,
        tagName: tag,
        name: nameController.text.trim(),
        body: bodyController.text,
        draft: draft,
        prerelease: prerelease,
        targetCommitish: widget.defaultBranch,
      );
      if (mounted) showTopNotification(context, t('releases.create_success'));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmDeleteRelease(GithubRelease release) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('releases.delete_confirm', {'name': release.name})),
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
      await widget.githubService.deleteRelease(widget.owner, widget.repo, release.id);
      if (mounted) showTopNotification(context, t('releases.delete_success'));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _downloadAsset(ReleaseAsset asset) {
    DownloadManager.instance.runDownload(
      label: asset.name,
      navigatorKey: navigatorKey,
      fetch: (onProgress) => widget.githubService.downloadReleaseAsset(widget.owner, widget.repo, asset.id),
      save: (bytes) => DownloadsService.saveBytes(asset.name, bytes),
      onSuccess: (ctx, savedPath) => showTopNotification(ctx, t('common.saved_at', {'path': savedPath})),
      onError: (ctx, error) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(error))),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(t('releases.title', {'owner': widget.owner, 'repo': widget.repo}))),
      floatingActionButton: FloatingActionButton(onPressed: _showCreateReleaseDialog, child: const Icon(Icons.add_rounded)),
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
              : _releases.isEmpty
                  ? Center(child: Text(t('releases.empty'), style: TextStyle(color: scheme.outline)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _releases.length,
                        itemBuilder: (context, index) {
                          final release = _releases[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            child: ExpansionTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              leading: Icon(release.draft ? Icons.edit_note_rounded : Icons.sell_rounded),
                              title: Text(release.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                [
                                  release.tagName,
                                  if (release.draft) t('releases.badge_draft'),
                                  if (release.prerelease) t('releases.badge_prerelease'),
                                  if (release.publishedAt != null) timeAgo(release.publishedAt!),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              children: [
                                if (release.body != null && release.body!.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Align(alignment: Alignment.centerLeft, child: Text(release.body!)),
                                  ),
                                ...release.assets.map(
                                  (asset) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.attachment_rounded, size: 20),
                                    title: Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(_formatSize(asset.size)),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.download_rounded),
                                      onPressed: () => _downloadAsset(asset),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => launchUrl(Uri.parse(release.htmlUrl), mode: LaunchMode.externalApplication),
                                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                        label: Text(t('actions.open_browser_tooltip')),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _confirmDeleteRelease(release),
                                        style: TextButton.styleFrom(foregroundColor: scheme.error),
                                        icon: const Icon(Icons.delete_rounded, size: 18),
                                        label: Text(t('admin.remove_button')),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
