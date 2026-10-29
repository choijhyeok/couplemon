import AppKit

@MainActor
final class MenuBarController: NSObject {
    var onToggleOverlay: (() -> Void)?
    var onChooseCharacter: (() -> Void)?
    var onChooseHatchPet: (() -> Void)?
    var onResetCharacter: (() -> Void)?
    var onClearMessage: (() -> Void)?
    var onToggleTodoList: (() -> Void)?
    var onToggleTodoVisibility: (() -> Void)?
    var onToggleChatInput: (() -> Void)?
    var onToggleTerminalMode: (() -> Void)?
    var onIncreaseCharacterSize: (() -> Void)?
    var onDecreaseCharacterSize: (() -> Void)?
    var onResetCharacterSize: (() -> Void)?
    var onConfigureRealtime: (() -> Void)?
    var onReconnect: (() -> Void)?
    var onConnectionHelp: (() -> Void)?
    var onCopyRoomCode: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var characterSizeItem: NSMenuItem!
    private var realtimeStatusItem: NSMenuItem!
    private var copyRoomCodeItem: NSMenuItem!
    private var todoListItem: NSMenuItem!
    private var reconnectItem: NSMenuItem!
    private var terminalModeItem: NSMenuItem!
    private var realtimeState: CoupleRealtimeState = .notConfigured
    private var isPartnerReachable = false

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "CoupleMon")

        let menu = NSMenu()
        menu.addItem(item("보이기 / 숨기기", action: #selector(toggleOverlay)))
        terminalModeItem = item("터미널 모드 열기", action: #selector(toggleTerminalMode))
        menu.addItem(terminalModeItem)
        menu.addItem(.separator())
        menu.addItem(item("Codex 애니메이션 펫 선택…", action: #selector(chooseHatchPet)))
        menu.addItem(item("일반 이미지 선택…", action: #selector(chooseCharacter)))
        menu.addItem(item("기본 캐릭터로 되돌리기", action: #selector(resetCharacter)))

        characterSizeItem = NSMenuItem(title: "캐릭터 크기 (100%)", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "캐릭터 크기")
        sizeMenu.addItem(item("크게", action: #selector(increaseCharacterSize), keyEquivalent: "+"))
        sizeMenu.addItem(item("작게", action: #selector(decreaseCharacterSize), keyEquivalent: "-"))
        sizeMenu.addItem(item("기본 크기", action: #selector(resetCharacterSize)))
        menu.addItem(characterSizeItem)
        menu.setSubmenu(sizeMenu, for: characterSizeItem)

        menu.addItem(item("말풍선 지우기", action: #selector(clearMessage)))
        todoListItem = item("Todo List", action: #selector(toggleTodoList))
        menu.addItem(todoListItem)
        menu.addItem(item("Todo List 열기 / 닫기 (⌃⌥T)", action: #selector(toggleTodoVisibility)))
        menu.addItem(item("채팅 입력창 열기 / 닫기 (⌃⌥Space)", action: #selector(toggleChatInput)))
        menu.addItem(.separator())
        menu.addItem(item("실시간 연결 설정…", action: #selector(configureRealtime)))
        reconnectItem = item("지금 다시 연결", action: #selector(reconnect))
        reconnectItem.isEnabled = false
        menu.addItem(reconnectItem)
        menu.addItem(item("연결 오류 및 해결 방법…", action: #selector(connectionHelp)))
        copyRoomCodeItem = item("연결 코드 복사", action: #selector(copyRoomCode))
        copyRoomCodeItem.isEnabled = false
        menu.addItem(copyRoomCodeItem)
        realtimeStatusItem = NSMenuItem(title: CoupleRealtimeState.notConfigured.menuTitle, action: nil, keyEquivalent: "")
        realtimeStatusItem.isEnabled = false
        menu.addItem(realtimeStatusItem)
        menu.addItem(item("업데이트 확인…", action: #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(item("CoupleMon 종료", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func setCharacterScale(_ scale: CGFloat) {
        characterSizeItem.title = "캐릭터 크기 (\(Int((scale * 100).rounded()))%)"
    }

    func setRealtimeState(_ state: CoupleRealtimeState) {
        realtimeState = state
        updateRealtimeTitle()
        if case let .failed(reason) = state {
            realtimeStatusItem.toolTip = reason
        } else {
            realtimeStatusItem.toolTip = nil
        }
    }

    func setPartnerReachable(_ reachable: Bool) {
        isPartnerReachable = reachable
        updateRealtimeTitle()
    }

    private func updateRealtimeTitle() {
        realtimeStatusItem.title = realtimeState == .connected
            ? (isPartnerReachable ? "실시간: 상대 응답 확인됨" : "실시간: 서버 연결됨 · 상대 응답 대기")
            : realtimeState.menuTitle
    }

    func setRoomCodeAvailable(_ isAvailable: Bool) {
        copyRoomCodeItem.isEnabled = isAvailable
        reconnectItem.isEnabled = isAvailable
    }

    func setTodoEnabled(_ isEnabled: Bool) {
        todoListItem.state = isEnabled ? .on : .off
    }

    func setTerminalMode(_ enabled: Bool) {
        terminalModeItem.title = enabled ? "기본 화면으로 돌아가기" : "터미널 모드 열기"
        statusItem.button?.image = NSImage(
            systemSymbolName: enabled ? "terminal" : "heart.fill",
            accessibilityDescription: enabled ? "Codex" : "CoupleMon"
        )
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
    @objc private func toggleTodoList() { onToggleTodoList?() }
    @objc private func toggleTodoVisibility() { onToggleTodoVisibility?() }
    @objc private func toggleChatInput() { onToggleChatInput?() }
    @objc private func toggleTerminalMode() { onToggleTerminalMode?() }
    @objc private func increaseCharacterSize() { onIncreaseCharacterSize?() }
    @objc private func decreaseCharacterSize() { onDecreaseCharacterSize?() }
    @objc private func resetCharacterSize() { onResetCharacterSize?() }
    @objc private func configureRealtime() { onConfigureRealtime?() }
    @objc private func reconnect() { onReconnect?() }
    @objc private func connectionHelp() { onConnectionHelp?() }
    @objc private func copyRoomCode() { onCopyRoomCode?() }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
