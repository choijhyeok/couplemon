import SwiftUI

struct PetLetterEffect: ViewModifier {
    let activity: PetActivity?
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var isPlaying = false

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isPlaying)) { timeline in
            let motion = pose(at: timeline.date)
            content
                .scaleEffect(x: motion.petScaleX, y: motion.petScaleY, anchor: .bottom)
                .rotationEffect(.degrees(motion.petRotation), anchor: .bottom)
                .offset(x: size * motion.petX, y: size * motion.petY)
                .overlay {
                    Image(systemName: "envelope.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.85), Color.brown.opacity(0.7))
                        .font(.system(size: size * 0.2, weight: .medium))
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .scaleEffect(motion.letterScale)
                        .rotationEffect(.degrees(motion.letterRotation))
                        .offset(x: size * motion.letterX, y: size * motion.letterY)
                        .opacity(motion.letterOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
        .task(id: activity?.id) {
            isPlaying = false
            guard !reduceMotion, activity?.kind.letterDirection != nil else { return }
            startedAt = Date()
            isPlaying = true
            do { try await Task.sleep(for: .seconds(PetLetterAnimation.duration)) } catch { return }
            isPlaying = false
        }
    }

    private func pose(at date: Date) -> PetLetterAnimation.Motion {
        guard !reduceMotion, isPlaying, let direction = activity?.kind.letterDirection else { return .idle }
        return PetLetterAnimation.motion(elapsed: date.timeIntervalSince(startedAt), direction: direction)
    }
}
