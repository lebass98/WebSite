package com.local.epobrowser

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import com.local.epobrowser.ui.AppTheme
import com.local.epobrowser.ui.AppViewModel
import com.local.epobrowser.ui.RootScreen

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // 앱을 켜자마자 저장된 정보로 자동 로그인
        if (savedInstanceState == null) vm.login()
        setContent {
            AppTheme(vm.themeMode) { RootScreen(vm) }
        }
    }
}
