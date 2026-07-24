import XCTest
@testable import CoupleMon

final class HatchPetContractTests: XCTestCase {
    private let manifest = HatchPetManifest(
        id: "sample-pet",
        displayName: "Sample Pet",
        description: "A test pet.",
        spriteVersionNumber: 2,
        spritesheetPath: "spritesheet.webp"
    )

    func testV2ContractAcceptsExactAtlas() throws {
        XCTAssertNoThrow(
            try HatchPetContract.validate(manifest, atlasWidth: 1536, atlasHeight: 2288)
        )
    }

    func testContractsRejectWrongVersionSizeAndPath() {
        let legacyPet = HatchPetManifest(
            id: manifest.id,
            displayName: manifest.displayName,
            description: manifest.description,
            spriteVersionNumber: 1,
            spritesheetPath: manifest.spritesheetPath
        )
        let unsupportedPet = HatchPetManifest(
            id: manifest.id,
            displayName: manifest.displayName,
            description: manifest.description,
            spriteVersionNumber: 3,
            spritesheetPath: manifest.spritesheetPath
        )
        let unsafePet = HatchPetManifest(
            id: manifest.id,
            displayName: manifest.displayName,
            description: manifest.description,
            spriteVersionNumber: 2,
            spritesheetPath: "../spritesheet.webp"
        )

        XCTAssertNoThrow(try HatchPetContract.validate(legacyPet, atlasWidth: 1536, atlasHeight: 1872))
        XCTAssertThrowsError(try HatchPetContract.validate(legacyPet, atlasWidth: 1536, atlasHeight: 2288))
        XCTAssertThrowsError(try HatchPetContract.validate(unsupportedPet, atlasWidth: 1536, atlasHeight: 2288))
        XCTAssertThrowsError(try HatchPetContract.validate(manifest, atlasWidth: 1536, atlasHeight: 1872))
        XCTAssertThrowsError(try HatchPetContract.validate(unsafePet, atlasWidth: 1536, atlasHeight: 2288))
    }

    func testIdleAnimationUsesHatchPetTiming() {
        XCTAssertEqual(HatchPetContract.idleFrameIndex(elapsed: 0), 0)
        XCTAssertEqual(HatchPetContract.idleFrameIndex(elapsed: 0.279), 0)
        XCTAssertEqual(HatchPetContract.idleFrameIndex(elapsed: 0.280), 1)
        XCTAssertEqual(HatchPetContract.idleFrameIndex(elapsed: 0.391), 2)
        XCTAssertEqual(HatchPetContract.idleFrameIndex(elapsed: 1.100), 0)
    }
}
