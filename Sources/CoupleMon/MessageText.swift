import Foundation

enum MessageText {
    static let maxLength = 120

    static func normalize(_ rawValue: String) -> String {
        String(
            rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maxLength)
        )
    }
}
