import Foundation
import AppKit

/// Full Disk Access 권한을 관리하는 Manager 클래스
final class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()

    // MARK: - Published Properties
    @Published private(set) var hasFullDiskAccess: Bool = false

    // MARK: - Private Properties
    private let skipPromptKey = "MacViber.SkipFullDiskAccessPrompt"

    // MARK: - Initialization
    private init() {
        hasFullDiskAccess = checkFullDiskAccess()
    }

    // MARK: - Public Methods

    /// Full Disk Access 권한 확인
    func checkFullDiskAccess() -> Bool {
        let testPaths = [
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Preferences/com.apple.TimeMachine.plist"
        ]

        let fileManager = FileManager.default
        for path in testPaths {
            if fileManager.fileExists(atPath: path) &&
               fileManager.isReadableFile(atPath: path) {
                return true
            }
        }
        return false
    }

    /// 필요한 경우 Full Disk Access 권한 요청
    func requestFullDiskAccessIfNeeded() {
        hasFullDiskAccess = checkFullDiskAccess()

        if hasFullDiskAccess {
            Logger.shared.info("[FDA] Full Disk Access granted")
            return
        }

        // 사용자가 "더 이상 보지 않기"를 선택한 경우 스킵
        if UserDefaults.standard.bool(forKey: skipPromptKey) {
            Logger.shared.info("[FDA] User opted to skip prompt")
            return
        }

        showPermissionAlert()
    }

    /// 시스템 환경설정 열기
    func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// 프롬프트 스킵 설정 초기화
    func resetSkipPrompt() {
        UserDefaults.standard.removeObject(forKey: skipPromptKey)
    }

    // MARK: - Private Methods

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "전체 디스크 접근 권한 필요"
        alert.informativeText = """
        MacViber가 모든 폴더에 자유롭게 접근하려면 전체 디스크 접근 권한이 필요합니다.

        "설정 열기"를 클릭하여 시스템 환경설정에서 MacViber를 추가해주세요.
        """
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.cautionName)

        alert.addButton(withTitle: "설정 열기")
        alert.addButton(withTitle: "나중에")
        alert.addButton(withTitle: "다시 보지 않기")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            openSystemSettings()
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(true, forKey: skipPromptKey)
            Logger.shared.info("[FDA] User opted to not show prompt again")
        default:
            break
        }
    }
}
