import Foundation

struct HatchPetManifest: Codable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let spriteVersionNumber: Int?
    let spritesheetPath: String

    var spriteVersion: Int { spriteVersionNumber ?? 1 }
}

enum HatchPetError: LocalizedError {
    case invalidManifest
    case unsupportedVersion(Int)
    case unsafeSpritesheetPath
    case invalidAtlasDimensions(width: Int, height: Int)
    case unreadableAtlas

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            "유효한 hatch-pet pet.json이 아닙니다."
        case let .unsupportedVersion(version):
            "지원하지 않는 펫 버전입니다: \(version). v1 또는 v2 펫이 필요합니다."
        case .unsafeSpritesheetPath:
            "pet.json의 spritesheetPath가 올바르지 않습니다."
        case let .invalidAtlasDimensions(width, height):
            "스프라이트 크기가 \(width)×\(height)입니다. v1 1536×1872 또는 v2 1536×2288이 필요합니다."
        case .unreadableAtlas:
            "PNG 또는 WebP 스프라이트를 읽을 수 없습니다."
        }
    }
}

enum HatchPetContract {
    enum Animation: Int, CaseIterable {
        case idle
        case runningRight
        case runningLeft
        case waving
        case jumping
        case failed
        case waiting
        case running
        case review
        case lookAround

        var frameCount: Int {
            switch self {
            case .idle, .waiting, .running, .review: 6
            case .runningRight, .runningLeft, .failed: 8
            case .waving: 4
            case .jumping: 5
            case .lookAround: 16
            }
        }

        var durations: [TimeInterval] {
            switch self {
            case .idle: idleDurations
            case .runningRight, .runningLeft: Array(repeating: 0.120, count: 7) + [0.220]
            case .waving: Array(repeating: 0.140, count: 3) + [0.280]
            case .jumping: Array(repeating: 0.140, count: 4) + [0.280]
            case .failed: Array(repeating: 0.140, count: 7) + [0.240]
            case .waiting: Array(repeating: 0.150, count: 5) + [0.260]
            case .running: Array(repeating: 0.120, count: 5) + [0.220]
            case .review: Array(repeating: 0.150, count: 5) + [0.280]
            case .lookAround: Array(repeating: 0.120, count: 16)
            }
        }

        var duration: TimeInterval { durations.reduce(0, +) }
    }

    static let spriteVersion = 2
    static let columns = 8
    static let standardRows = 9
    static let extendedRows = 11
    static let cellWidth = 192
    static let cellHeight = 208
    static let atlasWidth = columns * cellWidth
    static let idleDurations: [TimeInterval] = [0.280, 0.110, 0.110, 0.140, 0.140, 0.320]
    static let chatAnimations = Animation.allCases.filter { $0 != .idle }

    static func validateManifest(_ manifest: HatchPetManifest) throws {
        guard !manifest.id.isEmpty, !manifest.displayName.isEmpty else {
            throw HatchPetError.invalidManifest
        }
        guard manifest.spriteVersion == 1 || manifest.spriteVersion == spriteVersion else {
            throw HatchPetError.unsupportedVersion(manifest.spriteVersion)
        }

        let path = manifest.spritesheetPath
        let fileExtension = (path as NSString).pathExtension.lowercased()
        guard
            !path.isEmpty,
            !(path as NSString).isAbsolutePath,
            path == (path as NSString).lastPathComponent,
            fileExtension == "png" || fileExtension == "webp"
        else {
            throw HatchPetError.unsafeSpritesheetPath
        }
    }

    static func validate(_ manifest: HatchPetManifest, atlasWidth width: Int, atlasHeight height: Int) throws {
        try validateManifest(manifest)
        let expectedHeight = (manifest.spriteVersion == 1 ? standardRows : extendedRows) * cellHeight
        guard width == atlasWidth, height == expectedHeight else {
            throw HatchPetError.invalidAtlasDimensions(width: width, height: height)
        }
    }

    static func idleFrameIndex(elapsed: TimeInterval) -> Int {
        frameIndex(elapsed: elapsed, durations: idleDurations)
    }

    static func frameIndex(elapsed: TimeInterval, animation: Animation) -> Int {
        frameIndex(elapsed: elapsed, durations: animation.durations)
    }

    static func chatAnimationChoices(
        available: Set<Animation>,
        excluding previous: Animation?
    ) -> [Animation] {
        chatAnimations.filter { available.contains($0) && $0 != previous }
    }

    private static func frameIndex(elapsed: TimeInterval, durations: [TimeInterval]) -> Int {
        let totalDuration = durations.reduce(0, +)
        let position = max(0, elapsed).truncatingRemainder(dividingBy: totalDuration)
        var boundary: TimeInterval = 0

        for (index, duration) in durations.enumerated() {
            boundary += duration
            if position < boundary { return index }
        }
        return 0
    }
}
