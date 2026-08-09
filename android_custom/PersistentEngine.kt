package com.tuytam.github_downloader

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Giữ 1 FlutterEngine duy nhất sống xuyên suốt vòng đời tiến trình app - không bị huỷ
 * khi Activity bị đóng (vd: người dùng vuốt app khỏi Recent Apps trong lúc đang tải file).
 *
 * Bình thường, FlutterFragmentActivity tự tạo và huỷ FlutterEngine theo vòng đời của chính
 * nó, nên mọi Future đang chạy dở trong Dart (vd: tác vụ tải file) sẽ bị giết theo khi
 * Activity bị đóng. Bằng cách tự quản lý engine ở đây (kết hợp MainActivity trả về
 * shouldDestroyEngineWithHost() = false), engine này tiếp tục sống dù không còn Activity
 * nào gắn vào nó - miễn là tiến trình app còn sống (xem thêm KeepAliveService ở phía Dart,
 * dùng foreground service để tránh bị hệ điều hành giết tiến trình).
 */
object PersistentEngine {
    const val ENGINE_ID = "github_downloader_persistent_engine"

    fun getOrCreate(context: Context): FlutterEngine {
        val cached = FlutterEngineCache.getInstance().get(ENGINE_ID)
        if (cached != null) return cached

        val engine = FlutterEngine(context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        GeneratedPluginRegistrant.registerWith(engine)
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }
}
