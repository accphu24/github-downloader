import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/github_service.dart';
import '../utils/time_ago.dart';

class RunDetailScreen extends StatefulWidget {
  final String owner;
  final String repo;
  final WorkflowRun run;
  final GithubService githubService;

  const RunDetailScreen({
    super.key,
    required this.owner,
    required this.repo,
    required this.run,
    required this.githubService,
  });

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  List<WorkflowJob> _jobs = [];
  List<Artifact> _artifacts = [];
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
      final results = await Future.wait([
        widget.githubService.listJobsForRun(widget.owner, widget.repo, widget.run.id),
        widget.githubService.listArtifacts(widget.owner, widget.repo, widget.run.id),
      ]);
      setState(() {
        _jobs = results[0] as List<WorkflowJob>;
        _artifacts = results[1] as List<Artifact>;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  ({IconData icon, Color color}) _statusIcon(String status, String? conclusion) {
    if (status != 'completed') return (icon: Icons.autorenew_rounded, color: Colors.orange);
    switch (conclusion) {
      case 'success':
        return (icon: Icons.check_circle_rounded, color: Colors.green);
      case 'failure':
        return (icon: Icons.cancel_rounded, color: Colors.red);
      case 'skipped':
        return (icon: Icons.remove_circle_outline_rounded, color: Colors.grey);
      case 'cancelled':
        return (icon: Icons.block_rounded, color: Colors.grey);
      default:
        return (icon: Icons.help_outline_rounded, color: Colors.grey);
    }
  }

  Future<void> _viewLog(WorkflowJob job) async {
    showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(content: SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))),
    );
    String? log;
    String? error;
    try {
      log = await widget.githubService.getJobLogs(widget.owner, widget.repo, job.id);
    } catch (e) {
      error = e.toString();
    }
    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    const maxChars = 15000;
    var displayLog = log!;
    final truncated = displayLog.length > maxChars;
    if (truncated) {
      displayLog = '... (đã cắt bớt phần đầu, tải file .txt để xem đầy đủ)\n\n${displayLog.substring(displayLog.length - maxChars)}';
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Log: ${job.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                    tooltip: 'Tải log .txt',
                    onPressed: () => _saveLogToFile(job.name, log!),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  displayLog,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.greenAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveLogToFile(String jobName, String log) async {
    final dir = await getExternalStorageDirectory();
    final safeName = jobName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final savePath = '${dir!.path}/log_$safeName.txt';
    await File(savePath).writeAsString(log);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu log: $savePath')));
    }
  }

  Future<void> _downloadArtifact(Artifact artifact) async {
    if (artifact.expired) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Artifact này đã hết hạn, không tải được nữa.')));
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: SizedBox(
          height: 60,
          child: Row(children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 16),
            Text('Đang tải artifact...'),
          ]),
        ),
      ),
    );

    try {
      final zipBytes = await widget.githubService.downloadArtifactZip(artifact.archiveDownloadUrl);
      final dir = await getExternalStorageDirectory();

      // GitHub luôn đóng gói artifact dạng .zip, kể cả khi bên trong chỉ có 1 file (vd: file .apk).
      // Tự giải nén ra để lấy trực tiếp file gốc (vd: app-release.apk) thay vì để lại dạng zip lồng nhau.
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final savedPaths = <String>[];
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final savePath = '${dir!.path}/${entry.name}';
        await File(savePath).writeAsBytes(entry.content as List<int>);
        savedPaths.add(savePath);
      }

      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã lưu: ${savedPaths.join(", ")}')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải artifact: $e')));
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final run = widget.run;

    return Scaffold(
      appBar: AppBar(title: Text(run.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Card(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(run.commitMessage, maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              Text(
                                '${run.branch} · ${timeAgo(run.createdAt)}',
                                style: TextStyle(color: scheme.outline, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Jobs', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ..._jobs.map((job) {
                        final jobStatus = _statusIcon(job.status, job.conclusion);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          child: ExpansionTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            leading: Icon(jobStatus.icon, color: jobStatus.color),
                            title: Text(job.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            trailing: IconButton(
                              icon: const Icon(Icons.article_rounded),
                              tooltip: 'Xem log',
                              onPressed: () => _viewLog(job),
                            ),
                            children: job.steps.map((step) {
                              final stepStatus = _statusIcon(step.status, step.conclusion);
                              return ListTile(
                                dense: true,
                                leading: Icon(stepStatus.icon, size: 18, color: stepStatus.color),
                                title: Text(step.name, style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                          ),
                        );
                      }),
                      const SizedBox(height: 20),
                      Text('Artifacts (file build ra)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_artifacts.isEmpty)
                        Text('Không có artifact nào.', style: TextStyle(color: scheme.outline))
                      else
                        ..._artifacts.map((artifact) => Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                leading: const Icon(Icons.inventory_2_rounded),
                                title: Text(artifact.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  artifact.expired ? 'Đã hết hạn' : _formatSize(artifact.sizeInBytes),
                                ),
                                trailing: artifact.expired
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.download_rounded),
                                        onPressed: () => _downloadArtifact(artifact),
                                      ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }
}
