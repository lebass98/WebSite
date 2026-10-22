import AppKit

/// 앱의 다른 창을 처음 눌렀을 때도 그 클릭이 바로 처리되게 함
/// (예: 재생 창을 보다가 목록 창의 다른 영상을 한 번만 눌러도 바로 바뀜)
/// macOS는 선택되지 않은 창의 첫 클릭을 "창 선택"에만 쓰는 경우가 있어서, 클릭이 처리되기 전에 그 창을 먼저 선택해 둠
@MainActor
enum ClickThrough {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let window = event.window, !window.isKeyWindow, window.canBecomeKey, window.isVisible {
                window.makeKey()
            }
            return event
        }
    }
}
