import SwiftUI
import WebKit
import AVKit

/// 지금 재생 창에 띄울 영상 (재생 창은 하나뿐)
@MainActor
final class PlayerCenter: ObservableObject {
    static let shared = PlayerCenter()
    @Published private(set) var current: PlayerItem?
    /// 지금 영상의 실제 해상도 (앱 플레이어로 재생할 때 알게 됨)
    @Published var videoSize: CGSize?
    /// 재생 창 (배율 바꾸기에 씀)
    weak var chrome: PlayerChrome?

    func play(_ item: PlayerItem) {
        if item != current { videoSize = nil }
        current = item
    }

    /// 재생 창 배율 (단축키 1·2·3·4)
    enum Scale: String, CaseIterable, Identifiable {
        case x1, half, w1920, quarter
        var id: String { rawValue }
        var key: String {
            switch self {
            case .x1: "1"
            case .half: "2"
            case .w1920: "3"
            case .quarter: "4"
            }
        }
        var label: String {
            switch self {
            case .x1: "1배 (원래 크기)"
            case .half: "0.5배"
            case .w1920: "가로 1920"
            case .quarter: "0.25배"
            }
        }
    }

    func resize(_ scale: Scale) {
        // 크기를 아직 모르면(사이트 플레이어 등) 1920×1080 기준
        chrome?.resize(scale, video: videoSize ?? CGSize(width: 1920, height: 1080))
    }
}

extension OpenWindowAction {
    /// 재생 창에서 영상 재생 (창이 이미 있으면 영상만 바꿈)
    @MainActor
    func play(_ item: PlayerItem) {
        PlayerCenter.shared.play(item)
        self(id: "player")
    }
}

/// 하나뿐인 재생 창의 내용 (영상이 바뀌면 플레이어·자막 등만 새로 준비)
struct PlayerHost: View {
    @ObservedObject private var center = PlayerCenter.shared
    @StateObject private var chrome = PlayerChrome()

    var body: some View {
        Group {
            if let item = center.current {
                PlayerView(item: item)
                    .id(item.id)
            } else {
                LibraryEmptyState(icon: "play.rectangle", title: "재생할 영상을 선택하세요",
                                  message: "라이브러리의 영상을 선택하면 이 창에서 재생됩니다.")
                    .preferredColorScheme(.dark)
                    .frame(minWidth: 240, minHeight: 135)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            }
        }
        // 위쪽 막대: 투명, 평소엔 숨기고 마우스가 위쪽에 오면 보임
        .toolbarBackground(.hidden, for: .windowToolbar)
        .ignoresSafeArea()
        .background(WindowReader { chrome.attach($0) })
        .onDisappear { chrome.detach() }
    }
}

/// 재생 창 위쪽 막대(제목·신호등 버튼·툴바)를 마우스가 위쪽에 있을 때만 보여 줌
@MainActor
final class PlayerChrome: NSObject, ObservableObject {
    private weak var window: NSWindow?
    /// 영상을 끌어 재생 창을 옮길 때 쓰는, 마지막으로 누른 순간
    private var dragStart: NSEvent?
    /// 아래쪽 재생 조절 막대 높이 (여기서는 끌어도 창이 아니라 재생 위치가 움직임)
    private let controlsHeight: CGFloat = 90
    private var monitors: [Any] = []          // 마우스 감시 (NSEvent)
    private var observers: [NSObjectProtocol] = []  // 전체 화면 알림
    private var hideTask: Task<Void, Never>?
    private var visible = true
    /// 전체 화면으로 바뀌는 중인지 (바뀌는 동안 또 누르면 켜기·끄기가 겹쳐서 취소되므로 무시)
    private var switching = false
    private var lastToggle = Date.distantPast
    /// 창 위쪽 몇 pt 안에 마우스가 오면 보일지
    private let revealHeight: CGFloat = 56
    /// 보이는 동안은 막대 높이보다 조금 넓게 (막대 위 버튼을 누를 수 있게)
    private let keepHeight: CGFloat = 90

    func attach(_ window: NSWindow?) {
        guard let window, window !== self.window else { return }
        self.window = window
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.acceptsMouseMovedEvents = true
        addBlur(to: window)
        // 이 앱을 쓰는 중이든 다른 앱을 쓰는 중이든 마우스 위치를 봄
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.check() }
            return event
        }) { monitors.append(local) }
        // 영상 아무 곳이나 더블클릭: 전체 화면 켜기·끄기 / 영상을 끌면 재생 창 옮기기
        if let mouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.handleMouse(event) ?? false }
            return swallow ? nil : event
        }) { monitors.append(mouse) }
        // 숫자 키 1·2·3·4: 재생 창 배율
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }) { monitors.append(keys) }
        PlayerCenter.shared.chrome = self
        // 녹색 버튼도 진짜 전체 화면으로 (항상 위에 창은 macOS가 그냥 크게만 키워서)
        if let zoom = window.standardWindowButton(.zoomButton) {
            zoom.target = self
            zoom.action = #selector(zoomButtonPressed(_:))
        }
        // 전체 화면에서는 툴바를 숨겨 영상이 화면을 꽉 채우게 (맨 위에 마우스를 대면 macOS가 막대를 보여 줌)
        let center = NotificationCenter.default
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.switching = true }
            })
        }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.switching = false }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window?.level = .normal
                self?.window?.toolbar?.isVisible = false
                self?.setVisible(true, animated: false)
            }
        })
        observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // 전체 화면에서 나오면 "항상 위에" 설정대로 다시
                if WindowPin.savedIsOn { self?.window?.level = .floating }
                self?.window?.toolbar?.isVisible = true
                self?.setVisible(false, animated: false)
            }
        })
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            Task { @MainActor in self?.check() }
        }) { monitors.append(global) }
        setVisible(false, animated: false)
    }

    /// 재생 창 또는 그 위에 붙은 작은 창(재생 조절 막대 등)의 클릭인지
    private func isOurs(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        var w: NSWindow? = event.window
        while let current = w {
            if current === window { return true }
            w = current.parent
        }
        return false
    }

    /// 돌려주는 값: 이 이벤트를 삼킬지 (창을 옮기기 시작하면 삼킴)
    private func handleMouse(_ event: NSEvent) -> Bool {
        guard let window, isOurs(event) else { return false }
        let full = window.styleMask.contains(.fullScreen)
        let mouse = NSEvent.mouseLocation
        let fromTop = window.frame.maxY - mouse.y
        let fromBottom = mouse.y - window.frame.minY

        switch event.type {
        case .leftMouseDown:
            dragStart = nil
            // 위쪽 막대(제목·버튼) 위는 빼고 영상 위에서만
            if !full, fromTop <= revealHeight { return false }
            if event.clickCount == 2 {
                DebugLog.write("재생 창 더블클릭 → 전체 화면 \(full ? "끄기" : "켜기")")
                toggleFullScreen()
                return false
            }
            // 영상 본문을 누른 경우만 창 옮기기 후보 (재생 조절 막대·작은 창은 제외)
            if !full, event.window === window, fromBottom > controlsHeight { dragStart = event }
        case .leftMouseDragged:
            if let start = dragStart {
                dragStart = nil
                window.performDrag(with: start)   // 영상을 끄는 동안 재생 창이 따라 움직임
                return true
            }
        default:
            dragStart = nil
        }
        return false
    }

    /// 숫자 키(수정 키 없이)로 배율 바꾸기, Esc로 재생 창 닫기 (재생 창이 선택돼 있고 글 입력 중이 아닐 때)
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard mods.isEmpty, !(window.firstResponder is NSText) else { return false }
        // Esc(키 코드 53): 재생 창 닫기 (닫히면 재생·자막도 멈춤)
        if event.keyCode == 53 {
            DebugLog.write("Esc → 재생 창 닫기")
            window.close()
            return true
        }
        guard let key = event.charactersIgnoringModifiers,
              let scale = PlayerCenter.Scale.allCases.first(where: { $0.key == key }) else { return false }
        PlayerCenter.shared.resize(scale)
        return true
    }

    /// 재생 창 크기를 영상 해상도 기준으로 바꿈 (왼쪽 위 위치는 그대로, 화면보다 크면 비율 유지하며 줄임)
    func resize(_ scale: PlayerCenter.Scale, video: CGSize) {
        guard let window, !window.styleMask.contains(.fullScreen), video.width > 0, video.height > 0 else { return }
        var size: CGSize
        switch scale {
        case .x1: size = video
        case .half: size = CGSize(width: video.width / 2, height: video.height / 2)
        case .quarter: size = CGSize(width: video.width / 4, height: video.height / 4)
        case .w1920: size = CGSize(width: 1920, height: 1920 * video.height / video.width)
        }
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if screen.width > 0 {
            let fit = min(1, screen.width / size.width, screen.height / size.height)
            size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
        }
        // 영상이 위쪽 막대 아래까지 차는 창이라 창 크기 = 영상 크기
        var frame = NSRect(x: window.frame.minX, y: window.frame.maxY - size.height, width: size.width, height: size.height)
        // 화면 밖으로 나가지 않게
        if screen.width > 0 {
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        window.setFrame(frame, display: true, animate: true)
        DebugLog.write("재생 창 배율 \(scale.label): 영상 \(Int(video.width))×\(Int(video.height)) → 창 \(Int(size.width))×\(Int(size.height))")
    }

    @objc private func zoomButtonPressed(_ sender: Any?) { toggleFullScreen() }

    /// 진짜 전체 화면 켜기·끄기 (항상 위에 창은 전체 화면이 안 돼서 잠깐 보통 높이로)
    private func toggleFullScreen() {
        guard let window else { return }
        // 바뀌는 중이거나 방금 바꿨으면 무시 (한 번의 더블클릭이 두 번 들어와 켜기·끄기가 상쇄되는 것 방지)
        // 바뀌는 중 표시가 어떤 이유로 안 풀려도 3초 뒤엔 다시 받음
        let since = Date().timeIntervalSince(lastToggle)
        if since < 0.8 || (switching && since < 3) {
            DebugLog.write("전체 화면 요청 무시 (바뀌는 중)")
            return
        }
        lastToggle = Date()
        if !window.styleMask.contains(.fullScreen) {
            window.level = .normal
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            // 영상을 바꾸면 SwiftUI가 창에 "전체 화면 불가"를 붙이는 경우가 있어서 떼어 냄
            window.collectionBehavior.remove(.fullScreenNone)
        }
        DebugLog.write("전체 화면 요청: 창 \(window.windowNumber) 높이 \(window.level.rawValue) 동작 \(window.collectionBehavior.rawValue) 시트 \(window.attachedSheet != nil) 키 \(window.isKeyWindow)")
        window.toggleFullScreen(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak window] in
            DebugLog.write("전체 화면 결과: \(window?.styleMask.contains(.fullScreen) == true ? "켜짐" : "꺼짐")")
        }
    }

    func detach() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        monitors = []
        hideTask?.cancel()
        hideTask = nil
        setVisible(true, animated: false)
        window = nil
    }

    private func check() {
        guard let window, window.isVisible else { return }
        // 전체 화면에서는 macOS가 알아서 위쪽 막대를 보여 줌
        if window.styleMask.contains(.fullScreen) { return }
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        let near = frame.contains(mouse) && frame.maxY - mouse.y <= (visible ? keepHeight : revealHeight)
        if near {
            hideTask?.cancel()
            hideTask = nil
            if !visible { setVisible(true, animated: true) }
        } else if visible, hideTask == nil {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let self, !Task.isCancelled else { return }
                self.hideTask = nil
                self.setVisible(false, animated: true)
            }
        }
    }

    /// 위쪽 막대 뒤에 반투명 흐림 배경 (영상이 은은하게 비치고 글자·버튼은 잘 보이게)
    private func addBlur(to window: NSWindow) {
        guard let bar = window.standardWindowButton(.closeButton)?.superview?.superview,
              !bar.subviews.contains(where: { $0.identifier?.rawValue == "epoTitlebarBlur" }) else { return }
        let blur = NSVisualEffectView(frame: bar.bounds)
        blur.identifier = NSUserInterfaceItemIdentifier("epoTitlebarBlur")
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        bar.addSubview(blur, positioned: .below, relativeTo: nil)
    }

    private func setVisible(_ show: Bool, animated: Bool) {
        visible = show
        // 제목·신호등 버튼·툴바가 들어 있는 위쪽 막대 전체
        guard let bar = window?.standardWindowButton(.closeButton)?.superview?.superview else { return }
        bar.wantsLayer = true
        guard let layer = bar.layer else { bar.alphaValue = show ? 1 : 0; return }
        // 숨길 때는 막대 높이만큼 위로 올려 두고, 보일 때 아래로 내려옴
        let up = bar.isFlipped ? -bar.bounds.height : bar.bounds.height
        let hidden = CATransform3DMakeTranslation(0, up, 0)
        let target = show ? CATransform3DIdentity : hidden
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let slide = CABasicAnimation(keyPath: "transform")
            slide.fromValue = layer.presentation()?.transform ?? layer.transform
            slide.toValue = target
            slide.duration = 0.22
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(slide, forKey: "epoSlide")
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                bar.animator().alphaValue = show ? 1 : 0
            }
        } else {
            bar.alphaValue = show ? 1 : 0
        }
        layer.transform = target
    }
}

/// 재생 창: 최고 화질 파일을 찾아 기본 플레이어로 자동 재생
/// (못 찾으면 사이트의 퍼가기 플레이어로 대신 재생)
struct PlayerView: View {
    let item: PlayerItem
    @StateObject private var sheet = SheetState()
    @StateObject private var loader = PlayerLoader()
    @StateObject private var subtitles = SubtitleEngine()
    @StateObject private var builder = SubtitleBuilder()
    @StateObject private var models = ModelsState()
    @StateObject private var fullScreen = FullScreenState()
    @StateObject private var pin = WindowPin()

    var body: some View {
        content
            .frame(minWidth: 240, minHeight: 135)
            .background(.black)
            // 전체 화면에서는 위쪽 막대(제목·버튼)를 숨기고 영상이 화면 끝까지 차게
            .ignoresSafeArea()
            .toolbar(fullScreen.isOn ? .hidden : .visible, for: .windowToolbar)
            .background(WindowReader { fullScreen.attach($0); pin.attach($0) })
            .navigationTitle(item.title)
            .navigationSubtitle(loader.subtitle)
            .sheet(item: $sheet.video) { DownloadSheet(video: $0) }
            .overlay(alignment: .bottom) { ToastView() }
            .task { [loader] in
                subtitles.listenAssetProvider = { [weak loader] in await loader?.listenAsset() }
                loader.start(item)
            }
            .task { models.models = await ModelScraper.load(pageURL: item.url) }
            .onDisappear { loader.stop(); subtitles.stop() }
            // 앱 플레이어로 재생이 시작되면 자막 자동으로 켜기 (설정에서 끌 수 있음)
            .onReceive(loader.$mode) { mode in
                switch mode {
                case .native(let player):
                    if let saved = SubtitleStore.load(item.id) {
                        subtitles.showPrebuilt(saved, player: player)
                    } else if subtitles.autoOn, !subtitles.isOn, let current = player.currentItem {
                        subtitles.start(item: current)
                    }
                case .embed:
                    subtitles.stop()   // 사이트 플레이어로 바뀌면 자막은 못 씀
                case .finding:
                    break
                }
            }
            // 자막 번역: 언어가 정해지면 번역 세션을 받아서 계속 번역
            .translationTask(subtitles.translationConfig) { session in
                await subtitles.runTranslation(session)
            }
            // 미리 만들기 번역: 받아쓰기가 끝나면 한꺼번에 번역
            .translationTask(builder.translationConfig) { session in
                await builder.translateAll(session)
            }
            .overlay(alignment: .topLeading) { builderStatus }
            .toolbar {
                // 영상에 나오는 모델 (있을 때만, 여러 명이면 모두)
                if !models.models.isEmpty {
                    ToolbarItem(placement: .navigation) {
                        ModelPicker(models: models.models)
                    }
                }
                ToolbarItem {
                    // 재생 창 배율 (단축키 1·2·3·4)
                    Menu {
                        ForEach(PlayerCenter.Scale.allCases) { scale in
                            Button("\(scale.label)    \(scale.key)") { PlayerCenter.shared.resize(scale) }
                        }
                    } label: {
                        Label("배율", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("재생 창 크기: 1 = 1배, 2 = 0.5배, 3 = 가로 1920, 4 = 0.25배")
                }
                ToolbarItem {
                    // 재생 창을 다른 창들 위에 늘 띄우기 (기본: 켜짐)
                    Button {
                        pin.isOn.toggle()
                    } label: {
                        Label(pin.isOn ? "항상 위에 끄기" : "항상 위에",
                              systemImage: pin.isOn ? "pin.fill" : "pin")
                    }
                    .help(pin.isOn ? "지금 다른 창들 위에 떠 있어요 (누르면 해제)" : "누르면 다른 창들 위에 늘 떠 있어요")
                }
                ToolbarItem {
                    // 누르면 자막 켜기·끄기, 화살표 메뉴에서 원문 보기·언어 다시 찾기
                    Menu {
                        // 미리 만들기: 영상 전체를 한 번에 받아쓰고 번역해서 저장 (말과 정확히 맞는 자막)
                        if builder.isWorking {
                            Button("자막 만들기 취소") { builder.cancel() }
                        } else if SubtitleStore.load(item.id) != nil {
                            Text("미리 만든 자막이 있어요")
                            Button("자막 다시 만들기") { SubtitleStore.delete(item.id); subtitles.stop(); buildSubtitles() }
                            Button("만든 자막 지우기") { SubtitleStore.delete(item.id); subtitles.stop() }
                            Button("자막 파일(SRT) Finder에서 보기") {
                                NSWorkspace.shared.activateFileViewerSelecting([SubtitleStore.srtURL(item.id)])
                            }
                        } else {
                            Button("자막 미리 만들기 (정확한 자막)") { buildSubtitles() }
                        }
                        Divider()
                        Toggle("영상 열 때 자막 자동으로 켜기", isOn: $subtitles.autoOn)
                        Toggle("원문도 같이 보기", isOn: $subtitles.showOriginal)
                        Toggle("일본어 원문은 한글 발음으로", isOn: $subtitles.japaneseHangul)
                        // 꺼져 있으면 자막을 켜면서 언어 찾기 시작
                        Button(subtitles.isOn ? "언어 다시 찾기" : "자막 켜고 언어 찾기") {
                            if subtitles.isOn { subtitles.restart() } else { toggleSubtitles() }
                        }
                        Divider()
                        Picker("자막 크기", selection: $subtitles.fontSize) {
                            ForEach(SubtitleEngine.fontSizes, id: \.size) { option in
                                Text("\(option.label) (\(Int(option.size)))").tag(option.size)
                            }
                            // 단축키로 바꾼 크기가 목록에 없을 때도 표시
                            if !SubtitleEngine.fontSizes.contains(where: { $0.size == subtitles.fontSize }) {
                                Text("사용자 지정 (\(Int(subtitles.fontSize)))").tag(subtitles.fontSize)
                            }
                        }
                        Picker("자막 위치", selection: $subtitles.position) {
                            ForEach(SubtitleEngine.positions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                            if !SubtitleEngine.positions.contains(where: { $0.value == subtitles.position }) {
                                Text("사용자 지정 (\(Int(subtitles.position * 100))%)").tag(subtitles.position)
                            }
                        }
                        Picker("자막 당기기 (실시간 자막)", selection: $subtitles.lead) {
                            ForEach(SubtitleEngine.leads, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        Button("자막 위로") { subtitles.moveUp() }
                            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                        Button("자막 아래로") { subtitles.moveDown() }
                            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                        Divider()
                        Button("자막 크게") { subtitles.biggerFont() }
                            .keyboardShortcut("=", modifiers: .command)
                        Button("자막 작게") { subtitles.smallerFont() }
                            .keyboardShortcut("-", modifiers: .command)
                    } label: {
                        Label(subtitles.isOn ? "자막 끄기" : "한국어 자막",
                              systemImage: subtitles.isOn ? "captions.bubble.fill" : "captions.bubble")
                    } primaryAction: {
                        toggleSubtitles()
                    }
                    .help("소리를 받아써서 한국어 자막으로 보여 줘요 (앱 플레이어에서만)")
                }
                ToolbarItem {
                    // 누르면 최고 화질 바로 복사, 화살표 메뉴에서 화질 고르기
                    Menu {
                        Button("화질 골라서 복사…") { sheet.video = Video(item: item) }
                        Button("4K 주소 모으기") { URLCollector.collect4K(for: Video(item: item)) }
                    } label: {
                        Label("다운로드 주소 복사", systemImage: "arrow.down.circle")
                    } primaryAction: {
                        QuickCopy.bestDownloadURL(for: Video(item: item))
                    }
                    .help("최고 화질 다운로드 주소를 복사")
                }
                ToolbarItem {
                    Menu {
                        SaveMenuItems(fid: item.fid ?? 0, videoID: item.id)
                    } label: {
                        Label("저장", systemImage: "heart")
                    }
                    .help("즐겨찾기·나중에 볼 영상·플레이리스트에 저장")
                }
                ToolbarItem {
                    Menu {
                        Button("최고 화질로 다시 연결") { subtitles.stop(); loader.stop(); loader.start(item) }
                        Button("사이트 플레이어로 전환") { subtitles.stop(); loader.showSitePlayer() }
                        Divider()
                        Text("더블클릭: 전체 화면")
                        Text("1·2·3·4: 재생 창 크기")
                    } label: {
                        Label("재생 옵션", systemImage: "ellipsis.circle")
                    }
                }
                ToolbarItem {
                    Button {
                        NSWorkspace.shared.open(URL(string: item.url)!)
                    } label: {
                        Label("브라우저에서 열기", systemImage: "safari")
                    }
                }
            }
    }

    private func toggleSubtitles() {
        if subtitles.isOn { subtitles.stop(); return }
        guard case .native(let player) = loader.mode, let current = player.currentItem else {
            Toast.shared.show("자막은 앱 플레이어로 재생할 때만 돼요.", error: true)
            return
        }
        if let saved = SubtitleStore.load(item.id) {
            subtitles.showPrebuilt(saved, player: player)
        } else {
            subtitles.start(item: current)
        }
    }

    /// 자막 미리 만들기 시작 (끝나면 바로 그 자막으로 바꿈)
    private func buildSubtitles() {
        builder.start(item) { saved in
            if case .native(let player) = loader.mode { subtitles.showPrebuilt(saved, player: player) }
        }
    }

    /// 왼쪽 위 진행 표시
    @ViewBuilder private var builderStatus: some View {
        switch builder.state {
        case .working(let message):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("자막 만드는 중: \(message)").font(.caption)
                Button("취소") { builder.cancel() }.buttonStyle(.link).font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.6), in: Capsule())
            .foregroundStyle(.white)
            .padding(10)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("자막을 만들지 못했어요", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.semibold))
                Text(message).font(.caption).lineLimit(3)
                Button("다시 만들기") { buildSubtitles() }.buttonStyle(.bordered)
            }
            .padding(14)
            .frame(maxWidth: 360, alignment: .leading)
            .foregroundStyle(.white)
            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .padding(12)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch loader.mode {
        case .finding:
            VStack(spacing: 10) {
                ProgressView().controlSize(.large)
                Text("최고 화질로 연결하고 있어요").font(.headline).foregroundStyle(.white)
                Text("연결이 어려우면 사이트 플레이어로 전환됩니다.")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                Button("사이트 플레이어로 열기") { loader.stop(); loader.showSitePlayer() }
                    .buttonStyle(.bordered).tint(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .native(let player):
            NativePlayerView(player: player)
                .overlay { SubtitleOverlay(engine: subtitles) }
        case .embed:
            EmbedWebView(url: URL(string: item.embed)!, autoplay: true)
        }
    }
}

@MainActor
final class PlayerLoader: ObservableObject {
    enum Mode { case finding, native(AVPlayer), embed }

    @Published private(set) var mode = Mode.finding
    @Published private(set) var subtitle = ""
    private var task: Task<Void, Never>?
    /// 자막 미리 듣기용: 가장 낮은 화질 주소 (소리는 화질과 상관없이 같아서 데이터를 아낌)
    private var lowLink: URL?
    private var cookies: [HTTPCookie] = []
    private var listenCache: AVURLAsset?
    private var statusObserver: NSKeyValueObservation?
    private var sizeObserver: NSKeyValueObservation?

    func start(_ item: PlayerItem) {
        guard task == nil else { return }
        mode = .finding
        subtitle = "연결 중"
        lowLink = nil
        listenCache = nil
        task = Task {
            do {
                let links = try await DownloadLoader.findLinks(pageURL: item.url)
                guard let best = links.max(by: { $0.height < $1.height }), let link = URL(string: best.url) else {
                    throw DownloadError("링크 없음")
                }
                // 다운로드 링크는 실제 파일로 넘겨 주는 주소라서 끝 주소를 먼저 알아냄
                let fileURL = (try? await DownloadLoader.resolve(link)) ?? link
                guard !Task.isCancelled else { return }
                let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
                self.cookies = cookies
                self.lowLink = links.min(by: { $0.height < $1.height }).flatMap { URL(string: $0.url) }
                let asset = AVURLAsset(url: fileURL, options: [AVURLAssetHTTPCookiesKey: cookies])
                let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                watchForFailure(player, item: item)
                // 영상 실제 해상도를 알게 되면 재생 창 배율에 씀
                sizeObserver = player.currentItem?.observe(\.presentationSize, options: [.initial, .new]) { playerItem, _ in
                    let size = playerItem.presentationSize
                    guard size.width > 0, size.height > 0 else { return }
                    Task { @MainActor in PlayerCenter.shared.videoSize = size }
                }
                mode = .native(player)
                subtitle = "\(best.qualityText) 재생"
                player.play()
                DebugLog.write("기본 플레이어로 재생: \(best.qualityText) \(fileURL)")
            } catch {
                guard !Task.isCancelled else { return }
                DebugLog.write("최고 화질 재생 불가, 사이트 플레이어로: \(error.localizedDescription)")
                useEmbed()
            }
        }
    }

    func showSitePlayer() {
        stop()
        useEmbed()
    }

    /// 파일을 못 여는 경우(형식·권한 문제) 사이트 플레이어로 바꿈
    private func watchForFailure(_ player: AVPlayer, item: PlayerItem) {
        statusObserver = player.currentItem?.observe(\.status) { [weak self] playerItem, _ in
            guard playerItem.status == .failed else { return }
            Task { @MainActor in
                DebugLog.write("기본 플레이어 재생 실패: \(String(describing: playerItem.error))")
                self?.useEmbed()
            }
        }
    }

    private func useEmbed() {
        if case .native(let player) = mode { player.pause() }
        mode = .embed
        subtitle = "사이트 플레이어"
    }

    /// 자막 미리 듣기용 영상 (가장 낮은 화질, 처음 한 번만 끝 주소를 알아냄)
    func listenAsset() async -> AVURLAsset? {
        if let listenCache { return listenCache }
        guard let lowLink else { return nil }
        let url = (try? await DownloadLoader.resolve(lowLink)) ?? lowLink
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
        listenCache = asset
        return asset
    }

    func stop() {
        task?.cancel()
        task = nil
        statusObserver = nil
        sizeObserver = nil
        if case .native(let player) = mode { player.pause() }
    }
}

/// 재생 창을 다른 창들 위에 늘 띄움 (설정은 다음 재생 창·다음 실행에도 유지, 기본 켜짐)
@MainActor
final class WindowPin: ObservableObject {
    private static let key = "playerAlwaysOnTop"

    /// 저장된 "항상 위에" 설정 (기본: 켜짐)
    static var savedIsOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    @Published var isOn: Bool = WindowPin.savedIsOn {
        didSet {
            UserDefaults.standard.set(isOn, forKey: Self.key)
            apply()
        }
    }
    private weak var window: NSWindow?

    func attach(_ window: NSWindow?) {
        guard let window, window !== self.window else { return }
        self.window = window
        apply()
    }

    private func apply() {
        guard let window else { return }
        // 전체 화면 중에는 보통 높이 그대로 (나오면 다시 적용됨)
        window.level = isOn && !window.styleMask.contains(.fullScreen) ? .floating : .normal
        // 앱이 뒤로 가도 숨지 않고 위에 남게
        window.hidesOnDeactivate = false
    }
}

/// 이 재생 창이 전체 화면인지 알려 줌
@MainActor
final class FullScreenState: ObservableObject {
    @Published private(set) var isOn = false
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func attach(_ window: NSWindow?) {
        guard let window, window !== self.window else { return }
        self.window = window
        isOn = window.styleMask.contains(.fullScreen)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isOn = true }
            },
            center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isOn = false }
            },
        ]
    }
}

/// SwiftUI 화면이 들어 있는 창을 알아냄
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

/// 재생 창 전체 화면 켜기·끄기
final class FullScreenToggler: NSObject {
    @objc func toggle(_ sender: NSGestureRecognizer) {
        sender.view?.window?.toggleFullScreen(nil)
    }
}

/// macOS 기본 영상 플레이어 (전체 화면, 화면 속 화면 지원)
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeCoordinator() -> FullScreenToggler { FullScreenToggler() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        // 자체 전체 화면은 자막이 안 보이는 별도 창이라 끔 (더블클릭하면 창 전체 화면)
        view.showsFullScreenToggleButton = false
        // 더블클릭 전체 화면은 재생 창(PlayerChrome)에서 한 번에 처리 (여기서도 하면 두 번 바뀌어 취소됨)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

struct EmbedWebView: NSViewRepresentable {
    let url: URL
    /// 로그인 창처럼 페이지 이동이 필요한 곳은 true
    var allowNavigation = false
    /// 페이지 안의 영상을 자동으로 재생
    var autoplay = false

    private static let doubleClickJS = """
    document.addEventListener('dblclick', (e) => {
      e.preventDefault(); e.stopPropagation();
    }, true);
    """

    /// 영상이 나타나면 재생을 누르고, 고를 수 있으면 가장 높은 화질로 바꿈
    private static let autoplayJS = """
    (() => {
      let tries = 0;
      const timer = setInterval(() => {
        tries++;
        const v = document.querySelector('video');
        if (v) {
          if (v.paused) { const p = v.play(); if (p) p.catch(() => {}); }
          if (!v.paused || tries > 40) clearInterval(timer);
        } else {
          const btn = document.querySelector('.vjs-big-play-button, .play-button, [class*="play" i] button, button[aria-label*="play" i]');
          if (btn) btn.click();
          if (tries > 40) clearInterval(timer);
        }
      }, 500);
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator(allowNavigation: allowNavigation) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // 로그인 쿠키 공유
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        if autoplay {
            config.userContentController.addUserScript(
                WKUserScript(source: Self.autoplayJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
            // 사이트 플레이어 자체 더블클릭 전체 화면은 막음 (재생 창 전체 화면은 PlayerChrome이 처리)
            config.userContentController.addUserScript(
                WKUserScript(source: Self.doubleClickJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.uiDelegate = context.coordinator
        web.navigationDelegate = context.coordinator
        context.coordinator.webView = web
        web.customUserAgent = HeadlessPage.userAgent
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        let allowNavigation: Bool
        weak var webView: WKWebView?
        init(allowNavigation: Bool) { self.allowNavigation = allowNavigation }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "toggleFullScreen" { webView?.window?.toggleFullScreen(nil) }
        }

        // 광고 새 창(팝업)은 열지 않음
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }

        // 재생 화면에서 다른 페이지로 넘어가는 클릭(광고 등)은 막음
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
            if !allowNavigation && isMainFrame && navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DebugLog.write("재생 페이지 실패: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DebugLog.write("재생 페이지 연결 실패: \(error)")
        }
    }
}
