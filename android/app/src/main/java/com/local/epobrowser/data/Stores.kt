package com.local.epobrowser.data

import android.content.Context
import org.json.JSONArray
import java.io.File

/** 최근 본 영상 (개수 제한 없이 전부 저장, 다시 보면 맨 위로) */
class RecentStore(context: Context) {
    private val file = File(context.filesDir, "recent.json")

    fun load(): List<RecentVideo> = runCatching {
        val arr = JSONArray(file.readText())
        (0 until arr.length()).map { RecentVideo.fromJson(arr.getJSONObject(it)) }
    }.getOrDefault(emptyList())

    fun save(items: List<RecentVideo>) {
        val arr = JSONArray()
        items.forEach { arr.put(it.toJson()) }
        file.writeText(arr.toString())
    }
}

/** 화면 설정 (썸네일 크기, 화면 모드) */
class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    var thumbWidth: Int
        get() = prefs.getInt("thumbWidth", 200)
        set(v) = prefs.edit().putInt("thumbWidth", v).apply()

    /** 재생 방법 (PlayerMode 순서: 앱, 사이트, 다른 앱, 매번 묻기) */
    var playerMode: Int
        get() = prefs.getInt("playerMode", 0)
        set(v) = prefs.edit().putInt("playerMode", v).apply()

    /** 0 = 시스템 설정, 1 = 라이트, 2 = 다크 */
    var themeMode: Int
        get() = prefs.getInt("themeMode", 0)
        set(v) = prefs.edit().putInt("themeMode", v).apply()
}
