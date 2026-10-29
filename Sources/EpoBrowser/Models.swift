import Foundation

/// 영상 한 개 (사이트 목록 카드에서 읽음)
struct Video: Identifiable, Hashable {
    let id: String
    let title: String
    let keywords: String
    let views: Int
    /// 5점 만점
    let rate: Double
    let url: String
    let added: String
    let lengthSec: Int
    let lengthText: String
    let embed: String
    let thumb: String
    let thumbs: [String]
    /// 사이트 안 영상 번호 (즐겨찾기 등 저장할 때 사용, 0 = 모름)
    let fid: Int
    /// 마우스를 올렸을 때 나오는 짧은 미리보기 영상
    let previewURL: String?
    /// 올린 사람 (카드 아래 프로필 바로가기)
    let uploaderName: String?
    let uploaderPath: String?

    init(id: String, title: String, keywords: String, views: Int, rate: Double, url: String, added: String,
         lengthSec: Int, lengthText: String, embed: String, thumb: String, thumbs: [String],
         fid: Int = 0, previewURL: String? = nil, uploaderName: String? = nil, uploaderPath: String? = nil) {
        self.id = id; self.title = title; self.keywords = keywords; self.views = views; self.rate = rate
        self.url = url; self.added = added; self.lengthSec = lengthSec; self.lengthText = lengthText
        self.embed = embed; self.thumb = thumb; self.thumbs = thumbs
        self.fid = fid; self.previewURL = previewURL
        self.uploaderName = uploaderName; self.uploaderPath = uploaderPath
    }

    /// 재생 창에서 다운로드 창을 열 때 쓰는 최소 정보
    init(item: PlayerItem) {
        self.init(id: item.id, title: item.title, keywords: "", views: 0, rate: 0, url: item.url, added: "",
                  lengthSec: 0, lengthText: "", embed: item.embed, thumb: "", thumbs: [], fid: item.fid ?? 0)
    }

    /// 제목·키워드로 본 VR 여부
    var looksVR: Bool { VRDetector.isVR(title + " " + keywords) }

    /// 앱 안 재생 창에 넘길 최소 정보
    var playerItem: PlayerItem { PlayerItem(id: id, title: title, embed: embed, url: url, fid: fid == 0 ? nil : fid) }
}

/// 재생 창에 넘기는 값 (창을 다시 열 때 복원되도록 Codable)
struct PlayerItem: Codable, Hashable {
    let id: String
    let title: String
    let embed: String
    let url: String
    /// 사이트 안 영상 번호 (예전에 저장된 값에는 없음)
    var fid: Int? = nil
}

enum SortOrder: String, CaseIterable, Identifiable {
    /// 즐겨찾기·나중에 볼 영상에 넣은 순서 (사이트가 보여 주는 순서 그대로, 최근에 넣은 것 먼저)
    case saved
    case latest, mostPopular = "most-viewed", topRated = "top-rated"
    case topWeekly = "top-weekly", topMonthly = "top-monthly", longest, shortest
    var id: String { rawValue }

    var label: String {
        switch self {
        case .saved: "추가한 순"
        case .latest: "최신순"
        case .mostPopular: "인기순"
        case .topRated: "평점순"
        case .topWeekly: "이번 주 인기"
        case .topMonthly: "이번 달 인기"
        case .longest: "긴 영상순"
        case .shortest: "짧은 영상순"
        }
    }

    /// 카테고리 페이지 주소용 (/cat/all/SORT-top-rated/)
    var catSegment: String { self == .latest || self == .saved ? "" : "SORT-\(rawValue)" }
    /// 검색(태그) 페이지 주소용 (/tag/taboo/top-rated/)
    var tagSegment: String { self == .latest || self == .saved ? "" : rawValue }
}

/// 게이 영상 (사이트 기본값은 제외)
enum Inclusion: Int, CaseIterable, Identifiable {
    case exclude = 0, include = 1, only = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .exclude: "제외"
        case .include: "포함"
        case .only: "만 보기"
        }
    }
}
