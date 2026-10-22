package com.local.epobrowser.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.local.epobrowser.PlayerActivity
import com.local.epobrowser.net.Http

/** 재생 방법 */
enum class PlayerMode(val label: String) {
    App("앱 플레이어"),
    Site("사이트 플레이어"),
    External("다른 앱 (VLC·MX Player 등)"),
    Ask("매번 묻기"),
}

/** 재생할 영상 (목록 카드·최근 본 영상 공통) */
data class PlayRequest(val id: String, val title: String, val url: String, val embed: String, val fid: Int)

/** 앱 플레이어·사이트 플레이어는 재생 화면으로 */
fun openPlayer(context: Context, r: PlayRequest, site: Boolean) {
    context.startActivity(PlayerActivity.intent(context, r.id, r.title, r.url, r.embed, r.fid, site))
}

/**
 * 다른 영상 앱으로 열기
 * 다른 앱은 이 앱의 로그인 정보를 못 쓰니, 다운로드 링크를 따라가 알아낸 실제 파일 주소를 넘김
 */
fun openExternal(context: Context, fileUrl: String, title: String) {
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(Uri.parse(fileUrl), "video/*")
        putExtra("title", title)
        // MX Player 등은 이 값으로 요청 머리글을 붙여 줌
        putExtra("headers", arrayOf("User-Agent", Http.USER_AGENT, "Referer", Http.BASE + "/"))
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    try {
        context.startActivity(Intent.createChooser(intent, "재생할 앱 선택").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (e: ActivityNotFoundException) {
        Toast.makeText(context, "영상을 열 수 있는 앱이 없어요. VLC 같은 플레이어를 설치해 주세요.", Toast.LENGTH_LONG).show()
    }
}

/** "매번 묻기"일 때 뜨는 선택 창 */
@Composable
fun PlayerChooserDialog(vm: AppViewModel, context: Context, r: PlayRequest, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("어떻게 재생할까요?") },
        text = {
            Column {
                Text(r.title, maxLines = 2)
                listOf(PlayerMode.App, PlayerMode.Site, PlayerMode.External).forEach { m ->
                    OutlinedButton(onClick = { onDismiss(); vm.play(context, r, m) }, modifier = Modifier.fillMaxWidth()) { Text(m.label) }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("취소") } },
    )
}
