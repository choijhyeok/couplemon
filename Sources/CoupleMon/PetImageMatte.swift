import AppKit
import CoreImage
import ImageIO
import Vision

/// Keeps the original canvas coordinates so the AI's anchors still match the texture.
enum PetImageMatte {
    static func prepare(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Pet3DError.message("이미지를 읽을 수 없습니다.")
        }
        // Preserve an artist's alpha rather than asking Vision to segment it again.
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let hasTransparency = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] < 255 }
        }
        if hasTransparency { return data }
        do {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else {
                throw Pet3DError.message("캐릭터를 찾을 수 없습니다.")
            }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
            let context = CIContext()
            guard let cutout = context.createCGImage(CIImage(cvPixelBuffer: buffer), from: CGRect(x: 0, y: 0, width: width, height: height)),
                  let png = NSBitmapImageRep(cgImage: cutout).representation(using: .png, properties: [:]) else {
                throw Pet3DError.message("배경 제거 결과를 저장할 수 없습니다.")
            }
            return png
        } catch {
            throw Pet3DError.message("배경을 분리하지 못했습니다. 배경이 투명한 PNG로 다시 시도하세요. (\(error.localizedDescription))")
        }
    }
}
