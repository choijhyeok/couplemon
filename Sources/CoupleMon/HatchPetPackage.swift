import AppKit
import ImageIO
import UniformTypeIdentifiers

struct HatchPet {
    let manifest: HatchPetManifest
    let animations: [HatchPetContract.Animation: [NSImage]]
}

enum HatchPetPackage {
    static func load(from directory: URL) throws -> HatchPet {
        let manifestURL = directory.appendingPathComponent("pet.json")
        let manifest: HatchPetManifest

        do {
            let values = try manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw HatchPetError.invalidManifest
            }
            manifest = try JSONDecoder().decode(HatchPetManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw HatchPetError.invalidManifest
        }

        try HatchPetContract.validateManifest(manifest)
        let atlasURL = directory.appendingPathComponent(manifest.spritesheetPath)
        let atlasValues = try? atlasURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let resolvedAtlasURL = atlasURL.resolvingSymlinksInPath().standardizedFileURL
        guard
            atlasValues?.isRegularFile == true,
            atlasValues?.isSymbolicLink != true,
            resolvedAtlasURL.deletingLastPathComponent() == resolvedDirectory,
            let source = CGImageSourceCreateWithURL(resolvedAtlasURL as CFURL, nil),
            let sourceType = CGImageSourceGetType(source) as String?,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw HatchPetError.unreadableAtlas
        }

        let expectedType = manifest.spritesheetPath.lowercased().hasSuffix(".png")
            ? UTType.png.identifier
            : UTType.webP.identifier
        guard sourceType == expectedType else { throw HatchPetError.unreadableAtlas }

        try HatchPetContract.validate(manifest, atlasWidth: width, atlasHeight: height)
        guard let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw HatchPetError.unreadableAtlas
        }

        let availableAnimations = HatchPetContract.Animation.allCases.filter {
            $0 != .lookAround || manifest.spriteVersion == HatchPetContract.spriteVersion
        }
        let animations = try Dictionary(uniqueKeysWithValues: availableAnimations.map { animation in
            let frames = try (0..<animation.frameCount).map { index in
                let row = animation == .lookAround
                    ? HatchPetContract.standardRows + (index / HatchPetContract.columns)
                    : animation.rawValue
                let column = index % HatchPetContract.columns
                let rect = CGRect(
                    x: column * HatchPetContract.cellWidth,
                    y: row * HatchPetContract.cellHeight,
                    width: HatchPetContract.cellWidth,
                    height: HatchPetContract.cellHeight
                )
                guard let frame = atlas.cropping(to: rect) else {
                    throw HatchPetError.unreadableAtlas
                }
                return NSImage(
                    cgImage: frame,
                    size: NSSize(width: HatchPetContract.cellWidth, height: HatchPetContract.cellHeight)
                )
            }
            return (animation, frames)
        })

        return HatchPet(manifest: manifest, animations: animations)
    }
}
