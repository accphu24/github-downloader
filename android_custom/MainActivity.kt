package com.tuytam.github_downloader

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Dùng FlutterFragmentActivity (thay vì FlutterActivity) vì thư viện local_auth
// (khoá vân tay/khuôn mặt) yêu cầu FragmentActivity để hiện hộp thoại xác thực.
class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "github_downloader/downloads"

    // Dùng engine dùng chung (xem PersistentEngine.kt) thay vì để Activity tự tạo/huỷ engine
    // theo vòng đời của nó - nhờ vậy tác vụ tải file (Future đang chạy dở trong Dart) không
    // bị giết khi người dùng đóng/vuốt app khỏi Recent Apps giữa lúc đang tải.
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return PersistentEngine.getOrCreate(context)
    }

    // false = engine này không bị huỷ khi Activity bị đóng.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveToDownloads") {
                try {
                    val fileName = call.argument<String>("fileName")!!
                    val bytes = call.argument<ByteArray>("bytes")!!
                    val savedName = saveToDownloads(fileName, bytes)
                    result.success(savedName)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    /// Lưu [bytes] vào thư mục Download công khai với tên [fileName].
    /// Từ Android 10 (API 29) trở lên dùng MediaStore (không cần quyền đặc biệt).
    /// Dưới Android 10 dùng ghi file trực tiếp (cần quyền WRITE_EXTERNAL_STORAGE).
    private fun saveToDownloads(fileName: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver

            // Xoá bản ghi CŨ (nếu có) cùng tên trong Downloads trước khi lưu bản mới,
            // để tải lại 1 file đã tải trước đó GHI ĐÈ thay vì Android tự động đổi
            // tên file mới thành "ten (1).ext" (hành vi mặc định của MediaStore khi
            // DISPLAY_NAME trùng với 1 bản ghi đã có). Dùng LIKE thay vì so khớp
            // tuyệt đối cho RELATIVE_PATH vì giá trị MediaStore lưu có thể có hoặc
            // không có dấu "/" ở cuối tuỳ phiên bản Android.
            val existingSelection = "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} LIKE ?"
            val existingArgs = arrayOf(fileName, "${Environment.DIRECTORY_DOWNLOADS}%")
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Downloads._ID),
                existingSelection,
                existingArgs,
                null,
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID)
                while (cursor.moveToNext()) {
                    val existingUri = ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cursor.getLong(idIndex))
                    resolver.delete(existingUri, null, null)
                }
            }

            val contentValues = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw Exception("Không tạo được entry trong MediaStore")

            resolver.openOutputStream(uri)?.use { out -> out.write(bytes) }

            contentValues.clear()
            contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)
        } else {
            @Suppress("DEPRECATION")
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) downloadsDir.mkdirs()
            val file = File(downloadsDir, fileName)
            file.writeBytes(bytes) // File.writeBytes ghi đè tự nhiên nếu file đã tồn tại
        }

        return fileName
    }
}
