import AppKit
import SwiftUI

struct CompanionView: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @State private var resizeStartScale: CGFloat?
    @State private var todoDraft = ""
    @FocusState private var draftIsFocused: Bool

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("TODO", systemImage: "doc.text.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Text("\(model.todoItems.filter(\.isCompleted).count)/\(model.todoItems.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.todoItems.isEmpty {
                        Text("할 일을 추가해 보세요")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 70)
                    }
                    ForEach(model.todoItems) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Button { model.toggleTodo(id: item.id) } label: {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.isCompleted ? "완료 취소" : "완료")

                            Text(item.text)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button { model.deleteTodo(id: item.id) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.text) 삭제")
                            .help("삭제")
                        }
                        .padding(9)
                        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("할 일 추가", text: $todoDraft)
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
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.6), lineWidth: 1) }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }

    private var speechBubble: some View {
        VStack(spacing: 9) {
            if model.messageHistory.isEmpty, !model.displayedMessage.isEmpty {
                Text(model.displayedMessage)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(model.messageHistory) { message in
                            HStack(alignment: .top, spacing: 6) {
                                if message.isLocal { Spacer(minLength: 18) }
                                Text(message.isLocal ? "나" : "상대")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(message.isLocal ? Color.accentColor : Color.secondary)
                                Text(message.text)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .help(message.text)
                                if !message.isLocal { Spacer(minLength: 18) }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                message.isLocal ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 130)
            }

            HStack(spacing: 8) {
                Button(action: showEmojiPicker) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("이모티콘 선택")

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
            AnimatedHatchPetView(pet: pet, size: 150 * model.characterScale)
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
            .overlay(alignment: .leading) {
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
                    .offset(x: -42)
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
        model.addTodo(todoDraft)
        if !MessageText.normalize(todoDraft).isEmpty { todoDraft = "" }
    }

    private func showEmojiPicker() {
        draftIsFocused = true
        DispatchQueue.main.async {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}

private struct AnimatedHatchPetView: View {
    let pet: HatchPet
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let frameIndex = reduceMotion ? 0 : HatchPetContract.idleFrameIndex(elapsed: elapsed)

            Image(nsImage: pet.idleFrames[frameIndex])
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: size, height: size)
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
