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

    static let previewMenuStates: [PetAnimationState] = [
        .idle,
        .waiting,
        .failed,
        .review,
        .waving,
        .jumping,
        .runningLeft,
        .runningRight
    ]

    var menuTitle: String {
        switch self {
        case .idle:
            "Idle"
        case .runningRight:
            "Running Right"
        case .runningLeft:
            "Running Left"
        case .waving:
            "Waving"
        case .jumping:
            "Jumping"
        case .failed:
            "Failed"
        case .waiting:
            "Waiting"
        case .running:
            "Running"
        case .review:
            "Review"
        }
    }

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

    let image: CGImage
    let framesByState: [PetAnimationState: [PetAtlasFrame]]

    init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PetAtlasError.unreadableImage(url.path)
        }

        try Self.validate(source: source, url: url)

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PetAtlasError.unreadableImage(url.path)
        }

        self.image = image

        var frames: [PetAnimationState: [PetAtlasFrame]] = [:]
        for state in PetAnimationState.allCases {
            frames[state] = Self.makeFrames(for: state)
        }

        framesByState = frames
    }

    func frames(for state: PetAnimationState) -> [PetAtlasFrame] {
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

    static func makeFrames(for state: PetAnimationState) -> [PetAtlasFrame] {
        // Pet atlas rows are documented from top to bottom, while CALayer.contentsRect
        // uses a bottom-origin unit coordinate space.
        let contentsRectY = CGFloat(Self.rows - state.row - 1) / CGFloat(Self.rows)

        return (0..<state.frameCount).map { column in
            PetAtlasFrame(
                column: column,
                row: state.row,
                contentsRect: CGRect(
                    x: CGFloat(column) / CGFloat(Self.columns),
                    y: contentsRectY,
                    width: 1.0 / CGFloat(Self.columns),
                    height: 1.0 / CGFloat(Self.rows)
                )
            )
        }
    }
}

struct PetAtlasFrame: Equatable {
    let column: Int
    let row: Int
    let contentsRect: CGRect
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

    var description: String {
        switch self {
        case .unreadableImage(let path):
            "Cannot read pet atlas at \(path)."
        case .missingImageProperties(let path):
            "Cannot read pixel dimensions for pet atlas at \(path)."
        case let .invalidDimensions(path, actualWidth, actualHeight, expectedWidth, expectedHeight):
            "Invalid pet atlas dimensions for \(path): got \(actualWidth)x\(actualHeight), expected \(expectedWidth)x\(expectedHeight)."
        }
    }
}
