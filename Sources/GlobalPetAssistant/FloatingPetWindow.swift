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

    var onThreadClick: ((PetThreadSnapshot) -> Void)? {
        get {
            petContentView.onThreadClick
        }
        set {
            petContentView.onThreadClick = newValue
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

    var onFocusTimerCancel: (() -> Void)? {
        get {
            petContentView.onFocusTimerCancel
        }
        set {
            petContentView.onFocusTimerCancel = newValue
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

    func updateFocusTimerSnapshot(_ snapshot: FocusTimerSnapshot?) {
        petContentView.updateFocusTimerSnapshot(snapshot)
    }

    private func fitToContentPreservingTopRight() {
        let desiredSize = petContentView.desiredContentSize
        guard frame.size != desiredSize else {
            return
        }

        let nextOriginX = petContentView.preservesRightEdgeOnResize
            ? frame.maxX - desiredSize.width
            : frame.minX
        let nextFrame = NSRect(
            x: nextOriginX,
            y: frame.maxY - desiredSize.height,
            width: desiredSize.width,
            height: desiredSize.height
        )
        setFrame(Self.constrainedFrame(nextFrame), display: true)
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
    private static let threadPanelMaxWidth: CGFloat = 300
    private static let threadPanelMinHeight: CGFloat = 78
    private static let threadRowHeight: CGFloat = 78
    private static let threadPanelVerticalInset: CGFloat = 0
    private static let threadStackSpacing: CGFloat = 8
    private static let threadPanelGap: CGFloat = 8
    private static let badgeSize: CGFloat = 30
    private static let flashStackWidth: CGFloat = 220
    private static let flashRowHeight: CGFloat = 34
    private static let flashStackSpacing: CGFloat = 6
    private static let flashPetGap: CGFloat = 8
    private static let flashTopOffset: CGFloat = 8

    var onClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDragChanged: ((PetDragDirection?) -> Void)?
    var onThreadClick: ((PetThreadSnapshot) -> Void)?
    var onThreadDismiss: ((PetThreadSnapshot) -> Void)?
    var onFocusTimerCancel: (() -> Void)?
    var onMoveEnded: ((NSPoint) -> Void)?
    var contextMenuProvider: (() -> NSMenu?)?
    var onDesiredSizeChanged: (() -> Void)?
    var preservesRightEdgeOnResize: Bool {
        !hasSideStack || isFlashPlacedLeft
    }

    var desiredContentSize: NSSize {
        let petSize = petView.intrinsicContentSize
        let flashSideWidth = hasSideStack ? Self.flashStackWidth + Self.flashPetGap : 0
        let primaryWidth = petSize.width + flashSideWidth
        let primaryHeight = max(petSize.height, flashStackHeight + Self.flashTopOffset)

        guard isThreadPanelExpanded else {
            return NSSize(width: primaryWidth, height: primaryHeight)
        }

        return NSSize(
            width: max(primaryWidth, Self.threadPanelMaxWidth),
            height: primaryHeight + Self.threadPanelGap + currentThreadPanelHeight
        )
    }

    private let petView: PetSpriteView
    private let threadBadgeButton = NSButton()
    private let threadPanelView = NSView()
    private let threadPanelContentView = NSView()
    private let threadStackView = NSStackView()
    private let flashStackView = NSStackView()
    private var threadPanelHeightConstraint: NSLayoutConstraint?
    private var petLeadingConstraint: NSLayoutConstraint?
    private var petTrailingConstraint: NSLayoutConstraint?
    private var flashLeadingConstraint: NSLayoutConstraint?
    private var flashTrailingConstraint: NSLayoutConstraint?
    private var mouseDownScreenPoint: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    private var didMouseDownOnPet = false
    private var didDrag = false
    private let clickMovementThreshold: CGFloat = 5
    private let dragAnimationThreshold: CGFloat = 1.5
    private var hoverTrackingArea: NSTrackingArea?
    private var threadSnapshot: EventRouterSnapshot?
    private var focusTimerSnapshot: FocusTimerSnapshot?
    private var isThreadPanelExpanded = false
    private var isFlashPlacedLeft = true
    private var hasFlashMessages: Bool {
        !(threadSnapshot?.flashMessages.isEmpty ?? true)
    }
    private var hasSideStack: Bool {
        hasFlashMessages || focusTimerSnapshot != nil
    }

    init(wrapping petView: PetSpriteView) {
        self.petView = petView
        super.init(frame: NSRect(origin: .zero, size: petView.intrinsicContentSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(petView)
        petView.translatesAutoresizingMaskIntoConstraints = false

        configureThreadBadgeButton()
        configureThreadPanel()
        configureFlashStack()

        let panelHeightConstraint = threadPanelView.heightAnchor.constraint(equalToConstant: Self.threadPanelMinHeight)
        threadPanelHeightConstraint = panelHeightConstraint
        let petLeadingConstraint = petView.leadingAnchor.constraint(equalTo: leadingAnchor)
        let petTrailingConstraint = petView.trailingAnchor.constraint(equalTo: trailingAnchor)
        let flashLeadingConstraint = flashStackView.leadingAnchor.constraint(
            equalTo: petView.trailingAnchor,
            constant: Self.flashPetGap
        )
        let flashTrailingConstraint = flashStackView.trailingAnchor.constraint(
            equalTo: petView.leadingAnchor,
            constant: -Self.flashPetGap
        )
        self.petLeadingConstraint = petLeadingConstraint
        self.petTrailingConstraint = petTrailingConstraint
        self.flashLeadingConstraint = flashLeadingConstraint
        self.flashTrailingConstraint = flashTrailingConstraint

        NSLayoutConstraint.activate([
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
            panelHeightConstraint,

            flashStackView.topAnchor.constraint(equalTo: petView.topAnchor, constant: Self.flashTopOffset),
            flashStackView.widthAnchor.constraint(equalToConstant: Self.flashStackWidth)
        ])
        petTrailingConstraint.isActive = true

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
        updateFlashPlacement()
        applyFlashVisibilityAndPlacement()

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
        updateFlashPlacement()

        if snapshot?.activeEventCount ?? 0 == 0 {
            isThreadPanelExpanded = false
        }

        updateThreadBadge()
        rebuildFlashStack()
        applyFlashVisibilityAndPlacement()
        rebuildThreadPanel()
        updateThreadPanelHeight()
        applyThreadPanelVisibility()

        let nextSize = desiredContentSize
        if previousSize != nextSize {
            frame.size = nextSize
            onDesiredSizeChanged?()
        }
    }

    func updateFocusTimerSnapshot(_ snapshot: FocusTimerSnapshot?) {
        let previousSize = desiredContentSize
        focusTimerSnapshot = snapshot
        updateFlashPlacement()
        rebuildFlashStack()
        applyFlashVisibilityAndPlacement()

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
        updateFlashPlacement()
        applyFlashVisibilityAndPlacement()

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
        threadStackView.distribution = .fillEqually
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

    private func configureFlashStack() {
        addSubview(flashStackView)
        flashStackView.translatesAutoresizingMaskIntoConstraints = false
        flashStackView.orientation = .vertical
        flashStackView.alignment = .width
        flashStackView.distribution = .fill
        flashStackView.spacing = Self.flashStackSpacing
        flashStackView.isHidden = true
    }

    private func updateFlashPlacement() {
        guard let window else {
            return
        }

        let screen = NSScreen.screens.first { screen in
            screen.visibleFrame.intersects(window.frame)
        } ?? window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return
        }

        let petFrameInWindow = convert(petView.frame, to: nil)
        let petCenterX = window.frame.minX + petFrameInWindow.midX
        isFlashPlacedLeft = petCenterX >= visibleFrame.midX
    }

    private func rebuildFlashStack() {
        flashStackView.arrangedSubviews.forEach { view in
            flashStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let focusTimerSnapshot {
            let row = FocusTimerBadgeView(snapshot: focusTimerSnapshot) { [weak self] in
                self?.onFocusTimerCancel?()
            }
            row.heightAnchor.constraint(equalToConstant: Self.flashRowHeight).isActive = true
            row.widthAnchor.constraint(equalToConstant: Self.flashStackWidth).isActive = true
            flashStackView.addArrangedSubview(row)
        }

        let messages = threadSnapshot?.flashMessages ?? []
        for message in messages {
            let row = FlashMessageRowView(message: message)
            row.heightAnchor.constraint(equalToConstant: Self.flashRowHeight).isActive = true
            row.widthAnchor.constraint(equalToConstant: Self.flashStackWidth).isActive = true
            flashStackView.addArrangedSubview(row)
        }
    }

    private func applyFlashVisibilityAndPlacement() {
        let hasMessages = hasSideStack
        flashStackView.isHidden = !hasMessages

        petLeadingConstraint?.isActive = false
        petTrailingConstraint?.isActive = false
        flashLeadingConstraint?.isActive = false
        flashTrailingConstraint?.isActive = false

        if hasMessages, !isFlashPlacedLeft {
            petLeadingConstraint?.isActive = true
            flashLeadingConstraint?.isActive = true
        } else {
            petTrailingConstraint?.isActive = true
            if hasMessages {
                flashTrailingConstraint?.isActive = true
            }
        }
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
            onOpen: { [weak self] thread in
                self?.onThreadClick?(thread)
            },
            onDismiss: { [weak self] thread in
                self?.onThreadDismiss?(thread)
            }
        )
        row.heightAnchor.constraint(equalToConstant: Self.threadRowHeight).isActive = true
        row.widthAnchor.constraint(equalToConstant: Self.threadPanelMaxWidth).isActive = true

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

    private var flashStackHeight: CGFloat {
        let count = (threadSnapshot?.flashMessages.count ?? 0) + (focusTimerSnapshot == nil ? 0 : 1)
        guard count > 0 else {
            return 0
        }

        return CGFloat(count) * Self.flashRowHeight
            + CGFloat(max(count - 1, 0)) * Self.flashStackSpacing
    }

    private func updateThreadPanelHeight() {
        threadPanelHeightConstraint?.constant = currentThreadPanelHeight
    }
}

private final class FocusTimerBadgeView: NSView {
    private static let cornerRadius: CGFloat = 8
    private static let iconSize: CGFloat = 14
    private static let cancelButtonSize: CGFloat = 18

    private let snapshot: FocusTimerSnapshot
    private let onCancel: () -> Void
    private let contentView = NSView()
    private let iconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")
    private let cancelButton = NSButton()

    init(snapshot: FocusTimerSnapshot, onCancel: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onCancel = onCancel
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.76).cgColor
        contentView.layer?.cornerRadius = Self.cornerRadius
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = accentColor.withAlphaComponent(0.36).cgColor
        contentView.layer?.masksToBounds = true

        contentView.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: "timer",
            accessibilityDescription: "Focus timer"
        )
        iconView.contentTintColor = accentColor
        iconView.imageScaling = .scaleProportionallyDown

        contentView.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.stringValue = snapshot.formattedRemaining
        textField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        textField.textColor = NSColor.white.withAlphaComponent(0.9)
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1
        textField.alignment = .left

        contentView.addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelTimer)
        cancelButton.isBordered = false
        cancelButton.bezelStyle = .regularSquare
        cancelButton.focusRingType = .none
        cancelButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Cancel focus timer"
        )
        cancelButton.imagePosition = .imageOnly
        cancelButton.imageScaling = .scaleProportionallyDown
        cancelButton.contentTintColor = NSColor.white.withAlphaComponent(0.72)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            textField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            cancelButton.leadingAnchor.constraint(greaterThanOrEqualTo: textField.trailingAnchor, constant: 8),
            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: Self.cancelButtonSize),
            cancelButton.heightAnchor.constraint(equalToConstant: Self.cancelButtonSize)
        ])
    }

    @objc private func cancelTimer() {
        onCancel()
    }

    private var accentColor: NSColor {
        snapshot.isEndingSoon ? .systemYellow : .systemTeal
    }
}

private final class FlashMessageRowView: NSView {
    private static let cornerRadius: CGFloat = 8
    private static let stripWidth: CGFloat = 3
    private static let iconSize: CGFloat = 14

    private let message: PetFlashSnapshot
    private let contentView = NSView()
    private let stripView = NSView()
    private let iconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")

    init(message: PetFlashSnapshot) {
        self.message = message
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        contentView.layer?.cornerRadius = Self.cornerRadius
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        contentView.layer?.masksToBounds = true

        contentView.addSubview(stripView)
        stripView.translatesAutoresizingMaskIntoConstraints = false
        stripView.wantsLayer = true
        stripView.layer?.backgroundColor = accentColor.cgColor

        contentView.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )
        iconView.contentTintColor = accentColor
        iconView.imageScaling = .scaleProportionallyDown

        contentView.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.stringValue = message.message
        textField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        textField.textColor = NSColor.white.withAlphaComponent(0.88)
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.alignment = .left

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stripView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stripView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stripView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stripView.widthAnchor.constraint(equalToConstant: Self.stripWidth),

            iconView.leadingAnchor.constraint(equalTo: stripView.trailingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            textField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    private var accentColor: NSColor {
        switch message.level {
        case .success:
            return NSColor.systemGreen.withAlphaComponent(0.9)
        case .danger:
            return NSColor.systemRed.withAlphaComponent(0.9)
        case .warning:
            return NSColor.systemYellow.withAlphaComponent(0.9)
        case .running:
            return NSColor.systemBlue.withAlphaComponent(0.85)
        case .info:
            return NSColor.white.withAlphaComponent(0.62)
        }
    }

    private var symbolName: String {
        switch message.level {
        case .success:
            return "checkmark.circle.fill"
        case .danger:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .info:
            return "info.circle.fill"
        }
    }
}

private final class ThreadMessageRowView: NSView {
    private static let cornerRadius: CGFloat = 16
    private static let statusBadgeSize: CGFloat = 30
    private static let closeButtonSize: CGFloat = 18
    private static let actionReserveWidth: CGFloat = 28
    private static let fixedHeight: CGFloat = 78

    private let thread: PetThreadSnapshot
    private let onOpen: (PetThreadSnapshot) -> Void
    private let onDismiss: (PetThreadSnapshot) -> Void
    private let glassView = NSGlassEffectView()
    private let contentView = NSView()
    private let statusBadgeView: ThreadStatusBadgeView
    private let textView: ThreadMessageTextView
    private let closeButton = NSButton()
    private var hoverTrackingArea: NSTrackingArea?

    init(
        thread: PetThreadSnapshot,
        onOpen: @escaping (PetThreadSnapshot) -> Void,
        onDismiss: @escaping (PetThreadSnapshot) -> Void
    ) {
        self.thread = thread
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        self.statusBadgeView = ThreadStatusBadgeView(status: thread.status)
        self.textView = ThreadMessageTextView(thread: thread)
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.fixedHeight)
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

    override func mouseUp(with event: NSEvent) {
        guard thread.action != nil else {
            return
        }

        onOpen(thread)
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

        contentView.addSubview(statusBadgeView)
        statusBadgeView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false

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

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: Self.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Self.closeButtonSize),

            statusBadgeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusBadgeView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusBadgeView.widthAnchor.constraint(equalToConstant: Self.statusBadgeSize),
            statusBadgeView.heightAnchor.constraint(equalToConstant: Self.statusBadgeSize),

            textView.leadingAnchor.constraint(equalTo: statusBadgeView.trailingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.actionReserveWidth),
            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc private func dismissNotification() {
        onDismiss(thread)
    }
}

private final class ThreadStatusBadgeView: NSView {
    private static let iconSize: CGFloat = 17

    private let status: PetThreadStatus
    private let iconView = NSImageView()

    init(status: PetThreadStatus) {
        self.status = status
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = accentColor.withAlphaComponent(0.18).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = accentColor.withAlphaComponent(0.46).cgColor
        layer?.cornerRadius = 15
        layer?.masksToBounds = true
        toolTip = status.indicator.accessibilityDescription

        addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: status.indicator.symbolName,
            accessibilityDescription: status.indicator.accessibilityDescription
        )
        iconView.contentTintColor = accentColor
        iconView.imageScaling = .scaleProportionallyDown

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize)
        ])
    }

    private var accentColor: NSColor {
        switch status {
        case .running:
            return NSColor.systemBlue.withAlphaComponent(0.92)
        case .waiting:
            return NSColor.systemYellow.withAlphaComponent(0.92)
        case .success:
            return NSColor.systemGreen.withAlphaComponent(0.92)
        case .failed:
            return NSColor.systemRed.withAlphaComponent(0.92)
        case .approvalRequired:
            return NSColor.systemOrange.withAlphaComponent(0.95)
        case .info:
            return NSColor.white.withAlphaComponent(0.68)
        }
    }
}

private final class ThreadMessageTextView: NSView {
    private let directoryName: String
    private let messagePreview: String

    init(thread: PetThreadSnapshot) {
        self.directoryName = thread.directoryName
        self.messagePreview = thread.messagePreview
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        toolTip = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let textRect = bounds.insetBy(dx: 0, dy: 12)
        let titleRect = NSRect(
            x: textRect.minX,
            y: textRect.minY,
            width: textRect.width,
            height: 20
        )
        let messageRect = NSRect(
            x: textRect.minX,
            y: titleRect.maxY + 4,
            width: textRect.width,
            height: 34
        )

        directoryName.draw(
            in: titleRect,
            withAttributes: Self.titleAttributes
        )
        messagePreview.draw(
            with: messageRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: Self.messageAttributes
        )
    }

    private static var titleAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byTruncatingTail
        return [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static var messageAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.82),
            .paragraphStyle: paragraphStyle
        ]
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
