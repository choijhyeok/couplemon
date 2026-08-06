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
    func testDismissChatInputHidesBubbleAndEndsEditing() {
        let model = AppModel()
        model.setMessageEditing(true)

        model.dismissChatInput()

        XCTAssertFalse(model.isEditingMessage)
        XCTAssertFalse(model.isBubbleVisible)
    }

    @MainActor
    func testIncomingMessageDoesNotOpenConversationHistory() {
        let model = AppModel()

        model.receive("상대 메시지")

        XCTAssertFalse(model.isEditingMessage)
        XCTAssertEqual(model.displayedMessage, "상대 메시지")
        XCTAssertTrue(model.isBubbleVisible)
    }

    func testCoupleMonEmoticonMessageRoundTrips() {
        for emoticon in CoupleMonEmoticon.allCases {
            XCTAssertEqual(CoupleMonEmoticon(messageValue: emoticon.messageValue), emoticon)
        }
        XCTAssertEqual(CoupleMonEmoticon(messageValue: "😀"), nil)
    }

    func testCoupleMonAnimatedEmoticonMessageRoundTripsAndMoves() {
        for emoticon in CoupleMonAnimatedEmoticon.allCases {
            XCTAssertEqual(CoupleMonAnimatedEmoticon(messageValue: emoticon.messageValue), emoticon)
            XCTAssertNotEqual(emoticon.motion(at: 0), emoticon.motion(at: 0.31))
        }
        XCTAssertEqual(CoupleMonAnimatedEmoticon(messageValue: "😀"), nil)
    }

    func testAllEmoticonsLoadFromPackagedResourceLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundle = root.appendingPathComponent("CoupleMon_CoupleMon.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CoupleMon/Resources/Emoticons")

        for emoticon in CoupleMonEmoticon.allCases {
            let filename = "\(emoticon.rawValue).png"
            try FileManager.default.copyItem(
                at: sourceDirectory.appendingPathComponent(filename),
                to: bundle.appendingPathComponent(filename)
            )
            XCTAssertNotNil(emoticon.image(resourceRootURL: root))
        }
    }

    func testMissingEmoticonBundleFallsBackWithoutCrashing() {
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        XCTAssertNil(CoupleMonEmoticon.quokka.image(resourceRootURL: missingRoot))
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
        XCTAssertEqual(restored.pendingTodoMutations.count, 4)
    }

    @MainActor
    func testTodoSeparatesMinePartnerAndCoupleAndProtectsPartnerRows() {
        let suiteName = "CoupleMonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(defaults: defaults)
        let mine = AppModel.TodoItem(
            id: UUID(), text: "내 일", isCompleted: false, ownerID: model.todoOwnerID
        )
        let partner = AppModel.TodoItem(
            id: UUID(), text: "상대 일", isCompleted: false, ownerID: UUID()
        )
        let couple = AppModel.TodoItem(
            id: UUID(), text: "같이 할 일", isCompleted: false, scope: .couple
        )
        model.replaceTodos([mine, partner, couple])

        XCTAssertEqual(model.todoItems(for: .mine), [mine])
        XCTAssertEqual(model.todoItems(for: .partner), [partner])
        XCTAssertEqual(model.todoItems(for: .couple), [couple])

        model.toggleTodo(id: partner.id)
        model.deleteTodo(id: partner.id)
        XCTAssertEqual(model.todoItems(for: .partner), [partner])

        model.toggleTodo(id: couple.id)
        XCTAssertTrue(model.todoItems(for: .couple)[0].isCompleted)
    }

    @MainActor
    func testTodoMutationsPersistInOrderUntilCompleted() {
        let suiteName = "CoupleMonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(defaults: defaults)

        model.addTodo("순서 보존")
        let id = model.todoItems[0].id
        model.toggleTodo(id: id)
        model.deleteTodo(id: id)

        let restored = AppModel(defaults: defaults)
        XCTAssertEqual(restored.pendingTodoMutations.map(\.action), [.upsert, .upsert, .delete])
        _ = restored.prepareTodoRoom("AAAAAAAAAAAAAAAA")
        let first = restored.nextTodoMutation(roomCode: "AAAAAAAAAAAAAAAA")!
        restored.completeTodoMutation(first)
        XCTAssertEqual(AppModel(defaults: defaults).pendingTodoMutations.count, 2)
    }

    @MainActor
    func testChangingRoomDoesNotCopyCachedTodosToNewCouple() {
        let suiteName = "CoupleMonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(defaults: defaults)
        model.addTodo("첫 연결의 할 일")

        XCTAssertEqual(model.prepareTodoRoom("AAAAAAAAAAAAAAAA").count, 1)
        model.markTodoRoomPrepared("AAAAAAAAAAAAAAAA")

        XCTAssertTrue(model.prepareTodoRoom("BBBBBBBBBBBBBBBB").isEmpty)
        XCTAssertTrue(model.todoItems.isEmpty)
        XCTAssertEqual(model.pendingTodoMutations.count, 1)
        XCTAssertEqual(model.pendingTodoMutations[0].roomCode, "AAAAAAAAAAAAAAAA")
    }

    @MainActor
    func testLegacyTodoAdoptsStableOwnerAfterUpdate() throws {
        struct LegacyTodo: Encodable {
            let id: UUID
            let text: String
            let isCompleted: Bool
        }

        let suiteName = "CoupleMonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = LegacyTodo(id: UUID(), text: "기존 할 일", isCompleted: false)
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "todoItems")

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.todoItems(for: .mine).map(\.text), ["기존 할 일"])
        XCTAssertEqual(model.todoItems[0].ownerID, model.todoOwnerID)
    }

    private static var defaultPetDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/DefaultPet", isDirectory: true)
    }
}
