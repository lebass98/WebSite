import SwiftUI
import Combine

/// 모은 4K 다운로드 주소 하나 (썸네일·제목과 함께)
struct CollectedVideo: Codable, Identifiable, Hashable {
    let videoID: String
    let title: String
    let thumb: String
    let pageURL: String
    let url: String          // 실제 파일 주소 (NAS에 넘기는 값)
    let added: Date
    var id: String { videoID.isEmpty ? url : videoID }
}

/// 4K 다운로드 주소 모음 (모은 순서대로 쌓임)
/// 저장: ~/Library/Application Support/EpoBrowser/4k-urls.json (+ NAS용 주소만 4k-urls.txt)
@MainActor
final class URLCollector: ObservableObject {
    static let shared = URLCollector()

    private static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpoBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let fileURL = folder.appendingPathComponent("4k-urls.txt")
    private static let jsonURL = folder.appendingPathComponent("4k-urls.json")

    @Published private(set) var items: [CollectedVideo] = [] {
        didSet { save() }
    }

    private init() {
        if let data = try? Data(contentsOf: Self.jsonURL),
           let saved = try? JSONDecoder().decode([CollectedVideo].self, from: data) {
            items = saved
        } else if let text = try? String(contentsOf: Self.fileURL, encoding: .utf8) {
            // 예전 글자 목록 옮겨 오기 (썸네일 정보는 없음)
            items = text.split(whereSeparator: \.isNewline).map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { CollectedVideo(videoID: "", title: "제목 없음", thumb: "", pageURL: "", url: $0, added: Date()) }
        }
    }

    /// 맨 뒤에 추가 (같은 영상이 이미 있으면 건너뜀)
    @discardableResult
    func append(_ item: CollectedVideo) -> Bool {
        if items.contains(where: { $0.url == item.url || (!item.videoID.isEmpty && $0.videoID == item.videoID) }) { return false }
        items.append(item)
        return true
    }

    func remove(_ item: CollectedVideo) { items.removeAll { $0.id == item.id } }

    /// 제목·썸네일이 빠진 항목을 사이트에서 채움 (목록을 열 때)
    func fillMissingInfo() async {
        for item in items where !item.videoID.isEmpty && (item.thumb.isEmpty || item.title == "제목 없음") {
            let page = item.pageURL.isEmpty ? "\(SiteScraper.base)/video-\(item.videoID)/" : item.pageURL
            guard let url = URL(string: page), let html = try? await SiteScraper.html(url) else { continue }
            func meta(_ key: String) -> String? {
                guard let re = try? NSRegularExpression(pattern: #"<meta[^>]+property="og:\#(key)"[^>]+content="([^"]*)""#),
                      let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                      let r = Range(m.range(at: 1), in: html) else { return nil }
                return SiteScraper.decode(String(html[r]))
            }
            guard let i = items.firstIndex(where: { $0.id == item.id }) else { continue }
            let fixed = CollectedVideo(videoID: item.videoID,
                                       title: item.title == "제목 없음" ? (meta("title") ?? item.title) : item.title,
                                       thumb: item.thumb.isEmpty ? (meta("image") ?? "") : item.thumb,
                                       pageURL: page, url: item.url, added: item.added)
            items[i] = fixed
        }
    }

    func clear() { items = [] }

    /// 주소만 한 줄에 하나씩 (NAS 명령용)
    var allURLsText: String { items.map(\.url).joined(separator: "\n") + (items.isEmpty ? "" : "\n") }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allURLsText, forType: .string)
    }

    private func save() {
        do {
            try JSONEncoder().encode(items).write(to: Self.jsonURL, options: .atomic)
            try allURLsText.write(to: Self.fileURL, atomically: true, encoding: .utf8)
            Backup.shared.schedule()
        } catch {
            DebugLog.write("4K 주소 목록 저장 실패: \(error)")
        }
    }

    /// 영상 하나의 4K 주소를 찾아서 모으기 (4K가 없으면 알림만)
    static func collect4K(for video: Video) {
        Toast.shared.show("4K 다운로드 주소 찾는 중…", seconds: 0)
        Task {
            do {
                let links = try await DownloadLoader.findLinks(pageURL: video.url)
                guard let best = links.filter({ $0.height >= 2160 }).first else {
                    let top = links.map(\.height).max() ?? 0
                    Toast.shared.show(top > 0 ? "4K가 없는 영상이에요 (최고 \(resolutionLabel(top)))" : "4K가 없는 영상이에요", error: true)
                    return
                }
                await add(best, video: video)
            } catch {
                Toast.shared.show(error.localizedDescription, error: true, seconds: 5)
            }
        }
    }

    /// 4K 링크를 실제 파일 주소로 바꿔 모으기 (NAS는 앱 로그인 정보를 못 쓰니 파일 주소로)
    static func add(_ link: DownloadLink, video: Video) async {
        let file = (try? await DownloadLoader.resolve(URL(string: link.url)!))?.absoluteString ?? link.url
        // 재생 창에서 모으면 썸네일이 없어서 최근 본 영상 기록에서 찾아 씀
        let thumb = video.thumb.isEmpty ? (RecentStore.shared.items.first { $0.id == video.id }?.thumb ?? "") : video.thumb
        let added = shared.append(CollectedVideo(videoID: video.id, title: video.title, thumb: thumb,
                                                 pageURL: video.url, url: file, added: Date()))
        DebugLog.write("4K 주소 모으기: \(added ? "추가" : "이미 있음") \(video.id)")
        Toast.shared.show(added ? "4K 주소를 모았어요 (모두 \(shared.items.count)개)" : "이미 모은 영상이에요 (모두 \(shared.items.count)개)")
    }
}

/// 다크 모드 버튼 옆: 모은 4K 주소 보기
struct URLCollectorButton: View {
    @ObservedObject private var collector = URLCollector.shared
    @StateObject private var popover = PopoverState()

    var body: some View {
        Button {
            popover.shown.toggle()
        } label: {
            Label("4K 주소 목록 (\(collector.items.count))", systemImage: collector.items.isEmpty ? "list.clipboard" : "list.clipboard.fill")
        }
        .help("모은 4K 다운로드 주소 \(collector.items.count)개")
        .popover(isPresented: $popover.shown, arrowEdge: .bottom) {
            URLCollectorPanel()
        }
    }
}

final class ConfirmClear: ObservableObject {
    @Published var shown = false
}

/// 모은 영상: 썸네일·제목 5칸 격자, 아래로 스크롤
struct URLCollectorPanel: View {
    @ObservedObject private var collector = URLCollector.shared
    @StateObject private var confirm = ConfirmClear()
    @StateObject private var copied = PopoverState()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("4K 다운로드 주소").font(.headline)
                Text("\(collector.items.count)개").foregroundStyle(.secondary)
                Spacer()
                Button("파일 보기") { NSWorkspace.shared.activateFileViewerSelecting([URLCollector.fileURL]) }
                    .help("주소만 모은 파일(4k-urls.txt)을 Finder에서 보기")
                Button("비우기", role: .destructive) { confirm.shown = true }
                    .disabled(collector.items.isEmpty)
                Button {
                    collector.copyAll()
                    copied.shown = true
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied.shown = false }
                } label: {
                    Label(copied.shown ? "복사했어요" : "전체 복사", systemImage: copied.shown ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(collector.items.isEmpty)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("주소만 한 줄에 하나씩 복사 (NAS 명령용)")
            }

            if collector.items.isEmpty {
                Text("영상을 오른쪽 클릭 → \"4K 주소 모으기\"를 누르면 여기에 쌓여요.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(collector.items.enumerated()), id: \.element.id) { index, item in
                            CollectedTile(index: index + 1, item: item)
                        }
                    }
                    .padding(2)
                }
            }

            Text("전체 복사는 주소만 한 줄에 하나씩 복사해요. 파일 주소는 시간이 지나면 만료될 수 있어요.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 820, height: 560)
        .task { await collector.fillMissingInfo() }
        .confirmationDialog("모은 영상 \(collector.items.count)개를 모두 지울까요?", isPresented: $confirm.shown) {
            Button("모두 지우기", role: .destructive) { collector.clear() }
        }
    }
}

private struct CollectedTile: View {
    let index: Int
    let item: CollectedVideo
    @Environment(\.openWindow) private var openWindow

    private var canPlay: Bool { !item.videoID.isEmpty && !item.pageURL.isEmpty }

    /// 다시 재생 (재생 창 열기)
    private func play() {
        guard canPlay else { return }
        let player = PlayerItem(id: item.videoID, title: item.title,
                                embed: "\(SiteScraper.base)/embed/\(item.videoID)/", url: item.pageURL)
        openWindow.play(player)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.secondary.opacity(0.15)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    AsyncImage(url: URL(string: item.thumb)) { phase in
                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                        else { Image(systemName: "film").foregroundStyle(.secondary) }
                    }
                }
                .overlay(alignment: .topLeading) {
                    Text("\(index)")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(item.title).font(.caption).lineLimit(2, reservesSpace: true)
        }
        .contentShape(Rectangle())
        .onTapGesture { play() }
        .help(canPlay ? "누르면 다시 재생 · \(item.url)" : item.url)
        .contextMenu {
            if canPlay { Button("재생") { play() } }
            Button("이 주소 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url, forType: .string)
            }
            if let page = URL(string: item.pageURL), !item.pageURL.isEmpty {
                Button("브라우저에서 열기") { NSWorkspace.shared.open(page) }
            }
            Divider()
            Button("목록에서 빼기", role: .destructive) { URLCollector.shared.remove(item) }
        }
    }
}
