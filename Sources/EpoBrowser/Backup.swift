import AppKit
import Combine

/// 앱 데이터 자동 백업·복원
/// 원본(~/Library/Application Support/EpoBrowser)과 설정은 정리 앱(CleanMyMac 등)이
/// 앱을 휴지통에 버릴 때 "남은 파일"로 같이 지울 수 있어서, 홈 폴더(~/Epo 백업)에 따로 복사해 둠.
/// - 앱을 켤 때: 원본에 없는 파일·설정은 백업에서 되살림
/// - 데이터나 설정이 바뀌면 몇 초 뒤 자동 백업, 앱을 끌 때도 백업
/// - 백업에서는 파일을 지우지 않음 (원본이 통째로 지워져도 백업은 남게). 사용자가 지운 자막만 따로 지움
final class Backup: ObservableObject {
    static let shared = Backup()

    static let dataFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("EpoBrowser", isDirectory: true)
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Epo 백업", isDirectory: true)

    private static let settingsName = "settings.plist"
    private static let readmeName = "읽어 주세요.txt"
    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.local.EpoBrowser" }

    /// 마지막으로 백업한 때
    @Published private(set) var lastBackup: Date?
    /// 앱을 켤 때 백업에서 되살린 내용 (없으면 nil)
    @Published private(set) var restoreNote: String?
    /// 되살렸다는 알림을 메인 창에 한 번만 띄우기 위한 표시
    var restoreToastShown = false

    private let queue = DispatchQueue(label: "EpoBrowser.backup", qos: .utility)
    private var pending: DispatchWorkItem?   // queue 안에서만 씀
    private var observers: [NSObjectProtocol] = []

    private init() {
        let settings = Self.folder.appendingPathComponent(Self.settingsName)
        lastBackup = (try? settings.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// 앱을 켤 때 한 번 (저장소들이 파일·설정을 읽기 전에 불러야 함)
    func start() {
        restoreIfNeeded()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.schedule()
        })
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.backupNow(wait: true)
        })
        backupNow()
    }

    /// 데이터가 바뀌었을 때: 잠깐 모았다가 한 번에 백업
    func schedule(after seconds: Double = 3) {
        queue.async { [self] in
            pending?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.performBackup() }
            pending = item
            queue.asyncAfter(deadline: .now() + seconds, execute: item)
        }
    }

    func backupNow(wait: Bool = false) {
        let work = { [self] in
            pending?.cancel()
            pending = nil
            performBackup()
        }
        if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    /// 사용자가 지운 파일은 백업에서도 지움 (안 그러면 다음 실행 때 되살아남)
    func forget(_ relativePaths: [String]) {
        queue.async {
            for path in relativePaths {
                try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(path))
            }
        }
    }

    // MARK: - 되살리기

    private func restoreIfNeeded() {
        let fm = FileManager.default
        var files = 0
        for path in Self.files(under: Self.folder) where path != Self.settingsName && path != Self.readmeName {
            let target = Self.dataFolder.appendingPathComponent(path)
            guard !fm.fileExists(atPath: target.path) else { continue }
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: Self.folder.appendingPathComponent(path), to: target)
                files += 1
            } catch {
                DebugLog.write("백업에서 되살리기 실패 \(path): \(error)")
            }
        }

        // 설정: 지금 비어 있는 값만 채움 (바꾼 설정을 덮어쓰지 않게)
        var settings = 0
        if let data = try? Data(contentsOf: Self.folder.appendingPathComponent(Self.settingsName)),
           let saved = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let current = UserDefaults.standard.persistentDomain(forName: Self.bundleID) ?? [:]
            for (key, value) in saved where current[key] == nil {
                UserDefaults.standard.set(value, forKey: key)
                settings += 1
            }
        }

        guard files + settings > 0 else { return }
        var parts: [String] = []
        if files > 0 { parts.append("파일 \(files)개") }
        if settings > 0 { parts.append("설정 \(settings)개") }
        let note = "앱 데이터가 지워져 있어서 백업에서 \(parts.joined(separator: "와 "))를 되살렸어요"
        restoreNote = note
        DebugLog.write(note)
    }

    // MARK: - 백업

    private func performBackup() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            var copied = 0
            for path in Self.files(under: Self.dataFolder) {
                let source = Self.dataFolder.appendingPathComponent(path)
                let target = Self.folder.appendingPathComponent(path)
                guard !Self.isUpToDate(target, source: source) else { continue }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contentsOf: source).write(to: target, options: .atomic)
                copied += 1
            }

            let settingsURL = Self.folder.appendingPathComponent(Self.settingsName)
            if let domain = UserDefaults.standard.persistentDomain(forName: Self.bundleID), !domain.isEmpty {
                let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
                if (try? Data(contentsOf: settingsURL)) != data {
                    try data.write(to: settingsURL, options: .atomic)
                } else {
                    // 바뀐 게 없어도 "마지막 백업" 시각은 갱신
                    try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: settingsURL.path)
                }
            }

            let readme = Self.folder.appendingPathComponent(Self.readmeName)
            if !fm.fileExists(atPath: readme.path) {
                try? """
                EpoBrowser 앱 데이터 백업이에요. 앱이 자동으로 관리하니 지우지 마세요.
                (최근 본 영상, 4K 주소 모음, 미리 만든 자막, 화면 설정)
                앱 데이터가 지워지면 다음에 앱을 켤 때 여기서 자동으로 되살려요.

                """.write(to: readme, atomically: true, encoding: .utf8)
            }

            if copied > 0 { DebugLog.write("백업: 파일 \(copied)개 복사 → \(Self.folder.path)") }
            DispatchQueue.main.async { self.lastBackup = Date() }
        } catch {
            DebugLog.write("백업 실패: \(error)")
        }
    }

    /// 백업 파일이 원본과 크기가 같고 원본보다 나중에 쓰였으면 건너뜀
    private static func isUpToDate(_ target: URL, source: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let s = try? source.resourceValues(forKeys: keys),
              let t = try? target.resourceValues(forKeys: keys),
              let sDate = s.contentModificationDate, let tDate = t.contentModificationDate
        else { return false }
        return s.fileSize == t.fileSize && tDate >= sDate
    }

    /// 폴더 안 모든 파일의 상대 경로 (숨김 파일 ._*, .DS_Store 제외)
    private static func files(under root: URL) -> [String] {
        let base = root.resolvingSymlinksInPath().path
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var paths: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(base + "/") else { continue }
            paths.append(String(path.dropFirst(base.count + 1)))
        }
        return paths
    }
}
