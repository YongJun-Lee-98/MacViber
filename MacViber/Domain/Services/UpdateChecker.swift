import Foundation
import AppKit

/// 업데이트 체크 결과
enum UpdateResult {
    case available(version: String, notes: String?, downloadURL: URL)
    case upToDate
    case error(Error)
}

/// 업데이트 관련 에러
enum UpdateError: LocalizedError {
    case noDownloadURL
    case networkError(Error)
    case invalidResponse
    case downloadFailed(Error)
    case fileOperationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noDownloadURL:
            return "다운로드 URL을 찾을 수 없습니다."
        case .networkError(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .invalidResponse:
            return "잘못된 응답입니다."
        case .downloadFailed(let error):
            return "다운로드 실패: \(error.localizedDescription)"
        case .fileOperationFailed(let error):
            return "파일 작업 실패: \(error.localizedDescription)"
        }
    }
}

/// GitHub Releases API 응답 모델
struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

/// GitHub Releases 기반 업데이트 체커
@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    // MARK: - Published Properties

    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadURL: URL?
    @Published var isChecking: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var showUpdateSheet: Bool = false
    @Published var showUpToDateAlert: Bool = false

    // MARK: - Properties

    private let repoOwner = "YongJun-Lee-98"
    private let repoName = "MacViber"

    var preferences: UpdatePreferences {
        didSet {
            preferences.save()
        }
    }

    /// 현재 앱 버전
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Initialization

    private init() {
        self.preferences = UpdatePreferences.load()
    }

    // MARK: - Public Methods

    /// 업데이트 체크 (수동)
    func checkForUpdatesManually() async {
        let result = await checkForUpdates()

        switch result {
        case .available:
            showUpdateSheet = true
        case .upToDate:
            showUpToDateAlert = true
        case .error(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// 업데이트 체크 (자동 - 앱 시작 시)
    func checkForUpdatesAutomatically() async {
        guard preferences.autoCheckEnabled else { return }

        let result = await checkForUpdates()

        switch result {
        case .available(let version, _, _):
            // skipVersion과 같으면 표시하지 않음
            if preferences.skipVersion != version {
                showUpdateSheet = true
            }
        case .upToDate, .error:
            // 자동 체크에서는 조용히 넘어감
            break
        }
    }

    /// 업데이트 체크
    func checkForUpdates() async -> UpdateResult {
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            return .error(UpdateError.invalidResponse)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .error(UpdateError.invalidResponse)
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            // 버전 비교
            let latestVersionString = release.tagName.replacingOccurrences(of: "v", with: "")

            if isNewerVersion(latestVersionString, than: currentVersion) {
                // DMG 에셋 찾기
                let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }

                if let dmgAsset = dmgAsset,
                   let dmgURL = URL(string: dmgAsset.browserDownloadUrl) {
                    self.updateAvailable = true
                    self.latestVersion = latestVersionString
                    self.releaseNotes = release.body
                    self.downloadURL = dmgURL

                    // 마지막 체크 일시 업데이트
                    preferences.lastCheckDate = Date()

                    return .available(version: latestVersionString, notes: release.body, downloadURL: dmgURL)
                }
            }

            self.updateAvailable = false
            preferences.lastCheckDate = Date()
            return .upToDate

        } catch {
            return .error(UpdateError.networkError(error))
        }
    }

    /// DMG 다운로드 및 열기
    func downloadAndInstall() async throws {
        guard let url = downloadURL else {
            throw UpdateError.noDownloadURL
        }

        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        do {
            // ~/Downloads/ 폴더에 저장
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let fileName = "MacViber-v\(latestVersion ?? "latest").dmg"
            let destinationURL = downloadsURL.appendingPathComponent(fileName)

            // 기존 파일이 있으면 삭제
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            // 다운로드
            let (tempURL, _) = try await URLSession.shared.download(from: url)

            // 파일 이동
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            // Finder에서 DMG 열기
            NSWorkspace.shared.open(destinationURL)

            // 업데이트 시트 닫기
            showUpdateSheet = false

        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.downloadFailed(error)
        }
    }

    /// 이 버전 건너뛰기
    func skipThisVersion() {
        if let version = latestVersion {
            preferences.skipVersion = version
        }
        showUpdateSheet = false
    }

    /// 나중에
    func remindLater() {
        showUpdateSheet = false
    }

    // MARK: - Version Comparison

    /// 버전 비교 (Semantic Versioning)
    /// - Returns: latest가 current보다 높으면 true
    func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        // 배열 길이를 맞추기 위해 0으로 패딩
        let maxLength = max(latestComponents.count, currentComponents.count)
        var latestPadded = latestComponents
        var currentPadded = currentComponents

        while latestPadded.count < maxLength { latestPadded.append(0) }
        while currentPadded.count < maxLength { currentPadded.append(0) }

        // 버전 비교
        for i in 0..<maxLength {
            if latestPadded[i] > currentPadded[i] {
                return true
            } else if latestPadded[i] < currentPadded[i] {
                return false
            }
        }

        return false // 같은 버전
    }
}
