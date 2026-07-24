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
        menuBarController.onChooseHatchPet = { [weak self] in self?.chooseHatchPet() }
        menuBarController.onResetCharacter = { [weak self] in
            do {
                try self?.model.resetCharacter()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
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

    private func chooseHatchPet() {
        let picker = NSOpenPanel()
        let petsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/pets", isDirectory: true)
        picker.directoryURL = FileManager.default.fileExists(atPath: petsDirectory.path) ? petsDirectory : nil
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.message = "hatch-pet으로 만든 v2 펫 폴더를 선택하세요."
        picker.prompt = "펫 선택"

        guard picker.runModal() == .OK, let url = picker.url else { return }

        do {
            try model.selectHatchPet(from: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
