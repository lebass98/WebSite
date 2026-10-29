import Foundation
import Combine

/// 영상 목록 하나 (사이트 페이지를 읽어 옴)
@MainActor
final class BrowserModel: ObservableObject {
    enum Source: Hashable {
        /// 사이드바 검색어·필터로 고르는 기본 목록 (/cat/all/, /tag/검색어/, /cat/vr-porn/)
        case browse
        /// 정해진 주소 (베스트 영상, 채널, 태그 등)
        case page(String)
    }

    let source: Source
    /// 사이트가 정렬해 주는 목록은 다시 불러오고, 아닌 목록은 불러온 영상을 앱에서 정렬
    @Published var order = SortOrder.latest { didSet { if order != oldValue, sortedBySite { reload() } } }
    /// 정렬 옆 카테고리 (기본 목록에서만)
    @Published var category: SiteCategory? { didSet { if category != oldValue { reload() } } }
    @Published var gay = Inclusion.exclude { didSet { if gay != oldValue { reload() } } }
    /// 이 목록 안에서 찾기 (제목·키워드·올린 사람). 찾는 동안 뒤 페이지도 이어서 불러옴
    @Published var localQuery = "" { didSet { if localQuery != oldValue { continueSearch() } } }
    /// 오름차순 (앱에서 정렬하는 목록만). 뒤집으려면 끝까지 받아야 해서 켜면 뒤 페이지도 이어서 불러옴
    @Published var ascending = false { didSet { if ascending != oldValue { continueSearch() } } }

    @Published private(set) var videos: [Video] = []
    /// 영상별 화질 (세로 픽셀, 0 = 모름)
    @Published private(set) var resolutions: [String: Int] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var page = 0
    private var hasMore = true
    private var loadTask: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()

    private var filters: VideoFilters { FilterStore.shared.applied }

    init(source: Source) {
        self.source = source
        if savedListLabel != nil { order = .saved }
        // 사이드바에서 적용하거나 검색하면 처음부터 다시
        FilterStore.shared.$applied.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reload() } }
            .store(in: &bag)
        if source == .browse {
            FilterStore.shared.$searchText.dropFirst().removeDuplicates()
                .sink { [weak self] _ in DispatchQueue.main.async { self?.reload() } }
                .store(in: &bag)
        }
    }

    var canLoadMore: Bool { hasMore }

    /// 사이트가 거른 결과를 앱에서 한 번 더 확인 (VR은 VR에서만, 4K 등에는 VR 제외)
    var visibleVideos: [Video] {
        let f = filters
        let filtered = videos.filter { video in
            if !ListSearch.matches(localQuery, video.title, video.keywords, video.uploaderName ?? "") { return false }
            let minutes = video.lengthSec / 60
            if minutes < f.minMinutes { return false }
            if f.maxMinutes < VideoFilters.openMax, video.lengthSec > f.maxMinutes * 60 + 59 { return false }
            switch f.quality {
            case .all: return true
            case .vr: return true  // VR 페이지에서 받아 옴
            default:
                if isVR(video) { return false }
                let h = resolutions[video.id] ?? 0
                return h == 0 || h >= f.quality.minHeight
            }
        }
        if sortedBySite { return filtered }
        let sorted = sortedLocally(filtered)
        return ascending ? sorted.reversed() : sorted
    }

    func isVR(_ video: Video) -> Bool {
        video.looksVR || (filters.quality == .vr && source == .browse)
    }

    /// 정렬 버튼은 모든 목록에서 보임
    var isSortable: Bool { true }

    /// 사이트가 정렬해 주는 목록인지 (카테고리·검색·포르노스타·채널)
    /// 베스트 영상·내 계정 목록·업로더 목록·플레이리스트는 사이트가 정렬을 안 해 줘서 앱에서 정렬
    var sortedBySite: Bool {
        switch source {
        case .browse: true
        case .page(let p): ["/cat/", "/tag/", "/pornstar/", "/channel/"].contains { p.hasPrefix($0) }
        }
    }

    /// 즐겨찾기·나중에 볼 영상이면 "넣은 순" 정렬 이름 (아니면 nil)
    var savedListLabel: String? {
        guard case .page(let p) = source, p.hasPrefix("/profile/") else { return nil }
        if p.hasSuffix("/favourite-videos/") { return "즐겨찾기한 순" }
        if p.hasSuffix("/watch-later/") { return "추가한 순" }
        return nil
    }

    /// 앱에서 정렬 (이번 주·이번 달 인기는 기간 정보가 없어서 조회수순으로)
    private func sortedLocally(_ list: [Video]) -> [Video] {
        switch order {
        case .saved: list
        // 넣은 순서로 오는 목록은 영상 번호가 클수록 새로 올라온 영상
        case .latest: savedListLabel == nil ? list : list.sorted { $0.fid > $1.fid }
        case .mostPopular, .topWeekly, .topMonthly: list.sorted { $0.views > $1.views }
        case .topRated: list.sorted { $0.rate > $1.rate }
        case .longest: list.sorted { $0.lengthSec > $1.lengthSec }
        case .shortest: list.sorted { $0.lengthSec < $1.lengthSec }
        }
    }

    func reload() {
        loadTask?.cancel()
        isLoading = false
        videos = []
        resolutions = [:]
        page = 0
        hasMore = true
        errorMessage = nil
        loadNextPage()
    }

    func loadNextPage() {
        guard !isLoading, hasMore else { return }
        isLoading = true
        errorMessage = nil
        let next = page + 1
        loadTask = Task {
            defer { if !Task.isCancelled { isLoading = false } }
            do {
                // 검색어(태그) 목록은 사이트가 고유 주소로 바꿔 보내면서 페이지 번호·정렬을 버려서,
                // 고유 주소를 먼저 알아내 두고 그 주소로 요청
                if let raw = rawTagPath(), canonicalTags[raw] == nil {
                    let final = try await SiteScraper.finalURL(URL(string: SiteScraper.base + raw)!)
                    var path = final.path
                    if !path.hasSuffix("/") { path += "/" }
                    canonicalTags[raw] = path.hasPrefix("/tag/") ? path : raw
                    if path != raw { DebugLog.write("검색 고유 주소: \(raw) → \(path)") }
                }
                guard !Task.isCancelled else { return }
                let url = requestURL(page: next)
                DebugLog.write("목록 요청: \(url.absoluteString)")
                let html = try await SiteScraper.html(url)
                guard !Task.isCancelled else { return }
                let scraped = SiteScraper.parseVideos(html)
                let known = Set(videos.map(\.id))
                let fresh = scraped.filter { !known.contains($0.video.id) }
                videos += fresh.map(\.video)
                for item in fresh where item.height > 0 { resolutions[item.video.id] = item.height }
                page = next
                hasMore = !fresh.isEmpty
                fillIfNeeded()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                DebugLog.write("목록 실패: \(error)")
                errorMessage = Self.describe(error)
            }
        }
    }

    /// 앱에서 걸러 화면이 많이 비면 다음 페이지를 자동으로 (최대 3페이지)
    private var autoPages = 0
    private func fillIfNeeded() {
        if page == 1 { autoPages = 0 }
        if isSearching { continueSearch(); return }
        guard visibleVideos.count < 24, hasMore, autoPages < 3 else { return }
        autoPages += 1
        isLoading = false
        loadNextPage()
    }

    /// 목록 안에서 찾는 중이면 끝(또는 최대 페이지)까지 이어서 불러옴
    var isSearching: Bool { (!localQuery.isEmpty || (ascending && !sortedBySite)) && hasMore && page < ListSearch.maxPages }

    private func continueSearch() {
        // 지금 불러오는 작업이 끝난 뒤에 다음 페이지로
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isSearching, !self.isLoading else { return }
            self.loadNextPage()
        }
    }

    // MARK: 주소 만들기

    private enum SortStyle { case cat, tag, none }

    /// 검색어 → 사이트 고유 주소 (/tag/japanese/ → /tag/japanese-CwEfWTjN/)
    private var canonicalTags: [String: String] = [:]

    /// 지금 목록이 검색어(태그) 목록이면 그 기본 주소
    private func rawTagPath() -> String? {
        switch source {
        case .browse:
            let text = FilterStore.shared.searchText
            return text.isEmpty ? nil : "/tag/\(FilterStore.slug(text))/"
        case .page(let p):
            return p.hasPrefix("/tag/") ? p : nil
        }
    }

    func requestURL(page: Int) -> URL {
        let f = filters
        var path: String
        var style: SortStyle
        var include = f.categories
        var exclude: [String] = []
        var unexclude: [String] = []

        switch source {
        case .page(let p):
            path = p.hasPrefix("/tag/") ? (canonicalTags[p] ?? p) : p
            // 카테고리는 SORT-…, 검색·포르노스타·채널은 /top-rated/ 같은 형식
            style = p.hasPrefix("/cat/") ? .cat
                : (p.hasPrefix("/tag/") || p.hasPrefix("/pornstar/") || p.hasPrefix("/channel/")) ? .tag : .none
        case .browse:
            let text = FilterStore.shared.searchText
            if !text.isEmpty {
                let raw = "/tag/\(FilterStore.slug(text))/"
                path = canonicalTags[raw] ?? raw
                style = .tag
                if let c = category { include.append(c.slug) }
            } else if f.quality == .vr {
                path = "/cat/vr-porn/"
                style = .cat
                if let c = category { include.append(c.slug) }
            } else if let c = category {
                path = c.path
                style = .cat
            } else {
                path = "/cat/all/"
                style = .cat
            }
        }

        // VR: VR만 / 그 밖의 화질: VR 제외
        if f.quality == .vr {
            // include=vr-porn 만 붙임 (unexclude 까지 붙이면 사이트 요청이 실패함)
            if !path.hasPrefix("/cat/vr-porn/") { include.append("vr-porn") }
        } else if f.quality != .all {
            exclude.append("vr-porn")
        }
        switch gay {
        case .exclude: break
        case .include: unexclude.append("gay")
        case .only: include.append("gay"); unexclude.append("gay")
        }

        var s = SiteScraper.base + path
        // 페이지 번호와 정렬의 순서가 목록 종류마다 다름 (반대로 쓰면 사이트가 1페이지로 돌려보냄)
        //  카테고리: /cat/all/SORT-top-rated/2/
        //  검색·포르노스타·채널: /tag/…/2/longest/
        switch style {
        case .cat:
            if !order.catSegment.isEmpty { s += order.catSegment + "/" }
            if page > 1 { s += "\(page)/" }
        case .tag:
            if page > 1 { s += "\(page)/" }
            if !order.tagSegment.isEmpty { s += order.tagSegment + "/" }
        case .none:
            if page > 1 { s += "\(page)/" }
        }

        var comps = URLComponents(string: s)!
        var items: [URLQueryItem] = []
        if let q = f.quality.siteValue { items.append(.init(name: "quality", value: q)) }
        if f.minMinutes > 0 { items.append(.init(name: "duration_min_minutes", value: String(f.minMinutes))) }
        if f.maxMinutes < VideoFilters.openMax { items.append(.init(name: "duration_max_minutes", value: String(f.maxMinutes))) }
        include = Array(NSOrderedSet(array: include)) as! [String]
        if !include.isEmpty { items.append(.init(name: "include", value: include.prefix(5).joined(separator: ","))) }
        if !exclude.isEmpty { items.append(.init(name: "exclude", value: exclude.joined(separator: ","))) }
        if !unexclude.isEmpty { items.append(.init(name: "unexclude", value: unexclude.joined(separator: ","))) }
        comps.queryItems = items.isEmpty ? nil : items
        return comps.url!
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .networkConnectionLost, .secureConnectionFailed, .cannotConnectToHost, .timedOut,
                 .notConnectedToInternet, .cannotFindHost:
                return "사이트에 연결하지 못했어요. VPN이 켜져 있는지 확인해 주세요.\n(\(e.localizedDescription))"
            default: break
            }
        }
        return error.localizedDescription
    }
}

/// 플레이리스트 목록 정렬 (베스트·최신·조회수는 사이트가, 영상 수·이름은 앱이 정렬)
enum PlaylistSort: String, CaseIterable, Identifiable {
    case best, recent, mostViewed, mostVideos, name
    var id: String { rawValue }

    var label: String {
        switch self {
        case .best: "베스트순"
        case .recent: "최신순"
        case .mostViewed: "조회수순"
        case .mostVideos: "영상 많은 순"
        case .name: "이름순"
        }
    }

    /// 사이트 주소에 붙일 값 (/best-playlists/recent/), 앱에서 정렬하면 nil
    var siteSegment: String? {
        switch self {
        case .best: ""
        case .recent: "recent"
        case .mostViewed: "most-viewed"
        case .mostVideos, .name: nil
        }
    }
}

/// 플레이리스트·포르노스타·채널 목록
@MainActor
final class CollectionModel: ObservableObject {
    let kind: CollectionKind
    @Published private(set) var items: [CollectionItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var page = 0
    private(set) var hasMore = true
    private var bag = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?

    /// 포르노스타 목록(여성·남성)은 사이드바 필터를 따름
    var usesPornstarFilters: Bool { kind == .pornstarsFemale || kind == .pornstarsMale }

    /// 플레이리스트 목록이면 위쪽에 정렬 버튼
    var usesPlaylistSort: Bool { kind.style == .playlist }

    @Published var playlistSort = PlaylistSort.best {
        didSet {
            guard playlistSort != oldValue else { return }
            // 베스트 플레이리스트에서 사이트 정렬끼리 바꿀 때만 다시 불러옴
            if kind == .playlists, playlistSort.siteSegment != nil || oldValue.siteSegment != nil,
               playlistSort.siteSegment != nil { reload() }
        }
    }

    /// 이 목록 안에서 찾기 (이름). 찾는 동안 뒤 페이지도 이어서 불러옴
    @Published var localQuery = "" { didSet { if localQuery != oldValue { continueSearch() } } }

    var isSearching: Bool { !localQuery.isEmpty && hasMore && page < ListSearch.maxPages }

    private func continueSearch() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isSearching, !self.isLoading else { return }
            self.loadNextPage()
        }
    }

    /// 화면에 보일 순서
    var visibleItems: [CollectionItem] {
        let items = items.filter { ListSearch.matches(localQuery, $0.title, $0.subtitle) }
        switch playlistSort {
        case .mostVideos:
            return items.sorted { Self.count($0) > Self.count($1) }
        case .name:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        default:
            return items
        }
    }

    private static func count(_ item: CollectionItem) -> Int {
        Int(item.subtitle.filter(\.isNumber)) ?? 0
    }

    init(kind: CollectionKind) {
        self.kind = kind
        if usesPornstarFilters {
            PornstarFilterStore.shared.$applied.dropFirst().removeDuplicates()
                .sink { [weak self] _ in DispatchQueue.main.async { self?.reload() } }
                .store(in: &bag)
        }
    }

    func reload() {
        loadTask?.cancel()
        isLoading = false
        items = []
        page = 0
        hasMore = true
        errorMessage = nil
        loadNextPage()
    }

    func loadNextPage() {
        guard !isLoading, hasMore else { return }
        isLoading = true
        errorMessage = nil
        let next = page + 1
        let query = usesPornstarFilters ? PornstarFilterStore.shared.applied.queryItems : []
        // 사이트 정렬은 베스트 플레이리스트 목록에서만 (검색·내 플레이리스트는 사이트가 지원 안 함)
        let sort = kind == .playlists ? (playlistSort.siteSegment ?? "") : ""
        loadTask = Task {
            defer { if !Task.isCancelled { isLoading = false } }
            do {
                let fetched = try await SiteScraper.collection(kind, page: next, query: query, sort: sort)
                guard !Task.isCancelled else { return }
                let known = Set(items.map(\.id))
                let fresh = fetched.filter { !known.contains($0.id) }
                items += fresh
                page = next
                // 채널 목록은 한 페이지뿐
                hasMore = !fresh.isEmpty && kind.paged
                continueSearch()
            } catch {
                DebugLog.write("목록 실패: \(error)")
                errorMessage = "목록을 불러오지 못했어요. VPN이 켜져 있는지 확인해 주세요."
            }
        }
    }
}

/// 목록 안에서 찾기 (띄어쓴 낱말이 모두 들어 있으면 맞음, 대소문자 무시)
enum ListSearch {
    /// 찾는 동안 자동으로 불러올 최대 페이지
    static let maxPages = 60

    static func matches(_ query: String, _ fields: String...) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = fields.joined(separator: " ")
        return words.allSatisfy { text.localizedStandardContains($0) }
    }
}

/// 메뉴를 오가도 불러온 목록이 유지되도록 보관
@MainActor
final class ModelCache {
    static let shared = ModelCache()
    private var videos: [BrowserModel.Source: BrowserModel] = [:]
    private var collections: [CollectionKind: CollectionModel] = [:]

    func videos(_ source: BrowserModel.Source) -> BrowserModel {
        if let m = videos[source] { return m }
        let m = BrowserModel(source: source)
        videos[source] = m
        return m
    }

    /// 내 계정 페이지(즐겨찾기 등)는 바뀌었을 수 있어서 다음에 새로 불러오게
    func forgetUserPages() {
        videos = videos.filter { key, _ in
            if case .page(let p) = key { return !p.hasPrefix("/profile/") }
            return true
        }
    }

    func collection(_ kind: CollectionKind) -> CollectionModel {
        if let m = collections[kind] { return m }
        let m = CollectionModel(kind: kind)
        collections[kind] = m
        return m
    }
}
