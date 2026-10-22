import SwiftUI
import AVFoundation

/// 썸네일 위에서 소리 없이 반복 재생되는 짧은 미리보기 영상
struct PreviewPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.start(url)
        return view
    }

    func updateNSView(_ view: PreviewNSView, context: Context) {
        if view.currentURL != url { view.start(url) }
    }

    static func dismantleNSView(_ view: PreviewNSView, coordinator: ()) {
        view.stop()
    }
}

final class PreviewNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private(set) var currentURL: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    // 클릭은 아래 카드가 받도록 통과
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func start(_ url: URL) {
        stop()
        currentURL = url
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        playerLayer.player = queue
        queue.play()
    }

    func stop() {
        player?.pause()
        looper = nil
        player = nil
        playerLayer.player = nil
        currentURL = nil
    }
}
