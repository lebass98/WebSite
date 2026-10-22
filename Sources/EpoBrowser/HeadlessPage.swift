import Foundation
import WebKit

/// 화면에 안 보이는 웹 페이지 (로그인, 다운로드 링크 찾기에 사용)
/// 쿠키 저장소가 재생 창과 같아서 여기서 로그인하면 앱 전체가 로그인 상태가 됨
@MainActor
final class HeadlessPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    nonisolated static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    let webView: WKWebView
    private var pending: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)
        super.init()
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// 페이지를 열고 다 뜰 때까지 기다림
    func load(_ url: URL, timeout: Double = 25) async throws {
        pending?.resume(throwing: CancellationError())
        pending = nil
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { cont in
                    self.pending = cont
                    self.webView.load(URLRequest(url: url))
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            try await group.next()
        }
        if let cont = pending { pending = nil; cont.resume() }
    }

    /// 페이지 안에서 자바스크립트 실행 (arguments는 문자열에 끼워 넣지 않고 안전하게 전달됨)
    func run(_ js: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(js, arguments: arguments, in: nil, contentWorld: .page)
    }

    /// 조건이 참이 될 때까지 0.5초마다 확인
    func wait(until js: String, seconds: Double) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let ok = try? await run(js) as? Bool, ok { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let cont = pending { pending = nil; cont.resume() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: error)
    }

    private func finish(with error: Error) {
        // 다른 페이지로 넘어가면서 취소된 것(-999)은 실패로 보지 않음
        if (error as NSError).code == NSURLErrorCancelled { return }
        if let cont = pending { pending = nil; cont.resume(throwing: error) }
    }

    // 팝업 창은 열지 않음
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }
}
