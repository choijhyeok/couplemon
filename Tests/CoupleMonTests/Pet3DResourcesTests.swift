import Foundation
import XCTest
@testable import CoupleMon

final class Pet3DResourcesTests: XCTestCase {
    func testRelocatedAppLoadsResourcesWithoutBuildDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Relocated.app/Contents")
        let resources = contents.appendingPathComponent("Resources/CoupleMon_CoupleMon.bundle/Pet3D")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: String] = ["CFBundleIdentifier": "com.couplemon.resource-test", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: contents.deletingLastPathComponent()))
        for name in Pet3DResources.requiredFiles {
            let file = resources.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.utf8).write(to: file)
            let resolved = try XCTUnwrap(Pet3DResources.url(for: name, bundle: bundle))
            XCTAssertEqual(try Data(contentsOf: resolved), Data(name.utf8))
        }
        XCTAssertNil(Pet3DResources.url(for: "missing.js", bundle: bundle))
        try FileManager.default.removeItem(at: resources)
        XCTAssertNil(Pet3DResources.url(for: "viewer.html", bundle: bundle))
    }
}
