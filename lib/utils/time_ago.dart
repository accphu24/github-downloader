String timeAgo(DateTime date) {
  final diff = DateTime.now().toUtc().difference(date.toUtc());

  if (diff.inSeconds < 60) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays < 7) return '${diff.inDays} ngày trước';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} tuần trước';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} tháng trước';
  return '${(diff.inDays / 365).floor()} năm trước';
}
