import Foundation

struct PetProgress: Equatable {
    enum Activity { case chat, drawing, emoji
        var experience: Int { switch self { case .chat: 10; case .drawing: 25; case .emoji: 5 } }
    }
    static let maximumLevel = 100
    static let maximumExperience = threshold(for: maximumLevel)
    private(set) var experience: Int
    init(experience: Int = 0) { self.experience = min(Self.maximumExperience, max(0, experience)) }
    static func threshold(for level: Int) -> Int {
        let previous = min(maximumLevel, max(1, level)) - 1
        return 100 * previous + 25 * previous * (previous - 1)
    }
    var level: Int {
        (1...Self.maximumLevel).last { experience >= Self.threshold(for: $0) } ?? 1
    }
    var currentExperience: Int { experience - Self.threshold(for: level) }
    var requiredExperience: Int { level == Self.maximumLevel ? 0 : Self.threshold(for: level + 1) - Self.threshold(for: level) }
    var fraction: Double { requiredExperience == 0 ? 1 : Double(currentExperience) / Double(requiredExperience) }
    mutating func award(_ activity: Activity) {
        experience = min(Self.maximumExperience, experience + activity.experience)
    }
    static func isEmojiOnly(_ value: String) -> Bool {
        let characters = value.filter { !$0.isWhitespace }
        return !characters.isEmpty && characters.allSatisfy { character in
            character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
                || character.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x7F }
                || (character.unicodeScalars.contains { $0.value == 0xFE0F || $0.value == 0x20E3 }
                    && character.unicodeScalars.contains { $0.properties.isEmoji })
        }
    }
}

enum Pet3DAction: String, CaseIterable, Identifiable {
    case idle, runningRight, runningLeft, waving, jumping, failed, waiting, running, review, lookAround
    case playStar, hugHeart, blowBubbles, restMoon, playBall, paint, playMusic, fish, celebrateCrown, castSpell, celebrate100
    static let basicActions: [Self] = [.idle, .runningRight, .runningLeft, .waving, .jumping, .failed, .waiting, .running, .review, .lookAround]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .idle: "기본 동작"
        case .runningRight: "오른쪽 달리기"
        case .runningLeft: "왼쪽 달리기"
        case .waving: "손 흔들기"
        case .jumping: "점프"
        case .failed: "시무룩"
        case .waiting: "기다리기"
        case .running: "제자리 달리기"
        case .review: "편지 읽기"
        case .lookAround: "둘러보기"
        case .playStar: "별 돌리기"
        case .hugHeart: "하트 안기"
        case .blowBubbles: "비눗방울 불기"
        case .restMoon: "달과 쉬기"
        case .playBall: "공놀이"
        case .paint: "그림 그리기"
        case .playMusic: "음악 연주"
        case .fish: "낚시"
        case .celebrateCrown: "왕관 인사"
        case .castSpell: "마법 부리기"
        case .celebrate100: "100LV 축하"
        }
    }
}

struct PetLevelReward: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case star, heart, bubbles, moon, ball, brush, music, fishing, crown, wand, trophy
        var title: String {
            switch self {
            case .star: "별 장난감"
            case .heart: "하트 인형"
            case .bubbles: "비눗방울 막대"
            case .moon: "초승달"
            case .ball: "공"
            case .brush: "그림 붓"
            case .music: "음악 방울"
            case .fishing: "낚싯대"
            case .crown: "왕관"
            case .wand: "마법 지팡이"
            case .trophy: "100LV 트로피"
            }
        }
        var action: Pet3DAction {
            switch self {
            case .star: .playStar
            case .heart: .hugHeart
            case .bubbles: .blowBubbles
            case .moon: .restMoon
            case .ball: .playBall
            case .brush: .paint
            case .music: .playMusic
            case .fishing: .fish
            case .crown: .celebrateCrown
            case .wand: .castSpell
            case .trophy: .celebrate100
            }
        }
    }
    let level: Int
    let kind: Kind
    var id: Int { level }
    var variant: Int { (level - 2) / 10 + 1 }
    var title: String { "LV \(level) · \(kind.title) \(variant)단계" }
    var action: Pet3DAction { kind.action }
    static func reward(at level: Int) -> Self? {
        guard (2...100).contains(level) else { return nil }
        if level == 100 { return Self(level: level, kind: .trophy) }
        let first: [Kind] = [.star, .heart, .bubbles, .moon, .ball, .brush, .music, .fishing, .crown, .wand]
        return Self(level: level, kind: first[(level - 2) % first.count])
    }
    var javascript: String {
        let data = try? JSONSerialization.data(withJSONObject: ["level": level, "kind": kind.rawValue,
                                                               "variant": variant, "action": action.rawValue])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }
}
