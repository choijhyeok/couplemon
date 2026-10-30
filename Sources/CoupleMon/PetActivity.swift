import Foundation

struct PetActivity: Identifiable, Equatable {
    enum Kind: Equatable {
        case chat
        case sendingLetter
        case receivingLetter

        var letterDirection: PetLetterAnimation.Direction? {
            switch self {
            case .chat: nil
            case .sendingLetter: .sending
            case .receivingLetter: .receiving
            }
        }

        var preferredAnimation: HatchPetContract.Animation? {
            switch self {
            case .chat: nil
            case .sendingLetter: .waving
            case .receivingLetter: .review
            }
        }
    }

    let id = UUID()
    let kind: Kind
}

enum PetLetterAnimation {
    enum Direction { case sending, receiving }

    struct Motion: Equatable {
        var petX = 0.0
        var petY = 0.0
        var petRotation = 0.0
        var petScaleX = 1.0
        var petScaleY = 1.0
        var letterX = 0.0
        var letterY = 0.08
        var letterRotation = 0.0
        var letterScale = 1.0
        var letterOpacity = 0.0

        static let idle = Motion()

        func blended(to other: Motion, progress t: Double) -> Motion {
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
            return Motion(
                petX: mix(petX, other.petX), petY: mix(petY, other.petY),
                petRotation: mix(petRotation, other.petRotation),
                petScaleX: mix(petScaleX, other.petScaleX), petScaleY: mix(petScaleY, other.petScaleY),
                letterX: mix(letterX, other.letterX), letterY: mix(letterY, other.letterY),
                letterRotation: mix(letterRotation, other.letterRotation),
                letterScale: mix(letterScale, other.letterScale), letterOpacity: mix(letterOpacity, other.letterOpacity)
            )
        }
    }

    static let duration = 1.4

    static func motion(elapsed: TimeInterval, direction: Direction) -> Motion {
        guard elapsed.isFinite, elapsed >= 0, elapsed < duration else { return .idle }
        let keyframes: [(Double, Motion)]
        switch direction {
        case .sending:
            keyframes = [
                (0, .idle),
                (0.2, Motion(petY: 0.02, petRotation: 4, letterOpacity: 1)),
                (0.5, Motion(petX: 0.02, petY: -0.04, petRotation: -6,
                             letterX: 0.12, letterY: -0.04, letterRotation: -18, letterOpacity: 1)),
                (0.88, Motion(letterX: 0.4, letterY: -0.48, letterRotation: -30,
                              letterScale: 0.65, letterOpacity: 0)),
                (1, .idle),
            ]
        case .receiving:
            keyframes = [
                (0, Motion(letterX: 0.4, letterY: -0.48, letterRotation: 25, letterScale: 0.65)),
                (0.25, Motion(petY: -0.03, petRotation: 3,
                              letterX: 0.22, letterY: -0.23, letterRotation: 12, letterScale: 0.85, letterOpacity: 1)),
                (0.55, Motion(petY: 0.02, petScaleX: 1.05, petScaleY: 0.95, letterOpacity: 1)),
                (0.78, Motion(petY: -0.015, petScaleX: 0.98, petScaleY: 1.02, letterOpacity: 1)),
                (1, .idle),
            ]
        }
        let position = elapsed / duration
        for index in 1..<keyframes.count where position <= keyframes[index].0 {
            let (start, from) = keyframes[index - 1]
            let (end, to) = keyframes[index]
            let t = (position - start) / (end - start)
            return from.blended(to: to, progress: t * t * (3 - 2 * t))
        }
        return .idle
    }
}
