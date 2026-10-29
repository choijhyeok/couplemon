import Foundation

assert(MessageText.normalize("  보고 싶어  \n") == "보고 싶어")
assert(MessageText.normalize("   \n").isEmpty)
assert(MessageText.normalize(String(repeating: "a", count: 121)).count == 120)
assert(MessageText.normalize("  보고 싶어 🥰  ") == "보고 싶어 🥰")

let drawingStroke = DrawingMessage.Stroke(
    color: .pink, width: 4,
    points: [.init(x: 0.1, y: 0.2), .init(x: 0.8, y: 0.9)]
)
let drawing = DrawingMessage(strokes: [drawingStroke])
assert(drawing.isValid)
let decodedDrawing = try JSONDecoder().decode(DrawingMessage.self, from: JSONEncoder().encode(drawing))
assert(decodedDrawing == drawing)
assert(!DrawingMessage(strokes: []).isValid)
assert(!DrawingMessage(strokes: Array(repeating: drawingStroke, count: 81)).isValid)
let oversizedDrawing = DrawingMessage(strokes: [.init(
    color: .black, width: 1,
    points: Array(repeating: .init(x: 0, y: 0), count: DrawingMessage.maxPoints + 1)
)])
assert(!oversizedDrawing.isValid)
let maximumDrawing = DrawingMessage(strokes: [.init(
    color: .purple, width: 16,
    points: Array(repeating: .init(x: 0.999, y: 0.999), count: DrawingMessage.maxPoints)
)])
assert(maximumDrawing.isValid)
let invalidDrawing = try JSONDecoder().decode(DrawingMessage.self, from: Data(
    #"{"strokes":[{"color":"pink","width":4,"points":[{"x":2,"y":0}]}]}"#.utf8
))
assert(!invalidDrawing.isValid)

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
assert(UpdateService.isNewer("0.2.0", than: "0.1.9"))
assert(!UpdateService.isNewer("0.2.0", than: "0.2.0"))

let releaseData = #"{"tag_name":"v0.2.0","html_url":"https://github.com/choijhyeok/couplemon/releases/tag/v0.2.0","assets":[{"name":"CoupleMon.pkg","browser_download_url":"https://github.com/choijhyeok/couplemon/releases/download/v0.2.0/CoupleMon.pkg","size":42}]}"#.data(using: .utf8)!
let release = try JSONDecoder().decode(GitHubRelease.self, from: releaseData)
assert(release.version == "0.2.0")
assert(release.installer?.name == "CoupleMon.pkg")

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
    let idleFrames = pet.animations[.idle] ?? []
    assert(idleFrames.count == 6)
    assert(idleFrames.allSatisfy { $0.size.width == 192 && $0.size.height == 208 })
}
print("CoupleMon self-check passed")
