import SwiftUI

@main
struct EpoBrowserApp: App {
    init() {
        DebugLog.write("앱 시작 — 위치: \(Bundle.main.bundlePath)")
        // 저장소들이 파일·설정을 읽기 전에, 지워진 데이터를 백업에서 되살림
        Backup.shared.start()
    }

    var body: some Scene {
        WindowGroup("EpoBrowser", id: "main") {
            RootView()
                .frame(minWidth: 1000, minHeight: 600)
        }

        // 영상마다 따로 뜨는 재생 창
        // 재생 창은 하나만: 다른 영상을 고르면 창은 그대로 두고 영상만 바뀜
        Window("재생", id: "player") {
            PlayerHost()
        }
        .defaultSize(width: 960, height: 580)

        Window("사이트 로그인", id: "login") {
            LoginWindowView()
        }
        .defaultSize(width: 560, height: 700)

        .commands {
            CommandGroup(after: .appInfo) {
                Button("업데이트 확인…") { Task { await Updater.shared.check(manual: true) } }
            }
        }

        Settings {
            SettingsView()
        }
    }
}
