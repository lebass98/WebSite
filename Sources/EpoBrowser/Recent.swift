import SwiftUI
import Combine

/// 최근 본 영상 한 개
struct RecentVideo: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let embed: String
    let thumb: String
    let lengthText: String
    var watchedAt: Date
    var fid: Int? = nil

    var playerItem: PlayerItem { PlayerItem(id: id, title: title, embed: embed, url: url, fid: fid) }
}

/// 최근 본 영상 기록 (개수 제한 없이 전부 저장, 다시 보면 맨 위로)
/// 저장 위치: ~/Library/Application Support/EpoBrowser/recent.json
@MainActor
final class RecentStore: ObservableObject {
    static let shared = RecentStore()

    @Published private(set) var items: [RecentVideo] = [] {
        didSet { watchedIDs = Set(items.map(\.id)) }
    }
    /// 본 적 있는 영상 (썸네일 "봤음" 표시용)
    private(set) var watchedIDs: Set<String> = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpoBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recent.json")
    }()

    private init() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try JSONDecoder().decode([RecentVideo].self, from: data)
            watchedIDs = Set(items.map(\.id))
        } catch {
            DebugLog.write("최근 본 영상 읽기 실패: \(error)")
        }
    }

    func add(_ video: Video) {
        add(RecentVideo(id: video.id, title: video.title, url: video.url, embed: video.embed,
                        thumb: video.thumb, lengthText: video.lengthText, watchedAt: Date(),
                        fid: video.fid == 0 ? nil : video.fid))
    }

    func add(_ recent: RecentVideo) {
        var entry = recent
        entry.watchedAt = Date()
        items.removeAll { $0.id == entry.id }
        items.insert(entry, at: 0)
        save()
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        items = []
        save()
    }

    private func save() {
        do {
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
            Backup.shared.schedule()
        } catch {
            DebugLog.write("최근 본 영상 저장 실패: \(error)")
        }
    }
}

final class ConfirmState: ObservableObject {
    @Published var shown = false
}

/// 사이드바의 최근 본 영상 (사이드바 안에서 따로 스크롤)
struct RecentListView: View {
    @ObservedObject private var store = RecentStore.shared
    @StateObject private var confirm = ConfirmState()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("최근 본 영상").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(store.items.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.items.isEmpty {
                    Button("모두 지우기") { confirm.shown = true }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            if store.items.isEmpty {
                Text("영상을 보면 여기에 쌓여요.").font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.items) { item in
                            RecentRow(item: item)
                                .onTapGesture {
                                    store.add(item)
                                    openWindow.play(item.playerItem)
                                }
                                .contextMenu {
                                    Button("앱에서 재생") {
                                        store.add(item)
                                        openWindow.play(item.playerItem)
                                    }
                                    Button("브라우저에서 열기") { NSWorkspace.shared.open(URL(string: item.url)!) }
                                    Divider()
                                    SaveMenuItems(fid: item.fid ?? 0, videoID: item.id)
                                    Divider()
                                    Button("목록에서 지우기") { store.remove(item.id) }
                                }
                        }
                    }
                }
                .frame(height: 360)
            }
        }
        .confirmationDialog("최근 본 영상 \(store.items.count)개를 모두 지울까요?", isPresented: $confirm.shown) {
            Button("모두 지우기", role: .destructive) { store.removeAll() }
        }
    }
}

struct RecentRow: View {
    let item: RecentVideo
    @ObservedObject private var favorites = FavoritesStore.shared

    var body: some View {
        HStack(spacing: 8) {
            Color.secondary.opacity(0.15)
                .frame(width: 72, height: 40)
                .overlay {
                    AsyncImage(url: URL(string: item.thumb)) { phase in
                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !item.lengthText.isEmpty {
                        Text(item.lengthText)
                            .font(.system(size: 8, weight: .bold).monospacedDigit())
                            .padding(.horizontal, 2)
                            .background(.black.opacity(0.7))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .topTrailing) {
                    if favorites.isFavorite(id: item.id, fid: item.fid) { FavoriteStar(size: 14).offset(x: 4, y: -4) }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.caption).lineLimit(2)
                Text(item.watchedAt, format: .relative(presentation: .named))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .contentShape(Rectangle())
        .help(item.title)
    }
}
