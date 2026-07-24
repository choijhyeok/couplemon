import AppKit

@MainActor
final class MenuBarController: NSObject {
    var onToggleOverlay: (() -> Void)?
    var onChooseCharacter: (() -> Void)?
    var onChooseHatchPet: (() -> Void)?
    var onResetCharacter: (() -> Void)?
    var onClearMessage: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "CoupleMon")

        let menu = NSMenu()
        menu.addItem(item("보이기 / 숨기기", action: #selector(toggleOverlay)))
        menu.addItem(.separator())
        menu.addItem(item("Codex 애니메이션 펫 선택…", action: #selector(chooseHatchPet)))
        menu.addItem(item("일반 이미지 선택…", action: #selector(chooseCharacter)))
        menu.addItem(item("기본 캐릭터로 되돌리기", action: #selector(resetCharacter)))
        menu.addItem(item("말풍선 지우기", action: #selector(clearMessage)))
        menu.addItem(.separator())
        menu.addItem(item("CoupleMon 종료", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func toggleOverlay() { onToggleOverlay?() }
    @objc private func chooseCharacter() { onChooseCharacter?() }
    @objc private func chooseHatchPet() { onChooseHatchPet?() }
    @objc private func resetCharacter() { onResetCharacter?() }
    @objc private func clearMessage() { onClearMessage?() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
