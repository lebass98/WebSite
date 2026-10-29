import SwiftUI
import Combine

/// 영상 목록 화면 (기본 목록·베스트·카테고리·태그·채널 등 공통)
struct VideoListView: View {
    @ObservedObject var model: BrowserModel
    let title: String
    /// 전체 카테고리에서 태그를 고르면 그 목록으로 이동
    var onOpen: (Route) -> Void = { _ in }
    @StateObject private var sheet = SheetState()
    @ObservedObject private var thumbSize = ThumbnailSize.shared
    @ObservedObject private var filters = FilterStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.bold)).lineLimit(1)
                    Text(status)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ListSearchField(text: $model.localQuery, prompt: "이 목록에서 찾기")
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
            FilterBar(model: model, onOpen: onOpen)
            if !filters.applied.isDefault {
                HStack(spacing: 8) {
                    Label("세부 필터 적용 중", systemImage: "line.3.horizontal.decrease.circle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(EpoStyle.accent)
                    Text(filters.applied.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("초기화") { filters.clear() }.font(.caption)
                }
                .padding(.horizontal, 24).padding(.bottom, 12)
            }
            Divider()
            content
        }
        .background(EpoStyle.canvas)
        .task { if model.videos.isEmpty && !model.isLoading { model.reload() } }
        .sheet(item: $sheet.video) { DownloadSheet(video: $0) }
        .navigationTitle(title)
        .navigationSubtitle(model.videos.isEmpty ? "" : "\(model.visibleVideos.count)개 표시")
        .toolbar {
            ToolbarItem {
                Button { model.reload() } label: { Label("새로고침", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
            }
        }
    }

    private var status: String {
        if !model.localQuery.isEmpty {
            return model.isSearching || model.isLoading
                ? "목록 전체에서 찾는 중… \(model.visibleVideos.count)개 찾음"
                : "‘\(model.localQuery)’ \(model.visibleVideos.count)개 찾음"
        }
        return model.isLoading ? "라이브러리를 불러오는 중…" : "\(model.visibleVideos.count)개 표시 · 영상을 선택해 재생하세요"
    }

    @ViewBuilder private var content: some View {
        if let error = model.errorMessage, model.videos.isEmpty {
            VStack(spacing: 12) {
                LibraryEmptyState(icon: "wifi.exclamationmark", title: "연결을 확인해 주세요", message: error)
                Button("다시 시도") { model.reload() }.buttonStyle(.borderedProminent)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleVideos.isEmpty && (model.isLoading || model.videos.isEmpty && model.canLoadMore) {
            ProgressView("불러오는 중…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleVideos.isEmpty, !model.localQuery.isEmpty {
            VStack(spacing: 12) {
                LibraryEmptyState(icon: "magnifyingglass", title: "‘\(model.localQuery)’와 맞는 영상이 없어요",
                                  message: "이 목록의 제목·키워드·올린 사람에서 찾았어요.")
                Button("찾기 지우기") { model.localQuery = "" }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleVideos.isEmpty {
            VStack(spacing: 12) {
                LibraryEmptyState(icon: "line.3.horizontal.decrease.circle", title: "조건에 맞는 영상이 없어요",
                                  message: "세부 필터를 초기화하거나 다른 검색어로 다시 찾아보세요.")
                Button("세부 필터 초기화") { FilterStore.shared.clear() }
                    .buttonStyle(.bordered)
                if model.canLoadMore { Button("더 찾아보기") { model.loadNextPage() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: thumbSize.columns, spacing: 18) {
                    ForEach(model.visibleVideos) { video in
                        VideoCard(video: video, resolution: model.resolutions[video.id], isVR: model.isVR(video),
                                  onUploader: { name, path in
                                      onOpen(Route(title: "\(name) 업로드 영상", path: path + "uploaded-videos/"))
                                  })
                            .onTapGesture { play(video) }
                            .accessibilityAction(named: Text("재생")) { play(video) }
                            .contextMenu { menu(for: video) }
                            .onAppear {
                                // 끝에 가까워지면 다음 페이지 자동으로 불러오기
                                if video.id == model.visibleVideos.last?.id { model.loadNextPage() }
                            }
                    }
                }
                .padding(24)

                footer
            }
        }
    }

    @ViewBuilder private var footer: some View {
        Group {
            if model.isLoading {
                ProgressView()
            } else if let error = model.errorMessage {
                VStack {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("다시 시도") { model.loadNextPage() }
                }
            } else if model.canLoadMore {
                Button("더 불러오기") { model.loadNextPage() }
            }
        }
        .padding(.bottom, 20)
    }

    /// 재생 창을 열고 최근 본 영상에 기록
    private func play(_ video: Video) {
        RecentStore.shared.add(video)
        openWindow.play(video.playerItem)
    }

    @ViewBuilder private func menu(for video: Video) -> some View {
        Button("앱에서 재생") { play(video) }
        Button("다운로드 주소 복사 (최고 화질)") { QuickCopy.bestDownloadURL(for: video) }
        Button("화질 골라서 복사…") { sheet.video = video }
        Button("4K 주소 모으기") { URLCollector.collect4K(for: video) }
        Divider()
        SaveMenuItems(fid: video.fid, videoID: video.id)
        Divider()
        Button("브라우저에서 열기") { NSWorkspace.shared.open(URL(string: video.url)!) }
        Button("링크 복사") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(video.url, forType: .string)
        }
    }
}

/// 툴바의 로그인 상태 버튼 — 누르면 아이디·비밀번호 입력 창이 뜸
struct LoginMenu: View {
    @ObservedObject var session: SiteSession
    @StateObject private var popover = PopoverState()

    var body: some View {
        Button {
            popover.shown.toggle()
        } label: {
            if session.status == .loggingIn {
                Label("로그인 중…", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleAndIcon)
            } else {
                Label(session.status.label, systemImage: session.status == .loggedIn
                      ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(session.status == .loggedIn ? .green : .secondary)
            }
        }
        .help(session.status.label)
        .popover(isPresented: $popover.shown, arrowEdge: .bottom) {
            LoginPanel(session: session)
        }
    }
}

final class PopoverState: ObservableObject {
    @Published var shown = false
}

/// 아이디·비밀번호 입력 + 로그인 버튼
struct LoginPanel: View {
    @ObservedObject var session: SiteSession
    @StateObject private var form = LoginForm()
    @Environment(\.openWindow) private var openWindow

    private var loggedIn: Bool { session.status == .loggedIn }
    private var busy: Bool { session.status == .loggingIn }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibraryHeader(title: loggedIn ? "내 계정" : "사이트 로그인",
                          subtitle: "로그인 상태와 저장된 계정을 관리하세요", icon: "person.crop.circle")

            TextField("아이디 또는 이메일", text: $form.username)
                .textFieldStyle(.roundedBorder)
                .disabled(loggedIn || busy)
            SecureField("비밀번호", text: $form.password)
                .textFieldStyle(.roundedBorder)
                .disabled(loggedIn || busy)
                .onSubmit(login)

            HStack {
                Button(action: login) {
                    HStack(spacing: 6) {
                        if busy { ProgressView().controlSize(.small) }
                        Text(loggedIn ? "로그인됨" : busy ? "로그인 중…" : "로그인")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                // 로그인된 동안은 누를 수 없음
                .disabled(loggedIn || busy || form.username.isEmpty || form.password.isEmpty)

                if loggedIn {
                    Button("로그아웃") { session.logout() }
                }
            }

            LoginStatusText(status: session.status)

            Divider()
            Button("자동 로그인이 안 되면: 사이트 화면에서 직접 로그인…") { openWindow(id: "login") }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            if let cred = Keychain.load() {
                form.username = cred.username
                form.password = cred.password
            }
        }
    }

    private func login() {
        guard !loggedIn, !busy, !form.username.isEmpty, !form.password.isEmpty else { return }
        // 키체인에 저장해 두고 다음부터는 앱을 켤 때 자동 로그인
        Keychain.save(username: form.username.trimmingCharacters(in: .whitespaces), password: form.password)
        session.login()
    }
}

/// 위쪽 정렬·카테고리·게이·전체 카테고리 줄 (화질·길이는 사이드바)
struct FilterBar: View {
    @ObservedObject var model: BrowserModel
    var onOpen: (Route) -> Void
    @StateObject private var popover = PopoverState()

    var body: some View {
        ScrollView(.horizontal) {
        HStack(spacing: 14) {
            if model.isSortable {
                Picker("정렬", selection: $model.order) {
                    ForEach(SortOrder.allCases.filter { $0 != .saved || model.savedListLabel != nil }) { sort in
                        Text(sort == .saved ? model.savedListLabel ?? sort.label : sort.label).tag(sort)
                    }
                }
                .fixedSize()
            }

            if model.source == .browse {
                Picker("카테고리", selection: $model.category) {
                    Text("전체 카테고리").tag(SiteCategory?.none)
                    Divider()
                    ForEach(SiteCategory.sorted) { Text($0.name).tag(SiteCategory?.some($0)) }
                }
                .fixedSize()
            }

            Picker("게이", selection: $model.gay) {
                ForEach(Inclusion.allCases) { Text($0.label).tag($0) }
            }
            .fixedSize()

            Button {
                popover.shown = true
            } label: {
                Label("전체 카테고리", systemImage: "list.bullet.rectangle")
            }
            .popover(isPresented: $popover.shown, arrowEdge: .bottom) {
                AllCategoriesView { tag in
                    popover.shown = false
                    onOpen(Route(title: tag.name, path: tag.path))
                }
                .frame(width: 760, height: 560)
            }

            Spacer()

            ThumbnailSizeSlider()
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        }
        .scrollIndicators(.automatic)
    }
}

/// 썸네일 카드 (마우스를 올리면 장면 미리보기가 넘어감)
struct VideoCard: View {
    let video: Video
    /// nil = 확인 중, 0 = 못 찾음
    let resolution: Int?
    let isVR: Bool
    /// 올린 사람 프로필 바로가기 (이름, /profile/이름/)
    var onUploader: (String, String) -> Void = { _, _ in }
    @StateObject private var hover = HoverState()
    @ObservedObject private var recent = RecentStore.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    private var hovering: Bool { hover.inside }
    private var frame: Int { hover.frame }
    private let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    private var imageURL: URL? {
        if hovering, !video.thumbs.isEmpty { return URL(string: video.thumbs[frame % video.thumbs.count]) }
        return URL(string: video.thumb)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Color.secondary.opacity(0.15)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: imageURL, transaction: .init(animation: nil)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else if phase.error != nil {
                                Image(systemName: "photo").foregroundStyle(.secondary)
                            }
                        }
                        if hover.showVideo, let preview = video.previewURL, let url = URL(string: preview) {
                            PreviewPlayerView(url: url)
                        }
                    }
                    .clipped()

                HStack(spacing: 4) {
                    if recent.watchedIDs.contains(video.id) { badge("봤음", .gray) }
                    if isVR { badge("VR", .orange) }
                    if let resolution, resolution > 0 {
                        badge(resolutionLabel(resolution), resolution >= 1440 ? .purple : .accentColor)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // 즐겨찾기한 영상: 오른쪽 위에 큰 별
                if favorites.isFavorite(video) {
                    FavoriteStar(size: 28)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                Text(video.lengthText)
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.tint, lineWidth: hovering ? 2 : 0))

            Text(video.title)
                .font(.callout.weight(.medium))
                .lineLimit(2, reservesSpace: true)

            HStack(spacing: 10) {
                Label(video.views.formatted(.number.notation(.compactName)), systemImage: "eye")
                Label(String(format: "%.1f", video.rate), systemImage: "star.fill")
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let name = video.uploaderName, let path = video.uploaderPath {
                    Button {
                        onUploader(name, path)
                    } label: {
                        Label(name, systemImage: "person.crop.circle").lineLimit(1)
                    }
                    .buttonStyle(.borderless)
                    .help("\(name) 님이 올린 영상 보기")
                }
                Spacer()
                Text(String(video.added.prefix(10)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(EpoStyle.surface, in: RoundedRectangle(cornerRadius: EpoStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: EpoStyle.radius)
            .strokeBorder(hovering ? EpoStyle.accent.opacity(0.5) : Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onDisappear {
            hover.delayTask?.cancel()
            hover.inside = false
            hover.showVideo = false
        }
        .onHover { inside in
            hover.inside = inside
            hover.frame = 0
            hover.delayTask?.cancel()
            if inside, video.previewURL != nil {
                hover.delayTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled, hover.inside { hover.showVideo = true }
                }
            } else {
                hover.showVideo = false
            }
        }
        // 미리보기 영상이 없는 영상은 예전처럼 장면 사진이 넘어감
        .onReceive(timer) { _ in if hover.inside, video.previewURL == nil { hover.frame += 1 } }
        .help(video.title)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
    }
}

/// 목록 화면 위쪽의 "이 목록에서 찾기" 칸 (Esc로 지움)
struct ListSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("찾기 지우기")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(width: 220)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
    }
}

// 이 환경(Command Line Tools)에는 @State 매크로 플러그인이 없어서 작은 상태 객체로 대신함
final class SearchField: ObservableObject {
    @Published var text = ""
}

/// 목록 화면으로 이동할 곳
struct Route: Hashable {
    let title: String
    let path: String
}

final class SheetState: ObservableObject {
    @Published var video: Video?
}

final class HoverState: ObservableObject {
    @Published var inside = false
    @Published var frame = 0
    /// 마우스를 잠깐 올려 두면 미리보기 영상을 켬 (스쳐 지나갈 때는 안 받음)
    @Published var showVideo = false
    var delayTask: Task<Void, Never>?
}
