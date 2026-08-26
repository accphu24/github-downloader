import 'dart:convert';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'log_service.dart';
import 'github_service.dart';

/// Hàm callback bắt buộc phải là top-level/static (yêu cầu của flutter_foreground_task)
/// vì nó được gọi trong 1 isolate riêng do Android tạo ra khi khởi động foreground service.
@pragma('vm:entry-point')
void _startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_AppTaskHandler());
}

/// TaskHandler DÙNG CHUNG cho MỌI lý do khiến app cần 1 foreground service (giữ
/// app sống khi tải file, và/hoặc theo dõi CI/CD nền). Dùng chung 1 handler duy
/// nhất - thay vì 1 handler riêng cho mỗi mục đích - vì flutter_foreground_task
/// chỉ chạy được 1 TaskHandler tại 1 thời điểm: nếu bật theo dõi CI trong lúc
/// service đang chạy vì lý do khác (đang tải file), updateService() không đổi
/// được TaskHandler đang hoạt động, nên việc polling CI phải nằm sẵn trong CÙNG
/// 1 handler, tự đọc cờ mỗi lần được gọi để quyết định có poll hay không.
class _AppTaskHandler extends TaskHandler {
  Map<String, String> _knownRunConclusions = {};
  bool _isPolling = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final saved = await FlutterForegroundTask.getData<String>(key: 'ci_known_runs');
    if (saved == null) return;
    try {
      final decoded = jsonDecode(saved) as Map;
      _knownRunConclusions = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      // Dữ liệu cũ hỏng/không đọc được - bỏ qua, bắt đầu lại từ đầu.
    }
  }

  // Chạy mỗi 60s (xem ForegroundTaskEventAction.repeat bên dưới) bất kể service
  // đang chạy vì lý do gì. Khi chỉ đang tải file (không bật theo dõi CI),
  // _pollCiIfEnabled tự thoát sớm nên không ảnh hưởng gì tới việc tải.
  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_isPolling) return;
    _isPolling = true;
    _pollCiIfEnabled().whenComplete(() => _isPolling = false);
  }

  Future<void> _pollCiIfEnabled() async {
    try {
      final enabled = await FlutterForegroundTask.getData<String>(key: 'ci_watch_enabled');
      if (enabled != 'true') return;

      final token = await FlutterForegroundTask.getData<String>(key: 'ci_watch_token');
      final reposJson = await FlutterForegroundTask.getData<String>(key: 'ci_watch_repos');
      if (token == null || token.isEmpty || reposJson == null) return;

      List<String> repos;
      try {
        repos = List<String>.from(jsonDecode(reposJson) as List);
      } catch (_) {
        return;
      }
      if (repos.isEmpty) return;

      final service = GithubService(token: token);
      var changed = false;

      for (final fullName in repos) {
        final parts = fullName.split('/');
        if (parts.length != 2) continue;
        try {
          final runs = await service.listWorkflowRuns(parts[0], parts[1]);
          for (final run in runs.take(5)) {
            if (run.status != 'completed') continue;
            final key = '$fullName#${run.id}';
            final conclusion = run.conclusion ?? 'unknown';
            final prev = _knownRunConclusions[key];
            if (prev == null) {
              // Lần đầu thấy run này (mới bật tính năng, hoặc service vừa khởi
              // động lại) - chỉ ghi nhận làm mốc so sánh, KHÔNG báo, để tránh
              // báo dồn dập toàn bộ lịch sử build cũ ngay khi vừa bật.
              _knownRunConclusions[key] = conclusion;
              changed = true;
            } else if (prev != conclusion) {
              _knownRunConclusions[key] = conclusion;
              changed = true;
              final ok = conclusion == 'success';
              FlutterForegroundTask.updateService(
                notificationTitle: ok ? '✅ Build xong: $fullName' : '⚠️ Build $conclusion: $fullName',
                notificationText: run.name,
              );
            }
          }
        } catch (e) {
          LogService.instance.warn('CiWatch: lỗi kiểm tra $fullName: $e');
        }
      }

      // Giới hạn kích thước lưu trữ, tránh phình to vô hạn qua thời gian dài.
      if (_knownRunConclusions.length > 300) {
        final entries = _knownRunConclusions.entries.toList();
        _knownRunConclusions = Map.fromEntries(entries.sublist(entries.length - 300));
        changed = true;
      }
      if (changed) {
        await FlutterForegroundTask.saveData(key: 'ci_known_runs', value: jsonEncode(_knownRunConclusions));
      }
    } catch (e) {
      LogService.instance.warn('CiWatch: lỗi polling: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Giữ cho app không bị hệ điều hành Android giết tiến trình khi người dùng
/// thoát/ẩn app, đồng thời (nếu bật) polling định kỳ trạng thái CI/CD của các
/// repo đã ghim. Nhiều "lý do" khác nhau (tải file, theo dõi CI) có thể cùng
/// cần service chạy cùng lúc - dùng đếm tham chiếu qua [_activeReasons] để 1 lý
/// do kết thúc (vd tải xong) không vô tình tắt luôn lý do khác đang cần service
/// (vd đang theo dõi CI).
class _ReasonInfo {
  final String title;
  final String text;
  const _ReasonInfo(this.title, this.text);
}

class KeepAliveService {
  static final KeepAliveService instance = KeepAliveService._internal();
  KeepAliveService._internal();

  bool _initialized = false;
  bool _permissionChecked = false;
  // Lưu cả title/text của từng lý do (không chỉ tên) để khi 1 lý do kết thúc mà
  // lý do khác vẫn còn, có thể KHÔI PHỤC lại đúng nội dung thông báo của lý do
  // còn lại - trước đây chỉ xoá khỏi Set nên nội dung cũ bị kẹt nguyên trên
  // thông báo (vd tải file xong trong lúc đang theo dõi CI thì thông báo vẫn
  // treo "Đang tải file" mãi vì không có bước ghi đè lại).
  final Map<String, _ReasonInfo> _activeReasons = {};

  // Mọi lệnh start/stop được xếp vào hàng đợi này để LUÔN chạy tuần tự theo
  // đúng thứ tự gọi, kể cả khi nơi gọi (vd download_manager.dart) không await.
  // Nếu không có hàng đợi này: lệnh "khởi động service" (nhiều bước async, có
  // gọi sang Android native, có thể mất vài trăm ms) và lệnh "dừng service"
  // (gọi ngay sau khi 1 tác vụ tải rất nhanh xong) có thể HOÀN TẤT SAI THỨ TỰ -
  // dừng xong trước, khởi động xong sau - khiến thông báo treo mãi ở nội dung
  // "đang tải" dù không còn gì đang tải cả.
  Future<void> _queue = Future.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.catchError((_) {});
    return result;
  }

  /// Gọi 1 lần lúc app khởi động.
  void init() {
    if (!Platform.isAndroid || _initialized) return;
    _initialized = true;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'app_background_service',
          channelName: 'Dịch vụ nền',
          channelDescription: 'Hiện khi app đang tải file hoặc theo dõi CI/CD nền.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(60000),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    } catch (e) {
      LogService.instance.warn('Không khởi tạo được KeepAliveService: $e');
    }
  }

  Future<void> _ensurePermissions() async {
    if (_permissionChecked || !Platform.isAndroid) return;
    _permissionChecked = true;
    try {
      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {
      // Không chặn tác vụ nếu xin quyền lỗi - chỉ là sẽ không hiện được thông báo.
    }
  }

  Future<void> _startForReason(String reason, {required String title, required String text}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ensurePermissions();
      _activeReasons[reason] = _ReasonInfo(title, text);
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
      } else {
        final result = await FlutterForegroundTask.startService(
          serviceId: 991,
          notificationTitle: title,
          notificationText: text,
          callback: _startForegroundCallback,
        );
        LogService.instance.info('Khởi động foreground service ($reason): $result');
      }
    } catch (e) {
      LogService.instance.warn('Không khởi động được service nền ($reason): $e');
    }
  }

  Future<void> _stopReason(String reason) async {
    if (!Platform.isAndroid) return;
    _activeReasons.remove(reason);
    if (_activeReasons.isEmpty) {
      try {
        if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
        }
      } catch (e) {
        LogService.instance.warn('Không tắt được service nền: $e');
      }
      return;
    }
    // Vẫn còn lý do khác cần service chạy tiếp - khôi phục lại nội dung thông
    // báo của lý do đó, tránh để nguyên nội dung cũ của lý do vừa kết thúc.
    try {
      final remaining = _activeReasons.values.last;
      await FlutterForegroundTask.updateService(notificationTitle: remaining.title, notificationText: remaining.text);
    } catch (e) {
      LogService.instance.warn('Không cập nhật lại thông báo nền: $e');
    }
  }

  /// Gọi khi bắt đầu có tác vụ tải chạy nền.
  Future<void> startKeepAlive({required String label}) =>
      _enqueue(() => _startForReason('download', title: 'Đang tải file', text: label));

  /// Gọi khi không còn tác vụ tải nào đang chạy.
  Future<void> stopKeepAliveIfIdle() => _enqueue(() => _stopReason('download'));

  /// Gọi khi bật tính năng theo dõi CI/CD nền.
  Future<void> startCiWatch({required String label}) =>
      _enqueue(() => _startForReason('ci_watch', title: 'Đang theo dõi CI/CD', text: label));

  /// Gọi khi tắt tính năng theo dõi CI/CD nền.
  Future<void> stopCiWatch() => _enqueue(() => _stopReason('ci_watch'));
}
