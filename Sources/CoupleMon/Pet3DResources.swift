import Foundation

enum Pet3DResources {
    // SwiftPM's Bundle.module can trap when an executable is moved into a .app:
    // it searches the app root and the build machine's absolute directory.
    static func url(for filename: String, bundle: Bundle = .main) -> URL? {
        let roots = [bundle.resourceURL, bundle.bundleURL, bundle.executableURL?.deletingLastPathComponent()]
        for root in roots.compactMap({ $0 }) {
            let file = root.appendingPathComponent("CoupleMon_CoupleMon.bundle/Pet3D")
                .appendingPathComponent(filename)
            if FileManager.default.isReadableFile(atPath: file.path) { return file }
        }
        return nil
    }

    static let requiredFiles = [
        "viewer.html", "viewer.js", "motion-player.js", "illustrated-motion.js", "couple-scene.js",
        "pet-props.js", "reward-items.js", "generation-prompt.txt",
        "build-model.py", "pet-actions.py", "image-rig.py", "image-rig-prompt.txt", "vendor/three.module.min.js",
        "vendor/three.core.min.js", "vendor/GLTFLoader.js", "vendor/BufferGeometryUtils.js",
    ]
}
