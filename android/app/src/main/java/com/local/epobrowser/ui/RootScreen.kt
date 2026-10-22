package com.local.epobrowser.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/** 화면 너비에 따른 배치 */
enum class LayoutSize { Compact, Medium, Expanded }

/**
 * 반응형 큰 틀
 * - 좁음(휴대폰, 폴드 접은 화면): 메뉴는 왼쪽에서 꺼내는 서랍, 필터는 아래에서 올라오는 창
 * - 중간(폴드 펼친 화면, 태블릿 세로): 왼쪽 아이콘 메뉴 + 서랍
 * - 넓음(태블릿 가로): 맥 앱처럼 왼쪽 사이드바가 늘 보임
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RootScreen(vm: AppViewModel) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val size = when {
            maxWidth < 600.dp -> LayoutSize.Compact
            maxWidth < 840.dp -> LayoutSize.Medium
            else -> LayoutSize.Expanded
        }
        val drawer = rememberDrawerState(DrawerValue.Closed)
        val scope = rememberCoroutineScope()
        var showFilters by remember { mutableStateOf(false) }
        var showLogin by remember { mutableStateOf(false) }

        BackHandler(enabled = drawer.isOpen || vm.stack.size > 1) {
            if (drawer.isOpen) scope.launch { drawer.close() } else vm.back()
        }

        val closeDrawer: () -> Unit = { scope.launch { drawer.close() } }
        val sidebar: @Composable (Boolean) -> Unit = { withFilters ->
            Sidebar(vm, includeFilters = withFilters, onNavigate = closeDrawer, onLogin = { showLogin = true; closeDrawer() })
        }

        val content: @Composable () -> Unit = {
            Scaffold(
                topBar = {
                    TopBar(
                        vm = vm,
                        showMenu = size != LayoutSize.Expanded,
                        showFilterButton = size != LayoutSize.Expanded,
                        onMenu = { scope.launch { drawer.open() } },
                        onFilters = { showFilters = true },
                        onLogin = { showLogin = true },
                    )
                },
            ) { padding ->
                Row(Modifier.padding(padding).fillMaxSize()) {
                    if (size == LayoutSize.Medium) {
                        Rail(vm)
                        VerticalDivider()
                    }
                    Box(Modifier.weight(1f).fillMaxHeight()) { ScreenContent(vm, size) }
                }
            }
        }

        if (size == LayoutSize.Expanded) {
            PermanentNavigationDrawer(drawerContent = {
                PermanentDrawerSheet(Modifier.width(300.dp)) { sidebar(true) }
            }) { content() }
        } else {
            ModalNavigationDrawer(drawerState = drawer, drawerContent = {
                ModalDrawerSheet(Modifier.widthIn(max = 320.dp)) { sidebar(false) }
            }) { content() }
        }

        if (showFilters) {
            ModalBottomSheet(onDismissRequest = { showFilters = false }) {
                FilterPanel(vm, onApplied = { showFilters = false })
            }
        }
        if (showLogin) LoginDialog(vm) { showLogin = false }
        val context = LocalContext.current
        vm.askPlay?.let { r -> PlayerChooserDialog(vm, context, r) { vm.askPlay = null } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TopBar(
    vm: AppViewModel, showMenu: Boolean, showFilterButton: Boolean,
    onMenu: () -> Unit, onFilters: () -> Unit, onLogin: () -> Unit,
) {
    var searching by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf(vm.searchText) }
    TopAppBar(
        navigationIcon = {
            when {
                vm.stack.size > 1 -> IconButton(onClick = { vm.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "뒤로") }
                showMenu -> IconButton(onClick = onMenu) { Icon(Icons.Default.Menu, "메뉴") }
            }
        },
        title = {
            if (searching) {
                OutlinedTextField(
                    value = query, onValueChange = { query = it }, singleLine = true,
                    placeholder = { Text("${vm.searchType.label} 검색") },
                    modifier = Modifier.fillMaxWidth(),
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { vm.search(query); searching = false }),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Search),
                    trailingIcon = {
                        IconButton(onClick = { query = ""; if (vm.searchText.isNotEmpty()) vm.search(""); searching = false }) {
                            Icon(Icons.Default.Close, "검색 지우기")
                        }
                    },
                )
            } else {
                Text(
                    if (vm.current is Screen.Browse && vm.searchText.isNotEmpty()) "검색: ${vm.searchText}" else vm.current.title,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
        },
        actions = {
            if (!searching) IconButton(onClick = { searching = true }) { Icon(Icons.Default.Search, "검색") }
            if (showFilterButton) IconButton(onClick = onFilters) {
                BadgedBox(badge = { if (!vm.applied.isDefault) Badge() }) { Icon(Icons.Default.Tune, "필터") }
            }
            PlayerModeMenu(vm)
            IconButton(onClick = { vm.cycleTheme() }) {
                Icon(when (vm.themeMode) { 1 -> Icons.Default.LightMode; 2 -> Icons.Default.DarkMode; else -> Icons.Default.Contrast }, "화면 모드")
            }
            IconButton(onClick = onLogin) {
                Icon(
                    if (vm.loginState == LoginState.LoggedIn) Icons.Default.AccountCircle else Icons.Default.PersonOutline, "로그인",
                    tint = if (vm.loginState == LoginState.LoggedIn) MaterialTheme.colorScheme.primary else LocalContentColor.current,
                )
            }
        },
    )
}

/** 위쪽 막대의 재생 방법 고르기 */
@Composable
private fun PlayerModeMenu(vm: AppViewModel) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.Default.SmartDisplay, "재생 방법") }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            Text("재생 방법", style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
            PlayerMode.entries.forEach { m ->
                DropdownMenuItem(
                    text = { Text(m.label) },
                    leadingIcon = { RadioButton(selected = vm.playerMode == m, onClick = null) },
                    onClick = { vm.setPlayer(m); open = false },
                )
            }
        }
    }
}

/** 중간 크기(폴드 펼친 화면 등)의 왼쪽 아이콘 메뉴 */
@Composable
private fun Rail(vm: AppViewModel) {
    NavigationRail {
        val items = listOf(
            Triple("영상", Icons.Default.VideoLibrary, Screen.Browse),
            Triple("베스트", Icons.Default.LocalFireDepartment, Screen.Videos("베스트 영상", "/best-videos/")),
            Triple("카테고리", Icons.Default.GridView, Screen.Categories),
            Triple("스타", Icons.Default.Person, Screen.Collection(com.local.epobrowser.data.CollectionKind.PornstarsFemale)),
            Triple("채널", Icons.Default.LiveTv, Screen.Collection(com.local.epobrowser.data.CollectionKind.Channels)),
        )
        items.forEach { (label, icon, screen) ->
            NavigationRailItem(
                selected = vm.stack.first() == screen,
                onClick = { vm.openRoot(screen) },
                icon = { Icon(icon, label) }, label = { Text(label) },
            )
        }
    }
}

@Composable
private fun ScreenContent(vm: AppViewModel, size: LayoutSize) {
    when (val s = vm.current) {
        Screen.Browse, is Screen.Videos -> VideoListScreen(vm, vm.listFor(s), size)
        Screen.Categories -> CategoryGrid(vm)
        Screen.AllCategories -> AllCategoriesScreen(vm) { vm.open(Screen.Videos(it.name, it.path)) }
        is Screen.Collection -> CollectionScreen(vm, vm.collectionFor(s.kind), size)
        is Screen.Web -> WebScreen(s.url)
        is Screen.User -> {}
    }
}

@Composable
fun LoginDialog(vm: AppViewModel, onDismiss: () -> Unit) {
    var user by remember { mutableStateOf(vm.session.savedUser ?: "") }
    var pass by remember { mutableStateOf("") }
    val loggedIn = vm.loginState == LoginState.LoggedIn
    val busy = vm.loginState == LoginState.LoggingIn
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("사이트 로그인") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(user, { user = it }, label = { Text("아이디") }, singleLine = true, enabled = !loggedIn && !busy)
                OutlinedTextField(
                    pass, { pass = it }, label = { Text("비밀번호") }, singleLine = true, enabled = !loggedIn && !busy,
                    visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                )
                when (vm.loginState) {
                    LoginState.LoggedIn -> Text("로그인됨: ${vm.userName ?: ""}", color = MaterialTheme.colorScheme.primary)
                    LoginState.LoggingIn -> Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)); Text("로그인 중…")
                    }
                    LoginState.Failed -> Text(vm.loginMessage ?: "로그인 실패", color = MaterialTheme.colorScheme.error)
                    LoginState.None -> Text("저장하면 다음부터는 앱을 켤 때 자동으로 로그인해요.", style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            // 로그인된 동안은 누를 수 없음
            Button(onClick = { vm.login(user.trim(), pass) }, enabled = !loggedIn && !busy && user.isNotBlank() && pass.isNotEmpty()) {
                Text(if (loggedIn) "로그인됨" else "로그인")
            }
        },
        dismissButton = {
            Row {
                if (loggedIn) TextButton(onClick = { vm.logout() }) { Text("로그아웃") }
                TextButton(onClick = onDismiss) { Text("닫기") }
            }
        },
    )
}
