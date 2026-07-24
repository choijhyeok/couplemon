import SwiftUI

struct CompanionView: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 4) {
            speechBubble
            character
        }
        .padding(12)
        .frame(width: 320, height: 300)
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
                TextField("한마디 보내기", text: $draft)
                    .textFieldStyle(.plain)
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
        if let image = model.characterImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 150, height: 150)
                .accessibilityLabel("내 캐릭터")
        } else {
            PixelHeart()
                .frame(width: 120, height: 105)
                .padding(.top, 16)
                .accessibilityLabel("기본 하트 캐릭터")
        }
    }

    private func send() {
        model.send(draft)
        if !MessageText.normalize(draft).isEmpty {
            draft = ""
        }
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
