import 'dart:io';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Lưu file vào thư mục Download công khai của máy (không phải thư mục riêng của app),
/// dùng MediaStore API của Android (bắt buộc từ Android 10 trở lên khi ghi vào thư mục dùng chung).
class DownloadsService {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized || !Platform.isAndroid) return;
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = 'GitHubDownloader';
    _initialized = true;
  }

  /// Ghi [bytes] ra file tạm rồi chuyển vào thư mục Download công khai với tên [fileName].
  /// Trả về đường dẫn hiển thị cho người dùng (tên file trong Download), hoặc null nếu lỗi.
  static Future<String?> saveBytes(String fileName, List<int> bytes) async {
    if (!Platform.isAndroid) {
      // Nền tảng khác (hiếm khi xảy ra vì app chỉ build cho Android): lưu vào thư mục app.
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$fileName';
      await File(path).writeAsBytes(bytes);
      return path;
    }

    await ensureInitialized();

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(bytes);

    final saveInfo = await MediaStore().saveFile(
      tempFilePath: tempFile.path,
      dirType: DirType.download,
      dirName: DirName.download,
    );

    try {
      await tempFile.delete();
    } catch (_) {}

    if (saveInfo == null) return null;
    return 'Download/${saveInfo.name}';
  }
}
