package com.local.epobrowser.net

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.local.epobrowser.data.SiteScraper
import okhttp3.FormBody
import okhttp3.Request
import org.json.JSONObject

/** 로그인 (사이트 로그인 창과 같은 방식: /xhr/login/ + 보안 값) */
class Session(context: Context) {
    // 아이디·비밀번호는 휴대폰 안의 암호화된 저장소에 보관
    private val secure = EncryptedSharedPreferences.create(
        context, "login",
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    var savedUser: String?
        get() = secure.getString("user", null)
        private set(v) { secure.edit().putString("user", v).apply() }

    private var savedPass: String?
        get() = secure.getString("pass", null)
        set(v) { secure.edit().putString("pass", v).apply() }

    /** 가장 최근에 읽은 페이지의 보안 값 */
    @Volatile var csrfToken: String? = null

    fun save(user: String, pass: String) { savedUser = user; savedPass = pass }

    fun forget() { secure.edit().clear().apply() }

    sealed class Result {
        data class Ok(val userName: String?) : Result()
        data class Failed(val message: String) : Result()
        data object NoCredentials : Result()
    }

    /** 저장된 쿠키로 이미 로그인돼 있으면 그대로, 아니면 저장된 정보로 로그인 (백그라운드에서 부를 것) */
    fun login(): Result {
        val home = Http.get(Http.BASE + "/")
        csrfToken = SiteScraper.csrfToken(home)
        if (SiteScraper.isLoggedIn(home)) return Result.Ok(SiteScraper.userName(home))

        val user = savedUser ?: return Result.NoCredentials
        val pass = savedPass ?: return Result.NoCredentials
        val body = FormBody.Builder().add("xhr", "1").add("act", "login").add("login", user).add("pass", pass).add("ref", "/").build()
        val req = Request.Builder().url(Http.BASE + "/xhr/login/").post(body)
            .header("X-Requested-With", "XMLHttpRequest")
            .header("X-CSRF-TOKEN", csrfToken ?: "")
            .header("Referer", Http.BASE + "/")
            .header("Origin", Http.BASE)
            .build()
        val text = Http.client.newCall(req).execute().use { it.body?.string() ?: "" }
        val json = runCatching { JSONObject(text) }.getOrNull()
        val status = json?.optString("status")
        if (status != "1") {
            val reason = listOf(json?.optString("msg_head"), json?.optString("msg_body"))
                .filterNot { it.isNullOrBlank() }.joinToString(" ") { SiteScraper.decode(it!!.replace(Regex("<[^>]+>"), "")) }
            return Result.Failed(if (reason.isBlank()) "로그인하지 못했어요. 아이디·비밀번호를 확인해 주세요." else "사이트 응답: $reason")
        }
        val after = Http.get(Http.BASE + "/")
        csrfToken = SiteScraper.csrfToken(after) ?: csrfToken
        return if (SiteScraper.isLoggedIn(after)) Result.Ok(SiteScraper.userName(after) ?: user)
        else Result.Failed("로그인은 됐다고 나왔는데 확인이 안 돼요. 다시 시도해 주세요.")
    }

    fun logout() {
        runCatching { Http.get(Http.BASE + "/logout/") }
        Http.cookies.clear()
    }

    /** 즐겨찾기·나중에 볼 영상·플레이리스트에 넣기/빼기 (/manage-list/) */
    fun manageList(fid: Int, list: String, add: Boolean): Boolean {
        if (csrfToken == null) csrfToken = SiteScraper.csrfToken(Http.get(Http.BASE + "/"))
        val body = FormBody.Builder().add("type", "video").add("fid", fid.toString()).add("list", list)
            .add("action", if (add) "add" else "remove").build()
        val req = Request.Builder().url(Http.BASE + "/manage-list/").post(body)
            .header("X-Requested-With", "XMLHttpRequest")
            .header("X-CSRF-TOKEN", csrfToken ?: "")
            .header("Referer", Http.BASE + "/")
            .build()
        val text = Http.client.newCall(req).execute().use { it.body?.string() ?: "" }
        return Regex(""""status"\s*:\s*"?1""").containsMatchIn(text)
    }
}
