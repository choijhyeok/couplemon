import AppKit

@main
struct CoupleMonApp {
    static func main() {
        if CommandLine.arguments.contains("--check-resources") {
            for name in Pet3DResources.requiredFiles {
                guard let url = Pet3DResources.url(for: name),
                      let data = try? Data(contentsOf: url), !data.isEmpty else {
                    fputs("Missing 3D resource: \(name)\n", stderr)
                    exit(1)
                }
            }
            print("PASS: packaged 3D resources")
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
