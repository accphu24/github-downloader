import 'package:flutter/material.dart';
import '../services/download_manager.dart';

/// Thanh nhỏ nổi ở dưới màn hình, hiện danh sách các tác vụ đang tải nền.
/// Không chặn thao tác - người dùng vẫn bấm/điều hướng bình thường phía trên nó.
class GlobalDownloadIndicator extends StatelessWidget {
  const GlobalDownloadIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DownloadManager.instance,
      builder: (context, _) {
        final tasks = DownloadManager.instance.tasks;
        if (tasks.isEmpty) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;
        return Positioned(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.of(context).padding.bottom,
          child: IgnorePointer(
            ignoring: false,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.inverseSurface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: tasks.map((task) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: task.progress,
                              color: scheme.onInverseSurface,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              task.progress != null
                                  ? '${task.label} · ${(task.progress! * 100).toStringAsFixed(0)}%'
                                  : task.label,
                              style: TextStyle(color: scheme.onInverseSurface, fontSize: 13, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
