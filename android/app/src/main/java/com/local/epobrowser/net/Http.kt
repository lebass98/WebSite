package com.local.epobrowser.net

import android.content.Context
import android.content.SharedPreferences
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/** 앱 전체가 함께 쓰는 연결 (로그인 쿠키가 저장되고 다음 실행에도 유지됨) */
object Http {
    const val BASE = "https://www.eporner.com"
    const val USER_AGENT = "Mozilla/5.0 (Linux; Android 15; Tablet) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

    lateinit var client: OkHttpClient
        private set
    lateinit var cookies: PersistentCookieJar
        private set

    fun init(context: Context) {
        if (::client.isInitialized) return
        cookies = PersistentCookieJar(context.getSharedPreferences("cookies", Context.MODE_PRIVATE))
        client = OkHttpClient.Builder()
            .cookieJar(cookies)
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                chain.proceed(chain.request().newBuilder().header("User-Agent", USER_AGENT).build())
            }
            .build()
    }

    /** 페이지 HTML 받기 (404는 빈 문자열 = 마지막 페이지 다음) */
    fun get(url: String): String {
        client.newCall(Request.Builder().url(url).build()).execute().use { res ->
            if (res.code == 404) return ""
            if (!res.isSuccessful) throw IOException("서버 응답 코드 ${res.code}")
            return res.body?.string() ?: ""
        }
    }
}

/** 쿠키를 휴대폰에 저장해서 로그인이 유지되게 */
class PersistentCookieJar(private val prefs: SharedPreferences) : CookieJar {
    private val store = mutableMapOf<String, Cookie>()

    init {
        val raw = prefs.getString("all", null)
        if (raw != null) runCatching {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val c = Cookie.Builder().name(o.getString("n")).value(o.getString("v"))
                    .domain(o.getString("d")).path(o.getString("p")).expiresAt(o.getLong("e"))
                    .apply { if (o.optBoolean("s")) secure(); if (o.optBoolean("h")) httpOnly() }.build()
                store[key(c)] = c
            }
        }
    }

    private fun key(c: Cookie) = "${c.domain}|${c.path}|${c.name}"

    @Synchronized override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        cookies.forEach { store[key(it)] = it }
        persist()
    }

    @Synchronized override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val now = System.currentTimeMillis()
        store.values.removeAll { it.expiresAt < now }
        return store.values.filter { it.matches(url) }
    }

    @Synchronized fun all(): List<Cookie> = store.values.toList()

    @Synchronized fun clear() { store.clear(); persist() }

    private fun persist() {
        val arr = JSONArray()
        store.values.forEach {
            arr.put(JSONObject().put("n", it.name).put("v", it.value).put("d", it.domain).put("p", it.path)
                .put("e", it.expiresAt).put("s", it.secure).put("h", it.httpOnly))
        }
        prefs.edit().putString("all", arr.toString()).apply()
    }
}
