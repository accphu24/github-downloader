import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'app_settings.dart';
import 'downloads_service.dart';

/// 1 dòng log chi tiết: thời điểm, mức độ (info/warn/error) và nội dung.
class LogEntry {
  final DateTime time;
  final String level;
  final String message;

  LogEntry(this.time, this.level, this.message);

  String _two(int n) => n.toString().padLeft(2, '0');

  String format() {
    final h = _two(time.hour), m = _two(time.minute), s = _two(time.second);
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '[$h:$m:$s.$ms] [$level] $message';
  }
}

/// Bộ nhớ log chi tiết trong toàn app. Chỉ ghi nhận khi người dùng bật
/// "Lưu log chi tiết" trong Cài đặt (xem [AppSettings.detailedLogEnabled]).
/// Log được giữ trong bộ nhớ (giới hạn số dòng để tránh phình RAM) và có thể
/// tự động lưu ra file trong thư mục Download của máy khi app đóng/ẩn xuống nền.
class LogService extends ChangeNotifier {
  static final LogService instance = LogService._internal();
  LogService._internal();

  static const int _maxEntries = 5000;

  final List<LogEntry> _entries = [];
  List<LogEntry> get entries => List.unmodifiable(_entries);

  int _savedCount = 0;
  bool _saving = false;

  bool get enabled => AppSettings.instance.detailedLogEnabled;

  void log(String message, {String level = 'INFO'}) {
    if (!enabled) return;
    _entries.add(LogEntry(DateTime.now(), level, message));
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifyListeners();
  }

  void info(String message) => log(message, level: 'INFO');
  void warn(String message) => log(message, level: 'WARN');
  void error(String message) => log(message, level: 'ERROR');

  void clear() {
    _entries.clear();
    _savedCount = 0;
    notifyListeners();
  }

  String _buildFileName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'github_downloader_log_$stamp.txt';
  }

  /// Xuất toàn bộ log hiện có ra file trong thư mục Download của máy.
  /// Trả về đường dẫn hiển thị, hoặc null nếu không có gì để lưu / lỗi.
  Future<String?> saveToDevice({bool force = false}) async {
    if (_saving) return null;
    if (_entries.isEmpty) return null;
    if (!force && _entries.length == _savedCount) return null; // không có gì mới từ lần lưu trước

    _saving = true;
    try {
      final buffer = StringBuffer()
        ..writeln('GitHub Repo Downloader - log chi tiết')
        ..writeln('Xuất lúc: ${DateTime.now()}')
        ..writeln('Số dòng: ${_entries.length}')
        ..writeln('----------------------------------------');
      for (final e in _entries) {
        buffer.writeln(e.format());
      }
      final bytes = utf8.encode(buffer.toString());
      final savedPath = await DownloadsService.saveBytes(_buildFileName(), bytes);
      if (savedPath != null) _savedCount = _entries.length;
      return savedPath;
    } finally {
      _saving = false;
    }
  }
}
