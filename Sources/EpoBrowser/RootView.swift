import SwiftUI
import Combine

/// 사이드바에서 고르는 화면
enum AppSection: Hashable {
    case videos, best, topRated, categories, allCategories
    case collection(CollectionKind)
    case user(UserLink)

    var title: String {
        switch self {
        case .videos: "영상"
        case .best: "베스트 영상"
        case .topRated: "최고 평점"
        case .categories: "카테고리"
        case .allCategories: "전체 카테고리"
        case .collection(let kind): kind.title
        case .user(let link): link.kind.label
        }
    }
}

/// 검색 종류 (사이트 사이드바의 SEARCH)
enum SearchType: String, CaseIterable, Identifiable {
    case videos, pornstars, playlists
    var id: String { rawValue }
    var label: String {
        switch self {
        case .videos: "영상"
        case .pornstars: "포르노스타"
        case .playlists: "플레이리스트"
        }
    }
}

@MainActor
final class NavState: ObservableObject {
    @Published var section = AppSection.videos {
        didSet {
            if section != oldValue { restoring ? () : (path = []) }
            recordTab()
        }
    }
    @Published var path: [Route] = [] { didSet { recordTab() } }
    @Published var searchType = SearchType.videos

    /// 이동한 페이지가 탭으로 쌓임 (누르면 그 페이지로 돌아감)
    struct Tab: Identifiable, Hashable {
        let section: AppSection
        let path: [Route]
        let title: String
        var id: String { "\(section)|" + path.map(\.path).joined(separator: ">") }
    }
    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeTabID: String?
    private var restoring = false
    private static let maxTabs = 30

    init() { recordTab() }

    private func recordTab() {
        guard !restoring else { return }
        let title = path.last?.title ?? (section == .videos && !FilterStore.shared.searchText.isEmpty
                                         ? "검색: \(FilterStore.shared.searchText)" : section.title)
        let tab = Tab(section: section, path: path, title: title)
        if !tabs.contains(where: { $0.id == tab.id }) {
            tabs.append(tab)
            if tabs.count > Self.maxTabs { tabs.removeFirst(tabs.count - Self.maxTabs) }
        }
        activeTabID = tab.id
    }

    /// 탭을 눌러 그 페이지로 돌아가기
    func select(_ tab: Tab) {
        restoring = true
        section = tab.section
        path = tab.path
        restoring = false
        activeTabID = tab.id
    }

    /// 탭 닫기 (보고 있던 탭이면 옆 탭으로)
    func close(_ tab: Tab) {
        guard tabs.count > 1, let i = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: i)
        if activeTabID == tab.id { select(tabs[min(i, tabs.count - 1)]) }
    }

    /// 검색어와 검색 종류에 맞는 화면으로
    func showSearchResults() {
        let text = FilterStore.shared.searchText
        switch searchType {
        case .videos: section = .videos
        case .pornstars: section = text.isEmpty ? .collection(.pornstarsFemale) : .collection(.searchPornstars(text))
        case .playlists: section = text.isEmpty ? .collection(.playlists) : .collection(.searchPlaylists(text))
        }
        path = []
    }

    func open(_ route: Route) { path.append(route) }
}

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
            .overlay(alignment: .bottom) { ToastView().animation(.spring(duration: 0.3), value: Toast.shared.message) }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $search.text, placement: .toolbar, prompt: "검색어")
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(nav.tabs) { tab in
                        let active = tab.id == nav.activeTabID
                        HStack(spacing: 4) {
                            Text(tab.title)
                                .font(.callout.weight(active ? .semibold : .regular))
                                .lineLimit(1)
                                .frame(maxWidth: 180)
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
                        .foregroundStyle(active ? Color.white : Color.primary)
                        .background(active ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { nav.select(tab) }
                        .help(tab.title)
                        .id(tab.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: nav.activeTabID) {
                if let id = nav.activeTabID { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }
}
