import SwiftUI
import Combine

/// 내 계정 목록에 영상 넣기·빼기 (즐겨찾기, 나중에 볼 영상, 내 플레이리스트)
/// 사이트와 같은 방식으로 /manage-list/ 에 보냄 (로그인 쿠키 사용)
@MainActor
final class SiteActions: ObservableObject {
    static let shared = SiteActions()

    struct Playlist: Identifiable, Hashable {
        let id: String   // 사이트 번호
        let title: String
        var listKey: String { "pl-\(id)" }
    }

    enum List: Hashable {
        case favorite, watchLater, playlist(Playlist)

        var key: String {
            switch self {
            case .favorite: "favorite"
            case .watchLater: "watch-later"
            case .playlist(let p): p.listKey
            }
        }

        var label: String {
            switch self {
            case .favorite: "즐겨찾기"
            case .watchLater: "나중에 볼 영상"
            case .playlist(let p): "플레이리스트 ‘\(p.title)’"
            }
        }
    }

    /// 내 플레이리스트 (로그인하면 한 번 읽어 옴)
    @Published private(set) var playlists: [Playlist] = []
    private var page: HeadlessPage?
    private var bag = Set<AnyCancellable>()

    private init() {
        SiteSession.shared.$userLinks
            .sink { [weak self] links in
                guard let self else { return }
                if let link = links.first(where: { $0.kind == .playlists }) { self.loadPlaylists(from: link.url) } else { self.playlists = [] }
            }
            .store(in: &bag)
    }

    func loadPlaylists(from url: String) {
        guard let u = URL(string: url) else { return }
        Task {
            do {
                let html = try await SiteScraper.html(u)
                playlists = Self.parsePlaylists(html)
                DebugLog.write("내 플레이리스트 \(playlists.count)개")
            } catch {
                DebugLog.write("내 플레이리스트 읽기 실패: \(error)")
            }
        }
    }

    private static func parsePlaylists(_ html: String) -> [Playlist] {
        guard let re = try? NSRegularExpression(pattern: #"<div class="mb mbplaylist" id="pl(\d+)">[\s\S]*?class="mbtitphoto2">([^<]+)<"#) else { return [] }
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            guard let i = Range(m.range(at: 1), in: html), let t = Range(m.range(at: 2), in: html) else { return nil }
            return Playlist(id: String(html[i]), title: SiteScraper.decode(String(html[t])))
        }
    }

    /// 넣기(add) 또는 빼기(remove)
    func change(_ list: List, fid: Int, add: Bool, videoID: String? = nil) {
        guard SiteSession.shared.status == .loggedIn else {
            Toast.shared.show("로그인해야 쓸 수 있어요.", error: true)
            return
        }
        guard fid > 0 else {
            Toast.shared.show("이 영상의 사이트 번호를 몰라서 저장할 수 없어요. 목록에서 다시 열어 주세요.", error: true, seconds: 5)
            return
        }
        Task {
            let ok = await send(["type": "video", "fid": String(fid), "list": list.key, "action": add ? "add" : "remove"])
            if ok {
                Toast.shared.show(add ? "\(list.label)에 넣었어요" : "\(list.label)에서 뺐어요")
                // 썸네일 별 표시 바로 반영
                if case .favorite = list {
                    FavoritesStore.shared.mark(fid: fid, favorite: add)
                    if !add, let id = videoID { FavoritesStore.shared.unmark(id: id) }
                }
                // 내 계정 목록이 열려 있으면 다음에 열 때 새로 불러오게
                ModelCache.shared.forgetUserPages()
            } else {
                Toast.shared.show("\(list.label) 저장에 실패했어요.", error: true)
            }
        }
    }

    /// 사이트 페이지 안에서 사이트와 똑같이 요청 (쿠키·보안 헤더가 그대로 붙음)
    private func send(_ data: [String: String]) async -> Bool {
        do {
            if page == nil {
                let p = HeadlessPage()
                try await p.load(SiteSession.home)
                page = p
            }
            let js = """
            const body = new URLSearchParams(data);
            const res = await fetch('/manage-list/', {
                method: 'POST', credentials: 'include',
                headers: { 'X-Requested-With': 'XMLHttpRequest',
                           // 사이트가 요청마다 확인하는 보안 값 (페이지에 들어 있음)
                           'X-CSRF-TOKEN': (window.EP && EP.user && EP.user.csrfToken) || '',
                           'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
                body });
            return res.status + ' ' + await res.text();
            """
            let result = try await page!.run(js, ["data": data]) as? String ?? ""
            DebugLog.write("목록 저장 \(data["action"] ?? "") \(data["list"] ?? ""): \(result.prefix(120))")
            // 응답 예: 200 {"status":1,...}
            return result.hasPrefix("200") && result.range(of: #""status"\s*:\s*"?1"#, options: .regularExpression) != nil
        } catch {
            DebugLog.write("목록 저장 실패: \(error)")
            page = nil
            return false
        }
    }
}

/// 오른쪽 클릭 메뉴·재생 창에 붙는 "저장" 메뉴 항목
struct SaveMenuItems: View {
    let fid: Int
    var videoID: String? = nil
    @ObservedObject private var actions = SiteActions.shared

    var body: some View {
        Menu("즐겨찾기") {
            Button("즐겨찾기에 넣기") { actions.change(.favorite, fid: fid, add: true, videoID: videoID) }
            Button("즐겨찾기에서 빼기") { actions.change(.favorite, fid: fid, add: false, videoID: videoID) }
        }
        Menu("나중에 볼 영상") {
            Button("나중에 볼 영상에 넣기") { actions.change(.watchLater, fid: fid, add: true) }
            Button("나중에 볼 영상에서 빼기") { actions.change(.watchLater, fid: fid, add: false) }
        }
        Menu("플레이리스트") {
            if actions.playlists.isEmpty {
                Text("내 플레이리스트가 없어요")
                Button("사이트에서 플레이리스트 만들기…") {
                    if let link = SiteSession.shared.userLinks.first(where: { $0.kind == .playlists }),
                       let url = URL(string: link.url) {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                ForEach(actions.playlists) { p in
                    Menu(p.title) {
                        Button("이 플레이리스트에 넣기") { actions.change(.playlist(p), fid: fid, add: true) }
                        Button("이 플레이리스트에서 빼기") { actions.change(.playlist(p), fid: fid, add: false) }
                    }
                }
            }
        }
    }
}
