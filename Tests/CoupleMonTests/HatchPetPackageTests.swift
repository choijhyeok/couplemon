import AppKit
import XCTest
@testable import CoupleMon

final class HatchPetPackageTests: XCTestCase {
    private var bundledDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/DefaultPet")
    }

    @MainActor
    func testPetSwitchingInPrivateDirectoryAndAfterRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "HatchPetPackageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: name) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let destination = root.appendingPathComponent("pet", isDirectory: true)
        let model = AppModel(characterURL: root.appendingPathComponent("character.png"), petDirectory: destination,
                             bundledPetDirectory: bundledDirectory, defaults: defaults)
        try model.selectHatchPet(from: bundledDirectory)
        try model.selectHatchPet(from: destination)
        XCTAssertEqual(model.hatchPet?.manifest.id, "kt-ribbon-pet")
        let restored = AppModel(characterURL: root.appendingPathComponent("character.png"), petDirectory: destination,
                                bundledPetDirectory: nil, defaults: defaults)
        XCTAssertEqual(restored.hatchPet?.manifest.id, "kt-ribbon-pet")
        XCTAssertNotNil(restored.hatchPet?.animations[.waving]?.first?.tiffRepresentation)
    }

    func testDecodedFramesSurviveMovingAndDeletingSourceFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: bundledDirectory, to: root)
        let pet = try HatchPetPackage.load(from: root)
        try FileManager.default.removeItem(at: root)
        XCTAssertEqual(pet.animations[.idle]?.count, 6)
        XCTAssertNotNil(pet.animations[.idle]?.first?.tiffRepresentation)
    }

    @MainActor
    func testFolderURLWithoutTrailingSlashLoadsAndImportsLikeDirectoryURL() throws {
        // NSOpenPanel can return a folder URL without a trailing directory separator.
        let withSlash = URL(fileURLWithPath: bundledDirectory.path, isDirectory: true)
        let withoutSlash = URL(fileURLWithPath: bundledDirectory.path, isDirectory: false)
        XCTAssertNotEqual(withSlash, withoutSlash)
        XCTAssertEqual(withSlash.pathComponents, withoutSlash.pathComponents)
        let expected = try HatchPetPackage.load(from: withSlash)
        let actual = try HatchPetPackage.load(from: withoutSlash)
        XCTAssertEqual(actual.manifest, expected.manifest)
        XCTAssertEqual(Set(actual.animations.keys), Set(expected.animations.keys))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "HatchPetPackageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: name) }
        let destination = root.appendingPathComponent("pet", isDirectory: true)
        let model = AppModel(characterURL: root.appendingPathComponent("character.png"), petDirectory: destination,
                             bundledPetDirectory: nil, defaults: defaults)
        try model.selectHatchPet(from: withoutSlash)
        let restored = try HatchPetPackage.load(from: destination)
        XCTAssertEqual(restored.manifest, expected.manifest)
        XCTAssertNotNil(restored.animations[.idle]?.first?.tiffRepresentation)
    }
}
