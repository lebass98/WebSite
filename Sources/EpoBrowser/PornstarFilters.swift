import SwiftUI
import Combine

/// 포르노스타 목록 필터 (사이트의 FILTERS와 같은 값)
struct PornstarFilters: Equatable {
    /// 범위 필터 하나 (사이트 기준 cm, 나이는 세)
    struct Range: Equatable {
        let bounds: ClosedRange<Int>
        var low: Int
        var high: Int
        init(_ bounds: ClosedRange<Int>) { self.bounds = bounds; low = bounds.lowerBound; high = bounds.upperBound }
        var isDefault: Bool { low == bounds.lowerBound && high == bounds.upperBound }
    }

    var inches = false
    var age = Range(18...107)
    var height = Range(109...203)
    var bust = Range(25...168)
    var waist = Range(35...166)
    var hips = Range(25...173)
    /// 여러 개 고르는 항목 (사이트 이름 → 고른 값)
    var choices: [String: Set<String>] = [:]

    var isDefault: Bool {
        age.isDefault && height.isDefault && bust.isDefault && waist.isDefault && hips.isDefault
            && choices.values.allSatisfy(\.isEmpty)
    }

    /// 사이트 주소에 붙일 값 (기본값인 항목은 빼고, 길이는 항상 cm로 보냄)
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        func range(_ name: String, _ r: Range) {
            guard !r.isDefault else { return }
            items.append(.init(name: "\(name)_from", value: String(r.low)))
            items.append(.init(name: "\(name)_to", value: String(r.high)))
        }
        range("age", age); range("height", height); range("bust", bust); range("waist", waist); range("hips", hips)
        if !items.isEmpty { items.insert(.init(name: "unit", value: "cm"), at: 0) }
        for (name, values) in choices.sorted(by: { $0.key < $1.key }) {
            for v in values.sorted() { items.append(.init(name: "\(name)[]", value: v)) }
        }
        return items
    }
}

/// 여러 개 고르는 항목 하나 (Cup, Hair …)
struct PornstarChoiceField: Identifiable {
    let name: String      // 사이트 이름 (cup, hair, country, ethnicity, eye)
    let label: String
    let options: [(value: String, label: String)]
    var id: String { name }
}

@MainActor
final class PornstarFilterStore: ObservableObject {
    static let shared = PornstarFilterStore()

    @Published var draft = PornstarFilters()
    @Published private(set) var applied = PornstarFilters()
    @Published private(set) var fields: [PornstarChoiceField] = PornstarFilterStore.builtInFields
    private var optionsLoaded = false

    var hasChanges: Bool { draft != applied }

    func apply() { applied = draft }

    func clear() {
        let inches = draft.inches
        draft = PornstarFilters()
        draft.inches = inches
        applied = draft
    }

    func toggle(_ field: String, _ value: String) {
        var set = draft.choices[field] ?? []
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
        draft.choices[field] = set
    }

    /// 국가 목록은 길어서 사이트 양식에서 읽어 옴 (실패하면 국가 빼고 기본 목록)
    func loadOptionsOnce() {
        guard !optionsLoaded else { return }
        optionsLoaded = true
        Task {
            do {
                let html = try await SiteScraper.html(URL(string: SiteScraper.base + "/pornstar-list/female/")!)
                let parsed = Self.parseFields(html)
                DebugLog.write("포르노스타 필터 항목 \(parsed.count)개 (페이지 \(html.count)자, select \(html.components(separatedBy: "<select").count - 1)개)")
                if !parsed.isEmpty { fields = parsed }
            } catch {
                optionsLoaded = false
                DebugLog.write("포르노스타 필터 목록 읽기 실패: \(error)")
            }
        }
    }

    private static let labels = ["cup": "컵", "hair": "머리색", "country": "국가", "ethnicity": "인종", "eye": "눈 색"]

    private static func parseFields(_ html: String) -> [PornstarChoiceField] {
        guard let re = try? NSRegularExpression(pattern: #"<select[^>]*name="([a-z]+)\[\]"[^>]*>([\s\S]*?)</select>"#),
              let opt = try? NSRegularExpression(pattern: #"<option[^>]*value="([^"]*)"[^>]*>([^<]*)<"#) else { return [] }
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            guard let n = Range(m.range(at: 1), in: html), let b = Range(m.range(at: 2), in: html) else { return nil }
            let name = String(html[n]), body = String(html[b])
            let options: [(value: String, label: String)] = opt.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { o in
                guard let v = Range(o.range(at: 1), in: body), let l = Range(o.range(at: 2), in: body), !body[v].isEmpty else { return nil }
                return (SiteScraper.decode(String(body[v])), SiteScraper.decode(String(body[l])))
            }
            return PornstarChoiceField(name: name, label: labels[name] ?? name, options: options)
        }
    }

    private static let builtInFields: [PornstarChoiceField] = [
        PornstarChoiceField(name: "cup", label: "컵", options: ["AA", "A", "B", "BB", "C", "D", "DD", "DDD", "E", "EE", "F", "FF", "G", "GG", "H", "HH", "I", "J", "K", "L", "LL"].map { ($0, $0) }),
        PornstarChoiceField(name: "hair", label: "머리색", options: [("blonde", "Blonde"), ("brown", "Brown / Brunette"), ("black", "Black"), ("red", "Red"), ("auburn", "Auburn"), ("other", "Other")]),
        PornstarChoiceField(name: "ethnicity", label: "인종", options: ["Asian", "Black", "Caucasian", "Indian", "Latin", "Middle Eastern", "Mixed", "Native American", "Other"].map { ($0, $0) }),
        PornstarChoiceField(name: "eye", label: "눈 색", options: ["Black", "Blue", "Brown", "Green", "Grey", "Hazel", "Mixed"].map { ($0, $0) }),
    ]
}

final class FilterBarState: ObservableObject {
    @Published var expanded = true
}

/// 포르노스타 목록 위쪽 필터 (사이트의 FILTERS를 가로로 재배치)
struct PornstarFilterBar: View {
    @ObservedObject private var store = PornstarFilterStore.shared
    @StateObject private var state = FilterBarState()

    private let rangeColumns = [GridItem(.adaptive(minimum: 170), spacing: 18, alignment: .top)]
    private let choiceColumns = [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 첫 줄: 제목·측정 단위·적용/초기화·접기
            HStack(spacing: 12) {
                Text("필터").font(.headline).foregroundStyle(.orange)
                Picker("측정 단위", selection: $store.draft.inches) {
                    Text("센티미터").tag(false)
                    Text("인치").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                if !store.applied.isDefault {
                    Text("적용 중").font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("초기화") { store.clear() }
                    .disabled(store.draft.isDefault && store.applied.isDefault)
                Button("적용") { store.apply() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!store.hasChanges)
                Button {
                    state.expanded.toggle()
                } label: {
                    Image(systemName: state.expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .help(state.expanded ? "필터 접기" : "필터 펼치기")
            }

            if state.expanded {
                // 둘째 줄: 나이·키·가슴·허리·엉덩이 범위
                LazyVGrid(columns: rangeColumns, alignment: .leading, spacing: 12) {
                    rangeBlock("나이", $store.draft.age, unitless: true)
                    rangeBlock("키", $store.draft.height)
                    rangeBlock("가슴", $store.draft.bust)
                    rangeBlock("허리", $store.draft.waist)
                    rangeBlock("엉덩이", $store.draft.hips)
                }
                // 셋째 줄: 컵·머리색·국가·인종·눈 색
                LazyVGrid(columns: choiceColumns, alignment: .leading, spacing: 10) {
                    ForEach(store.fields) { field in choiceBlock(field) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .task { store.loadOptionsOnce() }
    }

    private func rangeBlock(_ title: String, _ range: Binding<PornstarFilters.Range>, unitless: Bool = false) -> some View {
        let r = range.wrappedValue
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.bold()).foregroundStyle(.orange)
                Spacer()
                Text("\(valueText(r.low, edge: r.low == r.bounds.lowerBound ? "≤ " : "", unitless: unitless)) ~ \(valueText(r.high, edge: r.high == r.bounds.upperBound ? "≥ " : "", unitless: unitless))")
                    .font(.caption.monospacedDigit())
            }
            RangeSlider(low: range.low, high: range.high, range: r.bounds)
                .frame(height: 20)
        }
    }

    private func valueText(_ cm: Int, edge: String, unitless: Bool) -> String {
        if unitless { return "\(cm)" }
        if store.draft.inches { return "\(edge)\(Int((Double(cm) / 2.54).rounded())) in" }
        return "\(edge)\(cm) cm"
    }

    private func choiceBlock(_ field: PornstarChoiceField) -> some View {
        let selected = store.draft.choices[field.name] ?? []
        return VStack(alignment: .leading, spacing: 4) {
            Text(field.label).font(.caption.bold()).foregroundStyle(.secondary)
            Menu {
                if !selected.isEmpty {
                    Button("선택 지우기") { store.draft.choices[field.name] = [] }
                    Divider()
                }
                ForEach(field.options, id: \.value) { option in
                    Toggle(option.label, isOn: Binding(
                        get: { selected.contains(option.value) },
                        set: { _ in store.toggle(field.name, option.value) }))
                }
            } label: {
                Text(selected.isEmpty ? "상관없음" : selected.count == 1 ? label(of: selected.first!, in: field) : "\(selected.count)개 선택")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func label(of value: String, in field: PornstarChoiceField) -> String {
        field.options.first { $0.value == value }?.label ?? value
    }
}
