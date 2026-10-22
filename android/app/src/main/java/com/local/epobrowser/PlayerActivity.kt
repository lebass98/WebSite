package com.local.epobrowser

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.annotation.OptIn
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import com.local.epobrowser.data.SiteScraper
import com.local.epobrowser.net.Http
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 재생 화면: 최고 화질 파일을 찾아 자동 재생, 못 찾으면 사이트 플레이어 */
@OptIn(UnstableApi::class)
class PlayerActivity : ComponentActivity() {

    companion object {
        fun intent(context: Context, id: String, title: String, url: String, embed: String, fid: Int, site: Boolean = false) =
            Intent(context, PlayerActivity::class.java)
                .putExtra("id", id).putExtra("title", title).putExtra("url", url).putExtra("embed", embed).putExtra("fid", fid)
                .putExtra("site", site)
    }

    private lateinit var root: DoubleTapFrame
    private var player: ExoPlayer? = null
    private var fullScreen = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Http.init(this)
        root = DoubleTapFrame(this) { toggleFullScreen() }
        root.setBackgroundColor(0xFF000000.toInt())
        root.addView(ProgressBar(this), FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, android.view.Gravity.CENTER))
        setContentView(root)
        title = intent.getStringExtra("title")

        val pageUrl = intent.getStringExtra("url") ?: return finish()
        if (intent.getBooleanExtra("site", false)) { playEmbed(); return }
        lifecycleScope.launch {
            val best = runCatching {
                withContext(Dispatchers.IO) { SiteScraper.parseDownloadLinks(Http.get(pageUrl)) }.maxByOrNull { it.height }
            }.getOrNull()
            if (best == null) {
                Toast.makeText(this@PlayerActivity, "다운로드 링크가 없어서 사이트 플레이어로 열어요 (로그인 상태 확인)", Toast.LENGTH_LONG).show()
                playEmbed(); return@launch
            }
            // 다운로드 링크를 따라가 실제 파일 주소를 먼저 알아냄 (플레이어가 중간 주소에서 막히지 않게)
            val file = runCatching {
                withContext(Dispatchers.IO) {
                    val req = okhttp3.Request.Builder().url(best.url).header("Range", "bytes=0-0").header("Referer", Http.BASE + "/").build()
                    Http.client.newCall(req).execute().use { r ->
                        val type = r.header("Content-Type") ?: ""
                        if (type.startsWith("text/html")) throw IllegalStateException("파일 대신 웹 페이지가 왔어요")
                        r.request.url.toString()
                    }
                }
            }
            file.onSuccess { playNative(it, best.qualityText) }.onFailure {
                Toast.makeText(this@PlayerActivity, "파일 주소를 못 찾아서 사이트 플레이어로 열어요 (${it.message})", Toast.LENGTH_LONG).show()
                playEmbed()
            }
        }
    }

    private fun playNative(url: String, quality: String) {
        // 다운로드 링크는 실제 파일로 넘겨 주는 주소 (로그인 쿠키가 붙은 연결로 따라감)
        val source = OkHttpDataSource.Factory(Http.client)
            .setDefaultRequestProperties(mapOf("Referer" to Http.BASE + "/"))
        val exo = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(source))
            .build()
        player = exo
        val view = PlayerView(this).apply { this.player = exo; keepScreenOn = true }
        root.removeAllViews()
        root.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        exo.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                // 파일을 못 열면 이유를 알리고 사이트 플레이어로
                Toast.makeText(this@PlayerActivity, "앱 플레이어로 재생하지 못했어요 (${error.errorCodeName}). 사이트 플레이어로 바꿔요.", Toast.LENGTH_LONG).show()
                exo.release(); player = null
                playEmbed()
            }
        })
        exo.setMediaItem(MediaItem.fromUri(url))
        exo.playWhenReady = true   // 자동 재생
        exo.prepare()
        Toast.makeText(this, "$quality 재생", Toast.LENGTH_SHORT).show()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun playEmbed() {
        val embed = intent.getStringExtra("embed") ?: return
        val cm = CookieManager.getInstance()
        Http.cookies.all().forEach { c -> cm.setCookie("https://${c.domain}", "${c.name}=${c.value}; path=${c.path}") }
        val web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.userAgentString = Http.USER_AGENT
            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                // 광고 등 다른 페이지로 넘어가는 클릭은 막음
                override fun shouldOverrideUrlLoading(view: WebView, request: android.webkit.WebResourceRequest) = request.isForMainFrame && request.hasGesture()
                override fun onPageFinished(view: WebView, url: String) {
                    view.evaluateJavascript(
                        "(function(){var n=0;var t=setInterval(function(){n++;var v=document.querySelector('video');" +
                            "if(v){if(v.paused){var p=v.play();if(p)p.catch(function(){});}if(!v.paused||n>40)clearInterval(t);}" +
                            "else{var b=document.querySelector('.vjs-big-play-button');if(b)b.click();if(n>40)clearInterval(t);}},500);})();", null)
                }
            }
            loadUrl(embed)
        }
        root.removeAllViews()
        root.addView(web, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }

    /** 더블탭: 전체 화면(위·아래 막대 숨김) 켜기·끄기 */
    private fun toggleFullScreen() {
        fullScreen = !fullScreen
        val c = WindowInsetsControllerCompat(window, window.decorView)
        WindowCompat.setDecorFitsSystemWindows(window, !fullScreen)
        if (fullScreen) {
            c.hide(WindowInsetsCompat.Type.systemBars())
            c.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            c.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    override fun onStop() { super.onStop(); player?.pause() }
    override fun onDestroy() { super.onDestroy(); player?.release() }
}

/** 화면 아무 곳이나 더블탭을 알아챔 (한 번 탭은 아래 플레이어가 그대로 받음) */
class DoubleTapFrame(context: Context, private val onDoubleTap: () -> Unit) : FrameLayout(context) {
    private val detector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDoubleTap(e: MotionEvent): Boolean { onDoubleTap(); return true }
    })

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        detector.onTouchEvent(ev)
        return super.dispatchTouchEvent(ev)
    }
}
