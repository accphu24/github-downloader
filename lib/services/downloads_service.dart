import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Lưu file vào thư mục Download công khai của máy qua code Android gốc (Kotlin),
/// dùng MediaStore API trực tiếp - không phụ thuộc thư viện bên thứ 3 (tránh lỗi
/// xung đột phiên bản compileSdk như đã từng gặp).
class DownloadsService {
  static const _channel = MethodChannel('github_downloader/downloads');

  /// Ghi [bytes] ra thư mục Download công khai với tên [fileName].
  /// Trả về tên hiển thị cho người dùng, hoặc null nếu lỗi.
  static Future<String?> saveBytes(String fileName, List<int> bytes) async {
    if (!Platform.isAndroid) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$fileName';
      await File(path).writeAsBytes(bytes);
      return path;
    }

    try {
      final savedName = await _channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'bytes': Uint8List.fromList(bytes),
      });
      if (savedName == null) return null;
      return 'Download/$savedName';
    } catch (_) {
      return null;
    }
  }
}
