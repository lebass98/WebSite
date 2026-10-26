import SwiftUI
import Combine
import WebKit

struct DownloadLink: Identifiable, Hashable {
    let label: String
    let url: String
    var id: String { url }
    /// 주소·이름에서 읽은 세로 픽셀 (모르면 0)
    var height: Int { ResolutionProbe.heights(in: url + " " + label).max() ?? 0 }
    var qualityText: String { height > 0 ? resolutionLabel(height) : "알 수 없는 화질" }
}

/// 다운로드 링크를 찾다 실패한 이유 (화면에 그대로 보여 줌)
struct DownloadError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// 영상 페이지를 몰래 열어 다운로드 링크를 모음 (로그인 쿠키가 함께 쓰임)
@MainActor
final class DownloadLoader: ObservableObject {
    enum State { case loading, done([DownloadLink]), failed(String) }

    @Published private(set) var state = State.loading
    @Published private(set) var copiedURL: String?
    @Published private(set) var resolvingURL: String?

    /// 다운로드 링크로 보이는 a 태그를 모두 모음
    private static let collectJS = """
    const seen = new Set();
    const out = [];
    for (const a of document.querySelectorAll('a[href]')) {
        const href = a.href;
        if (!/\\/dload\\/|\\/download\\/|\\.(mp4|webm|mkv|mov)(\\?|$)/i.test(href)) continue;
        if (seen.has(href)) continue;
        seen.add(href);
        const label = (a.textContent || a.title || '').replace(/\\s+/g, ' ').trim();
        out.push({ label: label || href.split('/').filter(Boolean).slice(-2).join(' '), url: href });
    }
    return JSON.stringify(out);
    """

    func load(pageURL: String) {
        state = .loading
        Task {
            do {
                // 화질 높은 순으로 보여 줌
                state = .done(try await Self.findLinks(pageURL: pageURL).sorted { $0.height > $1.height })
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// 영상 페이지에서 다운로드 링크를 모두 찾음
    static func findLinks(pageURL: String) async throws -> [DownloadLink] {
        guard let url = URL(string: pageURL) else { throw DownloadError("영상 주소가 이상해요.") }
        // 빠른 길: 페이지 HTML만 받아서 링크를 읽음 (약 1초, 숨은 웹페이지는 광고까지 다 떠야 해서 5초 넘게 걸림)
        if let html = try? await SiteScraper.html(url) {
            let links = links(inHTML: html, base: url)
            if !links.isEmpty {
                DebugLog.write("다운로드 링크 \(links.count)개 (HTML): \(pageURL)")
                return links
            }
        }
        let page = HeadlessPage()
        do {
            try await page.load(url)
        } catch {
            DebugLog.write("다운로드 링크 찾기 실패: \(error)")
            throw DownloadError("영상 페이지를 열지 못했어요. VPN이 켜져 있는지 확인해 주세요.")
        }
        // 링크가 늦게 그려지는 경우를 위해 최대 6초 기다림
        var links: [DownloadLink] = []
        let end = Date().addingTimeInterval(6)
        repeat {
            links = try await collect(page)
            if !links.isEmpty { break }
            try await Task.sleep(nanoseconds: 700_000_000)
        } while Date() < end
        DebugLog.write("다운로드 링크 \(links.count)개: \(pageURL)")
        if links.isEmpty {
            let loggedIn = (try? await page.run(SiteSession.isLoggedInJS) as? Bool) ?? false
            throw DownloadError(loggedIn
                ? "이 영상 페이지에서 다운로드 링크를 찾지 못했어요."
                : "다운로드 링크가 없어요. 로그인이 안 된 상태일 수 있어요.")
        }
        return links
    }

    /// HTML 글에서 다운로드 링크(a 태그)를 모음 — collectJS와 같은 기준
    static func links(inHTML html: String, base: URL) -> [DownloadLink] {
        guard let re = try? NSRegularExpression(
            pattern: #"<a[^>]+href="([^"]*(?:/dload/|/download/)[^"]*)"[^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        var seen = Set<String>()
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            guard let h = Range(m.range(at: 1), in: html), let t = Range(m.range(at: 2), in: html),
                  let full = URL(string: SiteScraper.decode(String(html[h])), relativeTo: base)?.absoluteString,
                  seen.insert(full).inserted
            else { return nil }
            let label = SiteScraper.decode(String(html[t]).replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return DownloadLink(label: label.isEmpty ? full : label, url: full)
        }
    }

    private static func collect(_ page: HeadlessPage) async throws -> [DownloadLink] {
        guard let json = try await page.run(Self.collectJS) as? String,
              let rows = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]]
        else { return [] }
        return rows.compactMap { row in
            guard let url = row["url"] else { return nil }
            return DownloadLink(label: row["label"] ?? url, url: url)
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedURL = text
    }

    /// 링크를 따라가서 실제 파일 주소(리다이렉트 끝)를 복사
    func copyFinalURL(of link: DownloadLink) {
        guard let url = URL(string: link.url) else { return }
        resolvingURL = link.url
        Task {
            defer { resolvingURL = nil }
            do {
                let final = try await Self.resolve(url)
                copy(final.absoluteString)
                copiedURL = link.url  // 어느 줄에서 복사했는지 표시용
            } catch {
                DebugLog.write("최종 주소 찾기 실패: \(error)")
                state = .failed("실제 파일 주소를 찾지 못했어요: \(error.localizedDescription)")
            }
        }
    }

    static func resolve(_ url: URL) async throws -> URL {
        // 앱의 로그인 쿠키를 그대로 붙여서 요청
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            .filter { url.host?.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) ?? false }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(HeadlessPage.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")  // 파일 전체를 받지 않음
        for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) { req.setValue(v, forHTTPHeaderField: k) }
        let session = URLSession(configuration: .ephemeral)
        let (_, resp) = try await session.data(for: req)
        guard let final = resp.url else { throw URLError(.badServerResponse) }
        return final
    }
}

/// 다운로드 주소 고르는 창
struct DownloadSheet: View {
    let video: Video
    @StateObject private var loader = DownloadLoader()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LibraryHeader(title: "다운로드 주소", subtitle: "원하는 화질의 주소를 복사하세요", icon: "arrow.down.circle")
            Text(video.title).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Text("화질을 선택해 다운로드 주소를 복사하세요.")
                .font(.caption).foregroundStyle(.secondary)

            switch loader.state {
            case .loading:
                HStack { ProgressView().controlSize(.small); Text("영상 페이지에서 링크 찾는 중…") }
                    .frame(maxWidth: .infinity, minHeight: 80)
            case .failed(let message):
                LibraryEmptyState(icon: "arrow.down.circle", title: "주소를 찾지 못했어요", message: message)
                    .frame(maxWidth: .infinity)
                Button("다시 시도") { loader.load(pageURL: video.url) }.buttonStyle(.borderedProminent)
            case .done(let links):
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(links) { link in row(link) }
                    }
                }
                .frame(maxHeight: 320)
            }

            HStack {
                if loader.copiedURL != nil {
                    Label("클립보드에 복사했어요", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { loader.load(pageURL: video.url) }
    }

    private func row(_ link: DownloadLink) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(link.qualityText) · \(link.label)").font(.callout.weight(.medium)).lineLimit(1)
                Text(link.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if loader.copiedURL == link.url {
                Image(systemName: "checkmark").foregroundStyle(.green)
            }
            Button("주소 복사") { loader.copy(link.url) }
                .help("사이트의 다운로드 링크를 복사")
            Button {
                loader.copyFinalURL(of: link)
            } label: {
                if loader.resolvingURL == link.url { ProgressView().controlSize(.small) } else { Text("파일 주소 복사") }
            }
            .help("링크를 따라가 실제 파일 주소를 복사 (시간이 지나면 만료될 수 있음)")
            .disabled(loader.resolvingURL != nil)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 화면 아래에 잠깐 뜨는 알림
@MainActor
final class Toast: ObservableObject {
    static let shared = Toast()
    @Published private(set) var message: String?
    @Published private(set) var isError = false
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, error: Bool = false, seconds: Double = 3) {
        message = text
        isError = error
        hideTask?.cancel()
        guard seconds > 0 else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { message = nil }
        }
    }
}

struct ToastView: View {
    @ObservedObject var toast = Toast.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let message = toast.message {
            Label(message, systemImage: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
                .foregroundStyle(toast.isError ? .orange : .green)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 6)
                .padding(.bottom, 20)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// "다운로드 주소 복사": 최고 화질 링크를 찾아 바로 복사
@MainActor
enum QuickCopy {
    static func bestDownloadURL(for video: Video) {
        Toast.shared.show("최고 화질 다운로드 주소 찾는 중…", seconds: 0)
        Task {
            do {
                let links = try await DownloadLoader.findLinks(pageURL: video.url)
                // 화질이 같으면 먼저 나온 링크 (보통 기본 형식)
                let best = links.enumerated().max { a, b in
                    a.element.height != b.element.height ? a.element.height < b.element.height : a.offset > b.offset
                }!.element
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(best.url, forType: .string)
                DebugLog.write("최고 화질 복사: \(best.qualityText) \(best.url)")
                Toast.shared.show("\(best.qualityText) 다운로드 주소를 복사했어요")
                // 4K면 주소 목록에도 쌓아 둠
                if best.height >= 2160 { await URLCollector.add(best, video: video) }
            } catch {
                Toast.shared.show(error.localizedDescription, error: true, seconds: 5)
            }
        }
    }
}
