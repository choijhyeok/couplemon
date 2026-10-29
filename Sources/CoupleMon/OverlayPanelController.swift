import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayPanelController {
    let panel: NSPanel
    private let model: AppModel
    private(set) var terminalController: TerminalWindowController?
    var onTerminalModeChange: ((Bool) -> Void)?
    private let compactSize = CGSize(width: 320, height: 410)
    private let expandedSize = CGSize(width: 600, height: 410)

    init(model: AppModel) {
        self.model = model
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
        model.onTerminalModeChange = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.panel.makeFirstResponder(nil)
                self.panel.orderOut(nil)
                self.showTerminal()
            } else {
                self.terminalController?.hide()
                self.panel.orderFrontRegardless()
                self.model.showBubble()
            }
            self.onTerminalModeChange?(enabled)
        }
    }

    func show() {
        if model.isTerminalMode { showTerminal() } else { panel.orderFrontRegardless() }
    }

    func toggle() {
        if model.isTerminalMode {
            if terminalController?.window.isVisible == true { terminalController?.hide() } else { showTerminal() }
            return
        }
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
        if model.isTerminalMode {
            showTerminal()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismissChatInput() {
        if model.isTerminalMode {
            terminalController?.window.makeFirstResponder(nil)
            return
        }
        panel.makeFirstResponder(nil)
    }

    private func showTerminal() {
        if terminalController == nil { terminalController = TerminalWindowController(model: model) }
        terminalController?.show()
    }
}
