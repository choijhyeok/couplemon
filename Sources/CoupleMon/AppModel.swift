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
    @Published private(set) var hatchPet: HatchPet?

    private let characterURL: URL
    private let petDirectory: URL

    init(characterURL: URL? = nil, petDirectory: URL? = nil) {
        let resolvedCharacterURL = characterURL ?? Self.defaultCharacterURL
        let resolvedPetDirectory = petDirectory ?? Self.defaultPetDirectory
        self.characterURL = resolvedCharacterURL
        self.petDirectory = resolvedPetDirectory
        displayedMessage = "오늘도 같이 있자 💛"
        hatchPet = try? HatchPetPackage.load(from: resolvedPetDirectory)
        characterImage = hatchPet == nil ? NSImage(contentsOf: resolvedCharacterURL) : nil
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
        if FileManager.default.fileExists(atPath: petDirectory.path) {
            try FileManager.default.removeItem(at: petDirectory)
        }
        characterImage = NSImage(data: pngData)
        hatchPet = nil
    }

    func selectHatchPet(from sourceDirectory: URL) throws {
        let sourcePet = try HatchPetPackage.load(from: sourceDirectory)
        let parentDirectory = petDirectory.deletingLastPathComponent()
        let stagingDirectory = parentDirectory.appendingPathComponent(".pet-\(UUID().uuidString)")
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        try fileManager.copyItem(
            at: sourceDirectory.appendingPathComponent("pet.json"),
            to: stagingDirectory.appendingPathComponent("pet.json")
        )
        try fileManager.copyItem(
            at: sourceDirectory.appendingPathComponent(sourcePet.manifest.spritesheetPath),
            to: stagingDirectory.appendingPathComponent(sourcePet.manifest.spritesheetPath)
        )
        let installedPet = try HatchPetPackage.load(from: stagingDirectory)

        let backupDirectory = parentDirectory.appendingPathComponent(".pet-backup-\(UUID().uuidString)")
        let hadExistingPet = fileManager.fileExists(atPath: petDirectory.path)
        if hadExistingPet {
            try fileManager.moveItem(at: petDirectory, to: backupDirectory)
        }

        do {
            try fileManager.moveItem(at: stagingDirectory, to: petDirectory)
        } catch {
            if hadExistingPet { try? fileManager.moveItem(at: backupDirectory, to: petDirectory) }
            throw error
        }
        if hadExistingPet { try? fileManager.removeItem(at: backupDirectory) }

        hatchPet = installedPet
        characterImage = nil
        try? fileManager.removeItem(at: characterURL)
    }

    func resetCharacter() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: characterURL.path) {
            try fileManager.removeItem(at: characterURL)
        }
        if fileManager.fileExists(atPath: petDirectory.path) {
            try fileManager.removeItem(at: petDirectory)
        }
        characterImage = nil
        hatchPet = nil
    }

    private static var defaultCharacterURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleMon", isDirectory: true)
            .appendingPathComponent("character.png")
    }

    private static var defaultPetDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleMon", isDirectory: true)
            .appendingPathComponent("pet", isDirectory: true)
    }
}
