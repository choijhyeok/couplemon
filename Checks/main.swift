import Foundation

assert(MessageText.normalize("  보고 싶어  \n") == "보고 싶어")
assert(MessageText.normalize("   \n").isEmpty)
assert(MessageText.normalize(String(repeating: "a", count: 121)).count == 120)
assert(MessageText.normalize("  보고 싶어 🥰  ") == "보고 싶어 🥰")

let realtimeSettings = try RealtimeSettings(
    projectURL: " https://example.supabase.co ",
    publishableKey: " sb_publishable_example ",
    roomCode: "ABCD-EFGH-JKLM-NPQR"
).validated()
assert(realtimeSettings.projectURL == "https://example.supabase.co")
assert(realtimeSettings.roomCode == "ABCDEFGHJKLMNPQR")
let legacyAnonSettings = try RealtimeSettings(
    projectURL: "https://example.supabase.co",
    publishableKey: "e30.eyJyb2xlIjoiYW5vbiJ9.x",
    roomCode: "ABCDEFGHJKLMNPQR"
).validated()
assert(legacyAnonSettings.publishableKey.contains("eyJyb2xlIjoiYW5vbiJ9"))
assert(RealtimeSettings.makeRoomCode().count == 16)

let hatchPet = HatchPetManifest(
    id: "sample-pet",
    displayName: "Sample Pet",
    description: "A test pet.",
    spriteVersionNumber: 2,
    spritesheetPath: "spritesheet.webp"
)
try HatchPetContract.validate(hatchPet, atlasWidth: 1536, atlasHeight: 2288)

let legacyPet = try JSONDecoder().decode(
    HatchPetManifest.self,
    from: #"{"id":"legacy-pet","displayName":"Legacy Pet","description":"A v1 pet.","spritesheetPath":"spritesheet.webp"}"#.data(using: .utf8)!
)
try HatchPetContract.validate(legacyPet, atlasWidth: 1536, atlasHeight: 1872)
assert(HatchPetContract.idleFrameIndex(elapsed: 0.279) == 0)
assert(HatchPetContract.idleFrameIndex(elapsed: 0.280) == 1)
assert(HatchPetContract.idleFrameIndex(elapsed: 1.100) == 0)

let unsafePet = HatchPetManifest(
    id: hatchPet.id,
    displayName: hatchPet.displayName,
    description: hatchPet.description,
    spriteVersionNumber: 2,
    spritesheetPath: "../spritesheet.webp"
)
do {
    try HatchPetContract.validateManifest(unsafePet)
    assertionFailure("Unsafe spritesheet path was accepted")
} catch HatchPetError.unsafeSpritesheetPath {
    // Expected.
}

if let petDirectory = CommandLine.arguments.dropFirst().first {
    let pet = try HatchPetPackage.load(from: URL(fileURLWithPath: petDirectory))
    assert(pet.idleFrames.count == 6)
    assert(pet.idleFrames.allSatisfy { $0.size.width == 192 && $0.size.height == 208 })
}
print("CoupleMon self-check passed")
