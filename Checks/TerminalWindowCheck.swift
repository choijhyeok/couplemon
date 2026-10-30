import AppKit
@testable import CoupleMon

@MainActor
final class TerminalWindowCheck: NSObject, NSApplicationDelegate {
    enum Failure: Error { case failed(String) }
    private let suiteName = "CoupleMon.TerminalCheck.\(UUID().uuidString)"
    private var controller: OverlayPanelController!
    private var model: AppModel!
    private var screenshots: URL { URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) }

    private func makeModel(defaults: UserDefaults) -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        return AppModel(characterURL: root.appendingPathComponent("character.png"),
                        petDirectory: root.appendingPathComponent("pet", isDirectory: true),
                        bundledPetDirectory: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true),
                        defaults: defaults)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await runChecks()
                UserDefaults.standard.removePersistentDomain(forName: suiteName)
                controller.panel.close()
                controller.terminalController?.hide()
                print("PASS: terminal window, attachment click, drawing composer, hidden pet, close/minimize, return")
                NSApp.terminate(nil)
            } catch {
                UserDefaults.standard.removePersistentDomain(forName: suiteName)
                fputs("Terminal window check failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private func runChecks() async throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        try checkModel(defaults: defaults)
        model = makeModel(defaults: defaults)
        model.realtimeState = .connected
        model.isPartnerReachable = true
        controller = OverlayPanelController(model: model)
        controller.show()
        model.requestChatFocus()
        model.setMessageEditing(true)
        try await Task.sleep(for: .milliseconds(300))
        try capture(controller.panel, name: "terminal-button-preview.png")
        click(controller.panel, x: 96, y: 198)
        try await Task.sleep(for: .milliseconds(400))
        guard model.isTerminalMode, !controller.panel.isVisible,
              let terminal = controller.terminalController, terminal.window.isVisible else {
            throw Failure.failed("Mode switch did not hide pet and open terminal")
        }
        model.onSend = { _ in }
        model.messageDraft = "현재 브랜치에서 입력 처리 흐름부터 확인해줘."
        try await Task.sleep(for: .milliseconds(150))
        click(terminal.window, x: terminal.window.contentView!.bounds.width - 46, y: 86)
        model.receive("관련 파일을 읽고 입력 처리와 이미지 경로를 확인했습니다.")
        model.send("이 부분은 이렇게 정리하면 될 것 같아.")
        let drawing = DrawingMessage(strokes: [
            .init(color: .blue, width: 4, points: [
                .init(x: 0.1, y: 0.25), .init(x: 0.4, y: 0.25), .init(x: 0.4, y: 0.7),
                .init(x: 0.1, y: 0.7), .init(x: 0.1, y: 0.25),
            ]),
            .init(color: .purple, width: 4, points: [
                .init(x: 0.6, y: 0.25), .init(x: 0.9, y: 0.25), .init(x: 0.9, y: 0.7),
                .init(x: 0.6, y: 0.7), .init(x: 0.6, y: 0.25),
            ]),
            .init(color: .black, width: 3, points: [
                .init(x: 0.4, y: 0.48), .init(x: 0.6, y: 0.48),
                .init(x: 0.55, y: 0.4), .init(x: 0.6, y: 0.48), .init(x: 0.55, y: 0.56),
            ]),
        ])
        model.receiveDrawing(drawing)
        try await Task.sleep(for: .milliseconds(1200))
        guard model.terminalHistory.first?.text == "현재 브랜치에서 입력 처리 흐름부터 확인해줘.",
              model.messageDraft.isEmpty, model.drawingLetter == nil, !controller.panel.isVisible else {
            throw Failure.failed("Messages or drawings revealed the pet")
        }
        try capture(terminal.window, name: "terminal-mode-preview.png")
        let imagePoint = try imageLinkPoint(in: terminal.window)
        click(terminal.window, x: imagePoint.x, y: imagePoint.y)
        try await waitFor("Click did not open the image preview") { self.visiblePopup(excluding: terminal.window) != nil }
        let preview = visiblePopup(excluding: terminal.window)!
        try capture(preview, name: "terminal-image-preview.png")
        click(preview, x: preview.contentView!.bounds.width - 22, y: preview.contentView!.bounds.height - 24)
        try await waitFor("Image close button failed") { !preview.isVisible }
        click(terminal.window, x: terminal.window.contentView!.bounds.width - 84, y: 86)
        try await waitFor("Drawing composer did not open") { self.visiblePopup(excluding: terminal.window) != nil }
        try capture(visiblePopup(excluding: terminal.window)!, name: "terminal-drawing-preview.png")
        terminal.window.performClose(nil)
        try await Task.sleep(for: .milliseconds(250))
        guard !model.isTerminalMode, !terminal.window.isVisible, controller.panel.isVisible else {
            throw Failure.failed("Red close button did not return to CoupleMon")
        }
        guard !NSApp.windows.contains(where: {
            $0.isVisible && $0 !== controller.panel && $0.frame.width > 250 && $0.frame.height > 200
        }) else {
            throw Failure.failed("Closing the terminal left an attachment popup visible")
        }
        model.setTerminalMode(true)
        model.receiveDrawing(drawing)
        controller.focusChatInput()
        model.requestChatFocus()
        try await Task.sleep(for: .milliseconds(250))
        guard terminal.window.isVisible, !controller.panel.isVisible,
              model.chatFocusRequest == 1 else { throw Failure.failed("Chat shortcut revealed hidden input") }
        terminal.window.miniaturize(nil)
        model.receive("다시 확인했어.")
        try await Task.sleep(for: .milliseconds(250))
        guard !controller.panel.isVisible else { throw Failure.failed("Minimized window exposed pet") }
        controller.show()
        try await Task.sleep(for: .milliseconds(300))
        guard !terminal.window.isMiniaturized else { throw Failure.failed("Window did not deminiaturize") }
        click(terminal.window, x: terminal.window.contentView!.bounds.width - 18,
              y: terminal.window.contentView!.bounds.height - 17)
        try await Task.sleep(for: .milliseconds(250))
        guard !terminal.window.isVisible, controller.panel.isVisible,
              model.drawingLetter == nil else { throw Failure.failed("Explicit return failed") }
    }

    private func checkModel(defaults: UserDefaults) throws {
        let probe = makeModel(defaults: defaults)
        let image = DrawingMessage(strokes: [.init(color: .blue, width: 4, points: [.init(x: 0.5, y: 0.5)])])
        probe.receiveDrawing(image)
        probe.messageDraft = "  draft across modes  "
        probe.setTerminalMode(true)
        guard probe.drawingLetter == nil, probe.terminalHistory.last?.drawing == image,
              probe.messageDraft == "  draft across modes  " else { throw Failure.failed("Mode switch lost data") }
        var sent: [String] = []
        probe.onSend = { sent.append($0) }
        probe.sendDraft()
        probe.sendDraft()
        probe.requestChatFocus()
        probe.showBubble()
        probe.setMessageEditing(true)
        guard sent == ["draft across modes"], probe.messageDraft.isEmpty,
              probe.chatFocusRequest == 0, probe.terminalFocusRequest == 1,
              !probe.isBubbleVisible, !probe.isEditingMessage else { throw Failure.failed("Draft or focus routing") }
        for index in 1...205 { probe.receive("line \(index)") }
        probe.receiveDrawing(image)
        guard probe.terminalHistory.count == 200, probe.messageHistory.count == 5,
              probe.terminalHistory.last?.attachmentNumber == 2,
              probe.drawingLetter == nil else { throw Failure.failed("History limit or stable image numbering") }
        probe.clearMessage()
        probe.receiveDrawing(image)
        guard probe.terminalHistory.last?.attachmentNumber == 1 else { throw Failure.failed("Clear image numbering") }
        probe.setTerminalMode(false)
        guard probe.drawingLetter == nil else { throw Failure.failed("Terminal image replayed as a letter") }
        probe.receiveDrawing(image)
        guard probe.drawingLetter != nil else { throw Failure.failed("Normal letter mode failed to resume") }
        probe.clearMessage()
        print("PASS: shared draft, mode switches, focus routing, stable attachments, bounded history, normal mode")
    }

    private func visiblePopup(excluding main: NSWindow) -> NSWindow? {
        NSApp.windows.first {
            $0.isVisible && $0 !== main && $0 !== controller.panel && $0.frame.width > 250 && $0.frame.height > 200
        }
    }

    private func waitFor(_ description: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            guard Date() < deadline else { throw Failure.failed(description) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func click(_ window: NSWindow, x: CGFloat, y: CGFloat) {
        let view = window.contentView!
        let origin = view.convert(NSPoint(x: view.bounds.minX,
                                          y: view.isFlipped ? view.bounds.maxY : view.bounds.minY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: NSPoint(x: origin.x + x, y: origin.y + y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1
            )!
            window.sendEvent(event)
        }
    }

    private func imageLinkPoint(in window: NSWindow) throws -> CGPoint {
        let view = window.contentView!
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = 0, maxY = 0
        for y in 0..<Int((view.bounds.height - 140) * scale) {
            for x in Int(200 * scale)..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.blueComponent > 0.85, (0.3...0.7).contains(color.redComponent),
                      (0.5...0.85).contains(color.greenComponent) else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { throw Failure.failed("Numbered image link was not rendered") }
        return CGPoint(x: CGFloat(minX + maxX) / 2 / scale,
                       y: view.bounds.height - CGFloat(minY + maxY) / 2 / scale)
    }

    private func capture(_ window: NSWindow, name: String) throws {
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure.failed("Could not capture \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure.failed("Could not encode screenshot")
        }
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        try data.write(to: screenshots.appendingPathComponent(name))
    }
}

@main
struct TerminalWindowCheckApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = TerminalWindowCheck()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
