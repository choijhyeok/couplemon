import AppKit
import Realtime
@testable import CoupleMon

// Run through: python3 Checks/check-realtime.py (does not contact Supabase).
@main
struct RealtimeCheck {
    enum CheckError: Error { case failed(String) }

    @MainActor
    static func waitFor(_ description: String, seconds: Double = 20, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { throw CheckError.failed(description) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)
        let endpoint = URL(string: CommandLine.arguments[1])!
        let a = CoupleRealtimeService { _, options in RealtimeClientV2(url: endpoint, options: options) }
        let b = CoupleRealtimeService { _, options in RealtimeClientV2(url: endpoint, options: options) }
        let settings = RealtimeSettings(
            projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_example",
            roomCode: "ABCDEFGHJKLMNPQR"
        )
        var aMessages: [String] = []
        var bMessages: [String] = []
        var receivedDrawing: DrawingMessage?
        var partnerA = false
        var partnerB = false
        var aError: String?
        var aReceipts = 0
        var bReceipts = 0
        var todoReceived = false
        var disconnectObserved = false
        let senderModel = AppModel()
        let receiverModel = AppModel()
        senderModel.onSend = { a.send($0) }
        senderModel.onSendDrawing = { a.sendDrawing($0) }
        a.onMessage = { aMessages.append($0) }
        b.onMessage = {
            bMessages.append($0)
            receiverModel.receive($0)
        }
        a.onPartnerChange = { partnerA = $0 }
        b.onPartnerChange = { partnerB = $0 }
        a.onSendError = { aError = $0; if $0 == nil { aReceipts += 1 } }
        b.onSendError = { if $0 == nil { bReceipts += 1 } }
        b.onDrawing = {
            receivedDrawing = $0
            receiverModel.receiveDrawing($0)
        }
        b.onTodoChanged = { todoReceived = true }
        a.onStateChange = {
            if case .failed = $0 { disconnectObserved = true }
        }

        await a.connect(to: settings)
        await b.connect(to: settings)
        try await waitFor("Two peers did not find each other") { partnerA && partnerB }
        a.send("안녕 💛")
        b.send("보고 싶어")
        try await waitFor("Bidirectional messages or receipts missing") {
            aMessages == ["보고 싶어"] && bMessages == ["안녕 💛"] && aReceipts == 1 && bReceipts == 1
        }
        let drawing = DrawingMessage(strokes: [.init(
            color: .pink, width: 4, points: [.init(x: 0.1, y: 0.2), .init(x: 0.8, y: 0.9)]
        )])
        senderModel.sendDrawing(drawing)
        a.sendTodoChanged()
        try await waitFor("Drawing, receipt, or Todo event missing") {
            receivedDrawing == drawing && aReceipts == 2 && todoReceived
        }
        guard let sentLetter = senderModel.drawingLetter, let receivedLetter = receiverModel.drawingLetter,
              sentLetter.isLocal, !receivedLetter.isLocal,
              senderModel.petActivity?.kind == .sendingLetter,
              receiverModel.petActivity?.kind == .receivingLetter,
              !senderModel.isBubbleVisible, !receiverModel.isBubbleVisible else {
            throw CheckError.failed("Both peers must present letters before the chat bubble")
        }
        try await Task.sleep(for: .milliseconds(200))
        guard !senderModel.isDrawingLetterOpen, !receiverModel.isDrawingLetterOpen,
              receiverModel.drawingLetter?.id == receivedLetter.id else {
            throw CheckError.failed("Unopened letter must wait for a click")
        }
        senderModel.openDrawingLetter(id: sentLetter.id)
        receiverModel.openDrawingLetter(id: receivedLetter.id)
        try await Task.sleep(for: .milliseconds(600))
        guard receiverModel.isDrawingLetterOpen else { throw CheckError.failed("Letter closed before reading") }
        try await waitFor("Opened letters did not automatically close", seconds: 4) {
            senderModel.drawingLetter == nil && receiverModel.drawingLetter == nil
        }
        guard senderModel.messageHistory.last?.drawing == drawing,
              receiverModel.messageHistory.last?.drawing == drawing,
              !senderModel.isBubbleVisible, !receiverModel.isBubbleVisible else {
            throw CheckError.failed("Letter dismissal must preserve chat history without reopening it")
        }
        receiverModel.receiveDrawing(drawing)
        let first = receiverModel.drawingLetter!
        receiverModel.openDrawingLetter(id: first.id)
        receiverModel.receiveDrawing(drawing)
        receiverModel.dismissDrawingLetter(id: first.id)
        guard let second = receiverModel.drawingLetter, second.id != first.id,
              !receiverModel.isDrawingLetterOpen else { throw CheckError.failed("Letter queue or X close") }
        receiverModel.dismissDrawingLetter(id: first.id)
        guard receiverModel.drawingLetter?.id == second.id else { throw CheckError.failed("Stale letter dismissal") }
        receiverModel.clearMessage()
        guard receiverModel.drawingLetter == nil else { throw CheckError.failed("Clearing queued letters") }
        print("PASS: peers, bidirectional text, drawing, receipts, Todo")
        print("PASS: sender/receiver letters, click to open, reading time, auto close, X close, queue, history")

        // Verify that a joined server channel is not confused with a reachable partner.
        let otherRoom = RealtimeSettings(
            projectURL: settings.projectURL, publishableKey: settings.publishableKey,
            roomCode: "ZZZZZZZZZZZZZZZZ"
        )
        await a.connect(to: otherRoom)
        guard a.state == .connected, !partnerA else { throw CheckError.failed("Room isolation") }
        a.send("다른 방")
        try await waitFor("Missing receipt timeout", seconds: 12) { aError != nil }
        guard bMessages == ["안녕 💛"] else { throw CheckError.failed("Cross-room message leak") }
        await a.connect(to: settings)
        a.send("다시 연결")
        try await waitFor("Reconnection or receipt error recovery") {
            bMessages.last == "다시 연결" && aError == nil
        }
        print("PASS: room isolation, receipt timeout, reconnect")

        var request = URLRequest(url: endpoint.deletingLastPathComponent().appendingPathComponent("drop"))
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
        try await waitFor("Socket loss was not observed") { disconnectObserved }
        try await waitFor("Automatic recovery failed") { a.state == .connected && b.state == .connected }
        a.send("복구 후 메시지")
        try await waitFor("Recovered transport did not deliver") { bMessages.last == "복구 후 메시지" }
        await a.reconnect()
        b.send("잠자기 복귀 후 메시지")
        try await waitFor("Explicit wake reconnect failed") { aMessages.last == "잠자기 복귀 후 메시지" }

        senderModel.setTerminalMode(true)
        receiverModel.setTerminalMode(true)
        senderModel.messageDraft = "터미널 모드 메시지"
        senderModel.sendDraft()
        try await waitFor("Terminal draft did not reach partner") {
            receiverModel.terminalHistory.last?.text == "터미널 모드 메시지"
        }
        let previousImageID = receiverModel.terminalHistory.last?.id
        senderModel.sendDrawing(drawing)
        try await waitFor("Terminal drawing did not reach partner") {
            receiverModel.terminalHistory.last?.drawing == drawing
                && receiverModel.terminalHistory.last?.id != previousImageID
        }
        guard senderModel.drawingLetter == nil, receiverModel.drawingLetter == nil,
              senderModel.petActivity == nil, receiverModel.petActivity == nil,
              !senderModel.isBubbleVisible, !receiverModel.isBubbleVisible,
              receiverModel.terminalHistory.last?.attachmentNumber != nil,
              senderModel.messageDraft.isEmpty else {
            throw CheckError.failed("Terminal mode exposed pet notifications or lost the attachment")
        }
        senderModel.setTerminalMode(false)
        receiverModel.setTerminalMode(false)
        guard senderModel.drawingLetter == nil, receiverModel.drawingLetter == nil else {
            throw CheckError.failed("Terminal drawings must not reappear as pending letters")
        }
        print("PASS: terminal mode live text/drawing, shared draft, attachment labels, suppressed pet notifications")
        await a.disconnect()
        await b.disconnect()
        print("PASS: socket loss, automatic recovery, wake reconnect")

        let model = AppModel()
        model.sendDrawing(drawing)
        guard model.displayedDrawing == drawing, model.messageHistory.last?.isLocal == true else {
            throw CheckError.failed("Local drawing history")
        }
        model.receiveDrawing(drawing)
        guard model.messageHistory.last?.isLocal == false else { throw CheckError.failed("Received drawing history") }
        model.receive("좋아")
        guard model.displayedDrawing == nil, model.petActivity?.kind == .chat else {
            throw CheckError.failed("Text must replace drawing without a letter gesture")
        }
        model.realtimeState = .connected
        guard model.connectionNotice != nil else { throw CheckError.failed("Server-only warning") }
        model.isPartnerReachable = true
        guard model.connectionNotice == nil else { throw CheckError.failed("Partner status") }
        model.clearMessage()
        guard model.messageHistory.isEmpty, model.displayedDrawing == nil else { throw CheckError.failed("Clear drawing") }
        print("PASS: drawing history, text replacement, connection notices")
    }
}
