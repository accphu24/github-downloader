import 'dart:convert';
import 'dart:io';
import 'package:home_widget/home_widget.dart';
import 'auth_service.dart';
import 'github_service.dart';
import 'pinned_repos_service.dart';

/// Cập nhật dữ liệu cho widget màn hình chính (nhóm C #3): danh sách build
/// CI/CD mới nhất của TẤT CẢ repo đã ghim. CHỈ gọi khi app mở lên (theo đúng
/// lựa chọn của Ruby - không polling nền tốn pin), nên dữ liệu trên widget có
/// thể hơi cũ nếu app lâu không mở - chấp nhận được, đổi lấy đỡ tốn pin.
class WidgetService {
  static const _androidProviderClass = 'CiStatusWidgetProvider';
  static const _qualifiedAndroidName = 'com.tuytam.github_downloader.CiStatusWidgetProvider';

  /// Không throw ra ngoài trong bất kỳ trường hợp nào - lỗi cập nhật widget
  /// không được phép ảnh hưởng tới trải nghiệm chính của app.
  static Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      final token = await AuthService().getToken();
      if (token == null) return;

      final pinned = await PinnedReposService().getPinned();
      if (pinned.isEmpty) return;

      final service = GithubService(token: token);
      final items = <Map<String, String>>[];

      await Future.wait(pinned.map((fullName) async {
        final parts = fullName.split('/');
        if (parts.length != 2) return;
        try {
          final runs = await service.listWorkflowRuns(parts[0], parts[1]);
          final latest = runs.isNotEmpty ? runs.first : null;
          items.add({
            'repo': fullName,
            'status': latest == null
                ? 'unknown'
                : (latest.status != 'completed' ? 'running' : (latest.conclusion ?? 'unknown')),
            'run_name': latest?.name ?? '',
          });
        } catch (_) {
          // Bỏ qua repo lỗi (vd hết quyền truy cập, repo rỗng...) - không chặn
          // widget hiện các repo còn lại.
        }
      }));

      items.sort((a, b) => a['repo']!.compareTo(b['repo']!));

      await HomeWidget.saveWidgetData<String>('ci_widget_repos', jsonEncode(items));
      await HomeWidget.updateWidget(
        androidName: _androidProviderClass,
        qualifiedAndroidName: _qualifiedAndroidName,
      );
    } catch (_) {
      // Lỗi cập nhật widget không được làm ảnh hưởng tới trải nghiệm chính của app.
    }
  }
}
