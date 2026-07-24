import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var overlayController: OverlayPanelController!
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = OverlayPanelController(model: model)
        menuBarController = MenuBarController()
        menuBarController.onToggleOverlay = { [weak self] in self?.overlayController.toggle() }
        menuBarController.onChooseCharacter = { [weak self] in self?.chooseCharacter() }
        menuBarController.onResetCharacter = { [weak self] in self?.model.resetCharacter() }
        menuBarController.onClearMessage = { [weak self] in self?.model.clearMessage() }
        overlayController.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func chooseCharacter() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.message = "도트 캐릭터 이미지를 선택하세요."

        guard picker.runModal() == .OK, let url = picker.url else { return }

        do {
            try model.selectCharacter(from: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
