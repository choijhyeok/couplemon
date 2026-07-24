import XCTest
@testable import CoupleMon

final class RealtimeSettingsTests: XCTestCase {
    func testSettingsNormalizeSharedRoomCode() throws {
        let settings = try RealtimeSettings(
            projectURL: " https://example.supabase.co ",
            publishableKey: " sb_publishable_example ",
            roomCode: "ABCD-EFGH-JKLM-NPQR"
        ).validated()

        XCTAssertEqual(settings.projectURL, "https://example.supabase.co")
        XCTAssertEqual(settings.roomCode, "ABCDEFGHJKLMNPQR")
    }

    func testSettingsRejectSecretKeyAndShortCode() {
        XCTAssertThrowsError(
            try RealtimeSettings(
                projectURL: "https://example.supabase.co",
                publishableKey: "sb_secret_example",
                roomCode: "TOO-SHORT"
            ).validated()
        )
    }
}
