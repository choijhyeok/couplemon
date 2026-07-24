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

    func testSettingsAcceptLegacyAnonKey() throws {
        let settings = try RealtimeSettings(
            projectURL: "https://example.supabase.co",
            publishableKey: "e30.eyJyb2xlIjoiYW5vbiJ9.x",
            roomCode: "ABCDEFGHJKLMNPQR"
        ).validated()

        XCTAssertEqual(settings.publishableKey, "e30.eyJyb2xlIjoiYW5vbiJ9.x")
    }

    func testSettingsRejectPrivilegedKeysAndShortCode() {
        XCTAssertThrowsError(
            try RealtimeSettings(
                projectURL: "https://example.supabase.co",
                publishableKey: "sb_secret_example",
                roomCode: "ABCDEFGHJKLMNPQR"
            ).validated()
        )
        XCTAssertThrowsError(
            try RealtimeSettings(
                projectURL: "https://example.supabase.co",
                publishableKey: "e30.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x",
                roomCode: "ABCDEFGHJKLMNPQR"
            ).validated()
        )
        XCTAssertThrowsError(
            try RealtimeSettings(
                projectURL: "https://example.supabase.co",
                publishableKey: "sb_publishable_example",
                roomCode: "TOO-SHORT"
            ).validated()
        )
    }
}
