import SwiftUI
import Combine

final class LoginForm: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var saved = false
}

/// 설정 창 (⌘,) — 로그인 정보 저장
struct SettingsView: View {
    @StateObject private var form = LoginForm()
    @ObservedObject private var session = SiteSession.shared
    @ObservedObject private var backup = Backup.shared
    @ObservedObject private var appearance = AppearanceSetting.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                LibraryHeader(title: "설정", subtitle: "화면, 계정과 라이브러리 백업", icon: "gearshape")
            }
            Section("화면") {
                Picker("화면 모드", selection: $appearance.mode) {
                    ForEach(AppearanceSetting.Mode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
            }
            Section {
                TextField("아이디 또는 이메일", text: $form.username)
                    .disabled(session.status == .loggingIn)
                SecureField("비밀번호", text: $form.password)
                    .disabled(session.status == .loggingIn)
            } header: {
                Text("로그인 정보")
            } footer: {
                Text("macOS 키체인에 안전하게 저장되고, 앱을 켤 때마다 자동으로 로그인해요.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("저장하고 로그인") {
                    Keychain.save(username: form.username.trimmingCharacters(in: .whitespaces),
                                  password: form.password)
                    form.saved = true
                    session.login()
                }
                .buttonStyle(.borderedProminent)
                .disabled(form.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || form.password.isEmpty || session.status == .loggingIn)

                Button("저장된 정보 지우기", role: .destructive) {
                    Keychain.delete()
                    form.username = ""
                    form.password = ""
                    session.logout()
                }
            }

            Section("상태") {
                LoginStatusText(status: session.status)
                HStack {
                    Button("다시 로그인") { session.login() }
                        .disabled(session.status == .loggingIn || Keychain.load() == nil)
                    Button("로그인 창 열기") { openWindow(id: "login") }
                        .help("자동 로그인이 안 될 때 사이트 화면에서 직접 로그인")
                }
            }

            UpdateSettingsSection()

            Section {
                LabeledContent("백업 위치", value: "홈 폴더 › \(Backup.folder.lastPathComponent)")
                LabeledContent("마지막 백업",
                               value: backup.lastBackup?.formatted(date: .abbreviated, time: .standard) ?? "아직 없음")
                if let note = backup.restoreNote {
                    Label(note, systemImage: "arrow.uturn.backward.circle")
                        .foregroundStyle(.green)
                }
                HStack {
                    Button("지금 백업") { backup.backupNow() }
                    Button("백업 폴더 열기") { NSWorkspace.shared.open(Backup.folder) }
                }
            } header: {
                Text("데이터 백업")
            } footer: {
                Text("최근 본 영상, 4K 주소 모음, 미리 만든 자막, 화면 설정을 자동으로 따로 복사해 둬요. 앱 데이터가 지워져도 다음에 앱을 켤 때 자동으로 되살려요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 740)
        .onAppear {
            if let cred = Keychain.load() {
                form.username = cred.username
                form.password = cred.password
            }
        }
    }
}

struct LoginStatusText: View {
    let status: SiteSession.Status

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(status.label, systemImage: icon).foregroundStyle(color)
            if case .failed(let message) = status {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch status {
        case .loggedIn: "person.crop.circle.badge.checkmark"
        case .loggingIn: "arrow.triangle.2.circlepath"
        case .noCredentials, .loggedOut: "person.crop.circle"
        case .failed: "person.crop.circle.badge.exclamationmark"
        }
    }

    private var color: Color {
        switch status {
        case .loggedIn: .green
        case .failed: .orange
        default: .secondary
        }
    }
}

/// 자동 로그인이 막힐 때 쓰는, 화면에 보이는 로그인 창
struct LoginWindowView: View {
    var body: some View {
        EmbedWebView(url: SiteSession.loginPage, allowNavigation: true)
            .frame(minWidth: 520, minHeight: 600)
            .onDisappear { SiteSession.shared.refreshStatus() }
    }
}
