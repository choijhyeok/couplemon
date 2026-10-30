import XCTest
@testable import CoupleMon

final class PetActivityTests: XCTestCase {
    private var drawing: DrawingMessage {
        DrawingMessage(strokes: [.init(color: .blue, width: 4, points: [.init(x: 0.5, y: 0.5)])])
    }

    @MainActor
    func testOnlyDrawingsUseLetterGesturesAndDirectionMatchesSender() {
        let model = AppModel()
        model.send("안녕")
        XCTAssertEqual(model.petActivity?.kind, .chat)
        model.sendDrawing(drawing)
        XCTAssertEqual(model.petActivity?.kind, .sendingLetter)
        let firstID = model.petActivity?.id
        model.sendDrawing(drawing)
        XCTAssertNotEqual(model.petActivity?.id, firstID)
        model.receiveDrawing(drawing)
        XCTAssertEqual(model.petActivity?.kind, .receivingLetter)
        model.receive(CoupleMonEmoticon.quokka.messageValue)
        XCTAssertEqual(model.petActivity?.kind, .chat)
        model.clearMessage()
        XCTAssertNil(model.petActivity)
    }

    @MainActor
    func testTerminalModeCancelsAndSuppressesPetGestures() {
        let model = AppModel()
        model.sendDrawing(drawing)
        model.setTerminalMode(true)
        XCTAssertNil(model.petActivity)
        model.receiveDrawing(drawing)
        model.sendDrawing(drawing)
        XCTAssertNil(model.petActivity)
        model.setTerminalMode(false)
        XCTAssertNil(model.petActivity)
        model.receiveDrawing(drawing)
        XCTAssertEqual(model.petActivity?.kind, .receivingLetter)
    }

    func testSendingMovesLetterAwayAndReceivingCatchesIt() {
        let outgoing = PetLetterAnimation.motion(elapsed: PetLetterAnimation.duration * 0.5, direction: .sending)
        let incoming = PetLetterAnimation.motion(elapsed: PetLetterAnimation.duration * 0.55, direction: .receiving)
        XCTAssertGreaterThan(outgoing.letterX, incoming.letterX)
        XCTAssertLessThan(outgoing.letterY, incoming.letterY)
        XCTAssertEqual(outgoing.letterOpacity, 1)
        XCTAssertEqual(incoming.letterOpacity, 1)
        XCTAssertLessThan(incoming.petScaleY, 1)
        XCTAssertEqual(PetActivity.Kind.sendingLetter.preferredAnimation, .waving)
        XCTAssertEqual(PetActivity.Kind.receivingLetter.preferredAnimation, .review)
    }

    func testGesturesFinishAtIdleAndRejectInvalidTimes() {
        for direction in [PetLetterAnimation.Direction.sending, .receiving] {
            for time in [-1.0, .nan, .infinity, PetLetterAnimation.duration, 100] {
                XCTAssertEqual(PetLetterAnimation.motion(elapsed: time, direction: direction), .idle)
            }
        }
    }
}
