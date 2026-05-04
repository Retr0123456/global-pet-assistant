import AppKit

final class FloatingPetWindow: NSPanel {
    init(contentView petView: PetSpriteView) {
        let size = NSSize(width: PetAtlas.cellWidth, height: PetAtlas.cellHeight)
        let frame = FloatingPetWindow.initialFrame(size: size)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = PetWindowContentView(wrapping: petView)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool {
        true
    }

    func show() {
        orderFrontRegardless()
    }

    private static func initialFrame(size: NSSize) -> NSRect {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSRect(origin: NSPoint(x: 120, y: 120), size: size)
        }

        return NSRect(
            x: visibleFrame.maxX - size.width - 40,
            y: visibleFrame.minY + 80,
            width: size.width,
            height: size.height
        )
    }
}

final class PetWindowContentView: NSView {
    init(wrapping petView: PetSpriteView) {
        super.init(frame: NSRect(origin: .zero, size: petView.intrinsicContentSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(petView)
        petView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            petView.leadingAnchor.constraint(equalTo: leadingAnchor),
            petView.trailingAnchor.constraint(equalTo: trailingAnchor),
            petView.topAnchor.constraint(equalTo: topAnchor),
            petView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }
}
