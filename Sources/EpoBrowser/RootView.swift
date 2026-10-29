import SwiftUI
import Combine

/// 왼쪽 사이드바(항상 보임) + 오른쪽 목록
struct RootView: View {
    @StateObject private var nav = NavState()
    @StateObject private var search = SearchField()
    @ObservedObject private var filters = FilterStore.shared
    @ObservedObject private var session = SiteSession.shared
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView(nav: nav, search: search)
                .navigationSplitViewColumnWidth(min: 250, ideal: 270, max: 320)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            // 탭 줄은 각 페이지 맨 위에 붙임 (들어간 페이지가 탭 줄 자리를 덮지 않게)
            NavigationStack(path: $nav.path) {
                sectionView(nav.section)
                    .safeAreaInset(edge: .top, spacing: 0) { tabBar }
                    .navigationDestination(for: Route.self) { route in
                        VideoListView(model: ModelCache.shared.videos(.page(route.path)), title: route.title,
                                      onOpen: nav.open)
                            .safeAreaInset(edge: .top, spacing: 0) { tabBar }
                    }
            }
            .overlay(alignment: .bottom) { ToastView() }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $search.text, placement: .toolbar, prompt: "영상·스타·플레이리스트 검색")
        // 입력하는 동안 맞는 카테고리를 추천 (맞는 글자는 강조색)
        .searchSuggestions {
            ForEach(categorySuggestions) { cat in
                Button {
                    search.text = ""
                    nav.open(Route(title: cat.name, path: cat.path))
                } label: {
                    Label { Text(highlighted(cat.name)) } icon: { Image(systemName: "square.grid.2x2") }
                }
            }
        }
        .onSubmit(of: .search) {
            filters.search(search.text)
            nav.showSearchResults()
        }
        .onChange(of: search.text) {
            // 검색창의 x를 누르면 검색 해제
            if search.text.isEmpty, !filters.searchText.isEmpty {
                filters.search("")
                nav.showSearchResults()
            }
        }
        .onChange(of: nav.activeTabID) {
            search.text = filters.searchText
        }
        // 재생 창 등에서 부탁한 이동 (예: 모델 고르기)
        .onChange(of: router.pending) {
            if let route = router.pending {
                nav.open(route)
                router.pending = nil
            }
        }
        .task {
            AppearanceSetting.shared.apply()
            ClickThrough.install()
            _ = SiteActions.shared
            _ = FavoritesStore.shared
            session.startIfNeeded()
            updater.startAutoCheck()
            let backup = Backup.shared
            if let note = backup.restoreNote, !backup.restoreToastShown {
                backup.restoreToastShown = true
                Toast.shared.show(note, seconds: 8)
            }
        }
        .sheet(isPresented: $updater.showSheet) { UpdateSheet() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                LoginMenu(session: session)
            }
            ToolbarItem(placement: .primaryAction) {
                UpdateButton()
            }
            ToolbarItem(placement: .primaryAction) {
                AppearanceButton()
            }
            ToolbarItem(placement: .primaryAction) {
                URLCollectorButton()
            }
        }
    }

    private var categorySuggestions: [SiteCategory] {
        let text = search.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != filters.searchText else { return [] }
        return Array(SiteCategory.sorted.filter { $0.name.localizedStandardContains(text) || $0.slug.localizedStandardContains(text) }.prefix(6))
    }

    private func highlighted(_ name: String) -> AttributedString {
        var out = AttributedString(name)
        let text = search.text.trimmingCharacters(in: .whitespaces)
        if let r = out.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) {
            out[r].foregroundColor = EpoStyle.accent
            out[r].font = .body.bold()
        }
        return out
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            TabStrip(nav: nav)
            Divider()
        }
        .background(.bar)
    }

    @ViewBuilder private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .videos:
            VideoListView(model: ModelCache.shared.videos(.browse),
                          title: filters.searchText.isEmpty ? "영상" : "검색: \(filters.searchText)",
                          onOpen: nav.open)
        case .best:
            VideoListView(model: ModelCache.shared.videos(.page("/best-videos/")), title: "베스트 영상", onOpen: nav.open)
        case .topRated:
            VideoListView(model: ModelCache.shared.videos(.page("/cat/all/SORT-top-rated/")), title: "최고 평점", onOpen: nav.open)
        case .categories:
            CategoryGridView(onOpen: nav.open)
        case .allCategories:
            AllCategoriesView(onSelect: { nav.open(Route(title: $0.name, path: $0.path)) })
                .navigationTitle("전체 카테고리")
        case .collection(let kind):
            CollectionView(model: ModelCache.shared.collection(kind), onOpen: nav.open)
                .id(kind)
        case .user(let link):
            UserPageView(link: link, onOpen: nav.open)
                .id(link)
        }
    }
}

/// 목록 위쪽 탭 줄 (이동한 페이지가 쌓임)
struct TabStrip: View {
    @ObservedObject var nav: NavState
    @Namespace private var tabSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(nav.tabs) { tab in
                        let active = tab.id == nav.activeTabID
                        HStack(spacing: 4) {
                            Button { nav.select(tab) } label: {
                                Text(tab.title)
                                    .font(.callout.weight(active ? .semibold : .regular))
                                    .lineLimit(1)
                                    .frame(maxWidth: 180)
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(active ? [.isSelected] : [])
                            if nav.tabs.count > 1 {
                                Button {
                                    nav.close(tab)
                                } label: {
                                    Image(systemName: "xmark").font(.caption2.bold())
                                }
                                .buttonStyle(.borderless)
                                .help("탭 닫기")
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(active ? EpoStyle.accent : Color.primary)
                        // 선택 캡슐 하나가 탭 사이를 스프링으로 미끄러져 이동
                        .background {
                            if active {
                                Capsule().fill(EpoStyle.accent.opacity(0.12))
                                    .matchedGeometryEffect(id: "activeTab", in: tabSpace)
                            } else {
                                Capsule().fill(Color.primary.opacity(0.04))
                            }
                        }
                        .contentShape(Capsule())
                        .help(tab.title)
                        .id(tab.id)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .offset(y: 24).combined(with: .opacity)))
                    }
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.3), value: nav.activeTabID)
                .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2), value: nav.tabs.map(\.id))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: nav.activeTabID) {
                if let id = nav.activeTabID { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}
