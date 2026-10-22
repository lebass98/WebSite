import SwiftUI
import Combine

/// 다크·라이트 모드 (앱의 모든 창에 적용, 다음 실행에도 유지)
@MainActor
final class AppearanceSetting: ObservableObject {
    static let shared = AppearanceSetting()

    enum Mode: String, CaseIterable {
        case system, light, dark

        var label: String {
            switch self {
            case .system: "시스템 설정 따름"
            case .light: "라이트 모드"
            case .dark: "다크 모드"
            }
        }

        var icon: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max.fill"
            case .dark: "moon.fill"
            }
        }

        var next: Mode {
            switch self {
            case .system: .light
            case .light: .dark
            case .dark: .system
            }
        }
    }

    private static let key = "appearanceMode"

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.key)
            apply()
        }
    }

    private init() {
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .system
    }

    func apply() {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// 툴바 오른쪽의 화면 모드 버튼
struct AppearanceButton: View {
    @ObservedObject var setting = AppearanceSetting.shared

    var body: some View {
        Button {
            setting.mode = setting.mode.next
        } label: {
            Label(setting.mode.label, systemImage: setting.mode.icon)
        }
        .help("화면 모드: \(setting.mode.label) (누르면 \(setting.mode.next.label))")
        .contextMenu {
            ForEach(AppearanceSetting.Mode.allCases, id: \.self) { mode in
                Button(mode.label) { setting.mode = mode }
            }
        }
    }
}
