import SwiftUI
import MarkdownUI

/// 업데이트 알림 시트
struct UpdateAlertView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            headerView

            Divider()

            // 콘텐츠
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 버전 정보
                    versionInfoView

                    // 릴리스 노트
                    if let notes = updateChecker.releaseNotes, !notes.isEmpty {
                        releaseNotesView(notes)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 300)

            Divider()

            // 버튼
            buttonsView
        }
        .frame(width: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 12) {
            // 앱 아이콘
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("A new version of MacViber is available!")
                    .font(.headline)

                Text("MacViber \(updateChecker.latestVersion ?? "") is now available.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private var versionInfoView: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Version")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(updateChecker.currentVersion)
                    .font(.system(.body, design: .monospaced))
            }

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("New Version")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(updateChecker.latestVersion ?? "")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func releaseNotesView(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Release Notes")
                .font(.headline)

            Markdown(notes)
                .markdownTextStyle {
                    FontSize(13)
                }
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
        }
    }

    private var buttonsView: some View {
        HStack(spacing: 12) {
            // 자동 체크 토글
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updateChecker.preferences.autoCheckEnabled },
                set: { updateChecker.preferences.autoCheckEnabled = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)

            Spacer()

            // Skip This Version
            Button("Skip This Version") {
                updateChecker.skipThisVersion()
            }
            .buttonStyle(.borderless)

            // Later
            Button("Later") {
                updateChecker.remindLater()
            }
            .buttonStyle(.bordered)

            // Download & Install
            Button(action: {
                Task {
                    try? await updateChecker.downloadAndInstall()
                }
            }) {
                if updateChecker.isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text("Downloading...")
                } else {
                    Text("Download & Install")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(updateChecker.isDownloading)
        }
        .padding(20)
    }
}

/// 최신 버전 알림
struct UpToDateAlertView: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("You're up to date!")
                .font(.headline)

            Text("MacViber \(updateChecker.currentVersion) is the latest version.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("OK") {
                updateChecker.showUpToDateAlert = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(width: 300)
    }
}

#Preview("Update Available") {
    UpdateAlertView(updateChecker: UpdateChecker.shared)
}

#Preview("Up to Date") {
    UpToDateAlertView(updateChecker: UpdateChecker.shared)
}
