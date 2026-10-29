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
        a.onMessage = { aMessages.append($0) }
        b.onMessage = { bMessages.append($0) }
        a.onPartnerChange = { partnerA = $0 }
        b.onPartnerChange = { partnerB = $0 }
        a.onSendError = { aError = $0; if $0 == nil { aReceipts += 1 } }
        b.onSendError = { if $0 == nil { bReceipts += 1 } }
        b.onDrawing = { receivedDrawing = $0 }
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
        a.sendDrawing(drawing)
        a.sendTodoChanged()
        try await waitFor("Drawing, receipt, or Todo event missing") {
            receivedDrawing == drawing && aReceipts == 2 && todoReceived
        }
        print("PASS: peers, bidirectional text, drawing, receipts, Todo")

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
        guard model.displayedDrawing == nil else { throw CheckError.failed("Text must replace drawing") }
        model.realtimeState = .connected
        guard model.connectionNotice != nil else { throw CheckError.failed("Server-only warning") }
        model.isPartnerReachable = true
        guard model.connectionNotice == nil else { throw CheckError.failed("Partner status") }
        model.clearMessage()
        guard model.messageHistory.isEmpty, model.displayedDrawing == nil else { throw CheckError.failed("Clear drawing") }
        print("PASS: drawing history, text replacement, connection notices")
    }
}
