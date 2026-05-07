import AppKit

final class PetSpriteView: NSView {
    static let displayScale: CGFloat = 0.5
    private static let framesPerSecond: TimeInterval = 6.0
    private static let reducedMotionFrameHoldDuration: TimeInterval = 0.2
    static let displaySize = NSSize(
        width: CGFloat(PetAtlas.cellWidth) * displayScale,
        height: CGFloat(PetAtlas.cellHeight) * displayScale
    )

    private var atlas: PetAtlas
    private let spriteLayer = CALayer()
    private var timer: Timer?
    private var currentFrames: [PetAtlasFrame] = []
    private var frameIndex = 0
    private var playbackGeneration = 0

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
        spriteLayer.contents = atlas.image
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

    func replaceAtlas(_ atlas: PetAtlas, preserving state: PetAnimationState) {
        self.atlas = atlas
        playbackGeneration += 1
        timer?.invalidate()
        timer = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.contents = atlas.image
        CATransaction.commit()

        playLoop(state)
    }

    func playLoop(_ state: PetAnimationState) {
        playbackGeneration += 1
        timer?.invalidate()
        timer = nil
        currentFrames = atlas.frames(for: state)
        frameIndex = 0
        renderCurrentFrame()

        guard currentFrames.count > 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
    }

    func playOnce(_ state: PetAnimationState, completion: @escaping @MainActor () -> Void) {
        playbackGeneration += 1
        let generation = playbackGeneration
        timer?.invalidate()
        timer = nil
        currentFrames = atlas.frames(for: state)
        frameIndex = 0
        renderCurrentFrame()

        guard currentFrames.count > 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            timer = Timer.scheduledTimer(
                withTimeInterval: Self.reducedMotionFrameHoldDuration,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playbackGeneration == generation else {
                        return
                    }

                    self.timer = nil
                    completion()
                }
            }
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceOneShotFrame(generation: generation, completion: completion)
            }
        }
    }

    func play(_ state: PetAnimationState) {
        playLoop(state)
    }

    private func advanceFrame() {
        guard !currentFrames.isEmpty else {
            return
        }

        frameIndex = (frameIndex + 1) % currentFrames.count
        renderCurrentFrame()
    }

    private func advanceOneShotFrame(generation: Int, completion: @escaping @MainActor () -> Void) {
        guard playbackGeneration == generation else {
            return
        }

        guard !currentFrames.isEmpty else {
            timer?.invalidate()
            timer = nil
            completion()
            return
        }

        let nextFrameIndex = frameIndex + 1
        guard nextFrameIndex < currentFrames.count else {
            timer?.invalidate()
            timer = nil
            completion()
            return
        }

        frameIndex = nextFrameIndex
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        guard currentFrames.indices.contains(frameIndex) else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.contentsRect = currentFrames[frameIndex].contentsRect
        CATransaction.commit()
    }
}
