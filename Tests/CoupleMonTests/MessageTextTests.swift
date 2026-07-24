import XCTest
@testable import CoupleMon

final class MessageTextTests: XCTestCase {
    func testNormalizeTrimsAndLimitsMessages() {
        XCTAssertEqual(MessageText.normalize("  보고 싶어  \n"), "보고 싶어")
        XCTAssertEqual(MessageText.normalize("   \n"), "")
        XCTAssertEqual(MessageText.normalize(String(repeating: "a", count: 121)).count, 120)
    }

    @MainActor
    func testEmptyMessageDoesNotReplaceCurrentMessage() {
        let characterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("character.png")

        let model = AppModel(characterURL: characterURL)
        model.send("잘 자 💛")
        model.send("   \n")

        XCTAssertEqual(model.displayedMessage, "잘 자 💛")
    }
}
