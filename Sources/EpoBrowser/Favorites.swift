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

/// 썸네일 위 즐겨찾기 별 (배경 원 없이 노란 별만, 밝은 장면용으로 아주 얇은 그림자)
struct FavoriteStar: View {
    var size: CGFloat = 26
    /// 값이 바뀌면 (즐겨찾기에 막 넣었을 때) 별이 두 번 튀고 불꽃이 퍼짐
    var pop = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: size * 0.8, weight: .black))
            .foregroundStyle(.yellow)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.5), radius: 1)
            .symbolEffect(.bounce, options: .repeat(2), value: pop)
            .background { if !reduceMotion { Sparks(trigger: pop, size: size) } }
            .help("즐겨찾기한 영상")
    }
}

/// 가운데에서 바깥으로 퍼지며 사라지는 작은 불꽃 8개
struct Sparks: View {
    let trigger: Int
    var size: CGFloat = 26
    var color: Color = .yellow

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Circle().fill(color).frame(width: 5, height: 5)
                    .keyframeAnimator(initialValue: 0.0, trigger: trigger) { dot, t in
                        let angle = Double(i) / 8 * 2 * .pi
                        let distance = size * 0.45 + size * 0.5 * t
                        dot.offset(x: cos(angle) * distance, y: sin(angle) * distance)
                            .scaleEffect(1 - t * 0.8)
                            .opacity(t > 0 && t < 1 ? 1 - t : 0)
                    } keyframes: { _ in
                        LinearKeyframe(0.0, duration: 0)
                        CubicKeyframe(1.0, duration: 0.55)
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 나중에 볼 영상에 넣었을 때 썸네일 모서리에 떨어지는 리본
struct WatchLaterRibbon: View {
    var body: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(EpoStyle.accent)
            .shadow(color: .black.opacity(0.4), radius: 1)
            .help("나중에 볼 영상에 넣었어요")
    }
}

extension Notification.Name {
    /// 나중에 볼 영상에 넣음 (object: 사이트 영상 번호 Int)
    static let watchLaterAdded = Notification.Name("watchLaterAdded")
}
