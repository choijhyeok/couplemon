import AppKit
import SwiftUI
@testable import CoupleMon

@MainActor
final class PetInteractionCheck: NSObject, NSApplicationDelegate {
    enum Failure: Error { case failed(String) }
    private let suite = "CoupleMon.PetInteraction.\(UUID().uuidString)"
    private var controller: OverlayPanelController!
    private var model: AppModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await runChecks()
                controller.panel.close()
                UserDefaults.standard.removePersistentDomain(forName: suite)
                print("PASS: native pet switching, persisted frames, distinct send/receive gestures, idle reset")
                NSApp.terminate(nil)
            } catch {
                UserDefaults.standard.removePersistentDomain(forName: suite)
                fputs("Pet check failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private func runChecks() async throws {
        let arguments = CommandLine.arguments
        let bundled = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let screenshots = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pet-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: suite)!
        let destination = root.appendingPathComponent("pet", isDirectory: true)
        model = AppModel(characterURL: root.appendingPathComponent("character.png"), petDirectory: destination,
                         bundledPetDirectory: bundled, defaults: defaults)
        let sources = [bundled] + arguments.dropFirst(3).map { URL(fileURLWithPath: $0, isDirectory: true) }
        for directory in sources {
            let expected = try HatchPetPackage.load(from: directory).manifest.id
            try model.selectHatchPet(from: directory)
            let restored = AppModel(characterURL: root.appendingPathComponent("character.png"), petDirectory: destination,
                                    bundledPetDirectory: nil, defaults: defaults)
            guard restored.hatchPet?.manifest.id == expected,
                  restored.hatchPet?.animations[.idle]?.first?.tiffRepresentation != nil else {
                throw Failure.failed("Could not restore \(directory.lastPathComponent)")
            }
            print("PASS: selected and restored", expected)
        }
        try model.selectHatchPet(from: destination)
        guard model.hatchPet?.animations[.idle]?.first?.tiffRepresentation != nil else {
            throw Failure.failed("Reselecting installed pet failed")
        }
        let installedID = model.hatchPet?.manifest.id
        do {
            try model.selectHatchPet(from: root.appendingPathComponent("missing"))
            throw Failure.failed("Invalid pet unexpectedly loaded")
        } catch is HatchPetError { }
        guard model.hatchPet?.manifest.id == installedID else { throw Failure.failed("Failed selection lost old pet") }

        let outgoing = PetLetterAnimation.motion(elapsed: 0.7, direction: .sending)
        let incoming = PetLetterAnimation.motion(elapsed: 0.77, direction: .receiving)
        guard outgoing.letterX > incoming.letterX, outgoing.letterY < incoming.letterY,
              incoming.petScaleY < 1,
              PetLetterAnimation.motion(elapsed: 10, direction: .sending) == .idle else {
            throw Failure.failed("Letter gesture direction or idle pose")
        }
        controller = OverlayPanelController(model: model)
        controller.show()
        model.clearMessage()
        try await Task.sleep(for: .milliseconds(300))
        let drawing = DrawingMessage(strokes: [.init(color: .blue, width: 4, points: [.init(x: 0.5, y: 0.5)])])
        model.sendDrawing(drawing)
        guard model.petActivity?.kind == .sendingLetter else { throw Failure.failed("Missing sending action") }
        try await Task.sleep(for: .milliseconds(350))
        try capture("send-hold", directory: screenshots)
        try await Task.sleep(for: .milliseconds(400))
        try capture("send-flight", directory: screenshots)
        try await Task.sleep(for: .milliseconds(800))
        try capture("send-finished", directory: screenshots)
        model.clearMessage()
        model.receiveDrawing(drawing)
        guard model.petActivity?.kind == .receivingLetter else { throw Failure.failed("Missing receiving action") }
        try await Task.sleep(for: .milliseconds(350))
        try capture("receive-flight", directory: screenshots)
        try await Task.sleep(for: .milliseconds(420))
        try capture("receive-catch", directory: screenshots)
        try await Task.sleep(for: .milliseconds(800))
        try capture("receive-finished", directory: screenshots)
        model.receive("일반 메시지")
        guard model.petActivity?.kind == .chat else { throw Failure.failed("Text used a letter action") }
        model.setTerminalMode(true)
        model.sendDrawing(drawing)
        model.receiveDrawing(drawing)
        guard model.petActivity == nil, model.drawingLetter == nil, !controller.panel.isVisible else {
            throw Failure.failed("Terminal mode exposed letter actions")
        }
        model.setTerminalMode(false)
    }

    private func capture(_ name: String, directory: URL) throws {
        let view = controller.panel.contentView!
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure.failed("Bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure.failed("PNG") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

@main
struct PetInteractionCheckApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = PetInteractionCheck()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
