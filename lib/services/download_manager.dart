import 'package:flutter/material.dart';
import 'log_service.dart';
import 'keep_alive_service.dart';

class DownloadTask {
  final String id;
  final String label;
  double? progress; // null = chưa biết % (indeterminate)

  DownloadTask({required this.id, required this.label, this.progress});
}

/// Quản lý các tác vụ tải chạy nền trong app: không chặn màn hình, người dùng
/// vẫn điều hướng/thao tác bình thường trong lúc tải. Khi xong sẽ tự hiện
/// thông báo (dùng context toàn app, không phụ thuộc màn hình cụ thể nào).
class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._internal();
  DownloadManager._internal();

  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool get hasActive => _tasks.isNotEmpty;

  void _start(String id, String label) {
    _tasks.add(DownloadTask(id: id, label: label));
    notifyListeners();
  }

  void _updateProgress(String id, double? progress) {
    for (final task in _tasks) {
      if (task.id == id) {
        task.progress = progress;
        notifyListeners();
        return;
      }
    }
  }

  void _finish(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
    if (_tasks.isEmpty) {
      // Hết tác vụ tải -> không cần giữ app "sống cưỡng bức" nữa.
      KeepAliveService.instance.stopKeepAliveIfIdle();
    }
  }

  /// Chạy 1 tác vụ tải ở chế độ "chạy nền" (fire-and-forget): hàm gọi không
  /// cần await, UI không bị chặn. [fetch] trả về dữ liệu tải được (nhận callback
  /// báo % tiến độ), [save] lưu dữ liệu đó và trả về đường dẫn hiển thị.
  /// [onSuccess]/[onError] dùng context toàn app (navigatorKey) nên vẫn chạy
  /// đúng dù người dùng đã chuyển sang màn hình khác.
  void runDownload({
    required String label,
    required Future<List<int>> Function(void Function(double? progress) onProgress) fetch,
    required Future<String?> Function(List<int> bytes) save,
    required void Function(BuildContext context, String savedPath) onSuccess,
    required void Function(BuildContext context, String error) onError,
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    _start(id, label);
    LogService.instance.info('Bắt đầu tải: $label');
    // Hiện thông báo "đang tải" để Android không giết tiến trình app nếu người
    // dùng thoát/ẩn app giữa lúc đang tải (xem KeepAliveService).
    KeepAliveService.instance.startKeepAlive(label: label);

    () async {
      try {
        final bytes = await fetch((p) => _updateProgress(id, p));
        final savedPath = await save(bytes);
        _finish(id);
        LogService.instance.info('Tải xong: $label (${bytes.length} byte) -> $savedPath');
        final ctx = navigatorKey.currentContext;
        if (ctx != null && savedPath != null) onSuccess(ctx, savedPath);
      } catch (e) {
        _finish(id);
        LogService.instance.error('Tải lỗi: $label -> $e');
        final ctx = navigatorKey.currentContext;
        if (ctx != null) onError(ctx, e.toString());
      }
    }();
  }
}
