package com.local.epobrowser.data

import org.json.JSONObject

/** 영상 한 개 (사이트 목록 카드에서 읽음) */
data class Video(
    val id: String,          // 주소 속 영상 코드
    val title: String,
    val url: String,
    val embed: String,
    val thumb: String,
    val lengthText: String,
    val lengthSec: Int,
    val views: Int,
    val rate: Double,        // 5점 만점
    val height: Int,         // 카드에 적힌 화질 (세로 픽셀, 0 = 모름)
    val fid: Int,            // 사이트 안 번호 (즐겨찾기 저장용)
    val previewUrl: String?, // 짧은 미리보기 영상
    val uploaderName: String? = null, // 올린 사람 (카드 아래 프로필 바로가기)
    val uploaderPath: String? = null,
) {
    val looksVR: Boolean get() = isVR(title)

    companion object {
        private val vrRegex = Regex("""(?<![a-z0-9])vr(?![a-z])|vr180|vr360|virtual reality|oculus|\bsbs\b""", RegexOption.IGNORE_CASE)
        fun isVR(text: String) = vrRegex.containsMatchIn(text)
    }
}

fun resolutionLabel(height: Int): String = when {
    height >= 2160 -> "4K"
    height >= 1440 -> "2K"
    else -> "${height}p"
}

/** 최근 본 영상 */
data class RecentVideo(
    val id: String, val title: String, val url: String, val embed: String,
    val thumb: String, val lengthText: String, val fid: Int, val watchedAt: Long,
) {
    fun toJson() = JSONObject().apply {
        put("id", id); put("title", title); put("url", url); put("embed", embed)
        put("thumb", thumb); put("lengthText", lengthText); put("fid", fid); put("watchedAt", watchedAt)
    }

    companion object {
        fun from(v: Video) = RecentVideo(v.id, v.title, v.url, v.embed, v.thumb, v.lengthText, v.fid, System.currentTimeMillis())
        fun fromJson(o: JSONObject) = RecentVideo(
            o.getString("id"), o.optString("title"), o.optString("url"), o.optString("embed"),
            o.optString("thumb"), o.optString("lengthText"), o.optInt("fid"), o.optLong("watchedAt"),
        )
    }
}

/** 플레이리스트·포르노스타·채널 목록의 한 칸 */
data class CollectionItem(val path: String, val title: String, val image: String, val subtitle: String)

enum class CollectionStyle { Playlist, Pornstar, Channel }

/** 목록 종류 (사이트 메뉴, 검색 종류, 내 계정 페이지) */
sealed class CollectionKind(val path: String, val title: String, val style: CollectionStyle) {
    data object Playlists : CollectionKind("/best-playlists/", "플레이리스트", CollectionStyle.Playlist)
    data object PornstarsFemale : CollectionKind("/pornstar-list/female/", "포르노스타 (여성)", CollectionStyle.Pornstar)
    data object PornstarsMale : CollectionKind("/pornstar-list/male/", "포르노스타 (남성)", CollectionStyle.Pornstar)
    data object Channels : CollectionKind("/channels/", "채널", CollectionStyle.Channel)
    class SearchPornstars(q: String) : CollectionKind("/search-pornstars/${Filters.slug(q)}/", "포르노스타 검색: $q", CollectionStyle.Pornstar)
    class SearchPlaylists(q: String) : CollectionKind("/search-playlists/${Filters.slug(q)}/", "플레이리스트 검색: $q", CollectionStyle.Playlist)
    class Custom(path: String, title: String, style: CollectionStyle) : CollectionKind(path, title, style)

    val paged get() = style != CollectionStyle.Channel
    val usesPornstarFilters get() = this == PornstarsFemale || this == PornstarsMale
    /** 그림 비율 (가로/세로) */
    val imageRatio get() = when (style) { CollectionStyle.Playlist -> 16f / 9; CollectionStyle.Pornstar -> 4f / 3; CollectionStyle.Channel -> 2f }
}

/** 전체 카테고리(A~Z)의 한 줄 */
data class TagItem(val name: String, val path: String, val count: String)

/** 다운로드 링크 */
data class DownloadLink(val label: String, val url: String) {
    val height: Int get() = SiteScraper.heights(url + " " + label).maxOrNull() ?: 0
    val qualityText get() = if (height > 0) resolutionLabel(height) else "알 수 없는 화질"
}

/** 계정 메뉴 한 칸 */
enum class UserPage(val label: String, val sub: String) {
    Profile("내 프로필", ""), Subscriptions("구독", "my/subscriptions/"), WatchLater("나중에 볼 영상", "watch-later/"),
    Favorites("즐겨찾기 영상", "favourite-videos/"), Watched("시청한 영상", "watched-videos/"),
    Uploaded("업로드한 영상", "uploaded-videos/"), Playlists("내 플레이리스트", "playlists/"), Settings("설정", "my/edit/");

    fun path(user: String) = "/profile/$user/$sub"
}

enum class SortOrder(val key: String, val label: String) {
    Latest("latest", "최신순"), MostViewed("most-viewed", "인기순"), TopRated("top-rated", "평점순"),
    TopWeekly("top-weekly", "이번 주 인기"), TopMonthly("top-monthly", "이번 달 인기"),
    Longest("longest", "긴 영상순"), Shortest("shortest", "짧은 영상순");

    /** 카테고리 페이지 (/cat/all/SORT-top-rated/) */
    val catSegment get() = if (this == Latest) "" else "SORT-$key"
    /** 검색(태그) 페이지 (/tag/taboo/top-rated/) */
    val tagSegment get() = if (this == Latest) "" else key
}

enum class Inclusion(val label: String) { Exclude("제외"), Include("포함"), Only("만 보기") }

/** 화질 (VR은 화질과 상관없이 따로) */
enum class Quality(val label: String, val siteValue: String?, val minHeight: Int) {
    All("전체", null, 0), P720("720p+", "720", 720), P1080("1080p+", "1080", 1080),
    K2("2K+", "1080", 1440), K4("4K", "2160", 2160), VR("VR", null, 0)
}
