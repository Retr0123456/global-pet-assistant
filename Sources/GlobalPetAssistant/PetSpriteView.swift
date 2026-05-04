import AppKit

final class PetSpriteView: NSView {
    static let displayScale: CGFloat = 0.25
    static let displaySize = NSSize(
        width: CGFloat(PetAtlas.cellWidth) * displayScale,
        height: CGFloat(PetAtlas.cellHeight) * displayScale
    )

    private let atlas: PetAtlas
    private let spriteLayer = CALayer()
    private var timer: Timer?
    private var currentFrames: [CGImage] = []
    private var frameIndex = 0

    init(atlas: PetAtlas) {
        self.atlas = atlas
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: Self.displaySize.width,
            height: Self.displaySize.height
        ))

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        spriteLayer.frame = bounds
        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        layer?.addSublayer(spriteLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        Self.displaySize
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.frame = bounds
        CATransaction.commit()
    }

    func play(_ state: PetAnimationState) {
        timer?.invalidate()
        currentFrames = atlas.frames(for: state)
        frameIndex = 0
        renderCurrentFrame()

        guard currentFrames.count > 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
    }

    private func advanceFrame() {
        guard !currentFrames.isEmpty else {
            return
        }

        frameIndex = (frameIndex + 1) % currentFrames.count
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        guard currentFrames.indices.contains(frameIndex) else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.contents = currentFrames[frameIndex]
        CATransaction.commit()
    }
}
