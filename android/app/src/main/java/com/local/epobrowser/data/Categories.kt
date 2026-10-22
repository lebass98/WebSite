package com.local.epobrowser.data

/** 사이트 주요 카테고리 */
data class SiteCategory(val slug: String, val name: String) {
    val path get() = "/cat/$slug/"

    companion object {
        val all: List<SiteCategory> = listOf(
            "4k-porn" to "4K Porn", "hd-1080p" to "HD 1080p", "60fps" to "60 FPS", "vr-porn" to "VR Porn",
            "japanese" to "Japanese", "anal" to "Anal", "pov-porn" to "POV", "indian" to "Indian", "milf" to "MILF",
            "hentai" to "Hentai", "bbw" to "BBW", "pinay" to "Pinay", "amateur" to "Amateur", "asian" to "Asian",
            "asmr" to "ASMR", "bdsm" to "BDSM", "big-ass" to "Big Ass", "big-dick" to "Big Dick", "big-tits" to "Big Tits",
            "cosplay" to "Cosplay", "creampie" to "Creampie", "cuckold" to "Cuckold", "ebony" to "Ebony",
            "footjob" to "Footjob", "group-sex" to "Group Sex", "hardcore" to "Hardcore", "homemade" to "Homemade",
            "indonesia" to "Indonesia", "interracial" to "Interracial", "latina" to "Latina", "massage" to "Massage",
            "mature" to "Mature", "orgy" to "Orgy", "redhead" to "Redhead", "stepmom" to "Stepmom",
            "stepsister" to "Stepsister", "teens" to "Teen", "threesome" to "Threesome", "vintage" to "Vintage",
            "gay" to "Gay", "lesbians" to "Lesbian", "shemale" to "Transgender", "hd-sex" to "HD Sex", "ai" to "AI",
            "bisexual" to "Bisexual", "blonde" to "Blonde", "blowjob" to "Blowjob", "bondage" to "Bondage",
            "brunette" to "Brunette", "bukkake" to "Bukkake", "casting" to "Casting", "compilation" to "Compilation",
            "cumshot" to "Cumshot", "double-penetration" to "Double Penetration", "fat" to "Fat", "fetish" to "Fetish",
            "fisting" to "Fisting", "for-women" to "For Women", "gloryhole" to "Gloryhole", "handjob" to "Handjob",
            "hotel" to "Hotel", "hotwife" to "Hotwife", "housewives" to "Housewives", "hq-porn" to "HQ Porn",
            "lingerie" to "Lingerie", "masturbation" to "Masturbation", "nurse" to "Nurses", "office" to "Office",
            "old-man" to "Older Men", "outdoor" to "Outdoor", "pawg" to "PAWG", "petite" to "Petite",
            "pornstar" to "Pornstar", "pregnant" to "Pregnant", "public" to "Public", "small-tits" to "Small Tits",
            "squirt" to "Squirt", "striptease" to "Striptease", "students" to "Students", "swingers" to "Swinger",
            "toys" to "Toys", "uniform" to "Uniform", "webcam" to "Webcam", "uncategorized" to "Uncategorized",
        ).map { SiteCategory(it.first, it.second) }.sortedBy { it.name.lowercase() }
    }
}
