import Foundation

struct DrawingMessage: Codable, Equatable {
    struct Point: Codable, Equatable {
        let x: Double
        let y: Double

        init(x: Double, y: Double) {
            self.x = (min(1, max(0, x)) * 1_000).rounded() / 1_000
            self.y = (min(1, max(0, y)) * 1_000).rounded() / 1_000
        }
    }

    struct Stroke: Codable, Equatable {
        let color: Ink
        let width: Double
        var points: [Point]
    }

    enum Ink: String, Codable, CaseIterable {
        case black, pink, red, orange, green, blue, purple, white
    }

    static let maxPoints = 1_200
    static let maxStrokes = 80
    static let maxPayloadBytes = 48_000
    let strokes: [Stroke]

    var pointCount: Int { strokes.reduce(0) { $0 + $1.points.count } }

    var isValid: Bool {
        guard !strokes.isEmpty, strokes.count <= Self.maxStrokes,
              pointCount <= Self.maxPoints,
              strokes.allSatisfy({ stroke in
                  stroke.width.isFinite && (1...16).contains(stroke.width)
                      && !stroke.points.isEmpty && stroke.points.allSatisfy {
                          $0.x.isFinite && $0.y.isFinite
                              && (0...1).contains($0.x) && (0...1).contains($0.y)
                      }
              }),
              let data = try? JSONEncoder().encode(self)
        else { return false }
        return data.count <= Self.maxPayloadBytes
    }
}
