import SwiftUI
import Combine

/// 카테고리 메뉴: 주요 카테고리 버튼 모음
struct CategoryGridView: View {
    var onOpen: (Route) -> Void
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        ScrollView {
            LibraryHeader(title: "카테고리", subtitle: "관심 있는 주제로 라이브러리를 둘러보세요", icon: "square.grid.2x2")
                .padding(24)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(SiteCategory.sorted) { cat in
                    Button {
                        onOpen(Route(title: cat.name, path: cat.path))
                    } label: {
                        Text(cat.name)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle("카테고리")
    }
}

@MainActor
final class TagListModel: ObservableObject {
    @Published var letter = "A" { didSet { if letter != oldValue { load() } } }
    @Published private(set) var tags: [TagItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var cache: [String: [TagItem]] = [:]
    private var task: Task<Void, Never>?

    func load() {
        task?.cancel()
        errorMessage = nil
        if let cached = cache[letter] { tags = cached; isLoading = false; return }
        isLoading = true
        tags = []
        let l = letter
        task = Task {
            defer { if !Task.isCancelled { isLoading = false } }
            do {
                let list = try await SiteScraper.tags(letter: l)
                guard !Task.isCancelled else { return }
                cache[l] = list
                tags = list
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "목록을 불러오지 못했어요. VPN이 켜져 있는지 확인해 주세요."
            }
        }
    }
}

/// 전체 카테고리 (A~Z) — 사이트의 /cats/T/ 목록
struct AllCategoriesView: View {
    var onSelect: (TagItem) -> Void
    @StateObject private var model = TagListModel()
    private let letters = (65...90).map { String(UnicodeScalar($0)!) }
    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 8, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("전체 카테고리 · \(model.letter)").font(.title2.bold())
            // A~Z 버튼
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 6)], spacing: 6) {
                ForEach(letters, id: \.self) { l in
                    Button {
                        model.letter = l
                    } label: {
                        Text(l).font(.callout.bold())
                            .frame(width: 30, height: 28)
                            .foregroundStyle(model.letter == l ? Color.white : Color.primary)
                            .background(model.letter == l ? Color.accentColor : Color.primary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()

            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage {
                VStack {
                    Text(error).foregroundStyle(.secondary)
                    Button("다시 시도") { model.load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(model.tags) { tag in
                            Button {
                                onSelect(tag)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(tag.name).lineLimit(1)
                                    Text(tag.count)
                                        .font(.caption2)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .task { if model.tags.isEmpty { model.load() } }
    }
}

/// 플레이리스트·포르노스타·채널 목록 (누르면 그 영상 목록)
struct CollectionView: View {
    @ObservedObject var model: CollectionModel
    var onOpen: (Route) -> Void
    @ObservedObject private var thumbSize = ThumbnailSize.shared

    /// 영상 목록과 같은 크기 설정을 씀 (포르노스타 사진은 비율이 달라 조금 좁게)
    private var columns: [GridItem] {
        let w = thumbSize.width * (model.kind.style == .pornstar ? 0.75 : 1)
        return [GridItem(.adaptive(minimum: w, maximum: w * 1.5), spacing: 14)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.kind.title).font(.title2.weight(.bold))
                Spacer()
                Text(!model.localQuery.isEmpty && (model.isSearching || model.isLoading)
                     ? "찾는 중… \(model.visibleItems.count)개" : "\(model.visibleItems.count)개 표시")
                    .font(.caption).foregroundStyle(.secondary)
                ListSearchField(text: $model.localQuery, prompt: "이 목록에서 찾기")
            }
            .padding(20)
            if model.usesPornstarFilters {
                PornstarFilterBar()
                Divider()
            }
            // 위쪽 줄: 왼쪽은 정렬(플레이리스트), 오른쪽 끝은 썸네일 크기 바 (영상 목록과 같은 배치)
            HStack(spacing: 14) {
                if model.usesPlaylistSort {
                    Picker("정렬", selection: $model.playlistSort) {
                        ForEach(PlaylistSort.allCases) { sort in
                            // 검색·내 플레이리스트는 사이트 정렬이 없어서 최신·조회수는 빼고 보여 줌
                            if model.kind == .playlists || sort.siteSegment == nil || sort == .best {
                                Text(sort == .best && model.kind != .playlists ? "기본순" : sort.label).tag(sort)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Spacer()
                ThumbnailSizeSlider()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            list
        }
        .navigationTitle(model.kind.title)
        .task { if model.items.isEmpty { model.loadNextPage() } }
    }

    @ViewBuilder private var list: some View {
        Group {
            if model.items.isEmpty && model.isLoading {
                ProgressView("불러오는 중…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty, let error = model.errorMessage {
                VStack(spacing: 12) {
                    LibraryEmptyState(icon: "wifi.exclamationmark", title: "목록을 불러오지 못했어요", message: error)
                    Button("다시 시도") { model.loadNextPage() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty && !model.hasMore {
                LibraryEmptyState(icon: "square.stack", title: "아직 표시할 항목이 없어요",
                                  message: "다른 검색어나 카테고리로 다시 찾아보세요.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleItems.isEmpty, !model.localQuery.isEmpty, !model.isSearching, !model.isLoading {
                VStack(spacing: 12) {
                    LibraryEmptyState(icon: "magnifyingglass", title: "‘\(model.localQuery)’와 맞는 항목이 없어요",
                                      message: "이 목록의 이름에서 찾았어요.")
                    Button("찾기 지우기") { model.localQuery = "" }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(model.visibleItems) { item in
                            tile(item)
                                .onTapGesture { onOpen(Route(title: item.title, path: item.path)) }
                                .onAppear { if item.id == model.visibleItems.last?.id { model.loadNextPage() } }
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .padding(16)
                    .animation(.spring(duration: 0.5, bounce: 0.25), value: model.localQuery)
                    .animation(.spring(duration: 0.5, bounce: 0.25), value: model.playlistSort)
                    if model.isLoading {
                        ProgressView().padding(.bottom, 20)
                    } else if let error = model.errorMessage {
                        VStack(spacing: 8) {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button("이어서 불러오기") { model.loadNextPage() }
                        }.padding(20)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ item: CollectionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.secondary.opacity(0.15)
                .aspectRatio(model.kind.imageRatio, contentMode: .fit)
                .overlay {
                    AsyncImage(url: URL(string: item.image)) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .aspectRatio(contentMode: model.kind.style == .channel ? .fit : .fill)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(EpoStyle.surface, in: RoundedRectangle(cornerRadius: EpoStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: EpoStyle.radius).strokeBorder(Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
    }
}
