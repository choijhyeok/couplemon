import AppKit

enum CoupleMonEmoticon: String, CaseIterable, Identifiable {
    case quokka
    case quokkaCheer = "quokka_cheer"
    case quokkaAngry = "quokka_angry"
    case quokkaSorry = "quokka_sorry"
    case otter
    case otterLaugh = "otter_laugh"
    case otterSleepy = "otter_sleepy"
    case otterEat = "otter_eat"
    case couple
    case coupleKiss = "couple_kiss"
    case coupleCheer = "couple_cheer"
    case coupleMiss = "couple_miss"

    var id: String { rawValue }
    var messageValue: String { "[[couplemon:\(rawValue)]]" }

    private var metadata: (title: String, accessibilityLabel: String) {
        switch self {
        case .quokka: ("쿼카", "볼을 감싼 행복한 쿼카")
        case .quokkaCheer: ("신나", "신나게 뛰는 쿼카")
        case .quokkaAngry: ("삐짐", "팔짱 끼고 삐진 쿼카")
        case .quokkaSorry: ("미안", "눈물을 흘리며 미안해하는 쿼카")
        case .otter: ("사랑", "하트를 안은 수달")
        case .otterLaugh: ("빵터짐", "배를 잡고 웃는 수달")
        case .otterSleepy: ("잘자", "베개를 안고 자는 수달")
        case .otterEat: ("밥먹자", "밥그릇을 든 수달")
        case .couple: ("꼬옥", "서로 꼭 안은 쿼카와 수달")
        case .coupleKiss: ("뽀뽀", "수달에게 뽀뽀하는 쿼카")
        case .coupleCheer: ("힘내", "하이파이브하는 쿼카와 수달")
        case .coupleMiss: ("보고싶어", "서로 그리워하는 쿼카와 수달")
        }
    }

    var title: String { metadata.title }
    var accessibilityLabel: String { metadata.accessibilityLabel }

    var image: NSImage? {
        image(resourceRootURL: Bundle.main.resourceURL)
    }

    func image(resourceRootURL: URL?) -> NSImage? {
        guard let resourceRootURL else { return nil }
        let bundleURL = resourceRootURL.appendingPathComponent("CoupleMon_CoupleMon.bundle")
        let candidates = [
            bundleURL.appendingPathComponent("\(rawValue).png"),
            bundleURL.appendingPathComponent("Emoticons/\(rawValue).png"),
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            .flatMap(NSImage.init(contentsOf:))
    }

    init?(messageValue: String) {
        let prefix = "[[couplemon:"
        let suffix = "]]"
        guard messageValue.hasPrefix(prefix), messageValue.hasSuffix(suffix) else { return nil }
        self.init(rawValue: String(messageValue.dropFirst(prefix.count).dropLast(suffix.count)))
    }
}
