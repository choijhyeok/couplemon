import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayPanelController {
    let panel: NSPanel
    private let compactSize = CGSize(width: 320, height: 410)
    private let expandedSize = CGSize(width: 600, height: 410)

    init(model: AppModel) {
        panel = OverlayPanel(
            contentRect: CGRect(origin: .zero, size: compactSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: CompanionView(model: model))

        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(
            CGPoint(x: visibleFrame.maxX - compactSize.width - 24, y: visibleFrame.minY + 24)
        )
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func toggle() {
        panel.isVisible ? panel.orderOut(nil) : show()
    }

    func setTodoVisible(_ isVisible: Bool) {
        let size = isVisible ? expandedSize : compactSize
        guard panel.frame.size != size else { return }
        let oldFrame = panel.frame
        let origin = CGPoint(x: oldFrame.maxX - size.width, y: oldFrame.minY)
        panel.setFrame(CGRect(origin: origin, size: size), display: true, animate: true)
    }

    func focusChatInput() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismissChatInput() {
        panel.makeFirstResponder(nil)
    }
}
