import AppKit
import SwiftUI

@MainActor
final class TerminalWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        super.init()
        window.title = "Codex"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed: 0.145, green: 0.157, blue: 0.184, alpha: 1)
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: TerminalWorkspaceView(model: model))
        window.center()
        window.setFrameAutosaveName("TerminalWorkspace")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        model.requestTerminalFocus()
    }

    func hide() {
        window.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        model.setTerminalMode(false)
        return false
    }
}
