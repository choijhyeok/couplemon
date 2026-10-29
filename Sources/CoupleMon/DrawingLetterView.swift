import SwiftUI

struct DrawingLetterView: View {
    let letter: AppModel.DrawingLetter
    let isOpen: Bool
    let height: CGFloat
    let onOpen: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasArrived = false

    private let paper = Color(red: 1, green: 0.985, blue: 0.955)

    var body: some View {
        ZStack(alignment: .bottom) {
            openedLetter
                .opacity(isOpen ? 1 : 0)
                .scaleEffect(x: isOpen || reduceMotion ? 1 : 0.35,
                             y: isOpen || reduceMotion ? 1 : 0.06, anchor: .bottom)
                .rotation3DEffect(.degrees(isOpen || reduceMotion ? 0 : -70),
                                  axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.4)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)

            Button(action: onOpen) {
                VStack(spacing: 5) {
                    foldedPaper
                        .frame(width: 84, height: 66)
                    Text(letter.isLocal ? "내 편지 열기" : "편지가 도착했어요")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("눌러서 손그림 편지 열기")
            .accessibilityLabel(letter.isLocal ? "내가 보낸 손그림 편지 열기" : "도착한 손그림 편지 열기")
            .scaleEffect(reduceMotion ? 1 : (isOpen ? 1.65 : (hasArrived ? 1 : 0.6)))
            .offset(y: reduceMotion || hasArrived ? 0 : -12)
            .opacity(isOpen ? 0 : 1)
            .allowsHitTesting(!isOpen)
            .accessibilityHidden(isOpen)
        }
        .frame(width: 268, height: height, alignment: .bottom)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeInOut(duration: AppModel.letterUnfoldDuration),
                   value: isOpen)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6), value: hasArrived)
        .onAppear { hasArrived = true }
    }

    private var openedLetter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                Text(letter.isLocal ? "내가 보낸 편지" : "너에게 온 편지")
                    .foregroundStyle(.black.opacity(0.65))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.65))
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.06), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("손그림 편지 닫기")
                .help("편지 닫기 · 그림은 대화에 남아요")
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))

            DrawingPreview(drawing: letter.drawing)
                .aspectRatio(1.4, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(width: 268, height: height)
        .background(paper, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var foldedPaper: some View {
        ZStack {
            paperPanel([(5, 15), (27, 3), (29, 51), (9, 63)], shade: 0)
            paperPanel([(27, 3), (53, 13), (55, 62), (29, 51)], shade: 0.06)
            paperPanel([(53, 13), (77, 1), (79, 49), (55, 62)], shade: 0)
            Image(systemName: "heart.fill")
                .font(.system(size: 14))
                .foregroundStyle(.pink)
                .position(x: 41, y: 32)
        }
        .rotationEffect(.degrees(reduceMotion ? 0 : -10))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
        .accessibilityHidden(true)
    }

    private func paperPanel(_ corners: [(CGFloat, CGFloat)], shade: Double) -> some View {
        let shape = Path { path in
            guard let first = corners.first else { return }
            path.move(to: CGPoint(x: first.0, y: first.1))
            for point in corners.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
            path.closeSubpath()
        }
        return shape.fill(paper)
            .overlay(shape.fill(.black.opacity(shade)))
            .overlay(shape.stroke(.black.opacity(0.3), lineWidth: 1))
    }
}
