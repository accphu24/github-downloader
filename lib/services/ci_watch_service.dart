import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'app_settings.dart';
import 'auth_service.dart';
import 'pinned_repos_service.dart';
import 'keep_alive_service.dart';

/// Điều phối tính năng theo dõi CI/CD nền: quyết định danh sách repo cần theo
/// dõi (= các repo đã ghim), đẩy dữ liệu cần thiết (token, danh sách repo) sang
/// cho TaskHandler chạy trong foreground service (xem keep_alive_service.dart),
/// và bật/tắt service tương ứng qua KeepAliveService. Việc polling GitHub thực
/// sự diễn ra bên trong TaskHandler (isolate riêng), không phải ở đây.
class CiWatchService {
  static final CiWatchService instance = CiWatchService._internal();
  CiWatchService._internal();

  /// Bật tính năng. Trả false nếu chưa đăng nhập hoặc chưa ghim repo nào
  /// (không có gì để theo dõi) - gọi nơi hiển thị UI có thể dùng để báo lỗi phù hợp.
  Future<bool> enable() async {
    final token = await AuthService().getToken();
    final pinned = await PinnedReposService().getPinned();
    if (token == null || pinned.isEmpty) return false;

    final repos = pinned.toList();
    await FlutterForegroundTask.saveData(key: 'ci_watch_enabled', value: 'true');
    await FlutterForegroundTask.saveData(key: 'ci_watch_token', value: token);
    await FlutterForegroundTask.saveData(key: 'ci_watch_repos', value: jsonEncode(repos));

    await AppSettings.instance.setCiWatchEnabled(true);
    await KeepAliveService.instance.startCiWatch(label: '${repos.length} repo đã ghim');
    return true;
  }

  Future<void> disable() async {
    await FlutterForegroundTask.saveData(key: 'ci_watch_enabled', value: 'false');
    await AppSettings.instance.setCiWatchEnabled(false);
    await KeepAliveService.instance.stopCiWatch();
  }

  /// Gọi lại mỗi khi danh sách repo ghim thay đổi (ghim thêm/bỏ ghim) trong lúc
  /// tính năng đang bật, để service theo dõi đúng danh sách mới nhất mà không
  /// cần tắt/bật lại toàn bộ tính năng.
  Future<void> syncWatchedReposIfEnabled() async {
    if (!AppSettings.instance.ciWatchEnabled) return;
    final pinned = await PinnedReposService().getPinned();
    await FlutterForegroundTask.saveData(key: 'ci_watch_repos', value: jsonEncode(pinned.toList()));
  }
}
