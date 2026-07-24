import AppKit
import SwiftUI

struct CompanionView: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @State private var resizeStartScale: CGFloat?
    @FocusState private var draftIsFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            speechBubble
                .opacity(model.isBubbleVisible ? 1 : 0)
                .allowsHitTesting(model.isBubbleVisible)
            resizableCharacter
        }
        .padding(12)
        .frame(width: 320, height: 340)
        .animation(.easeOut(duration: 0.2), value: model.isBubbleVisible)
        .onAppear { model.showBubble() }
        .onChange(of: draftIsFocused) { _, isFocused in
            model.setMessageEditing(isFocused)
        }
    }

    private var speechBubble: some View {
        VStack(spacing: 9) {
            if !model.displayedMessage.isEmpty {
                Text(model.displayedMessage)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
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
            draftIsFocused = false
        }
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
