import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    struct ConversationMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isLocal: Bool
        var drawing: DrawingMessage? = nil
    }

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
    @Published private(set) var displayedDrawing: DrawingMessage?
    @Published var realtimeState: CoupleRealtimeState = .notConfigured
    @Published var isPartnerReachable = false
    @Published var sendError: String?
    @Published private(set) var characterImage: NSImage?
    @Published private(set) var hatchPet: HatchPet?
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
    var onTodoVisibilityChange: ((Bool) -> Void)?
    var onTodoMutation: (() -> Void)?

    private let characterURL: URL
    private let petDirectory: URL
    private let bundledPetDirectory: URL?
    private let defaults: UserDefaults
    private(set) var todoOwnerID: UUID
    private(set) var pendingTodoMutations: [TodoMutation]
    private(set) var todoMutationRevision = 0
    private var bubbleDismissTask: Task<Void, Never>?
    private(set) var isEditingMessage = false

    init(
        characterURL: URL? = nil,
        petDirectory: URL? = nil,
        bundledPetDirectory: URL? = Bundle.main.resourceURL?
            .appendingPathComponent("DefaultPet", isDirectory: true),
        defaults: UserDefaults = .standard
    ) {
        let resolvedCharacterURL = characterURL ?? Self.defaultCharacterURL
        let resolvedPetDirectory = petDirectory ?? Self.defaultPetDirectory
        self.characterURL = resolvedCharacterURL
        self.petDirectory = resolvedPetDirectory
        self.bundledPetDirectory = bundledPetDirectory
        self.defaults = defaults
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
    }

    func send(_ rawValue: String) {
        let message = MessageText.normalize(rawValue)
        guard !message.isEmpty else { return }
        record(message, isLocal: true)
        onSend?(message)
    }

    func receive(_ rawValue: String) {
        let message = MessageText.normalize(rawValue)
        guard !message.isEmpty else { return }
        record(message, isLocal: false)
    }

    func sendDrawing(_ drawing: DrawingMessage) {
        guard drawing.isValid else { return }
        record("손그림", isLocal: true, drawing: drawing)
        onSendDrawing?(drawing)
    }

    func receiveDrawing(_ drawing: DrawingMessage) {
        guard drawing.isValid else { return }
        record("손그림", isLocal: false, drawing: drawing)
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
        isBubbleVisible = false
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
        if !isEnabled { setTodoVisible(false) }
    }

    func toggleTodoVisibility() {
        guard isTodoEnabled else { return }
        setTodoVisible(!isTodoVisible)
    }

    func requestChatFocus() {
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
        isBubbleVisible = true
        scheduleBubbleDismissal()
    }

    func setMessageEditing(_ isEditing: Bool) {
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
        messageHistory.append(ConversationMessage(text: message, isLocal: isLocal, drawing: drawing))
        messageHistory = Array(messageHistory.suffix(5))
        showBubble()
    }

    private func setTodoVisible(_ isVisible: Bool) {
        self.isTodoVisible = isVisible
        onTodoVisibilityChange?(isVisible)
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
    }

    func selectHatchPet(from sourceDirectory: URL) throws {
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
        try? fileManager.removeItem(at: characterURL)
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
    private static let todoItemsKey = "todoItems"
    private static let pendingTodoMutationsKey = "pendingTodoMutations"
    private static let todoEnabledKey = "todoEnabled"
    private static let todoOwnerIDKey = "todoOwnerID"
    private static let todoRoomCodeKey = "todoRoomCode"
}
