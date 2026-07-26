import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let realtime = CoupleRealtimeService()
    private let updateService = UpdateService()
    private var overlayController: OverlayPanelController!
    private var menuBarController: MenuBarController!
    private var isCheckingForUpdates = false
    private var chatHotKey: EventHotKeyRef?
    private var todoHotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        overlayController = OverlayPanelController(model: model)
        menuBarController = MenuBarController()
        menuBarController.onToggleOverlay = { [weak self] in self?.overlayController.toggle() }
        menuBarController.onChooseCharacter = { [weak self] in self?.chooseCharacter() }
        menuBarController.onChooseHatchPet = { [weak self] in self?.chooseHatchPet() }
        menuBarController.onIncreaseCharacterSize = { [weak self] in self?.model.resizeCharacter(by: 0.1) }
        menuBarController.onDecreaseCharacterSize = { [weak self] in self?.model.resizeCharacter(by: -0.1) }
        menuBarController.onResetCharacterSize = { [weak self] in self?.model.resetCharacterSize() }
        menuBarController.onConfigureRealtime = { [weak self] in self?.configureRealtime() }
        menuBarController.onCopyRoomCode = { [weak self] in self?.copyRoomCode() }
        menuBarController.onCheckForUpdates = { [weak self] in self?.checkForUpdates() }
        menuBarController.onToggleTodoList = { [weak self] in self?.toggleTodoList() }
        menuBarController.onToggleTodoVisibility = { [weak self] in self?.toggleTodoVisibility() }
        menuBarController.onFocusChatInput = { [weak self] in self?.focusChatInput() }
        menuBarController.onResetCharacter = { [weak self] in
            do {
                try self?.model.resetCharacter()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        menuBarController.onClearMessage = { [weak self] in self?.model.clearMessage() }
        menuBarController.setCharacterScale(model.characterScale)
        menuBarController.setTodoEnabled(model.isTodoEnabled)

        model.onSend = { [weak self] message in self?.realtime.send(message) }
        model.onCharacterScaleChange = { [weak self] scale in
            self?.menuBarController.setCharacterScale(scale)
        }
        model.onTodoVisibilityChange = { [weak self] isVisible in
            self?.overlayController.setTodoVisible(isVisible)
        }
        realtime.onMessage = { [weak self] message in self?.model.receive(message) }
        realtime.onStateChange = { [weak self] state in
            self?.menuBarController.setRealtimeState(state)
        }

        if
            let saved = RealtimeSettings.load(),
            let settings = try? saved.validated()
        {
            menuBarController.setRoomCodeAvailable(true)
            connectRealtime(using: settings)
        }
        installHotKeys()
        overlayController.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let chatHotKey { UnregisterEventHotKey(chatHotKey) }
        if let todoHotKey { UnregisterEventHotKey(todoHotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installEditMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: "CoupleMon 종료",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
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
        picker.message = "Codex가 만든 v1 또는 v2 펫 폴더를 선택하세요."
        picker.prompt = "펫 선택"

        guard picker.runModal() == .OK, let url = picker.url else { return }

        do {
            try model.selectHatchPet(from: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func configureRealtime() {
        let saved = RealtimeSettings.load()
        let urlField = NSTextField(string: saved?.projectURL ?? "")
        urlField.placeholderString = "https://프로젝트.supabase.co"
        let keyField = NSSecureTextField(string: saved?.publishableKey ?? "")
        keyField.placeholderString = "sb_publishable_... 또는 anon JWT"
        let roomField = NSTextField(string: saved?.roomCode ?? RealtimeSettings.makeRoomCode())

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Project URL"), urlField],
            [NSTextField(labelWithString: "Client key"), keyField],
            [NSTextField(labelWithString: "연결 코드"), roomField],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 360
        grid.rowSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 470, height: 82)

        let alert = NSAlert()
        alert.messageText = "Supabase 실시간 연결"
        alert.informativeText = "두 Mac에 같은 값과 연결 코드를 입력하세요. 메시지는 저장하지 않고 실시간으로만 전달합니다."
        alert.accessoryView = grid
        alert.addButton(withTitle: "저장하고 연결")
        alert.addButton(withTitle: "취소")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let settings = try RealtimeSettings(
                projectURL: urlField.stringValue,
                publishableKey: keyField.stringValue,
                roomCode: roomField.stringValue
            ).validated()
            try settings.save()
            menuBarController.setRoomCodeAvailable(true)
            connectRealtime(using: settings)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func connectRealtime(using settings: RealtimeSettings) {
        Task { [weak self] in
            await self?.realtime.connect(to: settings)
        }
    }

    private func copyRoomCode() {
        guard let code = RealtimeSettings.load()?.normalizedRoomCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    private func toggleTodoList() {
        model.setTodoEnabled(!model.isTodoEnabled)
        menuBarController.setTodoEnabled(model.isTodoEnabled)
    }

    private func focusChatInput() {
        overlayController.focusChatInput()
        DispatchQueue.main.async { [weak self] in self?.model.requestChatFocus() }
    }

    private func toggleTodoVisibility() {
        if !model.isTodoEnabled {
            model.setTodoEnabled(true)
            menuBarController.setTodoEnabled(true)
        }
        overlayController.show()
        model.toggleTodoVisibility()
    }

    private func installHotKeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                guard GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                ) == noErr, hotKeyID.signature == 0x434D4F4E else {
                    return OSStatus(eventNotHandledErr)
                }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    if hotKeyID.id == 1 {
                        appDelegate.focusChatInput()
                    } else if hotKeyID.id == 2 {
                        appDelegate.toggleTodoVisibility()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )
        let hotKeyID = EventHotKeyID(signature: 0x434D4F4E, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &chatHotKey
        )
        let todoHotKeyID = EventHotKeyID(signature: 0x434D4F4E, id: 2)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(controlKey | optionKey),
            todoHotKeyID,
            GetApplicationEventTarget(),
            0,
            &todoHotKey
        )
    }

    private func checkForUpdates() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true

        Task { [weak self] in
            guard let self else { return }
            defer { isCheckingForUpdates = false }

            do {
                let release = try await updateService.latestRelease()
                guard let version = release.version else {
                    throw UpdateService.UpdateError.invalidResponse
                }
                guard UpdateService.isNewer(version, than: UpdateService.currentVersion) else {
                    showUpdateAlert(
                        title: "최신 버전입니다",
                        message: "현재 CoupleMon \(UpdateService.currentVersion)을 사용 중입니다."
                    )
                    return
                }

                let alert = NSAlert()
                alert.messageText = "CoupleMon \(version) 업데이트"
                alert.informativeText = "SHA-256을 검증한 GitHub Release 패키지를 내려받아 Installer를 엽니다. Developer ID 공증 전이라 macOS 보안 경고가 표시될 수 있습니다."
                alert.addButton(withTitle: "다운로드 및 설치")
                alert.addButton(withTitle: "취소")
                guard alert.runModal() == .alertFirstButtonReturn else { return }

                let installerURL = try await updateService.downloadInstaller(from: release)
                guard NSWorkspace.shared.open(installerURL) else {
                    throw UpdateService.UpdateError.invalidDownload
                }
            } catch {
                showUpdateAlert(title: "업데이트 확인 실패", message: error.localizedDescription)
            }
        }
    }

    private func showUpdateAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
