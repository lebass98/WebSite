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

/// 화면 모드를 바꿀 때 누른 자리에서 원이 퍼지며 새 모드가 드러남
/// (바꾸기 전 창 모습을 덮어 두고, 그 덮개에 원형 구멍을 키움)
@MainActor
enum ThemeReveal {
    static func run(_ change: () -> Void) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let window = NSApp.keyWindow,
              let host = window.contentView?.superview ?? window.contentView,
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            change()
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(rep)
        let cover = NSImageView(frame: host.bounds)
        cover.image = image
        cover.imageScaling = .scaleAxesIndependently
        cover.wantsLayer = true
        host.addSubview(cover, positioned: .above, relativeTo: nil)
        change()

        let center = cover.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let b = cover.bounds
        let radius = hypot(max(center.x, b.width - center.x), max(center.y, b.height - center.y))
        func path(_ r: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.addRect(b)
            p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            return p
        }
        let mask = CAShapeLayer()
        mask.frame = b
        mask.fillRule = .evenOdd
        mask.path = path(radius)
        cover.layer?.mask = mask
        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = path(1)
        grow.toValue = path(radius)
        grow.duration = 0.55
        grow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { cover.removeFromSuperview() }
        mask.add(grow, forKey: "reveal")
        CATransaction.commit()
    }
}

/// 툴바 오른쪽의 화면 모드 버튼
struct AppearanceButton: View {
    @ObservedObject var setting = AppearanceSetting.shared

    var body: some View {
        Button {
            ThemeReveal.run { setting.mode = setting.mode.next }
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
