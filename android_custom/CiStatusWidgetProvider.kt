package com.tuytam.github_downloader

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/// Widget màn hình chính (nhóm C #3): hiện danh sách build CI/CD MỚI NHẤT của
/// TẤT CẢ repo đã ghim, dạng list cuộn được (4x2 ô). Dữ liệu CHỈ được cập nhật
/// khi app mở lên (xem WidgetService.refresh() ở phía Dart, gọi lúc khởi
/// động) - widget này KHÔNG tự poll nền, đỡ tốn pin, đổi lại dữ liệu có thể
/// hơi cũ nếu app lâu không mở (đúng như Ruby chọn).
class CiStatusWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.ci_status_widget)

            // ListView trong widget là 1 "collection" - KHÔNG thể set item trực
            // tiếp như RemoteViews thường, phải trỏ tới 1 RemoteViewsService để
            // Android tự gọi lại lấy dữ liệu (xem CiStatusWidgetService.kt).
            val serviceIntent = Intent(context, CiStatusWidgetService::class.java)
            views.setRemoteAdapter(R.id.ci_widget_list, serviceIntent)
            views.setEmptyView(R.id.ci_widget_list, R.id.ci_widget_empty)

            // Bấm vào widget (list rỗng hoặc bất kỳ dòng nào) đều mở app lên.
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setPendingIntentTemplate(R.id.ci_widget_list, pendingIntent)
            views.setOnClickPendingIntent(R.id.ci_widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.ci_widget_list)
        }
    }
}
