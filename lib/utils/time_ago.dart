import '../l10n/strings.dart';

/// Hiện thời gian tương đối (vd "3 giờ trước") theo NGÔN NGỮ đang chọn trong
/// Cài đặt, dùng chung hệ thống dịch t() với phần còn lại của app.
///
/// Trước đây hàm này trả thẳng chuỗi tiếng Việt hard-code, tách biệt hoàn toàn
/// khỏi lib/l10n/strings.dart - nên khi đổi ngôn ngữ app sang English, các chỗ
/// dùng timeAgo() (Actions, Commits, Notifications, RunDetail) vẫn hiện tiếng
/// Việt xen giữa giao diện English.
String timeAgo(DateTime date) {
  final diff = DateTime.now().toUtc().difference(date.toUtc());

  if (diff.inSeconds < 60) return t('time.just_now');
  if (diff.inMinutes < 60) return t('time.minutes_ago', {'n': '${diff.inMinutes}'});
  if (diff.inHours < 24) return t('time.hours_ago', {'n': '${diff.inHours}'});
  if (diff.inDays < 7) return t('time.days_ago', {'n': '${diff.inDays}'});
  if (diff.inDays < 30) return t('time.weeks_ago', {'n': '${(diff.inDays / 7).floor()}'});
  if (diff.inDays < 365) return t('time.months_ago', {'n': '${(diff.inDays / 30).floor()}'});
  return t('time.years_ago', {'n': '${(diff.inDays / 365).floor()}'});
}
