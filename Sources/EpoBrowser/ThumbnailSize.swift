import SwiftUI
import Combine

/// 썸네일 크기 (모든 목록에 적용, 다음 실행에도 유지)
@MainActor
final class ThumbnailSize: ObservableObject {
    static let shared = ThumbnailSize()
    static let range: ClosedRange<Double> = 160...520
    private static let key = "thumbnailWidth"

    @Published var width: Double {
        didSet { UserDefaults.standard.set(width, forKey: Self.key) }
    }

    private init() {
        let saved = UserDefaults.standard.double(forKey: Self.key)
        width = saved == 0 ? 240 : min(max(saved, Self.range.lowerBound), Self.range.upperBound)
    }

    /// 목록 칸: 고른 너비를 최소로 해서 창 너비에 맞게 채움
    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: width, maximum: width * 1.5), spacing: 14)]
    }
}

/// 위쪽 줄 오른쪽의 썸네일 크기 바
struct ThumbnailSizeSlider: View {
    @ObservedObject var size = ThumbnailSize.shared

    var body: some View {
        HStack(spacing: 6) {
            Button { size.width = max(size.width - 40, ThumbnailSize.range.lowerBound) } label: {
                Image(systemName: "square.grid.3x3")
            }
            .buttonStyle(.borderless)
            .help("썸네일 작게")

            Slider(value: $size.width, in: ThumbnailSize.range)
                .frame(width: 140)
                .controlSize(.small)
                .help("썸네일 크기")

            Button { size.width = min(size.width + 40, ThumbnailSize.range.upperBound) } label: {
                Image(systemName: "square.grid.2x2")
            }
            .buttonStyle(.borderless)
            .help("썸네일 크게")
        }
        .foregroundStyle(.secondary)
    }
}
