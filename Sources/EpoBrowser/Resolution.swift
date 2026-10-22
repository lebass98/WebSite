import Foundation
import WebKit

/// 세로 픽셀 수를 화면 표시용 글자로 (2160 → 4K)
func resolutionLabel(_ height: Int) -> String {
    switch height {
    case 2160...: "4K"
    case 1440..<2160: "2K"
    default: "\(height)p"
    }
}

/// 제목·키워드·주소로 VR 영상인지 판단
enum VRDetector {
    private static let regex = try! NSRegularExpression(
        pattern: #"(?<![a-z0-9])vr(?![a-z])|vr180|vr360|virtual reality|oculus|quest ?[23]|\b180 ?(°|deg)|\b360 ?(°|deg)|\bsbs\b"#,
        options: [.caseInsensitive])

    static func isVR(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

struct ProbeResult {
    /// 세로 픽셀, 못 찾으면 0
    let height: Int
    /// 다운로드 파일 이름 등에 VR 표시가 있음
    let isVR: Bool
}

/// 영상 페이지 HTML에서 다운로드 링크를 보고 최고 화질을 알아냄
enum ResolutionProbe {
    private static let known = [2160, 1440, 1080, 720, 480, 360, 240]

    static func probe(pageURL: String, cookieHeader: [String: String]) async throws -> ProbeResult {
        guard let url = URL(string: pageURL) else { return ProbeResult(height: 0, isVR: false) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(HeadlessPage.userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in cookieHeader { req.setValue(v, forHTTPHeaderField: k) }
        let (data, _) = try await URLSession.shared.data(for: req)
        let html = String(decoding: data, as: UTF8.self)
        let links = matches(of: #"/dload/[^"'\s<>]+"#, in: html)
        return ProbeResult(height: parse(html), isVR: links.contains(where: VRDetector.isVR))
    }

    static func parse(_ html: String) -> Int {
        // 1순위: 다운로드 링크 주소 안의 숫자 (예: /dload/abc/1080/abc-1080p.mp4)
        let links = matches(of: #"/dload/[^"'\s<>]+"#, in: html)
        var best = links.flatMap(heights(in:)).max() ?? 0
        if best > 0 { return best }

        // 2순위: 다운로드 영역 근처의 "1080p" 같은 글자
        if let range = html.range(of: "download", options: .caseInsensitive) {
            let tail = html[range.lowerBound...].prefix(6000)
            best = heights(in: String(tail)).max() ?? 0
        }
        return best
    }

    static func heights(in text: String) -> [Int] {
        matches(of: #"(?<![0-9])(2160|1440|1080|720|480|360|240)p?(?![0-9])"#, in: text)
            .compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "p"))) }
            .filter(known.contains)
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// 앱 로그인 쿠키를 요청 헤더로
    @MainActor
    static func cookieHeader() async -> [String: String] {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            .filter { $0.domain.contains("eporner") }
        return HTTPCookie.requestHeaderFields(with: cookies)
    }
}
