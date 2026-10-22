package com.local.epobrowser.data

import com.local.epobrowser.net.Http
import java.net.URLEncoder

/** 사이트 페이지(HTML)를 읽어 영상·목록을 꺼냄 (맥 앱과 같은 방식) */
object SiteScraper {
    const val BASE = Http.BASE

    fun url(path: String, segment: String = "", page: Int = 1, query: List<Pair<String, String>> = emptyList()): String {
        var s = BASE + path
        if (segment.isNotEmpty()) s += "$segment/"
        if (page > 1) s += "$page/"
        if (query.isNotEmpty()) s += "?" + query.joinToString("&") { (k, v) ->
            URLEncoder.encode(k, "UTF-8") + "=" + URLEncoder.encode(v, "UTF-8")
        }
        return s
    }

    // ---------- 영상 카드 ----------

    fun parseVideos(html: String): List<Video> = blocks(html, Regex("""<div class="mb[ "][^>]*data-id=""")).mapNotNull { b ->
        val hash = first("""href="/video-([A-Za-z0-9]+)/""", b) ?: return@mapNotNull null
        val link = first("""href="(/video-[^"]+)"""", b) ?: return@mapNotNull null
        val title = decode(first("""class="mbtit"><a[^>]*>([^<]*)</a>""", b) ?: first("""alt="([^"]*)"""", b) ?: "")
        val thumb = (first("""data-src="(https?://[^"]+)"""", b) ?: first("""src="(https?://[^"]+)"""", b) ?: "").replace("&amp;", "&")
        val length = first("""class="mbtim"[^>]*>([^<]+)<""", b) ?: ""
        val rating = first("""class="mbrate"[^>]*>(\d+)%""", b)?.toDoubleOrNull() ?: 0.0
        val views = first("""class="mbvie"[^>]*>([\d,]+)<""", b)?.replace(",", "")?.toIntOrNull() ?: 0
        val quality = first("""class="mvhdico"[^>]*><span>([^<]+)</span>""", b) ?: ""
        val fid = first("""data-id="(\d+)"""", b)?.toIntOrNull() ?: 0
        // data-vp="번호|…": 번호 > 0 이면 썸네일 폴더에 번호-preview.mp4 가 있음
        val vp = first("""data-vp="(\d+)\|""", b)?.toIntOrNull() ?: 0
        val preview = if (vp > 0 && thumb.contains('/')) thumb.substringBeforeLast('/') + "/$vp-preview.mp4" else null
        Video(
            id = hash, title = title, url = BASE + link, embed = "$BASE/embed/$hash/", thumb = thumb,
            lengthText = length, lengthSec = length.split(":").mapNotNull { it.toIntOrNull() }.fold(0) { a, x -> a * 60 + x },
            views = views, rate = rating / 20, height = heightFromBadge(quality), fid = fid,
            previewUrl = preview?.replace("static-key-cdn", "static-ca-cdn"),
            uploaderName = first("""class="mb-uploader"><a [^>]*>([^<]+)</a>""", b)?.let { decode(it) },
            uploaderPath = first("""class="mb-uploader"><a href="(/profile/[^"]+)""", b),
        )
    }

    fun heightFromBadge(text: String): Int {
        val t = text.uppercase()
        return when {
            "4K" in t || "2160" in t -> 2160
            "2K" in t || "1440" in t -> 1440
            else -> t.filter { it.isDigit() }.toIntOrNull() ?: 0
        }
    }

    private val known = setOf(2160, 1440, 1080, 720, 480, 360, 240)
    fun heights(text: String): List<Int> =
        Regex("""(?<![0-9])(2160|1440|1080|720|480|360|240)p?(?![0-9])""").findAll(text)
            .mapNotNull { it.groupValues[1].toIntOrNull() }.filter { it in known }.toList()

    // ---------- 플레이리스트·포르노스타·채널 ----------

    fun parseCollection(html: String, style: CollectionStyle): List<CollectionItem> = when (style) {
        CollectionStyle.Playlist -> blocks(html, Regex("""<div class="mb mbplaylist"""")).mapNotNull { b ->
            val path = first("""<a href="(/[^"]+/playlist/[^"]+)"""", b) ?: return@mapNotNull null
            CollectionItem(path, decode(first("""class="mbtitphoto2">([^<]+)<""", b) ?: ""),
                first("""src="(https?://[^"]+)"""", b) ?: "", first("""mbphoto2_playlistico">(\d+)<""", b)?.let { "영상 ${it}개" } ?: "")
        }
        CollectionStyle.Pornstar -> blocks(html, Regex("""<div class="mbprofile">""")).mapNotNull { b ->
            val path = first("""href="(/pornstar/[^"]+)"""", b) ?: return@mapNotNull null
            CollectionItem(path, decode(first("""title="([^"]+)"""", b) ?: ""),
                first("""src="(https?://[^"]+)"""", b) ?: "", first("""Videos: </span>([\d,]+)""", b)?.let { "영상 ${it}개" } ?: "")
        }
        CollectionStyle.Channel -> blocks(html, Regex("""<div class="channelscategoriesbox"""")).mapNotNull { b ->
            val path = first("""href="(/channel/[^"]+)"""", b) ?: return@mapNotNull null
            CollectionItem(path, decode(first("""<h2>([^<]+)</h2>""", b) ?: ""),
                first("""class="cclogo" src="([^"]+)"""", b) ?: "", first("""<span>([\d,]+)</span> Videos""", b)?.let { "영상 ${it}개" } ?: "")
        }
    }

    // ---------- 전체 카테고리, 포르노스타 필터 항목, 다운로드 링크 ----------

    fun parseTags(html: String): List<TagItem> {
        val start = html.indexOf("class=\"allcatslist\"").takeIf { it >= 0 } ?: return emptyList()
        return Regex("""<a href="(/tag/[^"]+)">([^<]+)</a><span>([^<]*)</span>""").findAll(html.substring(start))
            .map { TagItem(decode(it.groupValues[2]), it.groupValues[1], it.groupValues[3]) }.toList()
    }

    private val choiceLabels = mapOf("cup" to "컵", "hair" to "머리색", "country" to "국가", "ethnicity" to "인종", "eye" to "눈 색")

    fun parseChoiceFields(html: String): List<ChoiceField> =
        Regex("""<select[^>]*name="([a-z]+)\[\]"[^>]*>([\s\S]*?)</select>""").findAll(html).map { m ->
            val name = m.groupValues[1]
            val options = Regex("""<option[^>]*value="([^"]+)"[^>]*>([^<]*)<""").findAll(m.groupValues[2])
                .map { decode(it.groupValues[1]) to decode(it.groupValues[2]) }.toList()
            ChoiceField(name, choiceLabels[name] ?: name, options)
        }.toList()

    fun parseDownloadLinks(html: String): List<DownloadLink> {
        val seen = mutableSetOf<String>()
        return Regex("""<a[^>]+href="([^"]*/dload/[^"]+)"[^>]*>([\s\S]*?)</a>""").findAll(html).mapNotNull { m ->
            val href = m.groupValues[1].replace("&amp;", "&").let { if (it.startsWith("http")) it else BASE + it }
            if (!seen.add(href)) return@mapNotNull null
            val label = decode(m.groupValues[2].replace(Regex("<[^>]+>"), " ").replace(Regex("\\s+"), " "))
            DownloadLink(label.ifBlank { href.substringAfterLast('/') }, href)
        }.toList()
    }

    /** 페이지에 들어 있는 보안 값 (요청마다 X-CSRF-TOKEN 으로 보냄) */
    fun csrfToken(html: String) = first("""EP\.user\.csrfToken\s*=\s*'([a-f0-9]+)'""", html)
    fun isLoggedIn(html: String) = Regex("""EP\.user\.logged\s*=\s*true""").containsMatchIn(html)
    fun userName(html: String) = first("""EP\.user\.login\s*=\s*'([^']+)'""", html)
        ?: first("""href="/profile/([^/"]+)/"[^>]*>\s*(?:My profile|View profile)""", html)

    // ---------- 글자 처리 ----------

    private fun blocks(html: String, start: Regex): List<String> {
        val starts = start.findAll(html).map { it.range.first }.toList()
        return starts.mapIndexed { i, s -> html.substring(s, if (i + 1 < starts.size) starts[i + 1] else minOf(html.length, s + 6000)) }
    }

    fun first(pattern: String, text: String): String? = Regex(pattern).find(text)?.let { m ->
        if (m.groupValues.size > 1) m.groupValues[1] else m.value
    }

    fun decode(s: String): String {
        var out = s.replace("&amp;", "&").replace("&quot;", "\"").replace("&#039;", "'").replace("&#39;", "'")
            .replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ")
        out = Regex("&#(\\d+);").replace(out) { it.groupValues[1].toIntOrNull()?.let { c -> String(Character.toChars(c)) } ?: it.value }
        return out.trim()
    }
}
