import AppKit
import ImageIO

enum PetAnimationState: String, CaseIterable, Codable {
    case idle
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    var row: Int {
        switch self {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        case .waving: 3
        case .jumping: 4
        case .failed: 5
        case .waiting: 6
        case .running: 7
        case .review: 8
        }
    }

    var frameCount: Int {
        switch self {
        case .runningRight, .runningLeft, .failed:
            8
        case .waving:
            4
        case .jumping:
            5
        case .idle, .waiting, .running, .review:
            6
        }
    }
}

struct PetAtlas {
    static let width = 1536
    static let height = 1872
    static let columns = 8
    static let rows = 9
    static let cellWidth = 192
    static let cellHeight = 208

    let framesByState: [PetAnimationState: [CGImage]]

    init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PetAtlasError.unreadableImage(url.path)
        }

        try Self.validate(source: source, url: url)

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PetAtlasError.unreadableImage(url.path)
        }

        var frames: [PetAnimationState: [CGImage]] = [:]
        for state in PetAnimationState.allCases {
            frames[state] = try Self.makeFrames(for: state, from: image)
        }

        framesByState = frames
    }

    func frames(for state: PetAnimationState) -> [CGImage] {
        framesByState[state] ?? framesByState[.idle] ?? []
    }

    private static func validate(source: CGImageSource, url: URL) throws {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            throw PetAtlasError.missingImageProperties(url.path)
        }

        guard width.intValue == Self.width, height.intValue == Self.height else {
            throw PetAtlasError.invalidDimensions(
                path: url.path,
                actualWidth: width.intValue,
                actualHeight: height.intValue,
                expectedWidth: Self.width,
                expectedHeight: Self.height
            )
        }
    }

    private static func makeFrames(for state: PetAnimationState, from image: CGImage) throws -> [CGImage] {
        try (0..<state.frameCount).map { column in
            let rect = CGRect(
                x: column * Self.cellWidth,
                y: state.row * Self.cellHeight,
                width: Self.cellWidth,
                height: Self.cellHeight
            )

            guard let frame = image.cropping(to: rect) else {
                throw PetAtlasError.invalidFrame(state: state.rawValue, column: column)
            }

            return frame
        }
    }
}

enum PetAtlasError: Error, CustomStringConvertible {
    case unreadableImage(String)
    case missingImageProperties(String)
    case invalidDimensions(
        path: String,
        actualWidth: Int,
        actualHeight: Int,
        expectedWidth: Int,
        expectedHeight: Int
    )
    case invalidFrame(state: String, column: Int)

    var description: String {
        switch self {
        case .unreadableImage(let path):
            "Cannot read pet atlas at \(path)."
        case .missingImageProperties(let path):
            "Cannot read pixel dimensions for pet atlas at \(path)."
        case let .invalidDimensions(path, actualWidth, actualHeight, expectedWidth, expectedHeight):
            "Invalid pet atlas dimensions for \(path): got \(actualWidth)x\(actualHeight), expected \(expectedWidth)x\(expectedHeight)."
        case let .invalidFrame(state, column):
            "Cannot crop frame \(column) for state \(state)."
        }
    }
}
