import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'log_service.dart';

/// Hàm callback bắt buộc phải là top-level/static (yêu cầu của flutter_foreground_task)
/// vì nó được gọi trong 1 isolate riêng do Android tạo ra khi khởi động foreground service.
@pragma('vm:entry-point')
void _startKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_NoopTaskHandler());
}

/// TaskHandler gần như không làm gì. Mục đích duy nhất của foreground service này là
/// khiến Android coi tiến trình app có độ ưu tiên cao, để không bị hệ điều hành giết khi
/// người dùng thoát/ẩn app lúc đang có tác vụ tải chạy dở. Việc tải file THẬT SỰ vẫn chạy
/// trên isolate chính của app như bình thường (nhờ MainActivity dùng chung 1 FlutterEngine
/// sống xuyên suốt vòng đời tiến trình - xem android_custom/PersistentEngine.kt), nên không
/// cần viết lại logic tải file ở đây.
class _NoopTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Giữ cho app không bị hệ điều hành Android giết tiến trình khi người dùng thoát/ẩn app
/// trong lúc đang tải file. Cách hoạt động: hễ có tác vụ tải đang chạy, hiện 1 thông báo
/// "Đang tải file" thông qua foreground service của Android - đây chính là tín hiệu để
/// Android không tuỳ tiện giết tiến trình app. Hết tác vụ tải thì tự tắt thông báo.
class KeepAliveService {
  static final KeepAliveService instance = KeepAliveService._internal();
  KeepAliveService._internal();

  bool _initialized = false;
  bool _permissionChecked = false;

  /// Gọi 1 lần lúc app khởi động.
  void init() {
    if (!Platform.isAndroid || _initialized) return;
    _initialized = true;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'download_keep_alive',
          channelName: 'Đang tải file',
          channelDescription: 'Hiện khi app đang tải file, để tránh bị hệ thống đóng app giữa chừng.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.once(),
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
      // Không chặn việc tải file nếu xin quyền lỗi - chỉ là sẽ không hiện được thông báo.
    }
  }

  /// Gọi khi bắt đầu có tác vụ tải chạy nền.
  Future<void> startKeepAlive({required String label}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ensurePermissions();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Đang tải file',
          notificationText: label,
        );
      } else {
        final result = await FlutterForegroundTask.startService(
          serviceId: 991,
          notificationTitle: 'Đang tải file',
          notificationText: label,
          callback: _startKeepAliveCallback,
        );
        LogService.instance.info('Khởi động keep-alive service: $result');
      }
    } catch (e) {
      LogService.instance.warn('Không khởi động được thông báo giữ app sống: $e');
    }
  }

  /// Gọi khi không còn tác vụ tải nào đang chạy.
  Future<void> stopKeepAliveIfIdle() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      LogService.instance.warn('Không tắt được thông báo giữ app sống: $e');
    }
  }
}
