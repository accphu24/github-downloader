import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../utils/time_ago.dart';
import '../l10n/strings.dart';
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
      return (icon: Icons.autorenew_rounded, color: Colors.orange, label: t('actions.status_running'));
    }
    switch (run.conclusion) {
      case 'success':
        return (icon: Icons.check_circle_rounded, color: Colors.green, label: t('actions.status_success'));
      case 'failure':
        return (icon: Icons.cancel_rounded, color: Colors.red, label: t('actions.status_failure'));
      case 'cancelled':
        return (icon: Icons.block_rounded, color: Colors.grey, label: t('actions.status_cancelled'));
      default:
        return (icon: Icons.help_outline_rounded, color: Colors.grey, label: run.conclusion ?? t('actions.status_unknown'));
    }
  }

  /// Mở khay chọn workflow + branch để kích hoạt chạy 1 workflow thủ công
  /// (chỉ hoạt động với workflow có khai báo trigger `workflow_dispatch`).
  Future<void> _showDispatchSheet() async {
    List<GithubWorkflow> workflows;
    List<String> branches;
    try {
      final results = await Future.wait([
        widget.githubService.listWorkflows(widget.owner, widget.repo),
        widget.githubService.listBranches(widget.owner, widget.repo),
      ]);
      workflows = results[0] as List<GithubWorkflow>;
      branches = results[1] as List<String>;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      return;
    }

    final activeWorkflows = workflows.where((w) => w.state == 'active').toList();
    if (activeWorkflows.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('actions.no_dispatchable_workflow'))));
      return;
    }
    if (!mounted) return;

    GithubWorkflow selectedWorkflow = activeWorkflows.first;
    String selectedBranch = branches.isNotEmpty ? branches.first : 'main';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('actions.run_workflow_title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 16),
              DropdownButtonFormField<GithubWorkflow>(
                value: selectedWorkflow,
                decoration: InputDecoration(labelText: t('actions.workflow_label'), border: const OutlineInputBorder()),
                items: activeWorkflows
                    .map((w) => DropdownMenuItem(value: w, child: Text(w.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (w) => setSheetState(() => selectedWorkflow = w ?? selectedWorkflow),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedBranch,
                decoration: InputDecoration(labelText: t('actions.branch_label'), border: const OutlineInputBorder()),
                items: branches.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (b) => setSheetState(() => selectedBranch = b ?? selectedBranch),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(t('actions.run_workflow_button')),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await widget.githubService.dispatchWorkflow(widget.owner, widget.repo, selectedWorkflow.id, ref: selectedBranch);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('actions.dispatch_success'))));
      // GitHub cần vài giây để tạo run mới trong danh sách, đợi rồi mới refresh.
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(t('actions.title', {'owner': widget.owner, 'repo': widget.repo}))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showDispatchSheet,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(t('actions.run_workflow_button')),
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
              : _runs.isEmpty
                  ? Center(child: Text(t('actions.empty'), style: TextStyle(color: scheme.outline)))
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
                                tooltip: t('actions.open_browser_tooltip'),
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
