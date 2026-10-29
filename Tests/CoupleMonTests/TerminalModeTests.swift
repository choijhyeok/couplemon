import XCTest
@testable import CoupleMon

final class TerminalModeTests: XCTestCase {
    private var drawing: DrawingMessage {
        DrawingMessage(strokes: [.init(color: .blue, width: 4, points: [.init(x: 0.5, y: 0.5)])])
    }

    @MainActor
    func testSwitchingModesPreservesConversationAndDraftAndClearsLetters() {
        let model = AppModel()
        model.receiveDrawing(drawing)
        model.messageDraft = "작성 중인 메시지"
        let history = model.messageHistory
        var changes: [Bool] = []
        model.onTerminalModeChange = { changes.append($0) }
        model.setTerminalMode(true)
        model.setTerminalMode(true)
        XCTAssertTrue(model.isTerminalMode)
        XCTAssertNil(model.drawingLetter)
        XCTAssertFalse(model.isBubbleVisible)
        XCTAssertEqual(model.messageHistory, history)
        XCTAssertEqual(model.terminalHistory, history)
        XCTAssertEqual(model.messageDraft, "작성 중인 메시지")
        model.setTerminalMode(false)
        XCTAssertEqual(changes, [true, false])
    }

    @MainActor
    func testTerminalMessagesAndDrawingsNeverShowPetNotifications() {
        let model = AppModel()
        model.setTerminalMode(true)
        model.send("local")
        model.receive("remote")
        model.sendDrawing(drawing)
        model.receiveDrawing(drawing)
        model.showBubble()
        model.setMessageEditing(true)
        XCTAssertFalse(model.isBubbleVisible)
        XCTAssertFalse(model.isEditingMessage)
        XCTAssertNil(model.drawingLetter)
        XCTAssertEqual(model.terminalHistory.count, 4)
        XCTAssertEqual(model.terminalHistory.compactMap(\.attachmentNumber), [1, 2])
        model.setTerminalMode(false)
        XCTAssertNil(model.drawingLetter)
        model.receiveDrawing(drawing)
        XCTAssertNotNil(model.drawingLetter)
    }

    @MainActor
    func testSharedDraftSendsThroughExistingTransport() {
        let model = AppModel()
        var sent: [String] = []
        model.onSend = { sent.append($0) }
        model.messageDraft = "  같은 연결로 전송  "
        model.setTerminalMode(true)
        model.sendDraft()
        model.sendDraft()
        XCTAssertEqual(sent, ["같은 연결로 전송"])
        XCTAssertEqual(model.messageDraft, "")
        XCTAssertEqual(model.messageHistory.last?.text, sent.first)
        XCTAssertEqual(model.terminalHistory.last?.id, model.messageHistory.last?.id)
    }

    @MainActor
    func testAttachmentNumbersStayStableWhenRecentHistoryRollsOver() {
        let model = AppModel()
        model.setTerminalMode(true)
        model.receiveDrawing(drawing)
        for index in 1...205 { model.receive("line \(index)") }
        model.receiveDrawing(drawing)
        XCTAssertEqual(model.messageHistory.count, 5)
        XCTAssertEqual(model.terminalHistory.count, 200)
        XCTAssertEqual(model.terminalHistory.last?.attachmentNumber, 2)
        model.clearMessage()
        XCTAssertTrue(model.terminalHistory.isEmpty)
        model.receiveDrawing(drawing)
        XCTAssertEqual(model.terminalHistory.last?.attachmentNumber, 1)
    }

    @MainActor
    func testChatShortcutFocusesTerminalWithoutOpeningHiddenInput() {
        let model = AppModel()
        model.setTerminalMode(true)
        model.requestChatFocus()
        XCTAssertEqual(model.terminalFocusRequest, 1)
        XCTAssertEqual(model.chatFocusRequest, 0)
        XCTAssertFalse(model.isBubbleVisible)
        model.setTerminalMode(false)
        model.requestChatFocus()
        XCTAssertEqual(model.chatFocusRequest, 1)
        XCTAssertTrue(model.isBubbleVisible)
    }
}
