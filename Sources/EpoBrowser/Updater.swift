import AppKit
import SwiftUI

/// 새 버전 정보 (배포 폴더의 latest.json)
struct ReleaseInfo: Codable, Equatable {
    let version: String     // 보이는 버전 (예: 2.2)
    let build: Int          // 비교용 번호 (Info.plist CFBundleVersion)
    let file: String        // 설치 파일 이름 (예: EpoBrowser-2.2.pkg)
    let notes: [String]     // 바뀐 점
    let date: String
}

/// 업데이트 확인·설치
/// 배포 위치: 깃허브 저장소 lebass98/WebSite 의 dist/ (release.sh 가 설치 파일과 latest.json 을 올림)
/// 앱을 켤 때와 6시간마다 확인하고, 새 버전이 있으면 툴바에 알림 → 누르면 설치 프로그램을 띄움
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate, available(ReleaseInfo), downloading, failed(String)
    }

    @Published private(set) var state = State.idle
    @Published private(set) var lastChecked: Date?
    @Published var showSheet = false

    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    static let currentBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    /// 공개 저장소의 dist 폴더 (로그인 없이 받을 수 있음)
    private static let releaseBase = URL(string: "https://raw.githubusercontent.com/lebass98/WebSite/main/dist/")!
    /// 버전 정보는 깃허브 API로 읽음 (원본 주소는 5분 동안 캐시돼서 막 올린 버전이 안 보임)
    private static let manifestURL = URL(string: "https://api.github.com/repos/lebass98/WebSite/contents/dist/latest.json")!

    var available: ReleaseInfo? { if case .available(let info) = state { info } else { nil } }

    private var timer: Task<Void, Never>?
    private var announced: Int?

    /// 앱을 켤 때 한 번 (조금 기다렸다 확인, 그 뒤 6시간마다)
    func startAutoCheck() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            while !Task.isCancelled {
                await self?.check(manual: false)
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
            }
        }
    }

    func check(manual: Bool) async {
        if case .downloading = state { return }
        state = .checking
        var request = URLRequest(url: Self.manifestURL)
        request.setValue("application/vnd.github.raw", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let data = try? await URLSession.shared.data(for: request).0
        lastChecked = Date()
        guard let data, let info = try? JSONDecoder().decode(ReleaseInfo.self, from: data) else {
            state = .failed("새 버전 정보(latest.json)를 읽지 못했어요.")
            return
        }
        if info.build > Self.currentBuild {
            DebugLog.write("업데이트 있음: \(Self.currentVersion) → \(info.version)")
            // 직접 확인했거나, 이 버전을 이번 실행에서 처음 알게 됐으면 안내 창을 띄움
            if manual || announced != info.build { showSheet = true }
            announced = info.build
            state = .available(info)
        } else {
            state = .upToDate
            if manual { DebugLog.write("업데이트 확인: 최신 버전 \(Self.currentVersion)") }
        }
    }

    /// 설치 파일을 내려받아 macOS 설치 프로그램으로 엶 (비밀번호는 설치 프로그램에서 입력)
    func install(_ info: ReleaseInfo) async {
        state = .downloading
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(info.file)
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: Self.releaseBase.appendingPathComponent(info.file))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: downloaded, to: target)
        } catch {
            DebugLog.write("업데이트 받기 실패: \(error)")
            state = .failed("설치 파일(\(info.file))을 받지 못했어요.")
            return
        }
        DebugLog.write("업데이트 설치 시작: \(info.version)")
        state = .available(info)
        showSheet = false
        // 설치가 끝나면 설치 파일의 마무리 스크립트가 앱을 다시 켬
        NSWorkspace.shared.open(target)
    }
}

/// 툴바: 지금 버전을 늘 보여 주고, 누르면 업데이트 확인. 새 버전이 있으면 눈에 띄는 "업데이트" 버튼으로 바뀜
struct UpdateButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if let info = updater.available {
            Button {
                updater.showSheet = true
            } label: {
                Label("업데이트 \(info.version)", systemImage: "arrow.down.app.fill")
                    .labelStyle(.titleAndIcon)
                    // 새 버전이 생기면 아이콘이 두 번 튐
                    .symbolEffect(.bounce.up, options: .repeat(2), value: info.build)
            }
            .tint(.accentColor)
            .buttonStyle(.borderedProminent)
            .help("새 버전 \(info.version)이 나왔어요 (지금 \(Updater.currentVersion))")
        } else {
            Button {
                Task { await updater.check(manual: true) }
            } label: {
                Label("v\(Updater.currentVersion)", systemImage: updater.state == .checking ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(updater.state == .checking || updater.state == .downloading)
            .help("지금 버전 \(Updater.currentVersion) · 누르면 업데이트 확인")
        }
    }
}

/// 새 버전 안내 창
struct UpdateSheet: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch updater.state {
            case .available(let info):
                Label("새 버전 \(info.version)이 나왔어요", systemImage: "arrow.down.app.fill")
                    .font(.title3.bold())
                Text("지금 버전 \(Updater.currentVersion) · 배포일 \(info.date)")
                    .font(.caption).foregroundStyle(.secondary)
                if !info.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(info.notes, id: \.self) { note in
                            Label(note, systemImage: "checkmark.circle").font(.callout)
                        }
                    }
                }
                Text("설치를 누르면 macOS 설치 프로그램이 열려요. 안내대로 진행하고 비밀번호를 넣으면 앱이 새 버전으로 다시 켜져요.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("나중에") { updater.showSheet = false }
                    Button("설치") { Task { await updater.install(info) } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            case .downloading:
                HStack { ProgressView().controlSize(.small); Text("설치 파일 가져오는 중…") }
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("새 버전 확인 중…") }
            case .upToDate:
                Label("지금 최신 버전(\(Updater.currentVersion))이에요", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                HStack { Spacer(); Button("확인") { updater.showSheet = false }.keyboardShortcut(.defaultAction) }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                HStack { Spacer(); Button("닫기") { updater.showSheet = false }.keyboardShortcut(.defaultAction) }
            case .idle:
                EmptyView()
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// 설정 창의 업데이트 칸
struct UpdateSettingsSection: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Section("업데이트") {
            LabeledContent("지금 버전", value: "\(Updater.currentVersion) (\(Updater.currentBuild))")
            LabeledContent("상태", value: statusText)
            Button("지금 확인") { Task { await updater.check(manual: true) } }
                .disabled(updater.state == .checking || updater.state == .downloading)
        }
    }

    private var statusText: String {
        switch updater.state {
        case .idle: "아직 확인 안 함"
        case .checking: "확인 중…"
        case .upToDate: "최신 버전"
        case .available(let info): "새 버전 \(info.version) 있음"
        case .downloading: "설치 파일 가져오는 중…"
        case .failed(let message): message
        }
    }
}
