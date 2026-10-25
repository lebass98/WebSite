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
        let query: String
        let searchType: SearchType
        var id: String {
            "\(section)|\(searchType.rawValue)|\(query.count):\(query)|" + path.map(\.path).joined(separator: ">")
        }
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
        let tab = Tab(section: section, path: path, title: title, query: FilterStore.shared.searchText, searchType: searchType)
        if !tabs.contains(where: { $0.id == tab.id }) {
            tabs.append(tab)
            if tabs.count > Self.maxTabs { tabs.removeFirst(tabs.count - Self.maxTabs) }
        }
        activeTabID = tab.id
    }

    /// 탭을 눌러 그 페이지로 돌아가기
    func select(_ tab: Tab) {
        restoring = true
        searchType = tab.searchType
        FilterStore.shared.search(tab.query)
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
        restoring = true
        let text = FilterStore.shared.searchText
        switch searchType {
        case .videos: section = .videos
        case .pornstars: section = text.isEmpty ? .collection(.pornstarsFemale) : .collection(.searchPornstars(text))
        case .playlists: section = text.isEmpty ? .collection(.playlists) : .collection(.searchPlaylists(text))
        }
        path = []
        restoring = false
        recordTab()
    }

    func open(_ route: Route) { path.append(route) }
}
