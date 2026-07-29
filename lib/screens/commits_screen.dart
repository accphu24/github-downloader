import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../utils/time_ago.dart';

class CommitsScreen extends StatefulWidget {
  final String owner;
  final String repo;
  final GithubService githubService;

  const CommitsScreen({super.key, required this.owner, required this.repo, required this.githubService});

  @override
  State<CommitsScreen> createState() => _CommitsScreenState();
}

class _CommitsScreenState extends State<CommitsScreen> {
  List<GithubCommit> _commits = [];
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
      final commits = await widget.githubService.listCommits(widget.owner, widget.repo);
      setState(() => _commits = commits);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Commits · ${widget.owner}/${widget.repo}')),
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
                        FilledButton(onPressed: _load, child: const Text('Thử lại')),
                      ],
                    ),
                  ),
                )
              : _commits.isEmpty
                  ? Center(child: Text('Repo này chưa có commit nào.', style: TextStyle(color: scheme.outline)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _commits.length,
                        itemBuilder: (context, index) {
                          final commit = _commits[index];
                          final firstLine = commit.message.split('\n').first;
                          final shortSha = commit.sha.length >= 7 ? commit.sha.substring(0, 7) : commit.sha;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            child: ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              leading: CircleAvatar(
                                backgroundColor: scheme.tertiaryContainer,
                                child: Icon(Icons.commit_rounded, size: 18, color: scheme.onTertiaryContainer),
                              ),
                              title: Text(firstLine, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text('$shortSha · ${commit.authorName} · ${timeAgo(commit.date)}'),
                              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                              onTap: () {
                                if (commit.htmlUrl.isNotEmpty) {
                                  launchUrl(Uri.parse(commit.htmlUrl), mode: LaunchMode.externalApplication);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
