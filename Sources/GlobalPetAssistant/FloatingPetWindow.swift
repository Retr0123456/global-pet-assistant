import AppKit

final class FloatingPetWindow: NSPanel {
    private static let edgeSnapThreshold: CGFloat = 24
    private let petContentView: PetWindowContentView

    var onPetClick: (() -> Void)? {
        get {
            petContentView.onClick
        }
        set {
            petContentView.onClick = newValue
        }
    }

    var onPetHoverChanged: ((Bool) -> Void)? {
        get {
            petContentView.onHoverChanged
        }
        set {
            petContentView.onHoverChanged = newValue
        }
    }

    var onPetDragChanged: ((PetDragDirection?) -> Void)? {
        get {
            petContentView.onDragChanged
        }
        set {
            petContentView.onDragChanged = newValue
        }
    }

    var contextMenuProvider: (() -> NSMenu?)? {
        get {
            petContentView.contextMenuProvider
        }
        set {
            petContentView.contextMenuProvider = newValue
        }
    }

    var onMoveEnded: ((NSPoint) -> Void)? {
        get {
            petContentView.onMoveEnded
        }
        set {
            petContentView.onMoveEnded = newValue
        }
    }

    init(contentView petView: PetSpriteView, savedOrigin: StoredWindowOrigin?) {
        let size = petView.intrinsicContentSize
        let frame = FloatingPetWindow.initialFrame(size: size, savedOrigin: savedOrigin)
        let contentView = PetWindowContentView(wrapping: petView)
        self.petContentView = contentView

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool {
        true
    }

    func show() {
        orderFrontRegardless()
    }

    func moveToNextScreen() {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            return
        }

        let currentScreenIndex = screens.firstIndex { screen in
            frame.intersects(screen.visibleFrame)
        } ?? 0
        let nextScreen = screens[(currentScreenIndex + 1) % screens.count]
        let nextFrame = NSRect(
            x: nextScreen.visibleFrame.maxX - frame.width - 40,
            y: nextScreen.visibleFrame.minY + 80,
            width: frame.width,
            height: frame.height
        )
        setFrame(nextFrame, display: true)
        onMoveEnded?(nextFrame.origin)
        show()
    }

    static func constrainedFrame(_ frame: NSRect) -> NSRect {
        guard let screen = bestScreen(for: frame) else {
            return frame
        }

        let visibleFrame = screen.visibleFrame
        let x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        let y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
    }

    static func settledFrame(_ frame: NSRect) -> NSRect {
        let constrainedFrame = Self.constrainedFrame(frame)
        guard let screen = bestScreen(for: constrainedFrame) else {
            return constrainedFrame
        }

        let visibleFrame = screen.visibleFrame
        var origin = constrainedFrame.origin

        if abs(constrainedFrame.minX - visibleFrame.minX) <= edgeSnapThreshold {
            origin.x = visibleFrame.minX
        } else if abs(visibleFrame.maxX - constrainedFrame.maxX) <= edgeSnapThreshold {
            origin.x = visibleFrame.maxX - constrainedFrame.width
        }

        if abs(constrainedFrame.minY - visibleFrame.minY) <= edgeSnapThreshold {
            origin.y = visibleFrame.minY
        } else if abs(visibleFrame.maxY - constrainedFrame.maxY) <= edgeSnapThreshold {
            origin.y = visibleFrame.maxY - constrainedFrame.height
        }

        return Self.constrainedFrame(NSRect(origin: origin, size: constrainedFrame.size))
    }

    private static func initialFrame(size: NSSize, savedOrigin: StoredWindowOrigin?) -> NSRect {
        if let savedOrigin {
            let savedFrame = NSRect(
                x: savedOrigin.x,
                y: savedOrigin.y,
                width: size.width,
                height: size.height
            )
            let constrainedFrame = constrainedFrame(savedFrame)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(constrainedFrame) }) {
                return constrainedFrame
            }
        }

        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSRect(origin: NSPoint(x: 120, y: 120), size: size)
        }

        return constrainedFrame(NSRect(
            x: visibleFrame.maxX - size.width - 40,
            y: visibleFrame.minY + 80,
            width: size.width,
            height: size.height
        ))
    }

    private static func bestScreen(for frame: NSRect) -> NSScreen? {
        if let intersectingScreen = NSScreen.screens.max(by: { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }), intersectingScreen.visibleFrame.intersects(frame) {
            return intersectingScreen
        }

        let frameCenter = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.min { lhs, rhs in
            lhs.visibleFrame.center.distance(to: frameCenter) < rhs.visibleFrame.center.distance(to: frameCenter)
        }
    }
}

final class PetWindowContentView: NSView {
    var onClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDragChanged: ((PetDragDirection?) -> Void)?
    var onMoveEnded: ((NSPoint) -> Void)?
    var contextMenuProvider: (() -> NSMenu?)?

    private var mouseDownScreenPoint: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    private var didDrag = false
    private let clickMovementThreshold: CGFloat = 5
    private var hoverTrackingArea: NSTrackingArea?

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
        false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreenPoint = window?.convertPoint(toScreen: event.locationInWindow)
        mouseDownWindowOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let mouseDownScreenPoint,
            let mouseDownWindowOrigin
        else {
            return
        }

        let currentScreenPoint = window.convertPoint(toScreen: event.locationInWindow)
        let delta = NSPoint(
            x: currentScreenPoint.x - mouseDownScreenPoint.x,
            y: currentScreenPoint.y - mouseDownScreenPoint.y
        )
        let nextFrame = NSRect(
            x: mouseDownWindowOrigin.x + delta.x,
            y: mouseDownWindowOrigin.y + delta.y,
            width: window.frame.width,
            height: window.frame.height
        )
        window.setFrame(FloatingPetWindow.constrainedFrame(nextFrame), display: true)

        if delta.distance(to: .zero) > clickMovementThreshold {
            didDrag = true
            if delta.x < -clickMovementThreshold {
                onDragChanged?(.left)
            } else if delta.x > clickMovementThreshold {
                onDragChanged?(.right)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let window else {
            resetMouseTracking()
            return
        }

        let mouseUpScreenPoint = window.convertPoint(toScreen: event.locationInWindow)
        let movedDistance = mouseDownScreenPoint?.distance(to: mouseUpScreenPoint) ?? 0
        if !didDrag && movedDistance <= clickMovementThreshold {
            onClick?()
        } else {
            let settledFrame = FloatingPetWindow.settledFrame(window.frame)
            window.setFrame(settledFrame, display: true)
            onDragChanged?(nil)
            onMoveEnded?(settledFrame.origin)
        }

        resetMouseTracking()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?()
    }

    private func resetMouseTracking() {
        mouseDownScreenPoint = nil
        mouseDownWindowOrigin = nil
        didDrag = false
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull else {
            return 0
        }

        return width * height
    }

    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}

private extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
