import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Gửi notification RIÊNG BIỆT (khác với notification "dịch vụ đang chạy nền"
/// của flutter_foreground_task ở keep_alive_service.dart) mỗi khi 1 build
/// CI/CD của repo đã ghim hoàn tất. Dùng kênh Importance.max/Priority.high để
/// CÓ âm thanh + hiện heads-up - khác hẳn kênh LOW hiện có vốn chỉ lặng lẽ đổi
/// dòng chữ trên thông báo nền, không kêu và bị đè mất kết quả build trước đó.
///
/// QUAN TRỌNG: phải gọi init() ở CẢ isolate chính (main.dart, lúc app khởi
/// động) LẪN isolate nền của TaskHandler (keep_alive_service.dart, lúc poll
/// CI) - vì plugin flutter_local_notifications cần initialize() riêng ở từng
/// isolate mới show() được, 2 isolate không dùng chung 1 lần init.
class CiNotificationService {
  static final CiNotificationService instance = CiNotificationService._internal();
  CiNotificationService._internal();

  static const _channelId = 'ci_build_alerts';
  static const _channelName = 'Kết quả build CI/CD';
  static const _channelDescription = 'Báo khi 1 build CI/CD của repo đã ghim hoàn tất (thành công/thất bại).';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// [onTap] chỉ được gọi khi người dùng bấm vào notification LÚC main
  /// isolate của app vẫn còn sống (app đang mở hoặc bị ẩn xuống nền nhưng
  /// chưa bị hệ điều hành giết hẳn). Nếu app đã bị giết hẳn, tap sẽ khởi động
  /// lại app từ đầu - trường hợp đó main.dart tự xử lý qua getLaunchPayload()
  /// nên truyền onTap là null khi init() từ isolate nền (TaskHandler).
  Future<void> init({void Function(String repoFullName)? onTap}) async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onTap?.call(payload);
      },
    );
    _initialized = true;
  }

  /// Gọi 1 LẦN lúc app khởi động (sau init()) để biết app vừa được mở lên có
  /// phải do người dùng bấm vào notification build CI lúc app đã bị giết hẳn
  /// hay không. Trả về payload (tên đầy đủ "owner/repo") nếu đúng, null nếu
  /// app mở bình thường.
  Future<String?> getLaunchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  Future<void> showBuildResult({
    required String repoFullName,
    required bool success,
    required String runName,
  }) async {
    if (!_initialized) await init();
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: androidDetails);
    // ID = hash tên repo, ổn định cho cùng 1 repo qua các lần gọi - nhờ vậy
    // build mới của CÙNG repo sẽ đè lên build cũ của CHÍNH repo đó (đỡ rác
    // notification), nhưng KHÔNG đè lên notification của repo khác.
    await _plugin.show(
      repoFullName.hashCode & 0x7fffffff,
      success ? '✅ Build xong: $repoFullName' : '⚠️ Build lỗi: $repoFullName',
      runName,
      details,
      payload: repoFullName,
    );
  }
}
