import SwiftUI
import Combine

/// 영상에 나오는 모델(포르노스타) 한 명
struct VideoModel: Identifiable, Hashable {
    let name: String
    let path: String   // /pornstar/이름/
    var id: String { path }
}

enum ModelScraper {
    /// 영상 페이지에서 그 영상의 모델만 꺼냄 (사이트 메뉴의 인기 포르노스타 링크는 뺌)
    static func models(inVideoPage html: String) -> [VideoModel] {
        var found: [VideoModel] = []
        func add(_ path: String, _ name: String) {
            let n = SiteScraper.decode(name.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
            guard !n.isEmpty, !found.contains(where: { $0.path == path }) else { return }
            found.append(VideoModel(name: n, path: path))
        }

        // 1순위: 영상 태그 목록의 포르노스타 칸 (<li class="vit-pornstar …"><a href="/pornstar/…">이름</a>)
        if let re = try? NSRegularExpression(pattern: #"class="vit-pornstar[^"]*"[^>]*>[\s\S]{0,200}?<a[^>]*href="(/pornstar/[^"]+)"[^>]*>([\s\S]*?)</a>"#) {
            for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                if let p = Range(m.range(at: 1), in: html), let n = Range(m.range(at: 2), in: html) { add(String(html[p]), String(html[n])) }
            }
        }
        if !found.isEmpty { return found }

        // 2순위: 영상 정보 영역(태그 목록) 안의 포르노스타 링크만
        let markers = ["id=\"video-info-tags\"", "class=\"video-info-tags", "id=\"video-info\""]
        guard let start = markers.compactMap({ html.range(of: $0)?.lowerBound }).min() else { return [] }
        let area = String(html[start...].prefix(15000))
        if let re = try? NSRegularExpression(pattern: #"<a(?![^>]*data-nav-item)[^>]*href="(/pornstar/[^"]+)"[^>]*>([\s\S]*?)</a>"#) {
            for m in re.matches(in: area, range: NSRange(area.startIndex..., in: area)) {
                if let p = Range(m.range(at: 1), in: area), let n = Range(m.range(at: 2), in: area) { add(String(area[p]), String(area[n])) }
            }
        }
        return found
    }

    static func load(pageURL: String) async -> [VideoModel] {
        guard let url = URL(string: pageURL) else { return [] }
        do {
            let html = try await SiteScraper.html(url)
            let models = models(inVideoPage: html)
            DebugLog.write("영상 모델 \(models.count)명: " + models.map(\.name).joined(separator: ", "))
            return models
        } catch {
            DebugLog.write("영상 모델 읽기 실패: \(error)")
            return []
        }
    }
}

/// 다른 창(재생 창 등)에서 목록 창으로 이동을 부탁할 때
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var pending: Route?

    func open(_ route: Route) {
        pending = route
        // 목록 창을 앞으로 (재생 창은 항상 위라 그 아래에 보임)
        if let main = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            main.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }
}

final class ModelsState: ObservableObject {
    @Published var models: [VideoModel] = []
}

/// 재생 창 위쪽: 영상에 나오는 모델 고르기 (여러 명이면 모두)
struct ModelPicker: View {
    let models: [VideoModel]

    var body: some View {
        Menu {
            ForEach(models) { m in
                Button(m.name) {
                    AppRouter.shared.open(Route(title: m.name, path: m.path))
                }
            }
        } label: {
            Label(models.count == 1 ? models[0].name : "모델 \(models.count)명",
                  systemImage: models.count == 1 ? "person.crop.circle" : "person.2.crop.square.stack")
                .labelStyle(.titleAndIcon)
        }
        .help("이 영상의 모델: " + models.map(\.name).joined(separator: ", ") + " (고르면 그 모델의 영상 목록으로 가요)")
    }
}
