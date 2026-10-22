package com.local.epobrowser.data

/** 영상 필터 (화질·길이·카테고리) — 사이트에 그대로 보냄 */
data class Filters(
    val quality: Quality = Quality.All,
    val minMinutes: Int = 0,
    val maxMinutes: Int = OPEN_MAX,
    val categories: List<String> = emptyList(),
) {
    val isDefault get() = this == Filters()

    companion object {
        const val OPEN_MAX = 61   // 61 = 1시간 이상
        const val MAX_CATEGORIES = 5

        /** 검색어를 사이트 주소용으로 (공백 → -) */
        fun slug(text: String): String =
            text.lowercase().split(Regex("[^\\p{L}\\p{N}-]+")).filter { it.isNotEmpty() }.joinToString("-")
                .let { java.net.URLEncoder.encode(it, "UTF-8").replace("%2D", "-") }
    }
}

/** 포르노스타 필터 (사이트 FILTERS와 같은 값, 길이는 cm) */
data class PornstarFilters(
    val inches: Boolean = false,
    val age: IntRange = 18..107,
    val height: IntRange = 109..203,
    val bust: IntRange = 25..168,
    val waist: IntRange = 35..166,
    val hips: IntRange = 25..173,
    val choices: Map<String, Set<String>> = emptyMap(),
) {
    val isDefault get() = copy(inches = false) == PornstarFilters()

    fun query(): List<Pair<String, String>> {
        val d = PornstarFilters()
        val out = mutableListOf<Pair<String, String>>()
        fun range(name: String, r: IntRange, def: IntRange) {
            if (r != def) { out += "${name}_from" to "${r.first}"; out += "${name}_to" to "${r.last}" }
        }
        range("age", age, d.age); range("height", height, d.height); range("bust", bust, d.bust)
        range("waist", waist, d.waist); range("hips", hips, d.hips)
        if (out.isNotEmpty()) out.add(0, "unit" to "cm")
        choices.toSortedMap().forEach { (name, values) -> values.sorted().forEach { out += "$name[]" to it } }
        return out
    }
}

/** 여러 개 고르는 포르노스타 항목 (컵·머리색·국가·인종·눈 색) */
data class ChoiceField(val name: String, val label: String, val options: List<Pair<String, String>>)
