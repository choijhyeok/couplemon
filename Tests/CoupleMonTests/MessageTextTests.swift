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

    @MainActor
    func testHistoryKeepsFiveMessagesAndTheirSender() {
        let model = AppModel()

        for index in 1...6 { model.send("내 메시지 \(index)") }
        model.receive("상대 메시지")

        XCTAssertEqual(model.messageHistory.map(\.text), [
            "내 메시지 3", "내 메시지 4", "내 메시지 5", "내 메시지 6", "상대 메시지",
        ])
        XCTAssertEqual(model.messageHistory.map(\.isLocal), [true, true, true, true, false])
    }

    @MainActor
    func testCharacterScaleClampsAndPersists() {
        let suiteName = "CoupleMonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(defaults: defaults)

        model.setCharacterScale(2)

        XCTAssertEqual(model.characterScale, 1.3)
        XCTAssertEqual(AppModel(defaults: defaults).characterScale, 1.3)
    }

    @MainActor
    func testBundledPetIsFallbackAndReturnsAfterReset() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let model = AppModel(
            characterURL: temporaryDirectory.appendingPathComponent("character.png"),
            petDirectory: temporaryDirectory.appendingPathComponent("pet", isDirectory: true),
            bundledPetDirectory: Self.defaultPetDirectory
        )

        XCTAssertEqual(model.hatchPet?.manifest.id, "kt-ribbon-pet")
        try model.resetCharacter()
        XCTAssertEqual(model.hatchPet?.manifest.id, "kt-ribbon-pet")
    }

    @MainActor
    func testTodoPersistsCompletionAndVisibilitySetting() {
        let suiteName = "CoupleMonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(defaults: defaults)

        model.setTodoEnabled(true)
        model.toggleTodoVisibility()
        XCTAssertTrue(model.isTodoVisible)
        model.setTodoEnabled(false)
        XCTAssertFalse(model.isTodoVisible)
        model.setTodoEnabled(true)
        model.addTodo("  장보기  ")
        model.addTodo("삭제할 일")
        model.toggleTodo(id: model.todoItems[0].id)
        model.deleteTodo(id: model.todoItems[1].id)

        let restored = AppModel(defaults: defaults)
        XCTAssertTrue(restored.isTodoEnabled)
        XCTAssertEqual(restored.todoItems.map(\.text), ["장보기"])
        XCTAssertTrue(restored.todoItems[0].isCompleted)
    }

    private static var defaultPetDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/DefaultPet", isDirectory: true)
    }
}
