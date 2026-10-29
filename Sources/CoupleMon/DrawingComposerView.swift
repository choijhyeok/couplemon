import SwiftUI

struct DrawingPreview: View {
    let drawing: DrawingMessage

    var body: some View {
        Canvas { context, size in
            for stroke in drawing.strokes {
                guard let first = stroke.points.first else { continue }
                let scale = size.width / 280
                let width = stroke.width * scale
                if stroke.points.count == 1 {
                    let rect = CGRect(
                        x: first.x * size.width - width / 2,
                        y: first.y * size.height - width / 2,
                        width: width, height: width
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(stroke.color.color))
                } else {
                    var path = Path()
                    path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                    for point in stroke.points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                    }
                    context.stroke(path, with: .color(stroke.color.color), style: StrokeStyle(
                        lineWidth: width, lineCap: .round, lineJoin: .round
                    ))
                }
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("손그림 메시지")
    }
}

struct DrawingComposerView: View {
    let onSend: (DrawingMessage) -> Void
    @State private var strokes: [DrawingMessage.Stroke] = []
    @State private var currentStroke: DrawingMessage.Stroke?
    @State private var ink: DrawingMessage.Ink = .black
    @State private var width = 4.0

    private var drawing: DrawingMessage {
        DrawingMessage(strokes: strokes + (currentStroke.map { [$0] } ?? []))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("그림 그려 보내기").font(.headline)
                Spacer()
                Button {
                    if !strokes.isEmpty { strokes.removeLast() }
                } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(strokes.isEmpty)
                .help("되돌리기")
                Button("지우기") { strokes.removeAll() }
                    .disabled(strokes.isEmpty)
            }
            DrawingPreview(drawing: drawing)
                .frame(width: 280, height: 200)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.3)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard strokes.count < DrawingMessage.maxStrokes,
                              drawing.pointCount < DrawingMessage.maxPoints else { return }
                        let point = DrawingMessage.Point(
                            x: value.location.x / 280, y: value.location.y / 200
                        )
                        if currentStroke == nil {
                            currentStroke = .init(color: ink, width: width, points: [point])
                        } else if let last = currentStroke?.points.last,
                                  hypot(point.x - last.x, point.y - last.y) >= 0.004 {
                            currentStroke?.points.append(point)
                        }
                    }
                    .onEnded { _ in
                        if let currentStroke { strokes.append(currentStroke) }
                        currentStroke = nil
                    })
            HStack(spacing: 9) {
                ForEach(DrawingMessage.Ink.allCases, id: \.self) { color in
                    Button { ink = color } label: {
                        Circle().fill(color.color)
                            .frame(width: 23, height: 23)
                            .overlay(Circle().stroke(ink == color ? Color.accentColor : .gray.opacity(0.3),
                                                     lineWidth: ink == color ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.title)
                    .accessibilityAddTraits(ink == color ? .isSelected : [])
                }
            }
            HStack {
                Text("굵기").font(.caption)
                Slider(value: $width, in: 1...16, step: 1)
                    .accessibilityLabel("펜 굵기")
                Text("\(Int(width))").font(.caption.monospacedDigit()).frame(width: 20)
                Button("보내기") { onSend(drawing) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!drawing.isValid || currentStroke != nil)
            }
            if drawing.pointCount >= DrawingMessage.maxPoints || strokes.count >= DrawingMessage.maxStrokes {
                Text("그림이 가득 찼어요. 보내거나 일부를 되돌려 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 312)
    }
}

private extension DrawingMessage.Ink {
    var color: Color {
        switch self {
        case .black: .black
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .white: .white
        }
    }

    var title: String {
        switch self {
        case .black: "검정"
        case .pink: "분홍"
        case .red: "빨강"
        case .orange: "주황"
        case .green: "초록"
        case .blue: "파랑"
        case .purple: "보라"
        case .white: "흰색 지우개"
        }
    }
}
