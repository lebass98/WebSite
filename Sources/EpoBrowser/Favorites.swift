import SwiftUI
import Combine

/// 내 즐겨찾기 영상 (썸네일 별 표시용)
/// 로그인하면 사이트의 즐겨찾기 목록을 모든 페이지 읽어 두고, 앱에서 넣고 빼면 바로 반영
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var ids: Set<String> = []   // 주소 속 영상 코드
    @Published private(set) var fids: Set<Int> = []     // 사이트 안 번호
    private var bag = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?

    private init() {
        SiteSession.shared.$userLinks
            .sink { [weak self] links in
                guard let self else { return }
                if let link = links.first(where: { $0.kind == .favorites }) {
                    self.load(from: link.url)
                } else {
                    self.loadTask?.cancel()
                    self.ids = []; self.fids = []
                }
            }
            .store(in: &bag)
    }

    func isFavorite(_ video: Video) -> Bool {
        ids.contains(video.id) || (video.fid > 0 && fids.contains(video.fid))
    }

    func isFavorite(id: String, fid: Int?) -> Bool {
        ids.contains(id) || (fid.map { $0 > 0 && fids.contains($0) } ?? false)
    }

    /// 앱에서 넣거나 뺀 결과를 바로 반영
    func mark(fid: Int, favorite: Bool) {
        if favorite { fids.insert(fid) } else { fids.remove(fid) }
    }

    /// 빼기는 영상 코드로 알던 항목도 지워야 해서 코드도 함께 받음
    func unmark(id: String) { ids.remove(id) }

    /// 사이트 즐겨찾기 목록을 끝까지 읽기
    private func load(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        loadTask?.cancel()
        loadTask = Task {
            var newIDs: Set<String> = [], newFids: Set<Int> = []
            let base = url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/"
            for page in 1...60 {
                guard !Task.isCancelled,
                      let pageURL = URL(string: page == 1 ? base : base + "\(page)/"),
                      let html = try? await SiteScraper.html(pageURL) else { break }
                let videos = SiteScraper.parseVideos(html).map(\.video)
                let fresh = videos.filter { !newIDs.contains($0.id) }
                if fresh.isEmpty { break }
                for v in fresh {
                    newIDs.insert(v.id)
                    if v.fid > 0 { newFids.insert(v.fid) }
                }
            }
            guard !Task.isCancelled else { return }
            ids = newIDs
            fids = newFids
            DebugLog.write("내 즐겨찾기 \(newIDs.count)개 읽음")
        }
    }
}

/// 썸네일 위 즐겨찾기 별 (밝은 장면에서도 잘 보이게 어두운 원 안에 노란 별)
struct FavoriteStar: View {
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: size * 0.6, weight: .black))
            .foregroundStyle(.yellow)
            .frame(width: size, height: size)
            .background(Circle().fill(.black.opacity(0.7)))
            .overlay(Circle().strokeBorder(.yellow, lineWidth: max(1.5, size * 0.07)))
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .help("즐겨찾기한 영상")
    }
}
