package com.local.epobrowser.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Accent = Color(0xFF087F74)

/** themeMode: 0 = 시스템 설정, 1 = 라이트, 2 = 다크 */
@Composable
fun AppTheme(themeMode: Int, content: @Composable () -> Unit) {
    val dark = when (themeMode) { 1 -> false; 2 -> true; else -> isSystemInDarkTheme() }
    val colors = if (dark) darkColorScheme(
        primary = Color(0xFF78D6C5), onPrimary = Color(0xFF00382F),
        primaryContainer = Color(0xFF005046), onPrimaryContainer = Color(0xFF9AF2E1),
        secondary = Color(0xFFA8CDC5),
        secondaryContainer = Color(0xFF254A40), onSecondaryContainer = Color(0xFFC8EEDF),
        surfaceVariant = Color(0xFF283A32), outline = Color(0xFF82968C), background = Color(0xFF101615),
        surface = Color(0xFF151D1B), onSurface = Color(0xFFE0E5E1),
        onSurfaceVariant = Color(0xFFBACAC4),
    )
    else lightColorScheme(
        primary = Accent, onPrimary = Color.White,
        primaryContainer = Color(0xFFD0EEE6), onPrimaryContainer = Color(0xFF002D26),
        secondary = Color(0xFF48675F),
        secondaryContainer = Color(0xFFE0F1EB), onSecondaryContainer = Color(0xFF174C3F),
        surfaceVariant = Color(0xFFE7EEE8), outline = Color(0xFF71857B), background = Color(0xFFF5F7F5),
        surface = Color(0xFFFCFDFB), onSurface = Color(0xFF17231F),
        onSurfaceVariant = Color(0xFF4E6059),
    )
    MaterialTheme(colorScheme = colors, content = content)
}
