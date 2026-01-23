import Foundation

/// 업데이트 체크 관련 사용자 설정
struct UpdatePreferences: Codable {
    /// 앱 시작 시 자동으로 업데이트 체크
    var autoCheckEnabled: Bool = true

    /// 마지막 업데이트 체크 일시
    var lastCheckDate: Date?

    /// 건너뛸 버전 (이 버전은 알림 표시 안 함)
    var skipVersion: String?

    // MARK: - UserDefaults 저장/로드

    private static let key = "UpdatePreferences"

    static func load() -> UpdatePreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let preferences = try? JSONDecoder().decode(UpdatePreferences.self, from: data) else {
            return UpdatePreferences()
        }
        return preferences
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: UpdatePreferences.key)
        }
    }
}
