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
    @Published private(set) var characterScale: CGFloat
    @Published private(set) var isBubbleVisible = true

    var onSend: ((String) -> Void)?
    var onCharacterScaleChange: ((CGFloat) -> Void)?

    private let characterURL: URL
    private let petDirectory: URL
    private let defaults: UserDefaults
    private var bubbleDismissTask: Task<Void, Never>?
    private var isEditingMessage = false

    init(
        characterURL: URL? = nil,
        petDirectory: URL? = nil,
        defaults: UserDefaults = .standard
    ) {
        let resolvedCharacterURL = characterURL ?? Self.defaultCharacterURL
        let resolvedPetDirectory = petDirectory ?? Self.defaultPetDirectory
        self.characterURL = resolvedCharacterURL
        self.petDirectory = resolvedPetDirectory
        self.defaults = defaults
        displayedMessage = "오늘도 같이 있자 💛"
        let loadedPet = try? HatchPetPackage.load(from: resolvedPetDirectory)
        hatchPet = loadedPet
        characterImage = loadedPet == nil ? NSImage(contentsOf: resolvedCharacterURL) : nil
        let savedScale = defaults.object(forKey: Self.characterScaleKey) == nil
            ? 1
            : defaults.double(forKey: Self.characterScaleKey)
        characterScale = CGFloat(min(1.3, max(0.7, savedScale)))
    }

    func send(_ rawValue: String) {
        let message = MessageText.normalize(rawValue)
        guard !message.isEmpty else { return }
        displayedMessage = message
        showBubble()
        onSend?(message)
    }

    func receive(_ rawValue: String) {
        let message = MessageText.normalize(rawValue)
        guard !message.isEmpty else { return }
        displayedMessage = message
        showBubble()
    }

    func clearMessage() {
        displayedMessage = ""
        isBubbleVisible = false
        bubbleDismissTask?.cancel()
    }

    func resizeCharacter(by delta: Double) {
        let next = ((Double(characterScale) + delta) * 10).rounded() / 10
        setCharacterScale(CGFloat(next))
    }

    func setCharacterScale(_ scale: CGFloat) {
        characterScale = min(1.3, max(0.7, scale))
        defaults.set(Double(characterScale), forKey: Self.characterScaleKey)
        onCharacterScaleChange?(characterScale)
    }

    func resetCharacterSize() {
        setCharacterScale(1)
    }

    func showBubble() {
        isBubbleVisible = true
        scheduleBubbleDismissal()
    }

    func setMessageEditing(_ isEditing: Bool) {
        isEditingMessage = isEditing
        if isEditing {
            bubbleDismissTask?.cancel()
            isBubbleVisible = true
        } else {
            scheduleBubbleDismissal()
        }
    }

    private func scheduleBubbleDismissal() {
        bubbleDismissTask?.cancel()
        guard !isEditingMessage else { return }

        bubbleDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.displayedMessage = ""
            self?.isBubbleVisible = false
        }
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

    private static let characterScaleKey = "characterScale"
}
