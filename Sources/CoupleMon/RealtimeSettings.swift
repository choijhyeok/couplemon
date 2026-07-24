import Foundation

struct RealtimeSettings: Codable, Equatable {
    enum SettingsError: LocalizedError {
        case invalidProjectURL
        case invalidPublishableKey
        case invalidRoomCode

        var errorDescription: String? {
            switch self {
            case .invalidProjectURL:
                "Supabase Project URL은 https 주소여야 합니다."
            case .invalidPublishableKey:
                "sb_publishable_ 로 시작하는 Publishable key를 입력하세요."
            case .invalidRoomCode:
                "연결 코드는 영문 대문자와 숫자 16~32자여야 합니다."
            }
        }
    }

    let projectURL: String
    let publishableKey: String
    let roomCode: String

    private static let defaultsKey = "realtimeSettings"
    private static let roomAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    var normalizedRoomCode: String {
        let allowed = Set(Self.roomAlphabet)
        return roomCode.uppercased().filter { allowed.contains($0) }
    }

    func validated() throws -> RealtimeSettings {
        let urlValue = projectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyValue = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let codeValue = normalizedRoomCode

        guard
            let url = URL(string: urlValue),
            url.scheme == "https",
            url.host != nil
        else {
            throw SettingsError.invalidProjectURL
        }
        guard keyValue.hasPrefix("sb_publishable_") else {
            throw SettingsError.invalidPublishableKey
        }
        guard (16...32).contains(codeValue.count) else {
            throw SettingsError.invalidRoomCode
        }

        return RealtimeSettings(
            projectURL: urlValue,
            publishableKey: keyValue,
            roomCode: codeValue
        )
    }

    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> RealtimeSettings? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(RealtimeSettings.self, from: data)
    }

    static func makeRoomCode() -> String {
        String((0..<16).map { _ in roomAlphabet.randomElement()! })
    }
}

enum CoupleRealtimeState: Equatable {
    case notConfigured
    case connecting
    case connected
    case failed(String)

    var menuTitle: String {
        switch self {
        case .notConfigured:
            "실시간: 설정 안 됨"
        case .connecting:
            "실시간: 연결 중…"
        case .connected:
            "실시간: 연결됨"
        case .failed:
            "실시간: 연결 실패"
        }
    }
}
