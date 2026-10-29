import XCTest
@testable import CoupleMon

final class DrawingMessageTests: XCTestCase {
    private let stroke = DrawingMessage.Stroke(
        color: .pink, width: 4,
        points: [.init(x: 0.1, y: 0.2), .init(x: 0.8, y: 0.9)]
    )

    func testDrawingSurvivesTransportRoundTrip() throws {
        let drawing = DrawingMessage(strokes: [stroke])
        XCTAssertTrue(drawing.isValid)
        let data = try JSONEncoder().encode(drawing)
        XCTAssertEqual(try JSONDecoder().decode(DrawingMessage.self, from: data), drawing)
    }

    func testIncomingDrawingRejectsUnsafeCoordinatesAndSizes() throws {
        for json in [
            #"{"strokes":[{"color":"pink","width":4,"points":[{"x":2,"y":0}]}]}"#,
            #"{"strokes":[{"color":"pink","width":100,"points":[{"x":0,"y":0}]}]}"#,
            #"{"strokes":[{"color":"pink","width":4,"points":[]}]}"#,
        ] {
            let drawing = try JSONDecoder().decode(DrawingMessage.self, from: Data(json.utf8))
            XCTAssertFalse(drawing.isValid)
        }
        XCTAssertFalse(DrawingMessage(strokes: []).isValid)
        XCTAssertFalse(DrawingMessage(strokes: Array(repeating: stroke, count: 81)).isValid)
        let tooManyPoints = DrawingMessage.Stroke(
            color: .black, width: 1,
            points: Array(repeating: .init(x: 0, y: 0), count: DrawingMessage.maxPoints + 1)
        )
        XCTAssertFalse(DrawingMessage(strokes: [tooManyPoints]).isValid)
    }

    func testLargestComposerDrawingFitsBroadcastBudget() throws {
        let stroke = DrawingMessage.Stroke(
            color: .purple, width: 16,
            points: Array(repeating: .init(x: 0.999, y: 0.999), count: DrawingMessage.maxPoints)
        )
        let drawing = DrawingMessage(strokes: [stroke])
        XCTAssertTrue(drawing.isValid)
        XCTAssertLessThan(try JSONEncoder().encode(drawing).count, DrawingMessage.maxPayloadBytes)
    }

    @MainActor
    func testDrawingHistoryAndTextReplacement() {
        let drawing = DrawingMessage(strokes: [stroke])
        let model = AppModel()
        var sent: DrawingMessage?
        model.onSendDrawing = { sent = $0 }
        model.sendDrawing(drawing)
        XCTAssertEqual(sent, drawing)
        XCTAssertEqual(model.displayedDrawing, drawing)
        XCTAssertEqual(model.messageHistory.last?.isLocal, true)
        model.receiveDrawing(drawing)
        XCTAssertEqual(model.messageHistory.last?.isLocal, false)
        model.receive("좋아 💛")
        XCTAssertNil(model.displayedDrawing)
        XCTAssertEqual(model.messageHistory.first?.drawing, drawing)
        model.clearMessage()
        XCTAssertTrue(model.messageHistory.isEmpty)
        XCTAssertNil(model.displayedDrawing)
    }

    @MainActor
    func testServerConnectionDoesNotImplyPartnerReachable() {
        let model = AppModel()
        model.realtimeState = .connected
        XCTAssertNotNil(model.connectionNotice)
        model.isPartnerReachable = true
        XCTAssertNil(model.connectionNotice)
        model.sendError = "수신 확인 없음"
        XCTAssertEqual(model.connectionNotice, "수신 확인 없음")
    }
}
