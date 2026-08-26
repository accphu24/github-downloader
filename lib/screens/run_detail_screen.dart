import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import '../services/github_service.dart';
import '../services/downloads_service.dart';
import '../services/download_manager.dart';
import '../utils/time_ago.dart';
import '../l10n/strings.dart';
import '../widgets/top_notification.dart';
import '../main.dart' show navigatorKey;

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
      barrierDismissible: false,
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
      displayLog = '${t('rundetail.log_truncated')}\n\n${displayLog.substring(displayLog.length - maxChars)}';
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
                      t('rundetail.log_title', {'job': job.name}),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                    tooltip: t('rundetail.log_download_tooltip'),
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
    final safeName = jobName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final savedPath = await DownloadsService.saveBytes('log_$safeName.txt', utf8.encode(log));
    if (mounted && savedPath != null) {
      showTopNotification(context, t('rundetail.log_saved', {'path': savedPath}));
    }
  }

  void _downloadArtifact(Artifact artifact) {
    if (artifact.expired) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('rundetail.artifact_expired_msg'))));
      return;
    }

    DownloadManager.instance.runDownload(
      label: artifact.name,
      navigatorKey: navigatorKey,
      fetch: (onProgress) => widget.githubService.downloadArtifactZip(
        artifact.archiveDownloadUrl,
        onProgress: (received, total) {
          if (total != null && total > 0) onProgress(received / total);
        },
      ),
      save: (zipBytes) async {
        // Kiểm tra "chữ ký" đầu file để chắc chắn đây thật sự là file zip (PK\x03\x04),
        // tránh crash khó hiểu nếu server trả về nội dung khác (vd trang lỗi HTML).
        final isValidZip = zipBytes.length >= 4 &&
            zipBytes[0] == 0x50 &&
            zipBytes[1] == 0x4B &&
            (zipBytes[2] == 0x03 || zipBytes[2] == 0x05 || zipBytes[2] == 0x07);
        if (!isValidZip) {
          throw Exception('Dữ liệu tải về không đúng định dạng zip (có thể do lỗi mạng hoặc link đã hết hạn)');
        }

        final archive = ZipDecoder().decodeBytes(zipBytes);
        final fileEntries = archive.files.where((e) => e.isFile).toList();
        // Artifact CI có thể chứa nhiều file lồng trong thư mục con (rất phổ biến,
        // vd "app/build/app-release.apk"). entry.name giữ nguyên đường dẫn đó -
        // nếu dùng thẳng làm tên file lưu vào Downloads, dấu "/" bên trong sẽ khiến
        // MediaStore.DISPLAY_NAME (không được chứa "/") lưu lỗi hoặc sai tên. Chỉ
        // khi có ĐÚNG 1 file (vd artifact APK của chính app này) mới giữ nguyên tên
        // gốc như trước; nhiều file thì làm phẳng đường dẫn + thêm tiền tố tên
        // artifact để giảm khả năng trùng tên giữa các thư mục con khác nhau.
        final multiple = fileEntries.length > 1;
        final savedPaths = <String>[];
        for (final entry in fileEntries) {
          final safeName =
              multiple ? '${artifact.name}_${entry.name.replaceAll('/', '_')}' : entry.name.split('/').last;
          final savedPath = await DownloadsService.saveBytes(safeName, entry.content as List<int>);
          if (savedPath != null) savedPaths.add(savedPath);
        }
        return savedPaths.isEmpty ? null : savedPaths.join(', ');
      },
      onSuccess: (ctx, savedPath) => showTopNotification(ctx, t('common.saved_at', {'path': savedPath})),
      onError: (ctx, error) => ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(t('rundetail.artifact_download_error', {'error': error}))),
      ),
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
                        FilledButton(onPressed: _load, child: Text(t('common.retry'))),
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
                      Text(t('rundetail.jobs_title'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                              tooltip: t('rundetail.log_view_tooltip'),
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
                      Text(t('rundetail.artifacts_title'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_artifacts.isEmpty)
                        Text(t('rundetail.no_artifacts'), style: TextStyle(color: scheme.outline))
                      else
                        ..._artifacts.map((artifact) => Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                leading: const Icon(Icons.inventory_2_rounded),
                                title: Text(artifact.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  artifact.expired ? t('rundetail.expired') : _formatSize(artifact.sizeInBytes),
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
