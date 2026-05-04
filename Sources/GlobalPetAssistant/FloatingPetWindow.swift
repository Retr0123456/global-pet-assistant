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

    var onThreadDismiss: ((PetThreadSnapshot) -> Void)? {
        get {
            petContentView.onThreadDismiss
        }
        set {
            petContentView.onThreadDismiss = newValue
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
        contentView.onDesiredSizeChanged = { [weak self] in
            self?.fitToContentPreservingTopRight()
        }
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool {
        false
    }

    func show() {
        setFrame(Self.constrainedFrame(frame), display: true)
        orderFrontRegardless()
        AuditLogger.appendRuntime(
            status: "pet_window_ordered_front",
            message: "frame=\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width))x\(Int(frame.height)) level=\(level.rawValue)"
        )
    }

    func updateThreadSnapshot(_ snapshot: EventRouterSnapshot?) {
        petContentView.updateThreadSnapshot(snapshot)
    }

    private func fitToContentPreservingTopRight() {
        let desiredSize = petContentView.desiredContentSize
        guard frame.size != desiredSize else {
            return
        }

        let nextFrame = NSRect(
            x: frame.maxX - desiredSize.width,
            y: frame.maxY - desiredSize.height,
            width: desiredSize.width,
            height: desiredSize.height
        )
        setFrame(Self.constrainedFrame(nextFrame), display: true)
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
    private static let threadPanelMaxWidth: CGFloat = 320
    private static let threadPanelMinHeight: CGFloat = 78
    private static let threadRowHeight: CGFloat = 78
    private static let threadPanelVerticalInset: CGFloat = 0
    private static let threadStackSpacing: CGFloat = 8
    private static let threadPanelGap: CGFloat = 8
    private static let badgeSize: CGFloat = 30

    var onClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDragChanged: ((PetDragDirection?) -> Void)?
    var onThreadDismiss: ((PetThreadSnapshot) -> Void)?
    var onMoveEnded: ((NSPoint) -> Void)?
    var contextMenuProvider: (() -> NSMenu?)?
    var onDesiredSizeChanged: (() -> Void)?

    var desiredContentSize: NSSize {
        guard isThreadPanelExpanded else {
            return petView.intrinsicContentSize
        }

        return NSSize(
            width: max(petView.intrinsicContentSize.width, Self.threadPanelMaxWidth),
            height: petView.intrinsicContentSize.height + Self.threadPanelGap + currentThreadPanelHeight
        )
    }

    private let petView: PetSpriteView
    private let threadBadgeButton = NSButton()
    private let threadPanelView = NSView()
    private let threadPanelContentView = NSView()
    private let threadStackView = NSStackView()
    private var threadPanelHeightConstraint: NSLayoutConstraint?
    private var mouseDownScreenPoint: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    private var didMouseDownOnPet = false
    private var didDrag = false
    private let clickMovementThreshold: CGFloat = 5
    private let dragAnimationThreshold: CGFloat = 1.5
    private var hoverTrackingArea: NSTrackingArea?
    private var threadSnapshot: EventRouterSnapshot?
    private var isThreadPanelExpanded = false

    init(wrapping petView: PetSpriteView) {
        self.petView = petView
        super.init(frame: NSRect(origin: .zero, size: petView.intrinsicContentSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(petView)
        petView.translatesAutoresizingMaskIntoConstraints = false

        configureThreadBadgeButton()
        configureThreadPanel()

        let panelHeightConstraint = threadPanelView.heightAnchor.constraint(equalToConstant: Self.threadPanelMinHeight)
        threadPanelHeightConstraint = panelHeightConstraint

        NSLayoutConstraint.activate([
            petView.trailingAnchor.constraint(equalTo: trailingAnchor),
            petView.topAnchor.constraint(equalTo: topAnchor),
            petView.widthAnchor.constraint(equalToConstant: petView.intrinsicContentSize.width),
            petView.heightAnchor.constraint(equalToConstant: petView.intrinsicContentSize.height),

            threadBadgeButton.topAnchor.constraint(equalTo: petView.topAnchor),
            threadBadgeButton.trailingAnchor.constraint(equalTo: petView.trailingAnchor),
            threadBadgeButton.widthAnchor.constraint(equalToConstant: Self.badgeSize),
            threadBadgeButton.heightAnchor.constraint(equalToConstant: Self.badgeSize),

            threadPanelView.centerXAnchor.constraint(equalTo: centerXAnchor),
            threadPanelView.widthAnchor.constraint(equalToConstant: Self.threadPanelMaxWidth),
            threadPanelView.topAnchor.constraint(equalTo: petView.bottomAnchor, constant: Self.threadPanelGap),
            panelHeightConstraint
        ])

        updateThreadSnapshot(nil)
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
        let localPoint = convert(event.locationInWindow, from: nil)
        didMouseDownOnPet = petView.frame.contains(localPoint)
        mouseDownScreenPoint = window?.convertPoint(toScreen: event.locationInWindow)
        mouseDownWindowOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard didMouseDownOnPet else {
            return
        }

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
        }

        if delta.x < -dragAnimationThreshold {
            onDragChanged?(.left)
        } else if delta.x > dragAnimationThreshold {
            onDragChanged?(.right)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let window else {
            resetMouseTracking()
            return
        }

        let mouseUpScreenPoint = window.convertPoint(toScreen: event.locationInWindow)
        let movedDistance = mouseDownScreenPoint?.distance(to: mouseUpScreenPoint) ?? 0
        if didMouseDownOnPet && !didDrag && movedDistance <= clickMovementThreshold {
            onClick?()
        } else if didMouseDownOnPet {
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
        didMouseDownOnPet = false
        didDrag = false
    }

    func updateThreadSnapshot(_ snapshot: EventRouterSnapshot?) {
        let previousSize = desiredContentSize
        threadSnapshot = snapshot

        if snapshot?.activeEventCount ?? 0 == 0 {
            isThreadPanelExpanded = false
        }

        updateThreadBadge()
        rebuildThreadPanel()
        updateThreadPanelHeight()
        applyThreadPanelVisibility()

        let nextSize = desiredContentSize
        if previousSize != nextSize {
            frame.size = nextSize
            onDesiredSizeChanged?()
        }
    }

    @objc private func toggleThreadPanel() {
        guard threadSnapshot?.activeEventCount ?? 0 > 0 else {
            return
        }

        let previousSize = desiredContentSize
        isThreadPanelExpanded.toggle()
        updateThreadBadge()
        updateThreadPanelHeight()
        applyThreadPanelVisibility()

        let nextSize = desiredContentSize
        if previousSize != nextSize {
            frame.size = nextSize
            onDesiredSizeChanged?()
        }
    }

    private func configureThreadBadgeButton() {
        addSubview(threadBadgeButton)
        threadBadgeButton.translatesAutoresizingMaskIntoConstraints = false
        threadBadgeButton.target = self
        threadBadgeButton.action = #selector(toggleThreadPanel)
        threadBadgeButton.isBordered = true
        threadBadgeButton.bezelStyle = .glass
        threadBadgeButton.controlSize = .small
        threadBadgeButton.focusRingType = .none
        threadBadgeButton.contentTintColor = .labelColor
        threadBadgeButton.imagePosition = .imageOnly
        threadBadgeButton.setButtonType(.momentaryPushIn)
    }

    private func configureThreadPanel() {
        addSubview(threadPanelView)
        threadPanelView.translatesAutoresizingMaskIntoConstraints = false
        threadPanelView.wantsLayer = true
        threadPanelView.layer?.backgroundColor = NSColor.clear.cgColor
        threadPanelView.addSubview(threadPanelContentView)

        threadPanelContentView.translatesAutoresizingMaskIntoConstraints = false
        threadPanelContentView.wantsLayer = true
        threadPanelContentView.layer?.backgroundColor = NSColor.clear.cgColor
        threadPanelContentView.layer?.masksToBounds = true

        threadPanelContentView.addSubview(threadStackView)
        threadStackView.translatesAutoresizingMaskIntoConstraints = false
        threadStackView.orientation = .vertical
        threadStackView.alignment = .width
        threadStackView.distribution = .fill
        threadStackView.spacing = Self.threadStackSpacing

        NSLayoutConstraint.activate([
            threadPanelContentView.leadingAnchor.constraint(equalTo: threadPanelView.leadingAnchor),
            threadPanelContentView.trailingAnchor.constraint(equalTo: threadPanelView.trailingAnchor),
            threadPanelContentView.topAnchor.constraint(equalTo: threadPanelView.topAnchor),
            threadPanelContentView.bottomAnchor.constraint(equalTo: threadPanelView.bottomAnchor),

            threadStackView.leadingAnchor.constraint(equalTo: threadPanelContentView.leadingAnchor),
            threadStackView.trailingAnchor.constraint(equalTo: threadPanelContentView.trailingAnchor),
            threadStackView.topAnchor.constraint(equalTo: threadPanelContentView.topAnchor, constant: Self.threadPanelVerticalInset),
            threadStackView.bottomAnchor.constraint(equalTo: threadPanelContentView.bottomAnchor, constant: -Self.threadPanelVerticalInset)
        ])
    }

    private func updateThreadBadge() {
        let count = threadSnapshot?.activeEventCount ?? 0
        threadBadgeButton.isHidden = count == 0

        if isThreadPanelExpanded {
            threadBadgeButton.title = ""
            threadBadgeButton.attributedTitle = NSAttributedString(string: "")
            threadBadgeButton.image = NSImage(
                systemSymbolName: "chevron.down",
                accessibilityDescription: "Hide thread details"
            )
            threadBadgeButton.imagePosition = .imageOnly
            threadBadgeButton.imageScaling = .scaleProportionallyDown
        } else {
            threadBadgeButton.image = nil
            threadBadgeButton.imagePosition = .noImage
            threadBadgeButton.attributedTitle = NSAttributedString(
                string: "\(count)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ]
            )
        }
    }

    private func rebuildThreadPanel() {
        threadStackView.arrangedSubviews.forEach { view in
            threadStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let threads = threadSnapshot?.activeThreads ?? []
        for thread in threads {
            threadStackView.addArrangedSubview(makeThreadRow(for: thread))
        }
    }

    private func makeThreadRow(for thread: PetThreadSnapshot) -> NSView {
        let row = ThreadMessageRowView(
            thread: thread,
            onDismiss: { [weak self] thread in
                self?.onThreadDismiss?(thread)
            }
        )
        row.heightAnchor.constraint(equalToConstant: Self.threadRowHeight).isActive = true

        return row
    }

    private func applyThreadPanelVisibility() {
        threadPanelView.isHidden = !isThreadPanelExpanded || (threadSnapshot?.activeEventCount ?? 0) == 0
    }

    private var currentThreadPanelHeight: CGFloat {
        guard isThreadPanelExpanded else {
            return Self.threadPanelMinHeight
        }

        let threadCount = max(threadSnapshot?.activeThreads.count ?? 0, 1)
        let rowsHeight = CGFloat(threadCount) * Self.threadRowHeight
        let spacingHeight = CGFloat(max(threadCount - 1, 0)) * Self.threadStackSpacing
        let contentHeight = Self.threadPanelVerticalInset * 2 + rowsHeight + spacingHeight
        return max(Self.threadPanelMinHeight, contentHeight)
    }

    private func updateThreadPanelHeight() {
        threadPanelHeightConstraint?.constant = currentThreadPanelHeight
    }
}

private final class ThreadMessageRowView: NSView {
    private static let cornerRadius: CGFloat = 16
    private static let closeButtonSize: CGFloat = 18

    private let thread: PetThreadSnapshot
    private let onDismiss: (PetThreadSnapshot) -> Void
    private let glassView = NSGlassEffectView()
    private let contentView = NSView()
    private let closeButton = NSButton()
    private var hoverTrackingArea: NSTrackingArea?

    init(
        thread: PetThreadSnapshot,
        onDismiss: @escaping (PetThreadSnapshot) -> Void
    ) {
        self.thread = thread
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(glassView)
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.style = .regular
        glassView.cornerRadius = Self.cornerRadius
        glassView.clipsToBounds = true
        glassView.tintColor = NSColor.black.withAlphaComponent(0.84)
        glassView.contentView = contentView

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.76).cgColor
        contentView.layer?.cornerRadius = Self.cornerRadius
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        contentView.layer?.masksToBounds = true

        let directoryLabel = NSTextField(labelWithString: thread.directoryName)
        directoryLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        directoryLabel.textColor = .white
        directoryLabel.alignment = .right
        directoryLabel.lineBreakMode = .byTruncatingTail
        directoryLabel.maximumNumberOfLines = 1
        directoryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let messageLabel = NSTextField(wrappingLabelWithString: thread.messagePreview)
        messageLabel.font = .systemFont(ofSize: 13, weight: .regular)
        messageLabel.textColor = NSColor.white.withAlphaComponent(0.82)
        messageLabel.alignment = .right
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 2
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labelStackView = NSStackView(views: [directoryLabel, messageLabel])
        labelStackView.translatesAutoresizingMaskIntoConstraints = false
        labelStackView.orientation = .vertical
        labelStackView.alignment = .width
        labelStackView.distribution = .fill
        labelStackView.spacing = 3
        labelStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentView.addSubview(labelStackView)

        addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = true
        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Dismiss notification"
        )
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.72)
        closeButton.target = self
        closeButton.action = #selector(dismissNotification)
        closeButton.setButtonType(.momentaryPushIn)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: glassView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),

            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: Self.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Self.closeButtonSize),

            labelStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            labelStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            labelStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelStackView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 12),
            labelStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    @objc private func dismissNotification() {
        onDismiss(thread)
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
