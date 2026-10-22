import Foundation
import WebKit

/// 사이트 로그인 상태 관리 (앱 시작 시 키체인 정보로 자동 로그인)
@MainActor
final class SiteSession: ObservableObject {
    static let shared = SiteSession()

    enum Status: Equatable {
        case noCredentials, loggedOut, loggingIn, loggedIn, failed(String)

        var label: String {
            switch self {
            case .noCredentials: "로그인 정보 없음"
            case .loggedOut: "로그아웃됨"
            case .loggingIn: "로그인 중…"
            case .loggedIn: "로그인됨"
            case .failed: "로그인 실패"
            }
        }
    }

    @Published private(set) var status = Status.noCredentials {
        didSet {
            if status == .loggedIn, oldValue != .loggedIn { collectUserLinks() }
            if status != .loggedIn { userLinks = [] }
        }
    }
    /// 오른쪽 위 계정 메뉴 (내 프로필, 구독, 즐겨찾기 …) — 로그인하면 사이트에서 읽어 옴
    @Published private(set) var userLinks: [UserLink] = []
    private var page: HeadlessPage?
    private var started = false

    static let home = URL(string: "https://www.eporner.com/")!
    static let loginPage = URL(string: "https://www.eporner.com/login/")!

    /// 로그인됐는지 판단: 로그아웃 링크가 있고 비밀번호 칸이 없음
    static let isLoggedInJS = """
    return !!document.querySelector('a[href*="logout" i]') && !document.querySelector('input[type=password]');
    """

    /// 앱을 켤 때 한 번만
    func startIfNeeded() {
        guard !started else { return }
        started = true
        login()
    }

    func login() {
        guard status != .loggingIn else { return }
        guard let cred = Keychain.load() else {
            status = .noCredentials
            return
        }
        status = .loggingIn
        Task { await performLogin(username: cred.username, password: cred.password) }
    }

    /// 화면에 보이는 로그인 창을 닫은 뒤 등, 상태만 다시 확인
    func refreshStatus() {
        Task {
            let page = HeadlessPage()
            self.page = page
            do {
                try await page.load(Self.home)
                if await page.wait(until: Self.isLoggedInJS, seconds: 2) { status = .loggedIn }
            } catch {
                DebugLog.write("로그인 상태 확인 실패: \(error)")
            }
        }
    }

    private func performLogin(username: String, password: String) async {
        let page = HeadlessPage()
        self.page = page
        defer { self.page = nil }
        do {
            // 저장된 쿠키로 이미 로그인돼 있으면 끝
            try await page.load(Self.home)
            if await page.wait(until: Self.isLoggedInJS, seconds: 1.5) {
                DebugLog.write("이미 로그인 상태")
                status = .loggedIn
                return
            }

            // 사이트 로그인 창과 같은 방식: /xhr/login/ 에 아이디·비밀번호를 보냄 (값은 인자로 안전하게 전달)
            let raw = try await page.run(Self.loginJS, ["login": username, "pass": password]) as? String ?? ""
            let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
            let json = parts.count > 1 ? (try? JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any]) : nil
            let code = (json?["status"] as? Int) ?? Int(json?["status"] as? String ?? "") ?? -1
            DebugLog.write("로그인 요청 결과: HTTP \(parts.first ?? "?"), status \(code)")

            if code == 1 {
                // 쿠키가 잡혔는지 홈에서 한 번 더 확인
                try await page.load(Self.home)
                if await page.wait(until: Self.isLoggedInJS, seconds: 4) {
                    status = .loggedIn
                } else {
                    status = .failed("로그인은 됐다고 나왔는데 확인이 안 돼요. ‘다시 로그인’을 눌러 보세요.")
                }
            } else {
                // 사이트가 알려 준 이유 (예: 아이디·비밀번호 틀림)
                let head = SiteScraper.decode((json?["msg_head"] as? String ?? "").replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
                let body = SiteScraper.decode((json?["msg_body"] as? String ?? "").replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
                let reason = [head, body].filter { !$0.isEmpty }.joined(separator: " ")
                DebugLog.write("로그인 거절 이유: \(reason.isEmpty ? "(없음)" : reason)")
                status = .failed(reason.isEmpty
                    ? "로그인하지 못했어요. 아이디·비밀번호를 확인하거나 ‘로그인 창 열기’로 직접 로그인해 보세요."
                    : "사이트 응답: \(reason)")
            }
        } catch {
            DebugLog.write("로그인 실패: \(error)")
            status = .failed("사이트에 연결하지 못했어요. VPN이 켜져 있는지 확인해 주세요.")
        }
    }

    /// 계정 메뉴 링크 모으기 (주소만 로그에 남김)
    private func collectUserLinks() {
        Task {
            let page = HeadlessPage()
            do {
                try await page.load(Self.home)
                _ = await page.wait(until: Self.isLoggedInJS, seconds: 3)
                guard let json = try await page.run(Self.userLinksJS) as? String,
                      let rows = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]]
                else { return }
                userLinks = UserLink.pick(from: rows)
                DebugLog.write("계정 메뉴 \(userLinks.count)개: " + userLinks.map { "\($0.kind.rawValue)=\($0.url)" }.joined(separator: ", "))
            } catch {
                DebugLog.write("계정 메뉴 읽기 실패: \(error)")
            }
        }
    }

    /// 계정 메뉴로 보이는 링크 (글자나 주소로 판단)
    private static let userLinksJS = """
    const out = [];
    const seen = new Set();
    for (const a of document.querySelectorAll('a[href]')) {
        const text = (a.textContent || '').replace(/\\s+/g, ' ').trim();
        const href = a.href;
        const byText = /^(My profile|Subscriptions|Watch later|Favorite videos|Watched videos|Uploaded videos|Playlists|Settings|Logout)$/i.test(text);
        const byHref = /\\/profile\\/|logout|settings|favorite|watch|subscri/i.test(href);
        if (!(byText || byHref)) continue;
        const key = text + '|' + href;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ text, href });
    }
    return JSON.stringify(out);
    """

    func logout() {
        Task {
            // 사이트에서도 로그아웃
            try? await HeadlessPage().load(URL(string: "https://www.eporner.com/logout/")!)
            let store = WKWebsiteDataStore.default()
            let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                   for: records.filter { $0.displayName.contains("eporner") })
            status = Keychain.load() == nil ? .noCredentials : .loggedOut
        }
    }

    /// 사이트 스크립트와 같은 로그인 요청
    private static let loginJS = """
    const body = new URLSearchParams({ xhr: '1', act: 'login', login: login, pass: pass, ref: '/' });
    const res = await fetch('/xhr/login/', {
        method: 'POST', credentials: 'include',
        headers: { 'X-Requested-With': 'XMLHttpRequest',
                   'X-CSRF-TOKEN': (window.EP && EP.user && EP.user.csrfToken) || '',
                   'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
        body });
    return res.status + ' ' + await res.text();
    """
}

/// 계정 메뉴 한 칸
struct UserLink: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case profile = "My profile", subscriptions = "Subscriptions", watchLater = "Watch later"
        case favorites = "Favorite videos", watched = "Watched videos", uploaded = "Uploaded videos"
        case playlists = "Playlists", settings = "Settings", logout = "Logout"

        var label: String {
            switch self {
            case .profile: "내 프로필"
            case .subscriptions: "구독"
            case .watchLater: "나중에 볼 영상"
            case .favorites: "즐겨찾기 영상"
            case .watched: "시청한 영상"
            case .uploaded: "업로드한 영상"
            case .playlists: "내 플레이리스트"
            case .settings: "설정"
            case .logout: "로그아웃"
            }
        }

        var icon: String {
            switch self {
            case .profile: "person.crop.circle"
            case .subscriptions: "bell"
            case .watchLater: "clock"
            case .favorites: "heart"
            case .watched: "eye"
            case .uploaded: "square.and.arrow.up"
            case .playlists: "music.note.list"
            case .settings: "gearshape"
            case .logout: "rectangle.portrait.and.arrow.right"
            }
        }
    }

    let kind: Kind
    let url: String
    var id: String { kind.rawValue }

    /// 글자가 메뉴 이름과 같은 링크를 고름 (플레이리스트는 내 프로필 안의 것)
    static func pick(from rows: [[String: String]]) -> [UserLink] {
        Kind.allCases.compactMap { kind in
            let matches = rows.filter { ($0["text"] ?? "").caseInsensitiveCompare(kind.rawValue) == .orderedSame }
            let row = kind == .playlists
                ? matches.first { ($0["href"] ?? "").contains("/profile/") } ?? matches.first { !($0["href"] ?? "").contains("best-playlists") }
                : matches.first
            guard let href = row?["href"], !href.isEmpty, !href.hasPrefix("javascript") else { return nil }
            return UserLink(kind: kind, url: href)
        }
    }
}
