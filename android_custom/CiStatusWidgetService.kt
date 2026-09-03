package com.tuytam.github_downloader

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

class CiStatusWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return CiStatusRemoteViewsFactory(applicationContext)
    }
}

/// Đọc dữ liệu do WidgetService.refresh() (phía Dart) ghi vào SharedPreferences
/// dùng chung với plugin home_widget - key "ci_widget_repos" chứa 1 JSON array
/// dạng [{"repo": "owner/name", "status": "success|failure|running|unknown",
/// "run_name": "..."}].
private class CiStatusRemoteViewsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private data class Item(val repo: String, val status: String, val runName: String)

    private var items: List<Item> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        // Đọc lại MỖI LẦN Android yêu cầu vẽ lại list (vd sau khi
        // notifyAppWidgetViewDataChanged() được gọi từ Provider).
        items = try {
            val raw = HomeWidgetPlugin.getData(context).getString("ci_widget_repos", null)
            if (raw == null) {
                emptyList()
            } else {
                val arr = JSONArray(raw)
                (0 until arr.length()).map { i ->
                    val obj = arr.getJSONObject(i)
                    Item(
                        repo = obj.getString("repo"),
                        status = obj.optString("status", "unknown"),
                        runName = obj.optString("run_name", ""),
                    )
                }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    override fun onDestroy() {}
    override fun getCount(): Int = items.size
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
    override fun getLoadingView(): RemoteViews? = null

    override fun getViewAt(position: Int): RemoteViews {
        val item = items[position]
        val views = RemoteViews(context.packageName, R.layout.ci_status_widget_item)
        views.setTextViewText(R.id.ci_item_repo, item.repo)
        views.setTextViewText(R.id.ci_item_status, statusLabel(item.status, item.runName))
        views.setTextColor(R.id.ci_item_status, statusColor(item.status))
        return views
    }

    private fun statusLabel(status: String, runName: String): String {
        val icon = when (status) {
            "success" -> "\u2705"
            "failure" -> "\u26A0\uFE0F"
            "running" -> "\u23F3"
            else -> "\u2022"
        }
        return if (runName.isEmpty()) icon else "$icon $runName"
    }

    private fun statusColor(status: String): Int = when (status) {
        "success" -> 0xFF66BB6A.toInt()
        "failure" -> 0xFFEF5350.toInt()
        "running" -> 0xFFFFCA28.toInt()
        else -> 0xFFBDBDBD.toInt()
    }
}
