import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    enum CharacterError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            "이미지 파일을 읽을 수 없습니다."
        }
    }

    @Published private(set) var displayedMessage: String
    @Published private(set) var characterImage: NSImage?

    private let characterURL: URL

    init(characterURL: URL? = nil) {
        let resolvedCharacterURL = characterURL ?? Self.defaultCharacterURL
        self.characterURL = resolvedCharacterURL
        displayedMessage = "오늘도 같이 있자 💛"
        characterImage = NSImage(contentsOf: resolvedCharacterURL)
    }

    func send(_ rawValue: String) {
        let message = MessageText.normalize(rawValue)
        guard !message.isEmpty else { return }
        displayedMessage = message
    }

    func clearMessage() {
        displayedMessage = ""
    }

    func selectCharacter(from sourceURL: URL) throws {
        guard
            let image = NSImage(contentsOf: sourceURL),
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CharacterError.invalidImage
        }

        try FileManager.default.createDirectory(
            at: characterURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: characterURL, options: .atomic)
        characterImage = NSImage(data: pngData)
    }

    func resetCharacter() {
        try? FileManager.default.removeItem(at: characterURL)
        characterImage = nil
    }

    private static var defaultCharacterURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleMon", isDirectory: true)
            .appendingPathComponent("character.png")
    }
}
