import SwiftUI
import Combine

final class CategoryExpand: ObservableObject {
    @Published var open = false
    @Published var filtersOpen = false
}

/// 항상 보이는 왼쪽 사이드바 (검색 종류·메뉴·화질·길이·카테고리·최근 본 영상)
struct SidebarView: View {
    @ObservedObject var nav: NavState
    @ObservedObject var search: SearchField
    @ObservedObject private var filters = FilterStore.shared
    @ObservedObject private var session = SiteSession.shared
    @StateObject private var expand = CategoryExpand()

    var body: some View {
        // 사이드바 칸에서는 ScrollView 안 버튼이 실제 마우스 클릭을 못 받아서 기본 사이드바 목록(List)으로 만듦
        List {
            Group {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2).foregroundStyle(EpoStyle.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EpoBrowser").font(.headline)
                        Text("나만의 미디어 라이브러리").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)
                group("탐색 · 검색 유형") {
                    ForEach(SearchType.allCases) { type in
                        row(type.label, selected: nav.searchType == type && isSearchSection) {
                            nav.searchType = type
                            nav.showSearchResults()
                        }
                    }
                    if !filters.searchText.isEmpty {
                        Text("검색어: \(filters.searchText)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                group("둘러보기") {
                    row("베스트 영상", icon: "flame", selected: nav.section == .best) { nav.section = .best }
                    row("최고 평점", icon: "star", selected: nav.section == .topRated) { nav.section = .topRated }
                    row("카테고리", icon: "square.grid.2x2", selected: nav.section == .categories) { nav.section = .categories }
                    row("전체 카테고리 (A~Z)", icon: "list.bullet", selected: nav.section == .allCategories) { nav.section = .allCategories }
                    row("포르노스타 (여성)", icon: "person", selected: nav.section == .collection(.pornstarsFemale)) { nav.section = .collection(.pornstarsFemale) }
                    row("포르노스타 (남성)", icon: "person", selected: nav.section == .collection(.pornstarsMale)) { nav.section = .collection(.pornstarsMale) }
                    row("채널", icon: "play.tv", selected: nav.section == .collection(.channels)) { nav.section = .collection(.channels) }
                }

                if !session.userLinks.isEmpty {
                    group("내 계정") {
                        ForEach(session.userLinks) { link in
                            if link.kind == .logout {
                                row(link.kind.label, icon: link.kind.icon, selected: false) {
                                    session.logout()
                                    nav.section = .videos
                                }
                            } else {
                                row(link.kind.label, icon: link.kind.icon, selected: nav.section == .user(link)) {
                                    nav.section = .user(link)
                                }
                            }
                        }
                    }
                }

                DisclosureGroup(isExpanded: $expand.filtersOpen) {
                    group("화질 · 즉시 적용") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(QualityOption.allCases) { q in
                                chip(q.label, selected: filters.applied.quality == q) { filters.setQuality(q) }
                            }
                        }
                        Text("VR은 VR에서만 나오고, 다른 화질에서는 빠져요.").font(.caption2).foregroundStyle(.secondary)
                    }

                    group("길이 (분)") {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("최소").font(.caption).foregroundStyle(.secondary)
                                Text(minuteText(filters.draft.minMinutes)).bold()
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("최대").font(.caption).foregroundStyle(.secondary)
                                Text(minuteText(filters.draft.maxMinutes)).bold()
                            }
                        }
                        RangeSlider(low: $filters.draft.minMinutes, high: $filters.draft.maxMinutes,
                                    range: 0...VideoFilters.openMax)
                            .frame(height: 22)
                        HStack {
                            ForEach(["0", "15m", "30m", "45m", "1h+"], id: \.self) { t in
                                Text(t).font(.caption2).foregroundStyle(.secondary)
                                if t != "1h+" { Spacer() }
                            }
                        }
                    }

                    group("카테고리") {
                        Button {
                            expand.open.toggle()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("카테고리 고르기").bold()
                                    Text("\(filters.draft.categories.count)개 선택 (최대 \(VideoFilters.maxCategories)개)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: expand.open ? "chevron.up" : "chevron.down")
                            }
                            .padding(10)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if expand.open {
                            ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(SiteCategory.sorted) { cat in
                                    let on = filters.draft.categories.contains(cat.slug)
                                    Button {
                                        filters.toggleCategory(cat.slug)
                                    } label: {
                                        HStack {
                                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(on ? Color.accentColor : .secondary)
                                            Text(cat.name)
                                            Spacer()
                                        }
                                        .padding(.vertical, 3)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!on && filters.draft.categories.count >= VideoFilters.maxCategories)
                                }
                            }
                            }
                            .frame(height: 220)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            filters.apply()
                            expand.open = false
                        } label: {
                            Text("필터 적용").bold().frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(EpoStyle.accent)
                        .controlSize(.large)
                        .disabled(!filters.hasChanges)

                        Button {
                            filters.clear()
                        } label: {
                            Text("초기화").bold().frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(filters.draft.isDefault && filters.applied.isDefault)
                    }

                } label: {
                    Label(filters.applied.isDefault ? "세부 필터" : "세부 필터 · 적용 중", systemImage: "slider.horizontal.3")
                        .font(.callout.weight(.semibold))
                }

                RecentListView()
            }
            .listRowSeparator(.hidden)
            .padding(.vertical, 6)
        }
        .listStyle(.sidebar)
    }

    private var isSearchSection: Bool {
        switch nav.section {
        case .videos: nav.searchType == .videos
        case .collection(.searchPornstars), .collection(.searchPlaylists): true
        case .collection(.playlists): nav.searchType == .playlists
        default: false
        }
    }

    private func minuteText(_ m: Int) -> String {
        m >= VideoFilters.openMax ? "1h+" : "\(m)분"
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).frame(width: 18) }
                Text(title).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .foregroundStyle(selected ? EpoStyle.accent : Color.primary)
            .background(selected ? EpoStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(selected ? EpoStyle.accent : Color.primary)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? EpoStyle.accent : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 손잡이 두 개짜리 범위 슬라이더 (최소·최대 길이)
struct RangeSlider: View {
    @Binding var low: Int
    @Binding var high: Int
    let range: ClosedRange<Int>
    var accessibilityTitle = "길이"
    var accessibilityUnit = "분"

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width - 18)
            let span = CGFloat(max(1, range.upperBound - range.lowerBound))
            let x = { (v: Int) in CGFloat(v - range.lowerBound) / span * width + 9 }
            let value = { (px: CGFloat) in
                Int(((px - 9) / width * span).rounded()) + range.lowerBound
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                Capsule().fill(EpoStyle.accent)
                    .frame(width: max(0, x(high) - x(low)), height: 4)
                    .offset(x: x(low))
                knob.position(x: x(low), y: geo.size.height / 2)
                    .accessibilityLabel("최소 \(accessibilityTitle)")
                    .accessibilityValue("\(low) \(accessibilityUnit)")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: low = min(low + 1, high)
                        case .decrement: low = max(low - 1, range.lowerBound)
                        @unknown default: break
                        }
                    }
                    .gesture(DragGesture().onChanged { g in
                        low = min(max(value(g.location.x), range.lowerBound), high)
                    })
                knob.position(x: x(high), y: geo.size.height / 2)
                    .accessibilityLabel("최대 \(accessibilityTitle)")
                    .accessibilityValue("\(high) \(accessibilityUnit)")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: high = min(high + 1, range.upperBound)
                        case .decrement: high = max(high - 1, low)
                        @unknown default: break
                        }
                    }
                    .gesture(DragGesture().onChanged { g in
                        high = max(min(value(g.location.x), range.upperBound), low)
                    })
            }
        }
    }

    private var knob: some View {
        Circle().fill(.white)
            .overlay(Circle().strokeBorder(EpoStyle.accent, lineWidth: 3))
            .frame(width: 18, height: 18)
            .shadow(radius: 1)
    }
}
