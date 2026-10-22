import SwiftUI
import Combine

/// 내 계정 페이지가 어떤 형식인지 열어 보고 판단
@MainActor
final class UserPageModel: ObservableObject {
    enum Mode: Equatable {
        case detecting
        case videos(path: String)
        case collection(CollectionKind)
        case web(URL)
    }

    let link: UserLink
    @Published private(set) var mode = Mode.detecting

    init(link: UserLink) { self.link = link }

    func detect() {
        guard mode == .detecting, let url = URL(string: link.url) else { return }
        // 프로필·설정은 사이트 화면 그대로
        if link.kind == .profile || link.kind == .settings {
            mode = .web(url)
            return
        }
        Task {
            let path = url.path.hasSuffix("/") ? url.path : url.path + "/"
            do {
                let html = try await SiteScraper.html(url)
                let c = SiteScraper.cardCounts(html)
                DebugLog.write("내 페이지 형식 \(link.kind.rawValue): 영상 \(c.videos), 플레이리스트 \(c.playlists), 스타 \(c.pornstars), 채널 \(c.channels)")
                let title = link.kind.label
                if c.videos > 0 {
                    mode = .videos(path: path)
                } else if c.playlists > 0 {
                    mode = .collection(.custom(title: title, path: path, style: .playlist))
                } else if c.pornstars > 0 {
                    mode = .collection(.custom(title: title, path: path, style: .pornstar))
                } else if c.channels > 0 {
                    mode = .collection(.custom(title: title, path: path, style: .channel))
                } else {
                    // 비어 있거나 다른 형식이면 사이트 화면으로
                    mode = .web(url)
                }
            } catch {
                DebugLog.write("내 페이지 열기 실패: \(error)")
                mode = .web(url)
            }
        }
    }
}

/// 내 계정 메뉴 화면 (영상 목록·목록·사이트 화면 중 맞는 것으로)
struct UserPageView: View {
    @StateObject private var model: UserPageModel
    var onOpen: (Route) -> Void

    init(link: UserLink, onOpen: @escaping (Route) -> Void) {
        _model = StateObject(wrappedValue: UserPageModel(link: link))
        self.onOpen = onOpen
    }

    var body: some View {
        Group {
            switch model.mode {
            case .detecting:
                ProgressView("불러오는 중…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .videos(let path):
                VideoListView(model: ModelCache.shared.videos(.page(path)), title: model.link.kind.label, onOpen: onOpen)
            case .collection(let kind):
                CollectionView(model: ModelCache.shared.collection(kind), onOpen: onOpen)
            case .web(let url):
                EmbedWebView(url: url, allowNavigation: true)
                    .navigationTitle(model.link.kind.label)
                    .toolbar {
                        ToolbarItem {
                            Button { NSWorkspace.shared.open(url) } label: { Label("브라우저에서 열기", systemImage: "safari") }
                        }
                    }
            }
        }
        .task { model.detect() }
    }
}
