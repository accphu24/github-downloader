import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../l10n/strings.dart';

/// Xem hồ sơ công khai của 1 tài khoản GitHub (khác với tài khoản đang đăng
/// nhập), kèm nút theo dõi/bỏ theo dõi. Cần token có scope `user:follow` để
/// nút theo dõi hoạt động - nếu chưa có, GitHub trả 403 và app sẽ báo rõ cần
/// đăng nhập lại.
class UserProfileScreen extends StatefulWidget {
  final String username;
  final GithubService githubService;

  const UserProfileScreen({super.key, required this.username, required this.githubService});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  GithubUserProfile? _profile;
  bool _isFollowing = false;
  bool _loading = true;
  bool _followBusy = false;
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
      final results = await Future.wait([
        widget.githubService.getUserProfile(widget.username),
        widget.githubService.isFollowing(widget.username),
      ]);
      setState(() {
        _profile = results[0] as GithubUserProfile;
        _isFollowing = results[1] as bool;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _followBusy = true);
    try {
      if (_isFollowing) {
        await widget.githubService.unfollowUser(widget.username);
      } else {
        await widget.githubService.followUser(widget.username);
      }
      if (mounted) setState(() => _isFollowing = !_isFollowing);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.username)),
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
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: CircleAvatar(radius: 44, backgroundImage: NetworkImage(_profile!.avatarUrl)),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _profile!.name ?? _profile!.login,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                      ),
                    ),
                    Center(
                      child: Text('@${_profile!.login}', style: TextStyle(color: scheme.outline)),
                    ),
                    if (_profile!.bio != null && _profile!.bio!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_profile!.bio!, textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatChip(label: t('profile.repos'), value: _profile!.publicRepos),
                        const SizedBox(width: 12),
                        _StatChip(label: t('profile.followers'), value: _profile!.followers),
                        const SizedBox(width: 12),
                        _StatChip(label: t('profile.following'), value: _profile!.following),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _followBusy ? null : _toggleFollow,
                      icon: Icon(_isFollowing ? Icons.person_remove_rounded : Icons.person_add_rounded),
                      label: Text(_isFollowing ? t('profile.unfollow') : t('profile.follow')),
                      style: _isFollowing
                          ? FilledButton.styleFrom(backgroundColor: scheme.surfaceContainerHighest, foregroundColor: scheme.onSurface)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(_profile!.htmlUrl), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(t('profile.open_on_github')),
                    ),
                  ],
                ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(label, style: TextStyle(fontSize: 12, color: scheme.outline)),
        ],
      ),
    );
  }
}
