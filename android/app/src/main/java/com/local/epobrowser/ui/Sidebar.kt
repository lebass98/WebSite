package com.local.epobrowser.ui

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.local.epobrowser.PlayerActivity
import com.local.epobrowser.data.*

/** 사이드바 (메뉴·내 계정·필터·최근 본 영상) */
@Composable
fun Sidebar(vm: AppViewModel, includeFilters: Boolean, onNavigate: () -> Unit, onLogin: () -> Unit) {
    val context = LocalContext.current
    var confirmClear by remember { mutableStateOf(false) }
    if (confirmClear) AlertDialog(
        onDismissRequest = { confirmClear = false },
        title = { Text("최근 본 영상을 모두 지울까요?") },
        text = { Text("최근 본 영상 ${vm.recent.size}개의 기록을 지웁니다.") },
        confirmButton = { TextButton(onClick = { vm.clearRecent(); confirmClear = false }) { Text("모두 지우기") } },
        dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("취소") } },
    )
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
        item {
            Text("EpoBrowser", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp))
            Text("나만의 미디어 라이브러리", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 12.dp))
        }
        item { Header("탐색 · 검색 유형") }
        items(SearchType.entries) { t ->
            MenuRow(t.label, Icons.Default.Search, selected = vm.searchType == t && vm.stack.size == 1 && isSearchRoot(vm, t)) {
                vm.search(vm.searchText, t); onNavigate()
            }
        }
        item { Header("둘러보기") }
        item { MenuRow("베스트 영상", Icons.Default.LocalFireDepartment, vm.current == Screen.Videos("베스트 영상", "/best-videos/")) { vm.openRoot(Screen.Videos("베스트 영상", "/best-videos/")); onNavigate() } }
        item { MenuRow("최고 평점", Icons.Default.Star, vm.current == Screen.Videos("최고 평점", "/cat/all/SORT-top-rated/")) { vm.openRoot(Screen.Videos("최고 평점", "/cat/all/SORT-top-rated/")); onNavigate() } }
        item { MenuRow("카테고리", Icons.Default.GridView, vm.current == Screen.Categories) { vm.openRoot(Screen.Categories); onNavigate() } }
        item { MenuRow("전체 카테고리 (A~Z)", Icons.Default.SortByAlpha, vm.current == Screen.AllCategories) { vm.openRoot(Screen.AllCategories); onNavigate() } }
        item { MenuRow("포르노스타 (여성)", Icons.Default.Person, vm.current == Screen.Collection(CollectionKind.PornstarsFemale)) { vm.openRoot(Screen.Collection(CollectionKind.PornstarsFemale)); onNavigate() } }
        item { MenuRow("포르노스타 (남성)", Icons.Default.Person, vm.current == Screen.Collection(CollectionKind.PornstarsMale)) { vm.openRoot(Screen.Collection(CollectionKind.PornstarsMale)); onNavigate() } }
        item { MenuRow("채널", Icons.Default.LiveTv, vm.current == Screen.Collection(CollectionKind.Channels)) { vm.openRoot(Screen.Collection(CollectionKind.Channels)); onNavigate() } }

        item { Header("내 계정") }
        if (vm.loginState == LoginState.LoggedIn) {
            items(UserPage.entries) { p ->
                MenuRow(p.label, Icons.Default.ChevronRight, selected = vm.current.title == p.label) { vm.openUserPage(p); onNavigate() }
            }
            item { MenuRow("로그아웃", Icons.AutoMirrored.Filled.Logout, false) { vm.logout() } }
        } else {
            item { MenuRow(if (vm.loginState == LoginState.LoggingIn) "로그인 중…" else "로그인", Icons.AutoMirrored.Filled.Login, false, onLogin) }
        }

        if (includeFilters) {
            item { Spacer(Modifier.height(8.dp)); FilterPanel(vm, onApplied = {}) }
        }

        item {
            Row(Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("최근 본 영상 ${vm.recent.size}", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                if (vm.recent.isNotEmpty()) TextButton(onClick = { confirmClear = true }) { Text("모두 지우기", fontSize = 12.sp) }
            }
        }
        if (vm.recent.isEmpty()) item { Text("영상을 보면 여기에 쌓여요.", style = MaterialTheme.typography.bodySmall) }
        items(vm.recent, key = { "r" + it.id }) { r ->
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp))
                    .clickable { vm.markWatched(r); vm.play(context, PlayRequest(r.id, r.title, r.url, r.embed, r.fid)) }
                    .padding(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AsyncImage(r.thumb, null, contentScale = ContentScale.Crop, modifier = Modifier.size(72.dp, 40.dp).clip(RoundedCornerShape(4.dp)))
                Spacer(Modifier.width(8.dp))
                Text(r.title, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                IconButton(onClick = { vm.removeRecent(r.id) }, modifier = Modifier.size(28.dp)) { Icon(Icons.Default.Close, "지우기", Modifier.size(14.dp)) }
            }
        }
    }
}

private fun isSearchRoot(vm: AppViewModel, t: SearchType) = when (val s = vm.current) {
    Screen.Browse -> t == SearchType.Videos
    is Screen.Collection -> (t == SearchType.Pornstars && s.kind.style == CollectionStyle.Pornstar && s.kind !is CollectionKind.Custom) ||
        (t == SearchType.Playlists && s.kind.style == CollectionStyle.Playlist && s.kind !is CollectionKind.Custom)
    else -> false
}

@Composable
private fun Header(text: String) {
    Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp, bottom = 4.dp))
}

@Composable
private fun MenuRow(label: String, icon: ImageVector, selected: Boolean, onClick: () -> Unit) {
    NavigationDrawerItem(
        label = { Text(label, maxLines = 1) }, icon = { Icon(icon, null) }, selected = selected, onClick = onClick,
        modifier = Modifier.heightIn(min = 48.dp),
    )
}

/** 화질·길이·카테고리 필터 (넓은 화면은 사이드바, 좁은 화면은 아래에서 올라오는 창) */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FilterPanel(vm: AppViewModel, onApplied: () -> Unit) {
    var showCats by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("화질", color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Bold)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Quality.entries.forEach { q ->
                FilterChip(selected = vm.draft.quality == q, onClick = { vm.draft = vm.draft.copy(quality = q) }, label = { Text(q.label) })
            }
        }
        Text("VR은 VR에서만 나오고, 다른 화질에서는 빠져요.", style = MaterialTheme.typography.bodySmall)

        Text("길이 (분)", color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Bold)
        val d = vm.draft
        Row(Modifier.fillMaxWidth()) {
            Text("최소 ${d.minMinutes}분", Modifier.weight(1f))
            Text("최대 " + if (d.maxMinutes >= Filters.OPEN_MAX) "1h+" else "${d.maxMinutes}분")
        }
        RangeSlider(
            value = d.minMinutes.toFloat()..d.maxMinutes.toFloat(),
            onValueChange = { r -> vm.draft = vm.draft.copy(minMinutes = r.start.toInt(), maxMinutes = r.endInclusive.toInt()) },
            valueRange = 0f..Filters.OPEN_MAX.toFloat(),
        )

        Text("카테고리", color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Bold)
        OutlinedButton(onClick = { showCats = !showCats }, modifier = Modifier.fillMaxWidth()) {
            Text("${d.categories.size}개 선택 (최대 ${Filters.MAX_CATEGORIES}개)", Modifier.weight(1f))
            Icon(if (showCats) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null)
        }
        if (showCats) {
            Column(Modifier.heightIn(max = 280.dp).verticalScroll(rememberScrollState())) {
                SiteCategory.all.forEach { c ->
                    val on = c.slug in d.categories
                    Row(Modifier.fillMaxWidth().clickable(enabled = on || d.categories.size < Filters.MAX_CATEGORIES) { vm.toggleCategory(c.slug) },
                        verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = on, onCheckedChange = { vm.toggleCategory(c.slug) }, enabled = on || d.categories.size < Filters.MAX_CATEGORIES)
                        Text(c.name)
                    }
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { vm.applyFilters(); onApplied() }, enabled = vm.draft != vm.applied, modifier = Modifier.weight(1f)) { Text("적용") }
            OutlinedButton(onClick = { vm.clearFilters(); onApplied() }, enabled = !(vm.draft.isDefault && vm.applied.isDefault), modifier = Modifier.weight(1f)) { Text("초기화") }
        }
    }
}

