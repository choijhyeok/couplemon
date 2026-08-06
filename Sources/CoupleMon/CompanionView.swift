import AppKit
import SwiftUI

struct CompanionView: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @State private var resizeStartScale: CGFloat?
    @State private var todoDraft = ""
    @State private var selectedTodoList = AppModel.TodoListKind.mine
    @State private var isEmoticonPickerPresented = false
    @FocusState private var draftIsFocused: Bool

    private let basicEmoji = ["😀", "🥰", "😍", "😘", "😂", "😭", "👍", "❤️", "💛", "✨", "🎉", "🔥"]

    var body: some View {
        HStack(spacing: 0) {
            if model.isTodoVisible {
                todoList
                    .padding(12)
                    .frame(width: 280, height: 410)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            companion
        }
        .frame(width: model.isTodoVisible ? 600 : 320, height: 410, alignment: .trailing)
        .animation(.easeOut(duration: 0.2), value: model.isTodoVisible)
        .onChange(of: model.chatFocusRequest) { _, _ in draftIsFocused = true }
    }

    private var companion: some View {
        VStack(spacing: 4) {
            speechBubble
                .opacity(model.isBubbleVisible ? 1 : 0)
                .allowsHitTesting(model.isBubbleVisible)
            resizableCharacter
        }
        .padding(12)
        .frame(width: 320, height: 410)
        .animation(.easeOut(duration: 0.2), value: model.isBubbleVisible)
        .onAppear { model.showBubble() }
        .onChange(of: draftIsFocused) { _, isFocused in
            model.setMessageEditing(isFocused)
        }
    }

    private var todoList: some View {
        let items = model.todoItems(for: selectedTodoList)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("TODO", systemImage: "doc.text.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Text("\(items.filter(\.isCompleted).count)/\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Picker("Todo 목록", selection: $selectedTodoList) {
                ForEach(AppModel.TodoListKind.allCases) { list in
                    Text(list.title).tag(list)
                }
            }
            .pickerStyle(.segmented)

            if let error = model.todoSyncError {
                Label("DB 동기화 대기", systemImage: "exclamationmark.icloud")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(error)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if items.isEmpty {
                        Text(selectedTodoList == .partner ? "상대의 할 일이 없습니다" : "할 일을 추가해 보세요")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 70)
                    }
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            if model.canEdit(item) {
                                Button { model.toggleTodo(id: item.id) } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.isCompleted ? "완료 취소" : "완료")
                            } else {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
                                    .accessibilityLabel(item.isCompleted ? "완료됨" : "미완료")
                            }

                            Text(item.text)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if model.canEdit(item) {
                                Button { model.deleteTodo(id: item.id) } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(item.text) 삭제")
                                .help("삭제")
                            }
                        }
                        .padding(9)
                        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            if selectedTodoList != .partner {
                HStack(spacing: 8) {
                    TextField(selectedTodoList == .couple ? "커플 할 일 추가" : "내 할 일 추가", text: $todoDraft)
                        .textFieldStyle(.plain)
                        .onSubmit(addTodo)
                    Button(action: addTodo) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(MessageText.normalize(todoDraft).isEmpty)
                    .accessibilityLabel("할 일 추가")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.black.opacity(0.06), in: Capsule())
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.6), lineWidth: 1) }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }

    private var speechBubble: some View {
        VStack(spacing: 9) {
            if !model.isEditingMessage, !model.displayedMessage.isEmpty {
                messageContent(model.displayedMessage, emoticonSize: 84)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 4) {
                            ForEach(model.messageHistory) { message in
                                HStack(alignment: .top, spacing: 6) {
                                    if message.isLocal { Spacer(minLength: 18) }
                                    Text(message.isLocal ? "나" : "상대")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(message.isLocal ? Color.accentColor : Color.secondary)
                                    messageContent(message.text, emoticonSize: 54)
                                    if !message.isLocal { Spacer(minLength: 18) }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    message.isLocal ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                                .accessibilityElement(children: .combine)
                                .id(message.id)
                            }
                        }
                    }
                    .onAppear { scrollToLatestMessage(using: proxy) }
                    .onChange(of: model.messageHistory.last?.id) { _, _ in
                        scrollToLatestMessage(using: proxy)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 130)
            }

            HStack(spacing: 8) {
                Button { isEmoticonPickerPresented.toggle() } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("이모티콘 선택")
                .popover(isPresented: $isEmoticonPickerPresented, arrowEdge: .bottom) {
                    emoticonPicker
                }

                TextField("한마디 보내기", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($draftIsFocused)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .disabled(MessageText.normalize(draft).isEmpty)
                .accessibilityLabel("메시지 보내기")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.black.opacity(0.06), in: Capsule())
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .overlay(alignment: .bottom) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.9))
                .offset(y: 13)
        }
    }

    @ViewBuilder
    private var character: some View {
        if let pet = model.hatchPet {
            AnimatedHatchPetView(
                pet: pet,
                size: 150 * model.characterScale,
                messageID: model.messageHistory.last?.id
            )
                .id(pet.manifest.id)
        } else if let image = model.characterImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 150 * model.characterScale, height: 150 * model.characterScale)
                .accessibilityLabel("내 캐릭터")
        } else {
            PixelHeart()
                .frame(width: 120 * model.characterScale, height: 105 * model.characterScale)
                .padding(.top, 16)
                .accessibilityLabel("기본 하트 캐릭터")
        }
    }

    private var resizableCharacter: some View {
        character
            .contentShape(Rectangle())
            .onTapGesture { model.showBubble() }
            .accessibilityAction { model.showBubble() }
            .overlay(alignment: .bottomLeading) {
                if model.isTodoEnabled {
                    Button { model.toggleTodoVisibility() } label: {
                        Image(systemName: model.isTodoVisible ? "doc.text.fill" : "doc.text")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(model.isTodoVisible ? Color.accentColor : .black.opacity(0.62), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -7, y: 7)
                    .accessibilityLabel(model.isTodoVisible ? "Todo List 닫기" : "Todo List 열기")
                    .help(model.isTodoVisible ? "Todo List 닫기" : "Todo List 열기")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.62), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                    .offset(x: 7, y: 7)
                    .gesture(resizeGesture)
                    .accessibilityLabel("캐릭터 크기 조절")
                    .help("대각선으로 드래그해 캐릭터 크기 조절")
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizeStartScale == nil {
                    resizeStartScale = model.characterScale
                }
                let delta = (value.translation.width + value.translation.height) / 250
                model.setCharacterScale((resizeStartScale ?? model.characterScale) + delta)
            }
            .onEnded { _ in resizeStartScale = nil }
    }

    private func send() {
        model.send(draft)
        if !MessageText.normalize(draft).isEmpty {
            draft = ""
        }
    }

    private func addTodo() {
        model.addTodo(todoDraft, to: selectedTodoList)
        if !MessageText.normalize(todoDraft).isEmpty { todoDraft = "" }
    }

    private var emoticonPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("특전 애니메이션")
                        .font(.system(size: 13, weight: .bold, design: .rounded))

                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(68)), count: 3), spacing: 8) {
                        ForEach(CoupleMonAnimatedEmoticon.allCases) { emoticon in
                            Button { send(emoticon) } label: {
                                VStack(spacing: 4) {
                                    emoticonImage(emoticon.emoticon, size: 54)
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 16, height: 16)
                                                .background(Color.accentColor, in: Circle())
                                        }
                                    Text(emoticon.title)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                }
                                .frame(width: 68)
                                .padding(.vertical, 6)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emoticon.accessibilityLabel)
                        }
                    }

                    Divider()
                    Text("CoupleMon 특전")
                        .font(.system(size: 13, weight: .bold, design: .rounded))

                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(68)), count: 3), spacing: 8) {
                        ForEach(CoupleMonEmoticon.allCases) { emoticon in
                            Button { send(emoticon) } label: {
                                VStack(spacing: 4) {
                                    emoticonImage(emoticon, size: 54)
                                    Text(emoticon.title)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                }
                                .frame(width: 68)
                                .padding(.vertical, 6)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emoticon.accessibilityLabel)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()
            Text("기본 이모지")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 6), spacing: 8) {
                ForEach(basicEmoji, id: \.self) { emoji in
                    Button(emoji) { insert(emoji) }
                        .buttonStyle(.plain)
                        .font(.system(size: 20))
                        .frame(width: 30, height: 30)
                        .accessibilityLabel("\(emoji) 이모지")
                }
            }

            Button("macOS 전체 이모지 열기", systemImage: "character.book.closed") {
                showSystemEmojiPicker()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(14)
        .frame(width: 252)
    }

    @ViewBuilder
    private func messageContent(_ text: String, emoticonSize: CGFloat) -> some View {
        if let emoticon = CoupleMonAnimatedEmoticon(messageValue: text) {
            AnimatedEmoticonView(emoticon: emoticon, size: emoticonSize)
        } else if let emoticon = CoupleMonEmoticon(messageValue: text) {
            emoticonImage(emoticon, size: emoticonSize)
        } else {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .truncationMode(.tail)
                .help(text)
        }
    }

    private func scrollToLatestMessage(using proxy: ScrollViewProxy) {
        guard let messageID = model.messageHistory.last?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(messageID, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func emoticonImage(_ emoticon: CoupleMonEmoticon, size: CGFloat) -> some View {
        if let image = emoticon.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(emoticon.accessibilityLabel)
        } else {
            Text(emoticon.title)
                .frame(width: size, height: size)
        }
    }

    private func send(_ emoticon: CoupleMonEmoticon) {
        model.send(emoticon.messageValue)
        isEmoticonPickerPresented = false
        restoreDraftFocus()
    }

    private func send(_ emoticon: CoupleMonAnimatedEmoticon) {
        model.send(emoticon.messageValue)
        isEmoticonPickerPresented = false
        restoreDraftFocus()
    }

    private func insert(_ emoji: String) {
        guard draft.count < MessageText.maxLength else { return }
        draft.append(contentsOf: emoji)
        isEmoticonPickerPresented = false
        restoreDraftFocus()
    }

    private func showSystemEmojiPicker() {
        isEmoticonPickerPresented = false
        NSApp.activate(ignoringOtherApps: true)
        restoreDraftFocus {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }

    private func restoreDraftFocus(_ action: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            draftIsFocused = true
            DispatchQueue.main.async { action?() }
        }
    }
}

private struct AnimatedEmoticonView: View {
    let emoticon: CoupleMonAnimatedEmoticon
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
            let motion = reduceMotion
                ? CoupleMonAnimatedEmoticon.Motion.identity
                : emoticon.motion(at: timeline.date.timeIntervalSince(startedAt))

            if let image = emoticon.emoticon.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(CGFloat(motion.scale))
                    .offset(x: CGFloat(motion.x), y: CGFloat(motion.y))
                    .rotationEffect(.degrees(motion.rotation))
                    .frame(width: size, height: size)
                    .accessibilityLabel(emoticon.accessibilityLabel)
            } else {
                Text(emoticon.title)
                    .frame(width: size, height: size)
            }
        }
    }
}

private struct AnimatedHatchPetView: View {
    let pet: HatchPet
    let size: CGFloat
    let messageID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var activeAnimation: HatchPetContract.Animation?
    @State private var lastAnimation: HatchPetContract.Animation?

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)
        ) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let animation = activeAnimation ?? .idle
            let frameIndex = reduceMotion
                ? 0
                : HatchPetContract.frameIndex(elapsed: elapsed, animation: animation)
            let frames = pet.animations[animation] ?? pet.animations[.idle]!

            Image(nsImage: frames[frameIndex])
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: size, height: size)
        }
        .task(id: messageID) {
            guard messageID != nil, !reduceMotion else { return }
            let animations = HatchPetContract.chatAnimationChoices(
                available: Set(pet.animations.keys),
                excluding: lastAnimation
            )
            guard let animation = animations.randomElement() else { return }

            lastAnimation = animation
            activeAnimation = animation
            startedAt = Date()
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(animation.duration * 1_000_000_000)
                )
            } catch {
                return
            }
            startedAt = Date()
            activeAnimation = nil
        }
        .accessibilityLabel(pet.manifest.displayName)
    }
}

private struct PixelHeart: View {
    private let pixels = [
        "0110110",
        "1111111",
        "1111111",
        "0111110",
        "0011100",
        "0001000",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(pixels.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, pixel in
                        Rectangle()
                            .fill(pixel == "1" ? Color.pink : Color.clear)
                    }
                }
            }
        }
        .shadow(color: .pink.opacity(0.35), radius: 8, y: 5)
    }
}
