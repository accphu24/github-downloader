import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../utils/time_ago.dart';
import 'run_detail_screen.dart';

class ActionsScreen extends StatefulWidget {
  final String owner;
  final String repo;
  final GithubService githubService;

  const ActionsScreen({super.key, required this.owner, required this.repo, required this.githubService});

  @override
  State<ActionsScreen> createState() => _ActionsScreenState();
}

class _ActionsScreenState extends State<ActionsScreen> {
  List<WorkflowRun> _runs = [];
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
      final runs = await widget.githubService.listWorkflowRuns(widget.owner, widget.repo);
      setState(() => _runs = runs);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  ({IconData icon, Color color, String label}) _statusInfo(WorkflowRun run) {
    if (run.status != 'completed') {
      return (icon: Icons.autorenew_rounded, color: Colors.orange, label: 'Đang chạy');
    }
    switch (run.conclusion) {
      case 'success':
        return (icon: Icons.check_circle_rounded, color: Colors.green, label: 'Thành công');
      case 'failure':
        return (icon: Icons.cancel_rounded, color: Colors.red, label: 'Thất bại');
      case 'cancelled':
        return (icon: Icons.block_rounded, color: Colors.grey, label: 'Đã huỷ');
      default:
        return (icon: Icons.help_outline_rounded, color: Colors.grey, label: run.conclusion ?? 'Không rõ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Actions · ${widget.owner}/${widget.repo}')),
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
              : _runs.isEmpty
                  ? Center(child: Text('Repo này chưa chạy workflow nào.', style: TextStyle(color: scheme.outline)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _runs.length,
                        itemBuilder: (context, index) {
                          final run = _runs[index];
                          final info = _statusInfo(run);
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            child: ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              leading: Icon(info.icon, color: info.color),
                              title: Text(run.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${info.label} · ${run.branch} · ${timeAgo(run.createdAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                tooltip: 'Mở trên trình duyệt',
                                onPressed: () {
                                  if (run.htmlUrl.isNotEmpty) {
                                    launchUrl(Uri.parse(run.htmlUrl), mode: LaunchMode.externalApplication);
                                  }
                                },
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RunDetailScreen(
                                    owner: widget.owner,
                                    repo: widget.repo,
                                    run: run,
                                    githubService: widget.githubService,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
