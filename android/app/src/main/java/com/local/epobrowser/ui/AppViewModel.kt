package com.local.epobrowser.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.local.epobrowser.data.*
import com.local.epobrowser.net.Http
import com.local.epobrowser.net.Session
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 화면 (뒤로 가기는 이전 화면으로) */
sealed class Screen(val title: String) {
    data object Browse : Screen("영상")
    data class Videos(val name: String, val path: String) : Screen(name)
    data object Categories : Screen("카테고리")
    data object AllCategories : Screen("전체 카테고리")
    data class Collection(val kind: CollectionKind) : Screen(kind.title)
    data class User(val page: UserPage) : Screen(page.label)
    data class Web(val name: String, val url: String) : Screen(name)
}

enum class SearchType(val label: String) { Videos("영상"), Pornstars("포르노스타"), Playlists("플레이리스트") }

enum class LoginState { None, LoggingIn, LoggedIn, Failed }

/** 영상 목록 하나의 상태 */
class VideoListState(val source: Screen) {
    var videos = mutableStateListOf<Video>()
    var loading by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    var hasMore by mutableStateOf(true)
    var order by mutableStateOf(SortOrder.Latest)
    var category by mutableStateOf<SiteCategory?>(null)
    var gay by mutableStateOf(Inclusion.Exclude)
    var page = 0
    var job: Job? = null
    val sortable get() = source is Screen.Browse || (source is Screen.Videos && (source.path.startsWith("/cat/") || source.path.startsWith("/tag/")))
}

class CollectionState(val kind: CollectionKind) {
    var items = mutableStateListOf<CollectionItem>()
    var loading by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    var hasMore by mutableStateOf(true)
    var page = 0
    var job: Job? = null
}

class AppViewModel(app: Application) : AndroidViewModel(app) {
    init { Http.init(app) }

    val session = Session(app)
    private val recentStore = RecentStore(app)
    val settings = Settings(app)

    // ---------- 화면 이동 ----------
    val stack = mutableStateListOf<Screen>(Screen.Browse)
    val current get() = stack.last()
    fun open(screen: Screen) { stack.add(screen) }
    fun openRoot(screen: Screen) { stack.clear(); stack.add(screen) }
    fun back(): Boolean = if (stack.size > 1) { stack.removeAt(stack.lastIndex); true } else false

    // ---------- 검색·필터 ----------
    var searchText by mutableStateOf("")
        private set
    var searchType by mutableStateOf(SearchType.Videos)
    var draft by mutableStateOf(Filters())
    var applied by mutableStateOf(Filters())
        private set

    fun search(text: String, type: SearchType = searchType) {
        searchText = text.trim()
        searchType = type
        when (type) {
            SearchType.Videos -> { openRoot(Screen.Browse); reload(listFor(Screen.Browse)) }
            SearchType.Pornstars -> openRoot(Screen.Collection(if (searchText.isEmpty()) CollectionKind.PornstarsFemale else CollectionKind.SearchPornstars(searchText)))
            SearchType.Playlists -> openRoot(Screen.Collection(if (searchText.isEmpty()) CollectionKind.Playlists else CollectionKind.SearchPlaylists(searchText)))
        }
    }

    fun applyFilters() { applied = draft; videoLists.values.forEach { reload(it) } }
    fun clearFilters() { draft = Filters(); applyFilters() }
    fun toggleCategory(slug: String) {
        val list = draft.categories
        draft = draft.copy(categories = if (slug in list) list - slug else if (list.size < Filters.MAX_CATEGORIES) list + slug else list)
    }

    // ---------- 영상 목록 ----------
    private val videoLists = mutableMapOf<String, VideoListState>()

    fun listFor(screen: Screen): VideoListState {
        val key = when (screen) { is Screen.Videos -> screen.path; else -> "browse" }
        return videoLists.getOrPut(key) { VideoListState(screen) }
    }

    fun reload(s: VideoListState) {
        s.job?.cancel()
        s.videos.clear(); s.page = 0; s.hasMore = true; s.error = null; s.loading = false
        loadMore(s)
    }

    fun loadMore(s: VideoListState) {
        if (s.loading || !s.hasMore) return
        s.loading = true; s.error = null
        val next = s.page + 1
        val url = videoUrl(s, next)
        s.job = viewModelScope.launch {
            try {
                val html = withContext(Dispatchers.IO) { Http.get(url) }
                SiteScraper.csrfToken(html)?.let { session.csrfToken = it }
                val known = s.videos.map { it.id }.toSet()
                val fresh = SiteScraper.parseVideos(html).filter { it.id !in known }
                s.videos.addAll(fresh)
                s.page = next
                s.hasMore = fresh.isNotEmpty()
                s.loading = false
                // 앱에서 걸러 화면이 많이 비면 다음 페이지를 자동으로 (최대 3페이지)
                if (visible(s).size < 18 && s.hasMore && next < 4) loadMore(s)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                s.loading = false
                s.error = "사이트에 연결하지 못했어요. VPN이 켜져 있는지 확인해 주세요.\n(${e.message})"
            }
        }
    }

    /** 사이트가 거른 결과를 한 번 더 확인 (VR은 VR에서만, 다른 화질에는 VR 제외) */
    fun visible(s: VideoListState): List<Video> {
        val f = applied
        return s.videos.filter { v ->
            if (v.lengthSec / 60 < f.minMinutes) return@filter false
            if (f.maxMinutes < Filters.OPEN_MAX && v.lengthSec > f.maxMinutes * 60 + 59) return@filter false
            when (f.quality) {
                Quality.All, Quality.VR -> true
                else -> !v.looksVR && (v.height == 0 || v.height >= f.quality.minHeight)
            }
        }
    }

    private fun videoUrl(s: VideoListState, page: Int): String {
        val f = applied
        val include = f.categories.toMutableList()
        val exclude = mutableListOf<String>()
        val unexclude = mutableListOf<String>()
        var path: String
        var segment: String
        when (val src = s.source) {
            is Screen.Videos -> {
                path = src.path
                segment = when { path.startsWith("/cat/") -> s.order.catSegment; path.startsWith("/tag/") -> s.order.tagSegment; else -> "" }
            }
            else -> {
                if (searchText.isNotEmpty()) {
                    path = "/tag/${Filters.slug(searchText)}/"; segment = s.order.tagSegment
                    s.category?.let { include += it.slug }
                } else if (f.quality == Quality.VR) {
                    path = "/cat/vr-porn/"; segment = s.order.catSegment
                    s.category?.let { include += it.slug }
                } else {
                    path = s.category?.path ?: "/cat/all/"; segment = s.order.catSegment
                }
            }
        }
        if (f.quality == Quality.VR) {
            if (!path.startsWith("/cat/vr-porn/")) include += "vr-porn"
            unexclude += "vr-porn"
        } else if (f.quality != Quality.All) exclude += "vr-porn"
        when (s.gay) {
            Inclusion.Exclude -> {}
            Inclusion.Include -> unexclude += "gay"
            Inclusion.Only -> { include += "gay"; unexclude += "gay" }
        }
        val q = mutableListOf<Pair<String, String>>()
        f.quality.siteValue?.let { q += "quality" to it }
        if (f.minMinutes > 0) q += "duration_min_minutes" to "${f.minMinutes}"
        if (f.maxMinutes < Filters.OPEN_MAX) q += "duration_max_minutes" to "${f.maxMinutes}"
        if (include.isNotEmpty()) q += "include" to include.distinct().take(5).joinToString(",")
        if (exclude.isNotEmpty()) q += "exclude" to exclude.joinToString(",")
        if (unexclude.isNotEmpty()) q += "unexclude" to unexclude.joinToString(",")
        return SiteScraper.url(path, segment, page, q)
    }

    // ---------- 플레이리스트·포르노스타·채널 ----------
    private val collections = mutableMapOf<String, CollectionState>()
    var pornstarDraft by mutableStateOf(PornstarFilters())
    var pornstarApplied by mutableStateOf(PornstarFilters())
        private set
    val choiceFields = mutableStateListOf<ChoiceField>()

    fun collectionFor(kind: CollectionKind) = collections.getOrPut(kind.path) { CollectionState(kind) }

    fun reloadCollection(s: CollectionState) {
        s.job?.cancel(); s.items.clear(); s.page = 0; s.hasMore = true; s.error = null; s.loading = false
        loadMoreCollection(s)
    }

    fun loadMoreCollection(s: CollectionState) {
        if (s.loading || !s.hasMore) return
        s.loading = true; s.error = null
        val next = s.page + 1
        val url = SiteScraper.url(s.kind.path, page = next, query = if (s.kind.usesPornstarFilters) pornstarApplied.query() else emptyList())
        s.job = viewModelScope.launch {
            try {
                val html = withContext(Dispatchers.IO) { Http.get(url) }
                if (s.kind.usesPornstarFilters && choiceFields.isEmpty()) choiceFields.addAll(SiteScraper.parseChoiceFields(html))
                val known = s.items.map { it.path }.toSet()
                val fresh = SiteScraper.parseCollection(html, s.kind.style).filter { it.path !in known }
                s.items.addAll(fresh)
                s.page = next
                s.hasMore = fresh.isNotEmpty() && s.kind.paged
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                s.error = "목록을 불러오지 못했어요. VPN이 켜져 있는지 확인해 주세요."
            } finally {
                s.loading = false
            }
        }
    }

    fun applyPornstarFilters() {
        pornstarApplied = pornstarDraft
        collections.values.filter { it.kind.usesPornstarFilters }.forEach { reloadCollection(it) }
    }

    fun clearPornstarFilters() { pornstarDraft = PornstarFilters(inches = pornstarDraft.inches); applyPornstarFilters() }

    // ---------- 전체 카테고리 (A~Z) ----------
    var tagLetter by mutableStateOf("A")
    val tags = mutableStateListOf<TagItem>()
    var tagsLoading by mutableStateOf(false)
    private val tagCache = mutableMapOf<String, List<TagItem>>()
    var tagsError by mutableStateOf<String?>(null)
        private set
    private var tagsJob: Job? = null
    private var tagsRequest = 0

    fun loadTags(letter: String) {
        tagsJob?.cancel()
        val request = ++tagsRequest
        tagLetter = letter
        tagsError = null
        tagsLoading = false
        tagCache[letter]?.let { tags.clear(); tags.addAll(it); return }
        tagsLoading = true; tags.clear()
        tagsJob = viewModelScope.launch {
            try {
                val found = withContext(Dispatchers.IO) { SiteScraper.parseTags(Http.get("${Http.BASE}/cats/$letter/")) }
                tagCache[letter] = found
                tags.clear(); tags.addAll(found)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                tagsError = "카테고리를 불러오지 못했어요. 연결을 확인한 뒤 다시 시도하세요."
            } finally {
                if (tagsRequest == request) tagsLoading = false
            }
        }
    }

    // ---------- 내 계정 페이지: 영상 목록인지 다른 목록인지 열어 보고 판단 ----------
    fun openUserPage(page: UserPage) {
        val user = userName ?: return
        val path = page.path(user)
        if (page == UserPage.Profile || page == UserPage.Settings) { open(Screen.Web(page.label, Http.BASE + path)); return }
        viewModelScope.launch {
            val html = runCatching { withContext(Dispatchers.IO) { Http.get(Http.BASE + path) } }.getOrDefault("")
            val screen = when {
                SiteScraper.parseVideos(html).isNotEmpty() -> Screen.Videos(page.label, path).also { videoLists.remove(path) }
                SiteScraper.parseCollection(html, CollectionStyle.Playlist).isNotEmpty() -> Screen.Collection(CollectionKind.Custom(path, page.label, CollectionStyle.Playlist))
                SiteScraper.parseCollection(html, CollectionStyle.Pornstar).isNotEmpty() -> Screen.Collection(CollectionKind.Custom(path, page.label, CollectionStyle.Pornstar))
                SiteScraper.parseCollection(html, CollectionStyle.Channel).isNotEmpty() -> Screen.Collection(CollectionKind.Custom(path, page.label, CollectionStyle.Channel))
                else -> Screen.Web(page.label, Http.BASE + path)   // 비어 있거나 다른 형식이면 사이트 화면
            }
            openRoot(screen)
        }
    }

    // ---------- 로그인 ----------
    var loginState by mutableStateOf(LoginState.None)
    var loginMessage by mutableStateOf<String?>(null)
    var userName by mutableStateOf<String?>(null)
    val playlists = mutableStateListOf<CollectionItem>()

    fun login(user: String? = null, pass: String? = null) {
        if (user != null && pass != null) session.save(user, pass)
        loginState = LoginState.LoggingIn; loginMessage = null
        viewModelScope.launch {
            val r = runCatching { withContext(Dispatchers.IO) { session.login() } }
                .getOrElse { Session.Result.Failed("사이트에 연결하지 못했어요. VPN이 켜져 있는지 확인해 주세요.") }
            when (r) {
                is Session.Result.Ok -> { loginState = LoginState.LoggedIn; userName = r.userName; loadPlaylists() }
                is Session.Result.Failed -> { loginState = LoginState.Failed; loginMessage = r.message }
                Session.Result.NoCredentials -> loginState = LoginState.None
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { session.logout() }
            loginState = LoginState.None; userName = null; playlists.clear()
        }
    }

    private fun loadPlaylists() {
        val user = userName ?: return
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { Http.get(Http.BASE + UserPage.Playlists.path(user)) } }.onSuccess { html ->
                val items = Regex("""<div class="mb mbplaylist" id="pl(\d+)">[\s\S]*?class="mbtitphoto2">([^<]+)<""").findAll(html)
                    .map { CollectionItem("pl-" + it.groupValues[1], SiteScraper.decode(it.groupValues[2]), "", "") }.toList()
                playlists.clear(); playlists.addAll(items)
            }
        }
    }

    /** list: favorite / watch-later / pl-번호 */
    fun changeList(fid: Int, list: String, label: String, add: Boolean, toast: (String) -> Unit) {
        if (loginState != LoginState.LoggedIn) { toast("로그인해야 쓸 수 있어요."); return }
        if (fid <= 0) { toast("이 영상의 사이트 번호를 몰라서 저장할 수 없어요."); return }
        viewModelScope.launch {
            val ok = runCatching { withContext(Dispatchers.IO) { session.manageList(fid, list, add) } }.getOrDefault(false)
            toast(if (!ok) "$label 저장에 실패했어요." else if (add) "${label}에 넣었어요" else "${label}에서 뺐어요")
            if (ok) videoLists.keys.filter { it.startsWith("/profile/") }.forEach { videoLists.remove(it) }
        }
    }

    // ---------- 최근 본 영상 ----------
    val recent = mutableStateListOf<RecentVideo>().apply { addAll(recentStore.load()) }

    fun markWatched(v: Video) = markWatched(RecentVideo.from(v))
    fun markWatched(r: RecentVideo) {
        recent.removeAll { it.id == r.id }
        recent.add(0, r.copy(watchedAt = System.currentTimeMillis()))
        recentStore.save(recent)
    }
    fun removeRecent(id: String) { recent.removeAll { it.id == id }; recentStore.save(recent) }
    fun clearRecent() { recent.clear(); recentStore.save(recent) }
    fun watched(id: String) = recent.any { it.id == id }

    // ---------- 화면 설정 ----------
    var thumbWidth by mutableStateOf(settings.thumbWidth)
        private set
    fun setThumb(w: Int) { thumbWidth = w; settings.thumbWidth = w }
    var themeMode by mutableStateOf(settings.themeMode)
        private set
    fun cycleTheme() { themeMode = (themeMode + 1) % 3; settings.themeMode = themeMode }

    // ---------- 재생 방법 ----------
    var playerMode by mutableStateOf(PlayerMode.entries.getOrElse(settings.playerMode) { PlayerMode.App })
        private set
    fun setPlayer(m: PlayerMode) { playerMode = m; settings.playerMode = m.ordinal }
    /** "매번 묻기"일 때 고르는 창에 띄울 영상 */
    var askPlay by mutableStateOf<PlayRequest?>(null)

    /** 영상 열기: 정해 둔 재생 방법대로 (mode를 주면 그 방법으로) */
    fun play(context: android.content.Context, r: PlayRequest, mode: PlayerMode = playerMode) {
        when (mode) {
            PlayerMode.Ask -> askPlay = r
            PlayerMode.App -> openPlayer(context, r, site = false)
            PlayerMode.Site -> openPlayer(context, r, site = true)
            PlayerMode.External -> viewModelScope.launch {
                val app = context.applicationContext
                android.widget.Toast.makeText(app, "최고 화질 파일 주소 찾는 중…", android.widget.Toast.LENGTH_SHORT).show()
                val best = runCatching { downloadLinks(r.url) }.getOrDefault(emptyList()).maxByOrNull { it.height }
                if (best == null) {
                    android.widget.Toast.makeText(app, "다운로드 링크가 없어서 다른 앱으로 열 수 없어요. 로그인 상태를 확인해 주세요.", android.widget.Toast.LENGTH_LONG).show()
                    return@launch
                }
                val file = runCatching { resolveFileUrl(best.url) }.getOrDefault(best.url)
                openExternal(app, file, r.title)
            }
        }
    }

    /** 다운로드 링크를 따라가서 실제 파일 주소를 알아냄 (파일 전체는 받지 않음) */
    suspend fun resolveFileUrl(link: String): String = withContext(Dispatchers.IO) {
        val req = okhttp3.Request.Builder().url(link).header("Range", "bytes=0-0").header("Referer", Http.BASE + "/").build()
        Http.client.newCall(req).execute().use { it.request.url.toString() }
    }

    // ---------- 다운로드 주소 ----------
    suspend fun downloadLinks(pageUrl: String): List<DownloadLink> = withContext(Dispatchers.IO) {
        SiteScraper.parseDownloadLinks(Http.get(pageUrl))
    }
}
