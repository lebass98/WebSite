import Foundation

/// 일본어 문장을 한국어 발음 나는 한글로 바꿈 (예: 気持ちいい → 기모치 이이)
/// 한자는 macOS 일본어 사전으로 읽는 법을 알아낸 뒤, 가나를 한글 소리로 옮김
enum JapaneseReading {
    static func hangul(_ text: String) -> String {
        let cf = text as CFString
        let length = CFStringGetLength(cf)
        guard length > 0,
              let tokenizer = CFStringTokenizerCreate(nil, cf, CFRange(location: 0, length: length),
                                                      kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)
        else { return text }

        var words: [(hangul: String, glue: Bool)] = []
        var prefix = ""   // お·ご 같은 앞 붙이는 말은 다음 낱말에 붙임
        var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while type != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
            var hangul: String
            if containsKanji(token),
               let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                // 한자가 있으면 로마자 읽기 → 히라가나 → 한글
                hangul = kanaToHangul(latin.applyingTransform(.latinToHiragana, reverse: false) ?? latin)
            } else {
                hangul = kanaToHangul(token)   // 가나는 그대로 옮김 (가타카나 장음 ー 도 자연스럽게)
            }
            if token == "お" || token == "ご" {
                prefix += hangul
            } else {
                // 짧은 히라가나(조사·て·ます 등)는 앞 낱말에 붙여 읽기 쉽게: 혼토니, 맛테, 야메테
                let glue = isHiragana(token) && token.count <= 3
                words.append((prefix + hangul, glue && prefix.isEmpty))
                prefix = ""
            }
            type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        // 낱말 사이는 띄우고, 문장 부호는 앞 낱말에 붙임
        if !prefix.isEmpty { words.append((prefix, false)) }
        var out = ""
        var lastWasMark = true
        for (word, glue) in words where !word.trimmingCharacters(in: .whitespaces).isEmpty {
            let mark = word.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) || "。、！？!?…・「」".unicodeScalars.contains($0) }
            if mark {
                out += word.replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "、", with: ",")
                    .replacingOccurrences(of: "！", with: "!").replacingOccurrences(of: "？", with: "?")
            } else if glue, !lastWasMark {
                // 앞 낱말이 っ(받침 ㅅ)로 끝나면 이어지는 소리라 그대로 붙임
                out = joinLongVowel(out, word)
            } else {
                out += (out.isEmpty ? "" : " ") + word
            }
            lastWasMark = mark
        }
        return out.isEmpty ? text : out
    }

    private static func containsKanji(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) || $0.value == 0x3005 }
    }

    private static func isHiragana(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) }
    }

    /// 붙일 때도 오+우 장음 정리 (이코 + 우카 같은 경우는 드물어서 그냥 이어 붙임)
    private static func joinLongVowel(_ a: String, _ b: String) -> String { a + b }

    /// 가나(히라가나·가타카나) → 한글. 가나가 아닌 글자는 그대로 둠
    static func kanaToHangul(_ input: String) -> String {
        // 가타카나는 히라가나로 맞춤
        // 장음 ー 는 바꾸기 전에 뺌 (바꾸면 모음이 하나 더 붙음: 샤와아)
        let plain = input.replacingOccurrences(of: "ー", with: "")
        let kana = plain.applyingTransform(.hiraganaToKatakana, reverse: true) ?? plain
        let chars = Array(kana)
        var out: [Character] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if i + 1 < chars.count, let s = table[String(chars[i...i + 1])] {
                out.append(contentsOf: s); i += 2; continue
            }
            switch c {
            case "っ": addFinal(19, to: &out, fallback: "ㅅ")   // 받침 ㅅ (잇따, 잇테)
            case "ん": addFinal(4, to: &out, fallback: "ㄴ")    // 받침 ㄴ
            case "ー", "〜": break                               // 길게 끄는 소리는 생략
            case "う" where endsWithO(out):
                break   // おう·こう 같은 장음은 한 번만: 혼토, 아리가토, 이코
            default:
                if let s = table[String(c)] { out.append(contentsOf: s) } else { out.append(c) }
            }
            i += 1
        }
        return String(out)
    }

    /// 앞 글자가 받침 없는 ㅗ·ㅛ 소리인지 (오, 코, 쇼, 료 …)
    private static func endsWithO(_ out: [Character]) -> Bool {
        guard let v = out.last?.unicodeScalars.first?.value, (0xAC00...0xD7A3).contains(v) else { return false }
        let n = v - 0xAC00
        let jung = (n / 28) % 21
        return n % 28 == 0 && (jung == 8 || jung == 12)   // ㅗ=8, ㅛ=12
    }

    /// 앞 글자에 받침 붙이기 (앞 글자가 받침 없는 한글일 때만)
    private static func addFinal(_ jong: UInt32, to out: inout [Character], fallback: Character) {
        if let last = out.last, let v = last.unicodeScalars.first?.value, (0xAC00...0xD7A3).contains(v), (v - 0xAC00) % 28 == 0,
           let scalar = Unicode.Scalar(v + jong) {
            out[out.count - 1] = Character(scalar)
        } else {
            out.append(fallback)
        }
    }

    private static let table: [String: String] = {
        var t: [String: String] = [:]
        func row(_ kana: String, _ hangul: [String]) {
            for (k, h) in zip(kana, hangul) { t[String(k)] = h }
        }
        row("あいうえお", ["아", "이", "우", "에", "오"])
        row("ぁぃぅぇぉ", ["아", "이", "우", "에", "오"])
        row("かきくけこ", ["카", "키", "쿠", "케", "코"])
        row("がぎぐげご", ["가", "기", "구", "게", "고"])
        row("さしすせそ", ["사", "시", "스", "세", "소"])
        row("ざじずぜぞ", ["자", "지", "즈", "제", "조"])
        row("たちつてと", ["타", "치", "츠", "테", "토"])
        row("だぢづでど", ["다", "지", "즈", "데", "도"])
        row("なにぬねの", ["나", "니", "누", "네", "노"])
        row("はひふへほ", ["하", "히", "후", "헤", "호"])
        row("ばびぶべぼ", ["바", "비", "부", "베", "보"])
        row("ぱぴぷぺぽ", ["파", "피", "푸", "페", "포"])
        row("まみむめも", ["마", "미", "무", "메", "모"])
        row("やゆよ", ["야", "유", "요"])
        row("ゃゅょ", ["야", "유", "요"])
        row("らりるれろ", ["라", "리", "루", "레", "로"])
        row("わをゐゑゔ", ["와", "오", "이", "에", "부"])
        // 요음 (きゃ 캬 …)
        let youon: [(String, [String])] = [
            ("き", ["캬", "큐", "쿄"]), ("ぎ", ["갸", "규", "교"]), ("し", ["샤", "슈", "쇼"]), ("じ", ["자", "주", "조"]),
            ("ち", ["차", "추", "초"]), ("ぢ", ["자", "주", "조"]), ("に", ["냐", "뉴", "뇨"]), ("ひ", ["햐", "휴", "효"]),
            ("び", ["뱌", "뷰", "뵤"]), ("ぴ", ["퍄", "퓨", "표"]), ("み", ["먀", "뮤", "묘"]), ("り", ["랴", "류", "료"]),
        ]
        for (head, sounds) in youon {
            for (small, h) in zip(["ゃ", "ゅ", "ょ"], sounds) { t[head + small] = h }
        }
        // 외래어용 작은 모음 (ふぁ 파, てぃ 티 …)
        let extra: [String: String] = [
            "ふぁ": "파", "ふぃ": "피", "ふぇ": "페", "ふぉ": "포", "てぃ": "티", "でぃ": "디", "とぅ": "투", "どぅ": "두",
            "うぃ": "위", "うぇ": "웨", "うぉ": "워", "しぇ": "셰", "じぇ": "제", "ちぇ": "체", "ゔぁ": "바", "ゔぃ": "비",
        ]
        t.merge(extra) { _, new in new }
        return t
    }()
}
