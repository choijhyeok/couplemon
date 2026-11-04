import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    struct ConversationMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isLocal: Bool
        var drawing: DrawingMessage? = nil
        var attachmentNumber: Int? = nil

        var isImageAttachment: Bool {
            drawing != nil || CoupleMonEmoticon(messageValue: text) != nil
                || CoupleMonAnimatedEmoticon(messageValue: text) != nil
        }
    }

    struct DrawingLetter: Identifiable, Equatable {
        let id = UUID()
        let drawing: DrawingMessage
        let isLocal: Bool
    }

    static let letterUnfoldDuration = 0.45
    static let letterReadingDuration = 2.0

    enum TodoListKind: String, CaseIterable, Identifiable {
        case mine
        case partner
        case couple

        var id: String { rawValue }
        var title: String {
            switch self {
            case .mine: "내 할 일"
            case .partner: "상대"
            case .couple: "커플"
            }
        }
    }

    enum TodoScope: String, Codable {
        case personal
        case couple
    }

    struct TodoItem: Codable, Identifiable, Equatable {
        let id: UUID
        let text: String
        var isCompleted: Bool
        var scope: TodoScope
        var ownerID: UUID?

        init(
            id: UUID,
            text: String,
            isCompleted: Bool,
            scope: TodoScope = .personal,
            ownerID: UUID? = nil
        ) {
            self.id = id
            self.text = text
            self.isCompleted = isCompleted
            self.scope = scope
            self.ownerID = ownerID
        }

        private enum CodingKeys: String, CodingKey {
            case id, text, isCompleted, scope, ownerID
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(UUID.self, forKey: .id)
            text = try values.decode(String.self, forKey: .text)
            isCompleted = try values.decode(Bool.self, forKey: .isCompleted)
            scope = try values.decodeIfPresent(TodoScope.self, forKey: .scope) ?? .personal
            ownerID = try values.decodeIfPresent(UUID.self, forKey: .ownerID)
        }
    }

    struct TodoMutation: Codable, Equatable {
        enum Action: String, Codable {
            case upsert
            case delete
        }

        let action: Action
        let item: TodoItem?
        let id: UUID
        let roomCode: String?

        static func upsert(_ item: TodoItem, roomCode: String?) -> Self {
            Self(action: .upsert, item: item, id: item.id, roomCode: roomCode)
        }

        static func delete(_ id: UUID, roomCode: String?) -> Self {
            Self(action: .delete, item: nil, id: id, roomCode: roomCode)
        }
    }

    enum CharacterError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            "이미지 파일을 읽을 수 없습니다."
        }
    }

    @Published private(set) var displayedMessage: String
    @Published private(set) var messageHistory: [ConversationMessage] = []
    @Published private(set) var terminalHistory: [ConversationMessage] = []
    @Published private(set) var isTerminalMode = false
    @Published private(set) var terminalFocusRequest = 0
    @Published var messageDraft = ""
    @Published private(set) var displayedDrawing: DrawingMessage?
    @Published private(set) var drawingLetter: DrawingLetter?
    @Published private(set) var isDrawingLetterOpen = false
    @Published var realtimeState: CoupleRealtimeState = .notConfigured
    @Published var isPartnerReachable = false
    @Published var sendError: String?
    @Published private(set) var characterImage: NSImage?
    @Published private(set) var hatchPet: HatchPet?
    @Published private(set) var pet3D: Pet3DAsset?
    let together: CouplePetSession
    @Published private(set) var petProgress: PetProgress
    @Published private(set) var equippedRewardLevel: Int?
    var equippedReward: PetLevelReward? { equippedRewardLevel.flatMap(PetLevelReward.reward) }
    var unlockedRewards: [PetLevelReward] {
        guard petProgress.level >= 2 else { return [] }
        return (2...petProgress.level).compactMap(PetLevelReward.reward)
    }
    var pet3DModelURL: URL? { pet3D.map { pet3DLibrary.modelURL(for: $0) } }
    @Published private(set) var petActivity: PetActivity?
    @Published private(set) var isRandom3DEnabled: Bool
    @Published private(set) var random3DInterval: Int
    static let random3DIntervals = [3, 5, 10, 15, 30]
    @Published private(set) var characterScale: CGFloat
    @Published private(set) var isBubbleVisible = true
    @Published private(set) var todoItems: [TodoItem]
    @Published private(set) var todoSyncError: String?
    @Published private(set) var isTodoEnabled: Bool
    @Published private(set) var isTodoVisible = false
    @Published private(set) var chatFocusRequest = 0

    var onSend: ((String) -> Void)?
    var onSendDrawing: ((DrawingMessage) -> Void)?
    var onCharacterScaleChange: ((CGFloat) -> Void)?
    var onTodoMutation: (() -> Void)?
    var onTerminalModeChange: ((Bool) -> Void)?

    private let characterURL: URL
    private let petDirectory: URL
    private let bundledPetDirectory: URL?
    private let defaults: UserDefaults
    let pet3DLibrary: Pet3DLibrary
    private(set) var todoOwnerID: UUID
    private(set) var pendingTodoMutations: [TodoMutation]
    private(set) var todoMutationRevision = 0
    private var bubbleDismissTask: Task<Void, Never>?
    private var letterDismissTask: Task<Void, Never>?
    private var pendingDrawingLetters: [DrawingLetter] = []
    private var nextAttachmentNumber = 1
    private(set) var isEditingMessage = false

    init(
        characterURL: URL? = nil,
        petDirectory: URL? = nil,
        bundledPetDirectory: URL? = Bundle.main.resourceURL?
            .appendingPathComponent("DefaultPet", isDirectory: true),
        defaults: UserDefaults = .standard,
        pet3DLibrary: Pet3DLibrary? = nil
    ) {
        let resolvedCharacterURL = characterURL ?? Self.defaultCharacterURL
        let resolvedPetDirectory = petDirectory ?? Self.defaultPetDirectory
        self.characterURL = resolvedCharacterURL
        self.petDirectory = resolvedPetDirectory
        self.bundledPetDirectory = bundledPetDirectory
        self.defaults = defaults
        isRandom3DEnabled = defaults.bool(forKey: Self.random3DEnabledKey)
        let savedInterval = defaults.integer(forKey: Self.random3DIntervalKey)
        random3DInterval = Self.random3DIntervals.contains(savedInterval) ? savedInterval : 5
        petProgress = PetProgress(experience: defaults.integer(forKey: Self.petExperienceKey))
        let savedReward = defaults.integer(forKey: Self.petRewardKey)
        let savedLevel = PetProgress(experience: defaults.integer(forKey: Self.petExperienceKey)).level
        equippedRewardLevel = savedLevel < 2 ? nil : ((2...savedLevel).contains(savedReward) ? savedReward : savedLevel)
        let library = pet3DLibrary ?? Pet3DLibrary(directory: resolvedCharacterURL.deletingLastPathComponent()
            .appendingPathComponent("3DCharacters", isDirectory: true))
        self.pet3DLibrary = library
        together = CouplePetSession(cache: resolvedCharacterURL.deletingLastPathComponent().appendingPathComponent("PartnerCharacters"))
        let saved3DID = defaults.string(forKey: Self.pet3DSelectionKey)
        pet3D = (try? library.assets())?.first { $0.id.uuidString == saved3DID }
        let resolvedTodoOwnerID: UUID
        if
            let value = defaults.string(forKey: Self.todoOwnerIDKey),
            let savedID = UUID(uuidString: value)
        {
            resolvedTodoOwnerID = savedID
        } else {
            resolvedTodoOwnerID = UUID()
            defaults.set(resolvedTodoOwnerID.uuidString, forKey: Self.todoOwnerIDKey)
        }
        todoOwnerID = resolvedTodoOwnerID
        displayedMessage = "오늘도 같이 있자 💛"
        let loadedPet = try? HatchPetPackage.load(from: resolvedPetDirectory)
        let loadedImage = loadedPet == nil ? NSImage(contentsOf: resolvedCharacterURL) : nil
        let defaultPet = loadedPet == nil && loadedImage == nil
            ? bundledPetDirectory.flatMap { try? HatchPetPackage.load(from: $0) }
            : nil
        hatchPet = loadedPet ?? defaultPet
        characterImage = loadedImage
        let loadedTodos = defaults.data(forKey: Self.todoItemsKey)
            .flatMap { try? JSONDecoder().decode([TodoItem].self, from: $0) } ?? []
        todoItems = loadedTodos.map { item in
            var item = item
            if item.scope == .personal, item.ownerID == nil { item.ownerID = resolvedTodoOwnerID }
            return item
        }
        pendingTodoMutations = defaults.data(forKey: Self.pendingTodoMutationsKey)
            .flatMap { try? JSONDecoder().decode([TodoMutation].self, from: $0) } ?? []
        todoSyncError = nil
        isTodoEnabled = defaults.bool(forKey: Self.todoEnabledKey)
        let savedScale = defaults.object(forKey: Self.characterScaleKey) == nil
            ? 1
            : defaults.double(forKey: Self.characterScaleKey)
        characterScale = CGFloat(min(1.3, max(0.7, savedScale)))
        together.setLocal(url: pet3DModelURL, name: pet3D?.name ?? "캐릭터")
        together.suspended = isTerminalMode
    }

    func send(_ rawValue: String) {
        let message = MessageText.normalize(rawValue)
        guard !message.isEmpty else { return }
        record(message, isLocal: true)
        let isEmoji = CoupleMonEmoticon(messageValue: message) != nil
            || CoupleMonAnimatedEmoticon(messageValue: message) != nil || PetProgress.isEmojiOnly(message)
        awardExperience(isEmoji ? .emoji : .chat)
        onSend?(message)
    }

    func sendDraft() {
        guard !MessageText.normalize(messageDraft).isEmpty else { return }
        send(messageDraft)
        messageDraft = ""
    }

    func setTerminalMode(_ enabled: Bool) {
        guard isTerminalMode != enabled else { return }
        isTerminalMode = enabled
        together.suspended = enabled
        if enabled {
            dismissTodo()
            petActivity = nil
            letterDismissTask?.cancel()
            letterDismissTask = nil
            pendingDrawingLetters.removeAll()
            drawingLetter = nil
            isDrawingLetterOpen = false
            dismissChatInput()
        }
        onTerminalModeChange?(enabled)
    }

    func requestTerminalFocus() {
        terminalFocusRequest += 1
    }

    func receive(_ rawValue: String) {
        let message = MessageText.normalize(rawValue)
        guard !message.isEmpty else { return }
        record(message, isLocal: false)
    }

    func sendDrawing(_ drawing: DrawingMessage) {
        guard drawing.isValid else { return }
        record("손그림", isLocal: true, drawing: drawing)
        awardExperience(.drawing)
        enqueueDrawingLetter(drawing, isLocal: true)
        onSendDrawing?(drawing)
    }

    func receiveDrawing(_ drawing: DrawingMessage) {
        guard drawing.isValid else { return }
        record("손그림", isLocal: false, drawing: drawing)
        enqueueDrawingLetter(drawing, isLocal: false)
    }

    func openDrawingLetter(id: UUID) {
        guard drawingLetter?.id == id, !isDrawingLetterOpen else { return }
        isDrawingLetterOpen = true
        letterDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.letterUnfoldDuration + Self.letterReadingDuration))
            } catch { return }
            self?.dismissDrawingLetter(id: id)
        }
    }

    func dismissDrawingLetter(id: UUID) {
        guard drawingLetter?.id == id else { return }
        letterDismissTask?.cancel()
        letterDismissTask = nil
        isDrawingLetterOpen = false
        drawingLetter = nil
        dismissChatInput()
        presentNextDrawingLetter()
    }

    private func enqueueDrawingLetter(_ drawing: DrawingMessage, isLocal: Bool) {
        guard !isTerminalMode else { return }
        pendingDrawingLetters.append(DrawingLetter(drawing: drawing, isLocal: isLocal))
        dismissChatInput()
        presentNextDrawingLetter()
    }

    private func presentNextDrawingLetter() {
        guard drawingLetter == nil, !pendingDrawingLetters.isEmpty else { return }
        drawingLetter = pendingDrawingLetters.removeFirst()
    }

    var connectionNotice: String? {
        if let sendError { return sendError }
        switch realtimeState {
        case .notConfigured: return "연결 설정 전에는 내 화면에만 표시됩니다."
        case .connecting: return "연결 중 · 지금 보내면 상대에게 전달되지 않습니다."
        case .failed: return "연결 끊김 · 메뉴에서 연결 오류 및 해결 방법을 확인하세요."
        case .connected:
            return isPartnerReachable ? nil : "상대 응답 대기 · 양쪽 앱과 연결 설정을 확인하세요."
        }
    }

    func clearMessage() {
        displayedMessage = ""
        displayedDrawing = nil
        messageHistory.removeAll()
        terminalHistory.removeAll()
        nextAttachmentNumber = 1
        letterDismissTask?.cancel()
        letterDismissTask = nil
        pendingDrawingLetters.removeAll()
        drawingLetter = nil
        isDrawingLetterOpen = false
        isBubbleVisible = false
        petActivity = nil
        bubbleDismissTask?.cancel()
    }

    func addTodo(_ rawValue: String, to list: TodoListKind = .mine) {
        let text = MessageText.normalize(rawValue)
        guard !text.isEmpty, list != .partner else { return }
        let item = TodoItem(
            id: UUID(),
            text: text,
            isCompleted: false,
            scope: list == .couple ? .couple : .personal,
            ownerID: list == .couple ? nil : todoOwnerID
        )
        todoItems.append(item)
        saveTodos()
        enqueueTodoMutation(.upsert(item, roomCode: currentTodoRoomCode))
    }

    func toggleTodo(id: UUID) {
        guard
            let index = todoItems.firstIndex(where: { $0.id == id }),
            canEdit(todoItems[index])
        else { return }
        todoItems[index].isCompleted.toggle()
        saveTodos()
        enqueueTodoMutation(.upsert(todoItems[index], roomCode: currentTodoRoomCode))
    }

    func deleteTodo(id: UUID) {
        guard let item = todoItems.first(where: { $0.id == id }), canEdit(item) else { return }
        todoItems.removeAll { $0.id == id }
        saveTodos()
        enqueueTodoMutation(.delete(id, roomCode: currentTodoRoomCode))
    }

    func todoItems(for list: TodoListKind) -> [TodoItem] {
        todoItems.filter { item in
            switch list {
            case .mine: item.scope == .personal && item.ownerID == todoOwnerID
            case .partner: item.scope == .personal && item.ownerID != todoOwnerID
            case .couple: item.scope == .couple
            }
        }
    }

    func canEdit(_ item: TodoItem) -> Bool {
        item.scope == .couple || item.ownerID == todoOwnerID
    }

    func replaceTodos(_ items: [TodoItem], roomCode: String? = nil) {
        todoItems = items
        saveTodos()
        if let roomCode { defaults.set(roomCode, forKey: Self.todoRoomCodeKey) }
    }

    func setTodoSyncError(_ message: String?) {
        todoSyncError = message
    }

    func prepareTodoRoom(_ roomCode: String) -> [TodoItem] {
        guard let previousRoom = defaults.string(forKey: Self.todoRoomCodeKey) else {
            pendingTodoMutations = pendingTodoMutations.map { mutation in
                TodoMutation(
                    action: mutation.action,
                    item: mutation.item,
                    id: mutation.id,
                    roomCode: mutation.roomCode ?? roomCode
                )
            }
            saveTodoMutations()
            return todoItems
        }
        guard previousRoom != roomCode else { return [] }
        todoItems = []
        saveTodos()
        defaults.set(roomCode, forKey: Self.todoRoomCodeKey)
        return []
    }

    func markTodoRoomPrepared(_ roomCode: String) {
        defaults.set(roomCode, forKey: Self.todoRoomCodeKey)
    }

    func nextTodoMutation(roomCode: String) -> TodoMutation? {
        pendingTodoMutations.first { $0.roomCode == roomCode }
    }

    func completeTodoMutation(_ mutation: TodoMutation) {
        guard let index = pendingTodoMutations.firstIndex(of: mutation) else { return }
        pendingTodoMutations.remove(at: index)
        saveTodoMutations()
    }

    func setTodoEnabled(_ isEnabled: Bool) {
        isTodoEnabled = isEnabled
        defaults.set(isEnabled, forKey: Self.todoEnabledKey)
        if !isEnabled { dismissTodo() }
    }

    func toggleTodoVisibility() {
        guard isTodoEnabled else { return }
        isTodoVisible.toggle()
    }

    func dismissTodo() {
        isTodoVisible = false
    }

    func requestChatFocus() {
        if isTerminalMode {
            requestTerminalFocus()
            return
        }
        showBubble()
        chatFocusRequest += 1
    }

    func dismissChatInput() {
        isEditingMessage = false
        isBubbleVisible = false
        bubbleDismissTask?.cancel()
    }

    func resizeCharacter(by delta: Double) {
        let next = ((Double(characterScale) + delta) * 10).rounded() / 10
        setCharacterScale(CGFloat(next))
    }

    func setCharacterScale(_ scale: CGFloat) {
        characterScale = min(1.3, max(0.7, scale))
        defaults.set(Double(characterScale), forKey: Self.characterScaleKey)
        onCharacterScaleChange?(characterScale)
    }

    func resetCharacterSize() {
        setCharacterScale(1)
    }

    func showBubble() {
        guard !isTerminalMode else { return }
        isBubbleVisible = true
        scheduleBubbleDismissal()
    }

    func setMessageEditing(_ isEditing: Bool) {
        guard !isTerminalMode else { return }
        isEditingMessage = isEditing
        if isEditing {
            bubbleDismissTask?.cancel()
            isBubbleVisible = true
        } else {
            scheduleBubbleDismissal()
        }
    }

    private func scheduleBubbleDismissal() {
        bubbleDismissTask?.cancel()
        guard !isEditingMessage else { return }

        bubbleDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.isBubbleVisible = false
        }
    }

    private func record(_ message: String, isLocal: Bool, drawing: DrawingMessage? = nil) {
        sendError = nil
        displayedMessage = message
        displayedDrawing = drawing
        var entry = ConversationMessage(text: message, isLocal: isLocal, drawing: drawing)
        if entry.isImageAttachment {
            entry.attachmentNumber = nextAttachmentNumber
            nextAttachmentNumber += 1
        }
        messageHistory.append(entry)
        messageHistory = Array(messageHistory.suffix(5))
        terminalHistory.append(entry)
        terminalHistory = Array(terminalHistory.suffix(200))
        if !isTerminalMode {
            petActivity = PetActivity(kind: drawing == nil ? .chat : (isLocal ? .sendingLetter : .receivingLetter))
        }
        showBubble()
    }

    private func awardExperience(_ activity: PetProgress.Activity) {
        let previous = petProgress.level
        petProgress.award(activity)
        defaults.set(petProgress.experience, forKey: Self.petExperienceKey)
        if petProgress.level > previous { equipReward(at: petProgress.level); playEquippedInteraction() }
    }

    func equipReward(at level: Int) {
        guard level <= petProgress.level, PetLevelReward.reward(at: level) != nil else { return }
        equippedRewardLevel = level
        defaults.set(level, forKey: Self.petRewardKey)
    }

    func playEquippedInteraction() {
        guard pet3D != nil, !isTerminalMode, let reward = equippedReward else { return }
        play3DAction(reward.action)
    }

    func play3DAction(_ action: Pet3DAction) {
        guard pet3D != nil, !isTerminalMode,
              Pet3DAction.basicActions.contains(action) || equippedReward?.action == action else { return }
        if action == .idle { setRandom3DEnabled(false) }
        petActivity = PetActivity(action3D: action)
    }

    func setRandom3DEnabled(_ enabled: Bool) {
        guard !enabled || (pet3D != nil && !isTerminalMode) else { return }
        guard isRandom3DEnabled != enabled else { return }
        isRandom3DEnabled = enabled
        defaults.set(enabled, forKey: Self.random3DEnabledKey)
        if !enabled { petActivity = PetActivity(action3D: .idle) }
    }

    func setRandom3DInterval(_ seconds: Int) {
        guard Self.random3DIntervals.contains(seconds) else { return }
        random3DInterval = seconds
        defaults.set(seconds, forKey: Self.random3DIntervalKey)
    }

    func playRandom3DAction() {
        var actions = Pet3DAction.basicActions.filter { $0 != .idle && $0 != petActivity?.action3D }
        if let reward = equippedReward { actions.append(reward.action) }
        if let selected = actions.randomElement() { play3DAction(selected) }
    }

    func playRewardInteraction(at level: Int) {
        guard pet3D != nil, !isTerminalMode, level <= petProgress.level,
              let reward = PetLevelReward.reward(at: level) else { return }
        equipReward(at: level)
        play3DAction(reward.action)
    }

    private func saveTodos() {
        if let data = try? JSONEncoder().encode(todoItems) {
            defaults.set(data, forKey: Self.todoItemsKey)
        }
    }

    private func enqueueTodoMutation(_ mutation: TodoMutation) {
        pendingTodoMutations.append(mutation)
        todoMutationRevision += 1
        saveTodoMutations()
        onTodoMutation?()
    }

    private var currentTodoRoomCode: String? {
        defaults.string(forKey: Self.todoRoomCodeKey)
    }

    private func saveTodoMutations() {
        if let data = try? JSONEncoder().encode(pendingTodoMutations) {
            defaults.set(data, forKey: Self.pendingTodoMutationsKey)
        }
    }

    func selectCharacter(from sourceURL: URL) throws {
        guard
            let image = NSImage(contentsOf: sourceURL),
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CharacterError.invalidImage
        }

        try FileManager.default.createDirectory(
            at: characterURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: characterURL, options: .atomic)
        if FileManager.default.fileExists(atPath: petDirectory.path) {
            try FileManager.default.removeItem(at: petDirectory)
        }
        characterImage = NSImage(data: pngData)
        hatchPet = nil
        petActivity = nil
        clear3DSelection()
    }

    func selectHatchPet(from sourceDirectory: URL) throws {
        let accessed = sourceDirectory.startAccessingSecurityScopedResource()
        defer { if accessed { sourceDirectory.stopAccessingSecurityScopedResource() } }
        let sourcePet = try HatchPetPackage.load(from: sourceDirectory)
        let parentDirectory = petDirectory.deletingLastPathComponent()
        let stagingDirectory = parentDirectory.appendingPathComponent(".pet-\(UUID().uuidString)")
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        try fileManager.copyItem(
            at: sourceDirectory.appendingPathComponent("pet.json"),
            to: stagingDirectory.appendingPathComponent("pet.json")
        )
        try fileManager.copyItem(
            at: sourceDirectory.appendingPathComponent(sourcePet.manifest.spritesheetPath),
            to: stagingDirectory.appendingPathComponent(sourcePet.manifest.spritesheetPath)
        )
        let installedPet = try HatchPetPackage.load(from: stagingDirectory)

        let backupDirectory = parentDirectory.appendingPathComponent(".pet-backup-\(UUID().uuidString)")
        let hadExistingPet = fileManager.fileExists(atPath: petDirectory.path)
        if hadExistingPet {
            try fileManager.moveItem(at: petDirectory, to: backupDirectory)
        }

        do {
            try fileManager.moveItem(at: stagingDirectory, to: petDirectory)
        } catch {
            if hadExistingPet { try? fileManager.moveItem(at: backupDirectory, to: petDirectory) }
            throw error
        }
        if hadExistingPet { try? fileManager.removeItem(at: backupDirectory) }

        hatchPet = installedPet
        characterImage = nil
        petActivity = nil
        try? fileManager.removeItem(at: characterURL)
        clear3DSelection()
    }

    func select3DCharacter(_ asset: Pet3DAsset) throws {
        guard try pet3DLibrary.assets().contains(asset) else { throw Pet3DError.message("저장된 3D 캐릭터를 찾을 수 없습니다.") }
        let data = try Data(contentsOf: pet3DLibrary.modelURL(for: asset))
        try Pet3DLibrary.validateGLB(data)
        pet3D = asset
        petActivity = nil
        defaults.set(asset.id.uuidString, forKey: Self.pet3DSelectionKey)
        together.setLocal(url: pet3DModelURL, name: asset.name)
    }

    private func clear3DSelection() {
        pet3D = nil
        together.setLocal(url: nil)
        defaults.removeObject(forKey: Self.pet3DSelectionKey)
    }

    func resetCharacter() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: characterURL.path) {
            try fileManager.removeItem(at: characterURL)
        }
        if fileManager.fileExists(atPath: petDirectory.path) {
            try fileManager.removeItem(at: petDirectory)
        }
        characterImage = nil
        hatchPet = bundledPetDirectory.flatMap { try? HatchPetPackage.load(from: $0) }
        petActivity = nil
        clear3DSelection()
    }

    private static var defaultCharacterURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleMon", isDirectory: true)
            .appendingPathComponent("character.png")
    }

    private static var defaultPetDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleMon", isDirectory: true)
            .appendingPathComponent("pet", isDirectory: true)
    }

    private static let characterScaleKey = "characterScale"
    private static let pet3DSelectionKey = "pet3DSelection"
    private static let petExperienceKey = "petExperience"
    private static let random3DEnabledKey = "random3DEnabled"
    private static let random3DIntervalKey = "random3DInterval"
    private static let petRewardKey = "petEquippedRewardLevel"
    private static let todoItemsKey = "todoItems"
    private static let pendingTodoMutationsKey = "pendingTodoMutations"
    private static let todoEnabledKey = "todoEnabled"
    private static let todoOwnerIDKey = "todoOwnerID"
    private static let todoRoomCodeKey = "todoRoomCode"
}
