package com.local.epobrowser.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.local.epobrowser.PlayerActivity
import com.local.epobrowser.data.*
import com.local.epobrowser.net.Http
import kotlinx.coroutines.launch

// ================= 영상 목록 =================

@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoListScreen(vm: AppViewModel, s: VideoListState, size: LayoutSize) {
    val context = LocalContext.current
    var actionsFor by remember { mutableStateOf<Video?>(null) }
    var showAllCats by remember { mutableStateOf(false) }
    LaunchedEffect(s) { if (s.videos.isEmpty() && !s.loading) vm.reload(s) }
    val visible = vm.visible(s)

    Column(Modifier.fillMaxSize()) {
        // 위쪽 줄: 정렬·카테고리·게이·All Categories·썸네일 크기 (좁은 화면에서는 옆으로 밀어서 봄)
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
        ) {
            if (s.sortable) Dropdown("정렬", s.order.label, SortOrder.entries.map { it.label }) { s.order = SortOrder.entries[it]; vm.reload(s) }
            if (s.source is Screen.Browse) Dropdown("카테고리", s.category?.name ?: "전체", listOf("전체") + SiteCategory.all.map { it.name }) {
                s.category = if (it == 0) null else SiteCategory.all[it - 1]; vm.reload(s)
            }
            Dropdown("게이", s.gay.label, Inclusion.entries.map { it.label }) { s.gay = Inclusion.entries[it]; vm.reload(s) }
            AssistChip(onClick = { showAllCats = true }, label = { Text("전체 카테고리") }, leadingIcon = { Icon(Icons.Default.List, null) })
            Icon(Icons.Default.PhotoSizeSelectSmall, "썸네일 크기", Modifier.size(18.dp))
            Slider(value = vm.thumbWidth.toFloat(), onValueChange = { vm.setThumb(it.toInt()) }, valueRange = 120f..420f, modifier = Modifier.width(140.dp))
        }
        HorizontalDivider()

        when {
            s.error != null && s.videos.isEmpty() -> Message(s.error!!, retry = { vm.reload(s) })
            visible.isEmpty() && (s.loading || s.hasMore && s.videos.isEmpty()) -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            visible.isEmpty() -> Message(
                "조건에 맞는 영상이 없어요. 검색어나 세부 필터를 바꿔보세요.",
                if (s.hasMore) ({ vm.loadMore(s) }) else if (!vm.applied.isDefault) ({ vm.clearFilters() }) else null,
                if (s.hasMore) "더 찾아보기" else "세부 필터 초기화",
            )
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(vm.thumbWidth.dp),
                contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(visible, key = { it.id }) { v ->
                    VideoCard(v, watched = vm.watched(v.id), onClick = {
                        vm.markWatched(v)
                        vm.play(context, PlayRequest(v.id, v.title, v.url, v.embed, v.fid))
                    }, onLongClick = { actionsFor = v }, onUploader = { name, path ->
                        vm.open(Screen.Videos("$name 업로드 영상", path + "uploaded-videos/"))
                    })
                    // 끝에 가까워지면 다음 페이지 자동으로
                    if (v.id == visible.last().id) LaunchedEffect(v.id) { vm.loadMore(s) }
                }
                if (s.loading) item(span = { GridItemSpan(maxLineSpan) }) {
                    Box(Modifier.fillMaxWidth().padding(16.dp), Alignment.Center) { CircularProgressIndicator() }
                } else if (s.error != null) item(span = { GridItemSpan(maxLineSpan) }) {
                    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(s.error!!, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        TextButton(onClick = { vm.loadMore(s) }) { Text("이어서 불러오기") }
                    }
                }
            }
        }
    }

    actionsFor?.let { v -> VideoActionsSheet(vm, v) { actionsFor = null } }
    if (showAllCats) ModalBottomSheet(onDismissRequest = { showAllCats = false }) {
        Box(Modifier.fillMaxHeight(0.85f)) {
            AllCategoriesScreen(vm) { showAllCats = false; vm.open(Screen.Videos(it.name, it.path)) }
        }
    }
}

@Composable
private fun Dropdown(label: String, value: String, options: List<String>, onPick: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        AssistChip(onClick = { open = true }, label = { Text("$label: $value", maxLines = 1) }, trailingIcon = { Icon(Icons.Default.ArrowDropDown, null) })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.heightIn(max = 420.dp)) {
            options.forEachIndexed { i, o -> DropdownMenuItem(text = { Text(o) }, onClick = { open = false; onPick(i) }) }
        }
    }
}

@Composable
fun Message(text: String, retry: (() -> Unit)?, actionLabel: String = "다시 시도") {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Default.Info, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(16.dp))
        Text(text, style = MaterialTheme.typography.bodyLarge,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (retry != null) { Spacer(Modifier.height(16.dp)); Button(onClick = retry) { Text(actionLabel) } }
    }
}

@kotlin.OptIn(ExperimentalFoundationApi::class)
@Composable
fun VideoCard(v: Video, watched: Boolean, onClick: () -> Unit, onLongClick: () -> Unit, onUploader: (String, String) -> Unit = { _, _ -> }) {
    Column(Modifier.clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surface)
        .combinedClickable(onClick = onClick, onLongClick = onLongClick).padding(10.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9).clip(RoundedCornerShape(8.dp)).background(Color.Gray.copy(alpha = 0.2f))) {
            AsyncImage(v.thumb, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            Row(Modifier.padding(5.dp).align(Alignment.TopStart), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (watched) Badge("봤음", Color.Gray)
                if (v.looksVR) Badge("VR", Color(0xFFFF9800))
                if (v.height > 0) Badge(resolutionLabel(v.height), if (v.height >= 1440) Color(0xFF8E24AA) else Color(0xFF1E88E5))
            }
            Text(v.lengthText, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.BottomEnd).padding(5.dp).background(Color.Black.copy(alpha = 0.7f), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp))
        }
        Text(v.title, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
        Column {
            Text("조회 ${v.views}  ★ ${"%.1f".format(v.rate)}", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            // 올린 사람 프로필 바로가기
            if (v.uploaderName != null && v.uploaderPath != null) {
                Row(
                    Modifier.padding(start = 6.dp).clip(RoundedCornerShape(4.dp))
                        .clickable { onUploader(v.uploaderName, v.uploaderPath) }.padding(horizontal = 4.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Default.AccountCircle, "올린 사람", Modifier.size(13.dp), tint = MaterialTheme.colorScheme.primary)
                    Text(v.uploaderName, fontSize = 11.sp, color = MaterialTheme.colorScheme.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun Badge(text: String, color: Color) {
    Text(text, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.background(color, RoundedCornerShape(4.dp)).padding(horizontal = 4.dp, vertical = 1.dp))
}

/** 길게 누르면 뜨는 창: 미리보기 영상·다운로드 주소·즐겨찾기 등 */
@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoActionsSheet(vm: AppViewModel, v: Video, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var links by remember { mutableStateOf<List<DownloadLink>?>(null) }
    var busy by remember { mutableStateOf(false) }
    val toast: (String) -> Unit = { Toast.makeText(context, it, Toast.LENGTH_SHORT).show() }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().heightIn(max = 640.dp).verticalScrollCompat().navigationBarsPadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(v.title, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            v.previewUrl?.let { PreviewVideo(it) }
            // 재생 방법을 골라서 재생
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(PlayerMode.App to "앱 플레이어", PlayerMode.Site to "사이트", PlayerMode.External to "다른 앱").forEach { (m, label) ->
                    FilledTonalButton(onClick = {
                        vm.markWatched(v); onDismiss(); vm.play(context, PlayRequest(v.id, v.title, v.url, v.embed, v.fid), m)
                    }, modifier = Modifier.weight(1f)) { Text(label, maxLines = 1, fontSize = 12.sp) }
                }
            }
            TextButton(enabled = !busy, onClick = {
                busy = true
                scope.launch {
                    val found = runCatching { vm.downloadLinks(v.url) }.getOrDefault(emptyList())
                    busy = false
                    val best = found.maxByOrNull { it.height }
                    if (best == null) toast("다운로드 링크가 없어요. 로그인 상태를 확인해 주세요.")
                    else { copy(context, best.url); toast("${best.qualityText} 다운로드 주소를 복사했어요") }
                }
            }) { Text(if (busy) "찾는 중…" else "다운로드 주소 복사 (최고 화질)") }
            TextButton(enabled = !busy, onClick = {
                busy = true
                scope.launch {
                    try { links = vm.downloadLinks(v.url) }
                    catch (e: kotlinx.coroutines.CancellationException) { throw e }
                    catch (e: Exception) { links = emptyList() }
                    finally { busy = false }
                }
            }) { Text("화질 골라서 복사…") }
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            links?.let { list ->
                if (list.isEmpty()) Text("주소를 찾지 못했어요. 로그인과 연결 상태를 확인하고 다시 시도하세요.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                list.sortedByDescending { it.height }.forEach { l ->
                    OutlinedButton(onClick = { copy(context, l.url); toast("${l.qualityText} 주소를 복사했어요") }, modifier = Modifier.fillMaxWidth()) {
                        Text("${l.qualityText} · ${l.label}", maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            HorizontalDivider()
            SaveRow(vm, v.fid, "favorite", "즐겨찾기", toast)
            SaveRow(vm, v.fid, "watch-later", "나중에 볼 영상", toast)
            vm.playlists.forEach { p -> SaveRow(vm, v.fid, p.path, "플레이리스트 ‘${p.title}’", toast) }
            HorizontalDivider()
            TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(v.url))) }) { Text("브라우저에서 열기") }
            TextButton(onClick = { copy(context, v.url); toast("링크를 복사했어요") }) { Text("링크 복사") }
        }
    }
}

@Composable
private fun SaveRow(vm: AppViewModel, fid: Int, list: String, label: String, toast: (String) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        TextButton(onClick = { vm.changeList(fid, list, label, true, toast) }) { Text("넣기") }
        TextButton(onClick = { vm.changeList(fid, list, label, false, toast) }) { Text("빼기") }
    }
}

@Composable
private fun Modifier.verticalScrollCompat() = this.verticalScroll(rememberScrollState())

fun copy(context: Context, text: String) {
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("url", text))
}

/** 소리 없이 반복되는 짧은 미리보기 영상 */
@OptIn(UnstableApi::class)
@Composable
fun PreviewVideo(url: String) {
    val context = LocalContext.current
    val player = remember(url) {
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(OkHttpDataSource.Factory(Http.client)))
            .build().apply {
                volume = 0f; repeatMode = Player.REPEAT_MODE_ONE; playWhenReady = true
                setMediaItem(MediaItem.fromUri(url)); prepare()
            }
    }
    DisposableEffect(player) { onDispose { player.release() } }
    AndroidView(
        factory = { PlayerView(it).apply { useController = false; resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM; this.player = player } },
        modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9).clip(RoundedCornerShape(8.dp)),
    )
}

// ================= 카테고리 =================

@Composable
fun CategoryGrid(vm: AppViewModel) {
    LazyVerticalGrid(GridCells.Adaptive(140.dp), contentPadding = PaddingValues(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items(SiteCategory.all) { c ->
            OutlinedButton(onClick = { vm.open(Screen.Videos(c.name, c.path)) }) { Text(c.name, maxLines = 1) }
        }
    }
}

/** 전체 카테고리 (A~Z) */
@kotlin.OptIn(ExperimentalLayoutApi::class)
@Composable
fun AllCategoriesScreen(vm: AppViewModel, onPick: (TagItem) -> Unit) {
    LaunchedEffect(Unit) { if (vm.tags.isEmpty()) vm.loadTags(vm.tagLetter) }
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Text("전체 카테고리 · ${vm.tagLetter}", style = MaterialTheme.typography.titleLarge)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(vertical = 8.dp)) {
            ('A'..'Z').forEach { c ->
                val l = c.toString()
                FilterChip(selected = vm.tagLetter == l, onClick = { vm.loadTags(l) }, label = { Text(l) })
            }
        }
        if (vm.tagsLoading) Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        else if (vm.tagsError != null) Message(vm.tagsError!!, retry = { vm.loadTags(vm.tagLetter) })
        else if (vm.tags.isEmpty()) Message("이 글자로 시작하는 카테고리가 없어요", null)
        else LazyVerticalGrid(GridCells.Adaptive(170.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            items(vm.tags) { t ->
                Row(Modifier.clip(RoundedCornerShape(4.dp)).combinedClickableCompat { onPick(t) }.padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(t.name, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    Spacer(Modifier.width(4.dp))
                    Text(t.count, fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

private fun Modifier.combinedClickableCompat(onClick: () -> Unit) = this.clickable(onClick = onClick)

// ================= 플레이리스트·포르노스타·채널 =================

@Composable
fun CollectionScreen(vm: AppViewModel, s: CollectionState, size: LayoutSize) {
    LaunchedEffect(s) { if (s.items.isEmpty() && !s.loading) vm.loadMoreCollection(s) }
    Column(Modifier.fillMaxSize()) {
        if (s.kind.usesPornstarFilters) { PornstarFilterBar(vm, compact = size == LayoutSize.Compact); HorizontalDivider() }
        when {
            s.items.isEmpty() && s.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            s.items.isEmpty() && s.error != null -> Message(s.error!!, retry = { vm.reloadCollection(s) })
            s.items.isEmpty() -> Message("결과가 없어요", null)
            else -> LazyVerticalGrid(
                GridCells.Adaptive(if (s.kind.style == CollectionStyle.Pornstar) 150.dp else 200.dp),
                contentPadding = PaddingValues(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                items(s.items, key = { it.path }) { item ->
                    Column(Modifier.clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surface)
                        .combinedClickableCompat { vm.open(Screen.Videos(item.title, item.path)) }.padding(10.dp)) {
                        AsyncImage(item.image, null,
                            contentScale = if (s.kind.style == CollectionStyle.Channel) ContentScale.Fit else ContentScale.Crop,
                            modifier = Modifier.fillMaxWidth().aspectRatio(s.kind.imageRatio).clip(RoundedCornerShape(8.dp)).background(Color.Gray.copy(alpha = 0.2f)))
                        Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 13.sp)
                        if (item.subtitle.isNotEmpty()) Text(item.subtitle, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (item.path == s.items.last().path) LaunchedEffect(item.path) { vm.loadMoreCollection(s) }
                }
                if (s.loading) item(span = { GridItemSpan(maxLineSpan) }) {
                    Box(Modifier.fillMaxWidth().padding(20.dp), Alignment.Center) { CircularProgressIndicator() }
                } else if (s.error != null) item(span = { GridItemSpan(maxLineSpan) }) {
                    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(s.error!!)
                        TextButton(onClick = { vm.loadMoreCollection(s) }) { Text("이어서 불러오기") }
                    }
                }
            }
        }
    }
}

/** 포르노스타 필터 (목록 위쪽, 좁은 화면에서는 접어 둠) */
@kotlin.OptIn(ExperimentalLayoutApi::class)
@Composable
fun PornstarFilterBar(vm: AppViewModel, compact: Boolean) {
    var expanded by remember { mutableStateOf(false) }
    val d = vm.pornstarDraft
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("필터", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
            FilterChip(selected = !d.inches, onClick = { vm.pornstarDraft = d.copy(inches = false) }, label = { Text("cm") })
            FilterChip(selected = d.inches, onClick = { vm.pornstarDraft = d.copy(inches = true) }, label = { Text("inch") })
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { vm.clearPornstarFilters() }) { Text("초기화") }
            Button(onClick = { vm.applyPornstarFilters() }, enabled = vm.pornstarDraft != vm.pornstarApplied) { Text("적용") }
            IconButton(onClick = { expanded = !expanded }) { Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, "접기") }
        }
        if (expanded) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val w = if (compact) Modifier.fillMaxWidth() else Modifier.width(220.dp)
                RangeBox("나이", d.age, 18..107, true, d.inches, w) { vm.pornstarDraft = d.copy(age = it) }
                RangeBox("키", d.height, 109..203, false, d.inches, w) { vm.pornstarDraft = d.copy(height = it) }
                RangeBox("가슴", d.bust, 25..168, false, d.inches, w) { vm.pornstarDraft = d.copy(bust = it) }
                RangeBox("허리", d.waist, 35..166, false, d.inches, w) { vm.pornstarDraft = d.copy(waist = it) }
                RangeBox("엉덩이", d.hips, 25..173, false, d.inches, w) { vm.pornstarDraft = d.copy(hips = it) }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                vm.choiceFields.forEach { f -> ChoiceMenu(vm, f) }
            }
        }
    }
}

@Composable
private fun RangeBox(title: String, value: IntRange, bounds: IntRange, unitless: Boolean, inches: Boolean, modifier: Modifier, onChange: (IntRange) -> Unit) {
    fun text(v: Int, edge: String) = when { unitless -> "$v"; inches -> "$edge${Math.round(v / 2.54)} in"; else -> "$edge$v cm" }
    Column(modifier) {
        Row {
            Text(title, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.weight(1f))
            Text("${text(value.first, if (value.first == bounds.first) "≤ " else "")} ~ ${text(value.last, if (value.last == bounds.last) "≥ " else "")}", fontSize = 12.sp)
        }
        RangeSlider(value = value.first.toFloat()..value.last.toFloat(),
            onValueChange = { onChange(it.start.toInt()..it.endInclusive.toInt()) },
            valueRange = bounds.first.toFloat()..bounds.last.toFloat())
    }
}

@Composable
private fun ChoiceMenu(vm: AppViewModel, f: ChoiceField) {
    var open by remember { mutableStateOf(false) }
    val selected = vm.pornstarDraft.choices[f.name] ?: emptySet()
    Box {
        AssistChip(onClick = { open = true }, label = {
            Text("${f.label}: " + when (selected.size) { 0 -> "상관없음"; 1 -> f.options.firstOrNull { it.first == selected.first() }?.second ?: selected.first(); else -> "${selected.size}개" })
        })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.heightIn(max = 420.dp)) {
            f.options.forEach { (value, label) ->
                DropdownMenuItem(
                    text = { Text(label) },
                    leadingIcon = { Checkbox(checked = value in selected, onCheckedChange = null) },
                    onClick = {
                        val next = if (value in selected) selected - value else selected + value
                        vm.pornstarDraft = vm.pornstarDraft.copy(choices = vm.pornstarDraft.choices + (f.name to next))
                    },
                )
            }
        }
    }
}

// ================= 사이트 화면 그대로 (프로필·설정 등) =================

@Composable
fun WebScreen(url: String) {
    val context = LocalContext.current
    var loading by remember(url) { mutableStateOf(true) }
    var failed by remember(url) { mutableStateOf(false) }
    val web = remember(url) {
        val cm = CookieManager.getInstance()
        Http.cookies.all().forEach { c -> cm.setCookie("https://${c.domain}", "${c.name}=${c.value}; path=${c.path}") }
        WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.userAgentString = Http.USER_AGENT
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView, target: String, favicon: android.graphics.Bitmap?) {
                    loading = true; failed = false
                }
                override fun onPageFinished(view: WebView, target: String) { loading = false }
                override fun onReceivedError(view: WebView, request: android.webkit.WebResourceRequest, error: android.webkit.WebResourceError) {
                    if (request.isForMainFrame) { failed = true; loading = false }
                }
            }
            loadUrl(url)
        }
    }
    DisposableEffect(web) { onDispose { web.stopLoading(); web.destroy() } }
    Column(Modifier.fillMaxSize()) {
        Text("연결된 사이트의 계정 화면", style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp))
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        Box(Modifier.weight(1f)) {
            key(url) { AndroidView(factory = { web }, modifier = Modifier.fillMaxSize()) }
            if (failed) Surface(Modifier.fillMaxSize()) {
                Message("계정 화면에 연결하지 못했어요", retry = {
                    failed = false; loading = true; web.loadUrl(url)
                })
            }
        }
    }
}
