import Foundation

/// 사이트 카테고리 (정렬 옆 카테고리 버튼, 카테고리 메뉴에 사용)
struct SiteCategory: Hashable, Identifiable {
    let slug: String
    let name: String
    var id: String { slug }
    var path: String { "/cat/\(slug)/" }

    static let all: [SiteCategory] = [
        ("4k-porn", "4K Porn"), ("hd-1080p", "HD 1080p"), ("60fps", "60 FPS"), ("vr-porn", "VR Porn"),
        ("japanese", "Japanese"), ("anal", "Anal"), ("pov-porn", "POV"), ("indian", "Indian"), ("milf", "MILF"),
        ("hentai", "Hentai"), ("bbw", "BBW"), ("pinay", "Pinay"), ("amateur", "Amateur"), ("asian", "Asian"),
        ("asmr", "ASMR"), ("bdsm", "BDSM"), ("big-ass", "Big Ass"), ("big-dick", "Big Dick"), ("big-tits", "Big Tits"),
        ("cosplay", "Cosplay"), ("creampie", "Creampie"), ("cuckold", "Cuckold"), ("ebony", "Ebony"),
        ("footjob", "Footjob"), ("group-sex", "Group Sex"), ("hardcore", "Hardcore"), ("homemade", "Homemade"),
        ("indonesia", "Indonesia"), ("interracial", "Interracial"), ("latina", "Latina"), ("massage", "Massage"),
        ("mature", "Mature"), ("orgy", "Orgy"), ("redhead", "Redhead"), ("stepmom", "Stepmom"),
        ("stepsister", "Stepsister"), ("teens", "Teen"), ("threesome", "Threesome"), ("vintage", "Vintage"),
        ("gay", "Gay"), ("lesbians", "Lesbian"), ("shemale", "Transgender"), ("hd-sex", "HD Sex"), ("ai", "AI"),
        ("bisexual", "Bisexual"), ("blonde", "Blonde"), ("blowjob", "Blowjob"), ("bondage", "Bondage"),
        ("brunette", "Brunette"), ("bukkake", "Bukkake"), ("casting", "Casting"), ("compilation", "Compilation"),
        ("cumshot", "Cumshot"), ("double-penetration", "Double Penetration"), ("fat", "Fat"), ("fetish", "Fetish"),
        ("fisting", "Fisting"), ("for-women", "For Women"), ("gloryhole", "Gloryhole"), ("handjob", "Handjob"),
        ("hotel", "Hotel"), ("hotwife", "Hotwife"), ("housewives", "Housewives"), ("hq-porn", "HQ Porn"),
        ("lingerie", "Lingerie"), ("masturbation", "Masturbation"), ("nurse", "Nurses"), ("office", "Office"),
        ("old-man", "Older Men"), ("outdoor", "Outdoor"), ("pawg", "PAWG"), ("petite", "Petite"),
        ("pornstar", "Pornstar"), ("pregnant", "Pregnant"), ("public", "Public"), ("small-tits", "Small Tits"),
        ("squirt", "Squirt"), ("striptease", "Striptease"), ("students", "Students"), ("swingers", "Swinger"),
        ("toys", "Toys"), ("uniform", "Uniform"), ("webcam", "Webcam"), ("uncategorized", "Uncategorized"),
    ].map { SiteCategory(slug: $0.0, name: $0.1) }

    /// 메뉴에서 보기 좋게 이름순
    static let sorted = all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

/// 플레이리스트·포르노스타·채널 목록의 한 칸
struct CollectionItem: Identifiable, Hashable {
    let path: String
    let title: String
    let image: String
    let subtitle: String
    var id: String { path }
}

/// 목록 종류 (사이트 상단 메뉴, 검색 종류)
enum CollectionKind: Hashable {
    case playlists, pornstarsFemale, pornstarsMale, channels
    case searchPornstars(String), searchPlaylists(String)
    /// 내 계정 페이지 등 주소를 직접 주는 목록
    case custom(title: String, path: String, style: Style)

    var path: String {
        switch self {
        case .playlists: "/best-playlists/"
        case .pornstarsFemale: "/pornstar-list/female/"
        case .pornstarsMale: "/pornstar-list/male/"
        case .channels: "/channels/"
        case .searchPornstars(let q): "/search-pornstars/\(FilterStore.slug(q))/"
        case .searchPlaylists(let q): "/search-playlists/\(FilterStore.slug(q))/"
        case .custom(_, let path, _): path
        }
    }

    enum Style { case playlist, pornstar, channel }

    var style: Style {
        switch self {
        case .playlists, .searchPlaylists: .playlist
        case .pornstarsFemale, .pornstarsMale, .searchPornstars: .pornstar
        case .channels: .channel
        case .custom(_, _, let style): style
        }
    }

    var title: String {
        switch self {
        case .playlists: "플레이리스트"
        case .pornstarsFemale: "포르노스타 (여성)"
        case .pornstarsMale: "포르노스타 (남성)"
        case .channels: "채널"
        case .searchPornstars(let q): "포르노스타 검색: \(q)"
        case .searchPlaylists(let q): "플레이리스트 검색: \(q)"
        case .custom(let title, _, _): title
        }
    }

    var paged: Bool { style != .channel }

    /// 칸 이미지 비율 (가로/세로)
    var imageRatio: CGFloat {
        switch style {
        case .playlist: 16 / 9
        case .pornstar: 4 / 3
        case .channel: 2
        }
    }
}

/// 전체 카테고리(A~Z)의 한 줄
struct TagItem: Identifiable, Hashable {
    let name: String
    let path: String
    let count: String
    var id: String { path }
}

/// 사이트 페이지(HTML)를 읽어 영상·목록을 꺼냄 (API에 없는 메뉴용)
enum SiteScraper {
    static let base = "https://www.eporner.com"

    /// path(예: /cat/anal/) + 정렬 + 페이지 번호로 주소 만들기 (2페이지부터 /2/)
    static func url(path: String, sort: String = "", page: Int) -> URL {
        var s = base + path
        if !sort.isEmpty { s += sort + "/" }
        if page > 1 { s += "\(page)/" }
        return URL(string: s)!
    }

    /// 사이트가 바꿔 보내는 최종 주소 (예: /tag/japanese/ → /tag/japanese-CwEfWTjN/)
    static func finalURL(_ url: URL) async throws -> URL {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(HeadlessPage.userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in await ResolutionProbe.cookieHeader() { req.setValue(v, forHTTPHeaderField: k) }
        let (_, resp) = try await URLSession.shared.data(for: req)
        return resp.url ?? url
    }

    static func html(_ url: URL) async throws -> String {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(HeadlessPage.userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in await ResolutionProbe.cookieHeader() { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 404 { return "" }  // 마지막 페이지 다음
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "서버 응답 코드 \(http.statusCode)"])
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: 영상 카드

    struct ScrapedVideo {
        let video: Video
        /// 카드에 적힌 화질 (세로 픽셀, 없으면 0)
        let height: Int
    }

    static func videos(path: String, sort: String, page: Int) async throws -> [ScrapedVideo] {
        let page = try await html(url(path: path, sort: sort, page: page))
        return parseVideos(page)
    }

    static func parseVideos(_ html: String) -> [ScrapedVideo] {
        blocks(of: html, startingWith: #"<div class="mb[ "][^>]*data-id="#).compactMap { block in
            guard let hash = first(#"href="/video-([A-Za-z0-9]+)/"#, in: block),
                  let link = first(#"href="(/video-[^"]+)""#, in: block)
            else { return nil }
            let title = decode(first(#"class="mbtit"><a[^>]*>([^<]*)</a>"#, in: block)
                               ?? first(#"alt="([^"]*)""#, in: block) ?? "")
            var thumb = first(#"data-src="(https?://[^"]+)""#, in: block) ?? first(#"src="(https?://[^"]+)""#, in: block) ?? ""
            thumb = thumb.replacingOccurrences(of: "&amp;", with: "&")
            let length = first(#"class="mbtim"[^>]*>([^<]+)<"#, in: block) ?? ""
            let rating = Double(first(#"class="mbrate"[^>]*>(\d+)%"#, in: block) ?? "") ?? 0
            let views = Int((first(#"class="mbvie"[^>]*>([\d,]+)<"#, in: block) ?? "").replacingOccurrences(of: ",", with: "")) ?? 0
            let quality = first(#"class="mvhdico"[^>]*><span>([^<]+)</span>"#, in: block) ?? ""
            let fid = Int(first(#"data-id="(\d+)""#, in: block) ?? "") ?? 0
            // <span class="mb-uploader"><a href="/profile/이름/" …>이름</a>
            let uploaderPath = first(#"class="mb-uploader"><a href="(/profile/[^"]+)""#, in: block)
            let uploaderName = first(#"class="mb-uploader"><a [^>]*>([^<]+)</a>"#, in: block).map(decode)
            // data-vp="번호|…": 번호가 0보다 크면 미리보기 영상이 있음 (썸네일 폴더/번호-preview.mp4)
            let vp = Int(first(#"data-vp="(\d+)\|"#, in: block) ?? "") ?? 0
            let preview: String? = vp > 0 && thumb.contains("/")
                ? String(thumb[..<thumb.lastIndex(of: "/")!]) + "/\(vp)-preview.mp4"
                : nil

            let video = Video(
                id: hash, title: title, keywords: "", views: views,
                rate: rating / 20,  // 사이트는 %, 카드는 5점 만점
                url: base + link, added: "",
                lengthSec: seconds(length), lengthText: length,
                embed: "\(base)/embed/\(hash)/", thumb: thumb, thumbs: hoverThumbs(thumb),
                fid: fid, previewURL: preview?.replacingOccurrences(of: "static-key-cdn", with: "static-ca-cdn"),
                uploaderName: uploaderName, uploaderPath: uploaderPath)
            return ScrapedVideo(video: video, height: height(fromBadge: quality))
        }
    }

    /// "4K", "1080p" 같은 글자를 세로 픽셀로
    static func height(fromBadge text: String) -> Int {
        let t = text.uppercased()
        if t.contains("4K") || t.contains("2160") { return 2160 }
        if t.contains("2K") || t.contains("1440") { return 1440 }
        return Int(t.filter(\.isNumber)) ?? 0
    }

    /// ".../12345/5_240.jpg" → 1~15번 장면 미리보기
    private static func hoverThumbs(_ thumb: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"/\d+_(\d+)\.jpg"#),
              let m = re.firstMatch(in: thumb, range: NSRange(thumb.startIndex..., in: thumb)),
              let r = Range(m.range, in: thumb), let size = Range(m.range(at: 1), in: thumb)
        else { return [] }
        let suffix = thumb[size]
        return (1...15).map { thumb.replacingCharacters(in: r, with: "/\($0)_\(suffix).jpg") }
    }

    private static func seconds(_ text: String) -> Int {
        text.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    // MARK: 플레이리스트·포르노스타·채널

    static func collection(_ kind: CollectionKind, page: Int, query: [URLQueryItem] = [], sort: String = "") async throws -> [CollectionItem] {
        var comps = URLComponents(url: url(path: kind.path, sort: sort, page: page), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        let html = try await html(comps.url!)
        switch kind.style {
        case .playlist:
            return blocks(of: html, startingWith: #"<div class="mb mbplaylist""#).compactMap { b in
                guard let path = first(#"<a href="(/[^"]+/playlist/[^"]+)""#, in: b) else { return nil }
                let count = first(#"mbphoto2_playlistico">(\d+)<"#, in: b).map { "영상 \($0)개" } ?? ""
                return CollectionItem(path: path,
                                      title: decode(first(#"class="mbtitphoto2">([^<]+)<"#, in: b) ?? ""),
                                      image: first(#"src="(https?://[^"]+)""#, in: b) ?? "", subtitle: count)
            }
        case .pornstar:
            return blocks(of: html, startingWith: #"<div class="mbprofile">"#).compactMap { b in
                guard let path = first(#"href="(/pornstar/[^"]+)""#, in: b) else { return nil }
                let count = first(#"Videos: </span>([\d,]+)"#, in: b).map { "영상 \($0)개" } ?? ""
                return CollectionItem(path: path, title: decode(first(#"title="([^"]+)""#, in: b) ?? ""),
                                      image: first(#"src="(https?://[^"]+)""#, in: b) ?? "", subtitle: count)
            }
        case .channel:
            return blocks(of: html, startingWith: #"<div class="channelscategoriesbox""#).compactMap { b in
                guard let path = first(#"href="(/channel/[^"]+)""#, in: b) else { return nil }
                let count = first(#"<span>([\d,]+)</span> Videos"#, in: b).map { "영상 \($0)개" } ?? ""
                return CollectionItem(path: path, title: decode(first(#"<h2>([^<]+)</h2>"#, in: b) ?? ""),
                                      image: first(#"class="cclogo" src="([^"]+)""#, in: b) ?? "", subtitle: count)
            }
        }
    }

    // MARK: 전체 카테고리 (A~Z)

    static func tags(letter: String) async throws -> [TagItem] {
        let html = try await html(URL(string: "\(base)/cats/\(letter)/")!)
        guard let start = html.range(of: "class=\"allcatslist\"") else { return [] }
        let list = String(html[start.lowerBound...].prefix(400_000))
        guard let re = try? NSRegularExpression(pattern: #"<a href="(/tag/[^"]+)">([^<]+)</a><span>([^<]*)</span>"#) else { return [] }
        return re.matches(in: list, range: NSRange(list.startIndex..., in: list)).compactMap { m in
            guard let p = Range(m.range(at: 1), in: list), let n = Range(m.range(at: 2), in: list),
                  let c = Range(m.range(at: 3), in: list) else { return nil }
            return TagItem(name: decode(String(list[n])), path: String(list[p]), count: String(list[c]))
        }
    }

    // MARK: 글자 처리

    /// 페이지에 어떤 카드가 몇 개 있는지 (내 계정 페이지 형식 판단용)
    static func cardCounts(_ html: String) -> (videos: Int, playlists: Int, pornstars: Int, channels: Int) {
        (parseVideos(html).count,
         blocks(of: html, startingWith: #"<div class="mb mbplaylist""#).count,
         blocks(of: html, startingWith: #"<div class="mbprofile">"#).count,
         blocks(of: html, startingWith: #"<div class="channelscategoriesbox""#).count)
    }

    /// 시작 표시가 나올 때마다 잘라서 덩어리로
    private static func blocks(of html: String, startingWith pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        let starts = re.matches(in: html, range: NSRange(location: 0, length: ns.length)).map(\.range.location)
        return starts.enumerated().map { i, start in
            let end = i + 1 < starts.count ? starts[i + 1] : min(ns.length, start + 6000)
            return ns.substring(with: NSRange(location: start, length: end - start))
        }
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.numberOfRanges > 1 ? m.range(at: 1) : m.range, in: text)
        else { return nil }
        return String(text[r])
    }

    /// &amp; &#39; 같은 HTML 글자를 원래대로
    static func decode(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        if let re = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            for m in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                if let r = Range(m.range, in: out), let n = Range(m.range(at: 1), in: out),
                   let code = UInt32(out[n]), let scalar = Unicode.Scalar(code) {
                    out.replaceSubrange(r, with: String(Character(scalar)))
                }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
