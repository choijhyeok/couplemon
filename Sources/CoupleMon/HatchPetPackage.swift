import AppKit
import ImageIO
import UniformTypeIdentifiers

struct HatchPet {
    let manifest: HatchPetManifest
    let animations: [HatchPetContract.Animation: [NSImage]]
}

enum HatchPetPackage {
    static func load(from directory: URL) throws -> HatchPet {
        let accessed = directory.startAccessingSecurityScopedResource()
        defer { if accessed { directory.stopAccessingSecurityScopedResource() } }
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
        // Own the bytes before decoding: the chosen folder's access scope can end,
        // and the staging directory is moved after a successful import.
        guard
            atlasValues?.isRegularFile == true,
            atlasValues?.isSymbolicLink != true,
            // NSOpenPanel folder URLs may omit the trailing slash. Compare directory
            // identity by normalized components, not the URL's directory hint.
            resolvedAtlasURL.deletingLastPathComponent().pathComponents == resolvedDirectory.pathComponents,
            let atlasData = try? Data(contentsOf: resolvedAtlasURL),
            let source = CGImageSourceCreateWithData(atlasData as CFData, nil),
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
        guard let atlas = CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        ) else {
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
