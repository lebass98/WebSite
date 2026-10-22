package com.local.epobrowser.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Accent = Color(0xFFE53935)
val Highlight = Color(0xFFFFA000)

/** themeMode: 0 = 시스템 설정, 1 = 라이트, 2 = 다크 */
@Composable
fun AppTheme(themeMode: Int, content: @Composable () -> Unit) {
    val dark = when (themeMode) { 1 -> false; 2 -> true; else -> isSystemInDarkTheme() }
    val colors = if (dark) darkColorScheme(primary = Accent, secondary = Highlight)
    else lightColorScheme(primary = Accent, secondary = Highlight)
    MaterialTheme(colorScheme = colors, content = content)
}
