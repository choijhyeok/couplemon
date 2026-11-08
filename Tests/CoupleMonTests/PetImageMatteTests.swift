import AppKit
import XCTest
@testable import CoupleMon

final class PetImageMatteTests: XCTestCase {
    func testTransparentDrawingPreservesPixelsAndCanvas() throws {
        let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 48,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<48 {
            for x in 0..<32 {
                image.setColor(x > 8 && x < 24 && y > 8 && y < 40 ? .systemOrange : .clear, atX: x, y: y)
            }
        }
        let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        // No segmentation, crop, color conversion or re-encoding of an artist's alpha.
        XCTAssertEqual(try PetImageMatte.prepare(png), png)
    }

    func testInvalidImageFailsBeforeVision() {
        XCTAssertThrowsError(try PetImageMatte.prepare(Data("invalid".utf8)))
    }
}
