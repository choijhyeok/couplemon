import Foundation

struct HatchPetManifest: Codable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let spriteVersionNumber: Int
    let spritesheetPath: String
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
            "지원하지 않는 펫 버전입니다: \(version). v2 펫이 필요합니다."
        case .unsafeSpritesheetPath:
            "pet.json의 spritesheetPath가 올바르지 않습니다."
        case let .invalidAtlasDimensions(width, height):
            "스프라이트 크기가 \(width)×\(height)입니다. v2 규격 1536×2288이 필요합니다."
        case .unreadableAtlas:
            "PNG 또는 WebP 스프라이트를 읽을 수 없습니다."
        }
    }
}

enum HatchPetContract {
    static let spriteVersion = 2
    static let columns = 8
    static let rows = 11
    static let cellWidth = 192
    static let cellHeight = 208
    static let atlasWidth = columns * cellWidth
    static let atlasHeight = rows * cellHeight
    static let idleDurations: [TimeInterval] = [0.280, 0.110, 0.110, 0.140, 0.140, 0.320]

    static func validateManifest(_ manifest: HatchPetManifest) throws {
        guard !manifest.id.isEmpty, !manifest.displayName.isEmpty else {
            throw HatchPetError.invalidManifest
        }
        guard manifest.spriteVersionNumber == spriteVersion else {
            throw HatchPetError.unsupportedVersion(manifest.spriteVersionNumber)
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
        guard width == atlasWidth, height == atlasHeight else {
            throw HatchPetError.invalidAtlasDimensions(width: width, height: height)
        }
    }

    static func idleFrameIndex(elapsed: TimeInterval) -> Int {
        let totalDuration = idleDurations.reduce(0, +)
        let position = max(0, elapsed).truncatingRemainder(dividingBy: totalDuration)
        var boundary: TimeInterval = 0

        for (index, duration) in idleDurations.enumerated() {
            boundary += duration
            if position < boundary { return index }
        }
        return 0
    }
}
