import XCTest
@testable import CoupleMon

final class UpdateServiceTests: XCTestCase {
    func testNumericVersionComparison() {
        XCTAssertTrue(UpdateService.isNewer("0.2.0", than: "0.1.9"))
        XCTAssertFalse(UpdateService.isNewer("0.2.0", than: "0.2.0"))
        XCTAssertFalse(UpdateService.isNewer("0.1.9", than: "0.2.0"))
        XCTAssertFalse(UpdateService.isNewer("../../bad", than: "0.2.0"))
    }

    func testReleaseDecodesAndSelectsInstaller() throws {
        let data = #"{"tag_name":"v0.2.0","html_url":"https://github.com/choijhyeok/couplemon/releases/tag/v0.2.0","assets":[{"name":"CoupleMon.pkg","browser_download_url":"https://github.com/choijhyeok/couplemon/releases/download/v0.2.0/CoupleMon.pkg","size":42,"digest":"sha256:abc"}]}"#.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.installer?.name, "CoupleMon.pkg")
    }
}
