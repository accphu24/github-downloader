import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../services/auth_service.dart';
import '../utils/time_ago.dart';
import '../l10n/strings.dart';
import 'login_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final GithubService githubService;

  const NotificationsScreen({super.key, required this.githubService});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _knownReasons = {
    'mention', 'review_requested', 'assign', 'author', 'comment',
    'ci_activity', 'state_change', 'subscribed', 'security_alert',
    'team_mention', 'invitation', 'manual', 'your_activity',
  };

  List<GithubNotification> _notifications = [];
  bool _loading = true;
  String? _error;
  bool _scopeIssue = false;
  bool _showUnreadOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _scopeIssue = false;
    });
    try {
      final notifs = await widget.githubService.listNotifications(all: !_showUnreadOnly);
      setState(() => _notifications = notifs);
    } on GithubUnauthorizedException {
      await AuthService().logout();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('login.session_expired'))));
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _scopeIssue = _error!.contains('404');
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  void _setFilter(bool unreadOnly) {
    if (_showUnreadOnly == unreadOnly) return;
    setState(() => _showUnreadOnly = unreadOnly);
    _load();
  }

  Future<void> _openNotification(GithubNotification n) async {
    if (n.unread) {
      widget.githubService.markNotificationRead(n.id).catchError((_) {});
      setState(() {
        n.unread = false;
        if (_showUnreadOnly) _notifications.remove(n);
      });
    }
    final ok = await launchUrl(Uri.parse(n.webUrl), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('notif.open_error'))));
    }
  }

  Future<void> _confirmMarkAllRead() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(t('notif.mark_all_read_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('notif.mark_all_read'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.githubService.markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        if (_showUnreadOnly) {
          // Đang lọc "Chưa đọc": không còn gì chưa đọc nữa nên danh sách rỗng là đúng.
          _notifications.clear();
        } else {
          // Đang lọc "Tất cả": thông báo vẫn còn đó, chỉ chuyển trạng thái sang đã
          // đọc - trước đây luôn xoá sạch danh sách khiến tab "Tất cả" trống oan dù
          // vẫn còn thông báo (nay đã đọc) đáng lẽ phải tiếp tục hiển thị.
          for (final n in _notifications) {
            n.unread = false;
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('notif.mark_all_read_done'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _reloginForScope() async {
    await AuthService().logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  String _reasonLabel(String reason) {
    return _knownReasons.contains(reason) ? t('notif.reason.$reason') : t('notif.reason.default');
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'Issue':
        return Icons.error_outline_rounded;
      case 'PullRequest':
        return Icons.merge_type_rounded;
      case 'Commit':
        return Icons.commit_rounded;
      case 'Release':
        return Icons.new_releases_rounded;
      case 'Discussion':
        return Icons.forum_rounded;
      case 'CheckSuite':
      case 'WorkflowRun':
        return Icons.play_circle_outline_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('notif.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: t('notif.mark_all_read'),
            onPressed: _notifications.isEmpty ? null : _confirmMarkAllRead,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(t('notif.filter_unread')),
                  selected: _showUnreadOnly,
                  onSelected: (_) => _setFilter(true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(t('notif.filter_all')),
                  selected: !_showUnreadOnly,
                  onSelected: (_) => _setFilter(false),
                ),
              ],
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
                              Text(
                                _scopeIssue ? t('notif.scope_missing') : _error!,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              if (_scopeIssue)
                                FilledButton(onPressed: _reloginForScope, child: Text(t('notif.relogin_button')))
                              else
                                FilledButton(onPressed: _load, child: Text(t('common.retry'))),
                            ],
                          ),
                        ),
                      )
                    : _notifications.isEmpty
                        ? Center(
                            child: Text(
                              _showUnreadOnly ? t('notif.empty_unread') : t('notif.empty_all'),
                              style: TextStyle(color: scheme.outline),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: _notifications.length,
                              itemBuilder: (context, index) {
                                final n = _notifications[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  color: n.unread
                                      ? scheme.primaryContainer.withValues(alpha: 0.35)
                                      : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    leading: CircleAvatar(
                                      backgroundColor: scheme.tertiaryContainer,
                                      child: Icon(_iconForType(n.subjectType), size: 18, color: scheme.onTertiaryContainer),
                                    ),
                                    title: Text(
                                      n.subjectTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: n.unread ? FontWeight.w700 : FontWeight.normal),
                                    ),
                                    subtitle: Text('${n.repoFullName} · ${_reasonLabel(n.reason)} · ${timeAgo(n.updatedAt)}'),
                                    trailing: n.unread
                                        ? Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                                          )
                                        : const Icon(Icons.open_in_new_rounded, size: 18),
                                    onTap: () => _openNotification(n),
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
