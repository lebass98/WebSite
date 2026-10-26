import Foundation
import Combine

/// 사이드바 화질 선택 (VR은 화질과 상관없이 따로)
enum QualityOption: String, CaseIterable, Identifiable {
    case all, p720, p1080, k2, k4, vr
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "전체"
        case .p720: "720p+"
        case .p1080: "1080p+"
        case .k2: "2K+"
        case .k4: "4K"
        case .vr: "VR"
        }
    }

    /// 사이트에 보내는 quality 값 (2K는 사이트에 없어서 1080으로 받고 앱에서 한 번 더 거름)
    var siteValue: String? {
        switch self {
        case .all, .vr: nil
        case .p720: "720"
        case .p1080, .k2: "1080"
        case .k4: "2160"
        }
    }

    /// 앱에서 거를 때 쓰는 최소 세로 픽셀
    var minHeight: Int {
        switch self {
        case .all, .vr: 0
        case .p720: 720
        case .p1080: 1080
        case .k2: 1440
        case .k4: 2160
        }
    }
}

/// 사이드바 필터 묶음 (화질·길이·카테고리)
struct VideoFilters: Equatable {
    static let openMax = 61  // 61 = 1시간 이상

    var quality = QualityOption.all
    var minMinutes = 0
    var maxMinutes = openMax
    /// 사이트는 카테고리를 최대 5개까지 함께 거름
    var categories: [String] = []

    static let maxCategories = 5

    var isDefault: Bool { self == VideoFilters() }

    var summary: String {
        var parts: [String] = []
        if quality != .all { parts.append(quality.label) }
        if minMinutes > 0 || maxMinutes < Self.openMax {
            let maximum = maxMinutes >= Self.openMax ? "1시간 이상" : "\(maxMinutes)분"
            parts.append("\(minMinutes)분–\(maximum)")
        }
        if !categories.isEmpty { parts.append("카테고리 \(categories.count)개") }
        return parts.joined(separator: " · ")
    }
}

/// 사이드바 상태: 고르는 중인 값(draft)과 적용된 값(applied), 검색어
@MainActor
final class FilterStore: ObservableObject {
    static let shared = FilterStore()

    @Published var draft = VideoFilters()
    @Published private(set) var applied = VideoFilters()
    /// 적용된 검색어 (빈 문자열 = 검색 안 함)
    @Published private(set) var searchText = ""

    var hasChanges: Bool { draft != applied }

    func apply() { applied = draft }

    /// 화질은 고르는 즉시 적용 (길이·카테고리는 적용 버튼을 눌러야 반영)
    func setQuality(_ quality: QualityOption) {
        draft.quality = quality
        guard applied.quality != quality else { return }
        var next = applied
        next.quality = quality
        applied = next
    }

    func clear() {
        draft = VideoFilters()
        applied = draft
    }

    func search(_ text: String) {
        searchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toggleCategory(_ slug: String) {
        if let i = draft.categories.firstIndex(of: slug) {
            draft.categories.remove(at: i)
        } else if draft.categories.count < VideoFilters.maxCategories {
            draft.categories.append(slug)
        }
    }

    /// 검색어를 사이트 주소용으로 (공백 → -)
    nonisolated static func slug(_ text: String) -> String {
        let lowered = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "-")))
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return lowered.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? lowered
    }
}
