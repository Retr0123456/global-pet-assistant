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

    var onThreadClick: ((ThreadDisplayRow) -> Void)? {
        get {
            petContentView.onThreadClick
        }
        set {
            petContentView.onThreadClick = newValue
        }
    }

    var onThreadDismiss: ((ThreadDisplayRow) -> Void)? {
        get {
            petContentView.onThreadDismiss
        }
        set {
            petContentView.onThreadDismiss = newValue
        }
    }

    var onAgentMessageSubmit: ((ThreadDisplayRow, String) -> Void)? {
        get {
            petContentView.onAgentMessageSubmit
        }
        set {
            petContentView.onAgentMessageSubmit = newValue
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

    var onPetScaleChanged: ((Double) -> Void)? {
        get {
            petContentView.onPetScaleChanged
        }
        set {
            petContentView.onPetScaleChanged = newValue
        }
    }

    init(contentView petView: PetSpriteView, savedOrigin: StoredWindowOrigin?) {
        let contentView = PetWindowContentView(wrapping: petView)
        let frame = FloatingPetWindow.initialFrame(size: contentView.desiredContentSize, savedOrigin: savedOrigin)
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
        true
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

    func updateThreadPanelSnapshot(_ snapshot: ThreadPanelSnapshot?) {
        petContentView.updateThreadPanelSnapshot(snapshot)
    }

    func updateFocusTimerSnapshot(_ snapshot: FocusTimerSnapshot?) {
        petContentView.updateFocusTimerSnapshot(snapshot)
    }

    func applyUserInterfacePreferences(_ preferences: UserInterfacePreferences, display: Bool = false) {
        petContentView.applyUserInterfacePreferences(preferences)
    }

    func showPetResizeControl() {
        petContentView.setPetResizeControlVisible(true)
    }

    private func fitToContentPreservingTopRight() {
        let desiredSize = petContentView.desiredContentSize
        guard frame.size != desiredSize else {
            return
        }

        let nextOriginX = petContentView.preservesRightEdgeOnResize
            ? frame.maxX - desiredSize.width
            : frame.minX
        let nextOriginY = petContentView.preservesTopEdgeOnResize
            ? frame.maxY - desiredSize.height
            : frame.minY
        let nextFrame = NSRect(
            x: nextOriginX,
            y: nextOriginY,
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
    private enum HorizontalPlacement {
        case leading
        case trailing
    }

    private struct PetResizeAnchor {
        let horizontalPlacement: HorizontalPlacement
        let edgeX: CGFloat
        let midY: CGFloat
    }

    private enum ThreadPanelVerticalPlacement {
        case abovePet
        case belowPet
    }

    private static let threadPanelMaxWidth: CGFloat = 320
    private static let threadPanelMinHeight: CGFloat = 58
    private static let threadRowHeight: CGFloat = 58
    private static let threadPanelVerticalInset: CGFloat = 0
    private static let threadStackSpacing: CGFloat = 5
    private static let threadPanelGap: CGFloat = 6
    private static let threadStatusBarGap: CGFloat = 6
    private static let threadStatusBarWidth: CGFloat = 108
    private static let threadStatusBarHeight: CGFloat = 30
    private static let flashStackWidth: CGFloat = 220
    private static let flashRowHeight: CGFloat = 34
    private static let flashStackSpacing: CGFloat = 6
    private static let flashPetGap: CGFloat = 8
    private static let flashTopOffset: CGFloat = 8
    private static let scaleControlWidth: CGFloat = 26
    private static let scaleControlTrackHeight: CGFloat = 92
    private static let scaleControlCloseButtonSize: CGFloat = 18
    private static let scaleControlSpacing: CGFloat = 5
    private static let scaleControlGap: CGFloat = 6
    private static var scaleControlHeight: CGFloat {
        scaleControlCloseButtonSize + scaleControlSpacing + scaleControlTrackHeight
    }

    var onClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDragChanged: ((PetDragDirection?) -> Void)?
    var onThreadClick: ((ThreadDisplayRow) -> Void)?
    var onThreadDismiss: ((ThreadDisplayRow) -> Void)?
    var onAgentMessageSubmit: ((ThreadDisplayRow, String) -> Void)?
    var onFocusTimerCancel: (() -> Void)?
    var onMoveEnded: ((NSPoint) -> Void)?
    var onPetScaleChanged: ((Double) -> Void)?
    var contextMenuProvider: (() -> NSMenu?)?
    var onDesiredSizeChanged: (() -> Void)?
    var preservesRightEdgeOnResize: Bool {
        horizontalPlacement == .trailing
    }
    var preservesTopEdgeOnResize: Bool {
        threadPanelVerticalPlacement == .belowPet
    }

    var desiredContentSize: NSSize {
        let petSize = petView.intrinsicContentSize
        let scaleControlSideWidth = isPetResizeControlVisible ? Self.scaleControlWidth + Self.scaleControlGap : 0
        let flashSideWidth = hasSideStack ? Self.flashStackWidth + Self.flashPetGap : 0
        let primaryWidth = petSize.width + scaleControlSideWidth + flashSideWidth
        let resizeControlHeight = isPetResizeControlVisible ? Self.scaleControlHeight : 0
        let primaryHeight = max(petSize.height, resizeControlHeight, flashStackHeight + Self.flashTopOffset)
        let badgeHeight = isThreadBadgeVisible ? Self.threadStatusBarGap + Self.threadStatusBarHeight : 0

        guard isThreadPanelExpanded else {
            return NSSize(width: primaryWidth, height: primaryHeight + badgeHeight)
        }

        return NSSize(
            width: max(primaryWidth, Self.threadPanelMaxWidth),
            height: primaryHeight + badgeHeight + Self.threadPanelGap + currentThreadPanelHeight
        )
    }

    private let petView: PetSpriteView
    private let petScaleControlContainer = NSView()
    private let petScaleControl = PetScaleControlView()
    private let petScaleCloseButton = NSButton()
    private let threadBadgeButton = ThreadBadgeEffectButton()
    private let threadPanelView = NSView()
    private let threadPanelContentView = NSView()
    private let threadStackView = NSStackView()
    private let flashStackView = NSStackView()
    private var threadPanelHeightConstraint: NSLayoutConstraint?
    private var petTopConstraint: NSLayoutConstraint?
    private var petBelowThreadPanelConstraint: NSLayoutConstraint?
    private var petBelowThreadBadgeConstraint: NSLayoutConstraint?
    private var petLeadingConstraint: NSLayoutConstraint?
    private var petTrailingConstraint: NSLayoutConstraint?
    private var threadPanelTopConstraint: NSLayoutConstraint?
    private var threadPanelBelowPetConstraint: NSLayoutConstraint?
    private var threadPanelBelowThreadBadgeConstraint: NSLayoutConstraint?
    private var threadPanelLeadingConstraint: NSLayoutConstraint?
    private var threadPanelTrailingConstraint: NSLayoutConstraint?
    private var threadBadgeTopConstraint: NSLayoutConstraint?
    private var threadBadgeBelowPetConstraint: NSLayoutConstraint?
    private var threadBadgeBelowThreadPanelConstraint: NSLayoutConstraint?
    private var threadBadgeLeadingConstraint: NSLayoutConstraint?
    private var threadBadgeTrailingConstraint: NSLayoutConstraint?
    private var petWidthConstraint: NSLayoutConstraint?
    private var petHeightConstraint: NSLayoutConstraint?
    private var threadPanelWidthConstraint: NSLayoutConstraint?
    private var scaleControlLeadingConstraint: NSLayoutConstraint?
    private var scaleControlTrailingConstraint: NSLayoutConstraint?
    private var flashLeadingFromPetConstraint: NSLayoutConstraint?
    private var flashLeadingFromScaleControlConstraint: NSLayoutConstraint?
    private var flashTrailingFromPetConstraint: NSLayoutConstraint?
    private var flashTrailingFromScaleControlConstraint: NSLayoutConstraint?
    private var mouseDownScreenPoint: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    private var mouseDownPetScreenOrigin: NSPoint?
    private var didMouseDownOnPet = false
    private var didDrag = false
    private let clickMovementThreshold: CGFloat = 5
    private let dragAnimationThreshold: CGFloat = 1.5
    private var hoverTrackingArea: NSTrackingArea?
    private var threadSnapshot: ThreadPanelSnapshot?
    private var focusTimerSnapshot: FocusTimerSnapshot?
    private var isThreadPanelExpanded = false
    private var isPetResizeControlVisible = false
    private var userInterfacePreferences = UserInterfacePreferences()
    private var horizontalPlacement: HorizontalPlacement = .trailing
    private var threadPanelVerticalPlacement: ThreadPanelVerticalPlacement = .belowPet
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

        configurePetScaleControl()
        configureThreadBadgeButton()
        configureThreadPanel()
        configureFlashStack()

        let panelHeightConstraint = threadPanelView.heightAnchor.constraint(equalToConstant: Self.threadPanelMinHeight)
        threadPanelHeightConstraint = panelHeightConstraint
        let petTopConstraint = petView.topAnchor.constraint(equalTo: topAnchor)
        let petBelowThreadPanelConstraint = petView.topAnchor.constraint(
            equalTo: threadPanelView.bottomAnchor,
            constant: Self.threadPanelGap
        )
        let petBelowThreadBadgeConstraint = petView.topAnchor.constraint(
            equalTo: threadBadgeButton.bottomAnchor,
            constant: Self.threadStatusBarGap
        )
        let petLeadingConstraint = petView.leadingAnchor.constraint(equalTo: leadingAnchor)
        let petTrailingConstraint = petView.trailingAnchor.constraint(equalTo: trailingAnchor)
        let threadPanelTopConstraint = threadPanelView.topAnchor.constraint(equalTo: topAnchor)
        let threadPanelBelowPetConstraint = threadPanelView.topAnchor.constraint(
            equalTo: petView.bottomAnchor,
            constant: Self.threadPanelGap
        )
        let threadPanelBelowThreadBadgeConstraint = threadPanelView.topAnchor.constraint(
            equalTo: threadBadgeButton.bottomAnchor,
            constant: Self.threadPanelGap
        )
        let threadPanelLeadingConstraint = threadPanelView.leadingAnchor.constraint(equalTo: petView.leadingAnchor)
        let threadPanelTrailingConstraint = threadPanelView.trailingAnchor.constraint(equalTo: petView.trailingAnchor)
        let threadBadgeTopConstraint = threadBadgeButton.topAnchor.constraint(equalTo: topAnchor)
        let threadBadgeBelowPetConstraint = threadBadgeButton.topAnchor.constraint(
            equalTo: petView.bottomAnchor,
            constant: Self.threadStatusBarGap
        )
        let threadBadgeBelowThreadPanelConstraint = threadBadgeButton.topAnchor.constraint(
            equalTo: threadPanelView.bottomAnchor,
            constant: Self.threadStatusBarGap
        )
        let threadBadgeLeadingConstraint = threadBadgeButton.leadingAnchor.constraint(equalTo: petView.leadingAnchor)
        let threadBadgeTrailingConstraint = threadBadgeButton.trailingAnchor.constraint(equalTo: petView.trailingAnchor)
        let scaleControlLeadingConstraint = petScaleControlContainer.leadingAnchor.constraint(
            equalTo: petView.trailingAnchor,
            constant: Self.scaleControlGap
        )
        let scaleControlTrailingConstraint = petScaleControlContainer.trailingAnchor.constraint(
            equalTo: petView.leadingAnchor,
            constant: -Self.scaleControlGap
        )
        let flashLeadingFromPetConstraint = flashStackView.leadingAnchor.constraint(
            equalTo: petView.trailingAnchor,
            constant: Self.flashPetGap
        )
        let flashLeadingFromScaleControlConstraint = flashStackView.leadingAnchor.constraint(
            equalTo: petScaleControlContainer.trailingAnchor,
            constant: Self.flashPetGap
        )
        let flashTrailingFromPetConstraint = flashStackView.trailingAnchor.constraint(
            equalTo: petView.leadingAnchor,
            constant: -Self.flashPetGap
        )
        let flashTrailingFromScaleControlConstraint = flashStackView.trailingAnchor.constraint(
            equalTo: petScaleControlContainer.leadingAnchor,
            constant: -Self.flashPetGap
        )
        self.petTopConstraint = petTopConstraint
        self.petBelowThreadPanelConstraint = petBelowThreadPanelConstraint
        self.petBelowThreadBadgeConstraint = petBelowThreadBadgeConstraint
        self.petLeadingConstraint = petLeadingConstraint
        self.petTrailingConstraint = petTrailingConstraint
        self.threadPanelTopConstraint = threadPanelTopConstraint
        self.threadPanelBelowPetConstraint = threadPanelBelowPetConstraint
        self.threadPanelBelowThreadBadgeConstraint = threadPanelBelowThreadBadgeConstraint
        self.threadPanelLeadingConstraint = threadPanelLeadingConstraint
        self.threadPanelTrailingConstraint = threadPanelTrailingConstraint
        self.threadBadgeTopConstraint = threadBadgeTopConstraint
        self.threadBadgeBelowPetConstraint = threadBadgeBelowPetConstraint
        self.threadBadgeBelowThreadPanelConstraint = threadBadgeBelowThreadPanelConstraint
        self.threadBadgeLeadingConstraint = threadBadgeLeadingConstraint
        self.threadBadgeTrailingConstraint = threadBadgeTrailingConstraint
        self.scaleControlLeadingConstraint = scaleControlLeadingConstraint
        self.scaleControlTrailingConstraint = scaleControlTrailingConstraint
        self.flashLeadingFromPetConstraint = flashLeadingFromPetConstraint
        self.flashLeadingFromScaleControlConstraint = flashLeadingFromScaleControlConstraint
        self.flashTrailingFromPetConstraint = flashTrailingFromPetConstraint
        self.flashTrailingFromScaleControlConstraint = flashTrailingFromScaleControlConstraint

        let petWidthConstraint = petView.widthAnchor.constraint(equalToConstant: petView.intrinsicContentSize.width)
        let petHeightConstraint = petView.heightAnchor.constraint(equalToConstant: petView.intrinsicContentSize.height)
        let threadPanelWidthConstraint = threadPanelView.widthAnchor.constraint(equalToConstant: Self.threadPanelMaxWidth)
        self.petWidthConstraint = petWidthConstraint
        self.petHeightConstraint = petHeightConstraint
        self.threadPanelWidthConstraint = threadPanelWidthConstraint

        NSLayoutConstraint.activate([
            petWidthConstraint,
            petHeightConstraint,

            threadBadgeButton.widthAnchor.constraint(equalToConstant: Self.threadStatusBarWidth),
            threadBadgeButton.heightAnchor.constraint(equalToConstant: Self.threadStatusBarHeight),

            petScaleControlContainer.topAnchor.constraint(equalTo: petView.topAnchor),
            petScaleControlContainer.widthAnchor.constraint(equalToConstant: Self.scaleControlWidth),
            petScaleControlContainer.heightAnchor.constraint(equalToConstant: Self.scaleControlHeight),

            threadPanelWidthConstraint,
            panelHeightConstraint,

            flashStackView.topAnchor.constraint(equalTo: petView.topAnchor, constant: Self.flashTopOffset),
            flashStackView.widthAnchor.constraint(equalToConstant: Self.flashStackWidth)
        ])
        applyFloatingSurfacePlacement()

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

        layoutSubtreeIfNeeded()
        let trackingArea = NSTrackingArea(
            rect: petView.frame,
            options: [.activeAlways, .mouseEnteredAndExited],
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
        mouseDownPetScreenOrigin = petScreenFrame()?.origin
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
        if let mouseDownPetScreenOrigin {
            let desiredPetOrigin = NSPoint(
                x: mouseDownPetScreenOrigin.x + delta.x,
                y: mouseDownPetScreenOrigin.y + delta.y
            )
            let desiredPetFrame = NSRect(origin: desiredPetOrigin, size: petView.intrinsicContentSize)
            updateFloatingSurfacePlacement(forPetScreenFrame: desiredPetFrame)
            applyFloatingSurfacePlacement()
            placePet(at: desiredPetOrigin, display: true)
        } else {
            let nextFrame = NSRect(
                x: mouseDownWindowOrigin.x + delta.x,
                y: mouseDownWindowOrigin.y + delta.y,
                width: window.frame.width,
                height: window.frame.height
            )
            window.setFrame(FloatingPetWindow.constrainedFrame(nextFrame), display: true)
        }

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
            updateFloatingSurfacePlacement()
            applyFloatingSurfacePlacement(preservingPetPosition: true)
            onDragChanged?(nil)
            onMoveEnded?(window.frame.origin)
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
        mouseDownPetScreenOrigin = nil
        didMouseDownOnPet = false
        didDrag = false
    }

    private func updatePetSizeConstraints() {
        let size = petView.intrinsicContentSize
        petWidthConstraint?.constant = size.width
        petHeightConstraint?.constant = size.height
    }

    func applyUserInterfacePreferences(_ preferences: UserInterfacePreferences) {
        applyUserInterfacePreferences(preferences, display: false)
    }

    private func applyUserInterfacePreferences(_ preferences: UserInterfacePreferences, display: Bool) {
        let preferences = preferences.clamped()
        let previousPetAnchor = petResizeAnchor()
        let previousSize = desiredContentSize
        userInterfacePreferences = preferences
        petScaleControl.scale = preferences.petScale
        petView.setDisplayScaleMultiplier(CGFloat(preferences.petScale))
        updatePetSizeConstraints()
        updateThreadPanelHeight()
        applyFloatingSurfacePlacement()

        let nextSize = desiredContentSize
        if previousSize != nextSize {
            frame.size = nextSize
            onDesiredSizeChanged?()
        }

        if let previousPetAnchor {
            placePet(at: previousPetAnchor, display: display)
        }
    }

    func setPetResizeControlVisible(_ isVisible: Bool) {
        guard isPetResizeControlVisible != isVisible else {
            return
        }

        let previousPetAnchor = petResizeAnchor()
        let previousSize = desiredContentSize
        isPetResizeControlVisible = isVisible
        petScaleControlContainer.isHidden = !isVisible
        updateFloatingSurfacePlacement()
        applyFloatingSurfacePlacement()

        let nextSize = desiredContentSize
        if previousSize != nextSize {
            frame.size = nextSize
            onDesiredSizeChanged?()
        }

        if let previousPetAnchor {
            placePet(at: previousPetAnchor, display: true)
        }
    }

    func updateThreadSnapshot(_ snapshot: EventRouterSnapshot?) {
        updateThreadPanelSnapshot(ThreadPanelSnapshot(
            genericThreads: snapshot?.activeThreads ?? [],
            flashMessages: snapshot?.flashMessages ?? []
        ))
    }

    func updateThreadPanelSnapshot(_ snapshot: ThreadPanelSnapshot?) {
        updateFloatingSurfacePlacement()
        let previousSize = desiredContentSize
        threadSnapshot = snapshot

        if snapshot?.activeCount ?? 0 == 0 {
            isThreadPanelExpanded = false
        }

        updateThreadBadge()
        rebuildFlashStack()
        rebuildThreadPanel()
        updateThreadPanelHeight()
        applyThreadPanelVisibility()
        applyFloatingSurfacePlacement(preservingPetPosition: true)

        let nextSize = desiredContentSize
        if previousSize != nextSize {
            frame.size = nextSize
            onDesiredSizeChanged?()
        }
    }

    func updateFocusTimerSnapshot(_ snapshot: FocusTimerSnapshot?) {
        updateFloatingSurfacePlacement()
        let previousSize = desiredContentSize
        focusTimerSnapshot = snapshot
        rebuildFlashStack()
        applyFloatingSurfacePlacement(preservingPetPosition: true)

        let nextSize = desiredContentSize
        if previousSize != nextSize {
            frame.size = nextSize
            onDesiredSizeChanged?()
        }
    }

    @objc private func toggleThreadPanel() {
        guard threadSnapshot?.activeCount ?? 0 > 0 else {
            return
        }

        updateFloatingSurfacePlacement()
        let previousSize = desiredContentSize
        isThreadPanelExpanded.toggle()
        updateThreadBadge()
        updateThreadPanelHeight()
        applyThreadPanelVisibility()
        applyFloatingSurfacePlacement(preservingPetPosition: true)

        let nextSize = desiredContentSize
        if previousSize != nextSize {
            frame.size = nextSize
            onDesiredSizeChanged?()
        }
    }

    private func configureThreadBadgeButton() {
        addSubview(threadBadgeButton)
        threadBadgeButton.translatesAutoresizingMaskIntoConstraints = false
        threadBadgeButton.onPress = { [weak self] in
            self?.toggleThreadPanel()
        }
    }

    private func configureThreadPanel() {
        addSubview(threadPanelView)
        threadPanelView.translatesAutoresizingMaskIntoConstraints = false
        threadPanelView.addSubview(threadPanelContentView)

        threadPanelContentView.translatesAutoresizingMaskIntoConstraints = false

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

    private func configurePetScaleControl() {
        addSubview(petScaleControlContainer)
        petScaleControlContainer.translatesAutoresizingMaskIntoConstraints = false
        petScaleControlContainer.isHidden = true
        petScaleControlContainer.wantsLayer = true
        petScaleControlContainer.layer?.backgroundColor = NSColor.clear.cgColor

        petScaleControlContainer.addSubview(petScaleCloseButton)
        petScaleCloseButton.translatesAutoresizingMaskIntoConstraints = false
        petScaleCloseButton.isBordered = false
        petScaleCloseButton.bezelStyle = .regularSquare
        petScaleCloseButton.focusRingType = .none
        petScaleCloseButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Close resize control"
        )
        petScaleCloseButton.imagePosition = .imageOnly
        petScaleCloseButton.imageScaling = .scaleProportionallyDown
        petScaleCloseButton.contentTintColor = NSColor.secondaryLabelColor
        petScaleCloseButton.target = self
        petScaleCloseButton.action = #selector(closePetResizeControl)
        petScaleCloseButton.setButtonType(.momentaryPushIn)

        petScaleControlContainer.addSubview(petScaleControl)
        petScaleControl.translatesAutoresizingMaskIntoConstraints = false
        petScaleControl.onScaleChanged = { [weak self] scale in
            guard let self else {
                return
            }

            var nextPreferences = self.userInterfacePreferences
            nextPreferences.petScale = scale
            self.applyUserInterfacePreferences(nextPreferences, display: true)
            self.onPetScaleChanged?(self.userInterfacePreferences.petScale)
        }

        NSLayoutConstraint.activate([
            petScaleCloseButton.topAnchor.constraint(equalTo: petScaleControlContainer.topAnchor),
            petScaleCloseButton.centerXAnchor.constraint(equalTo: petScaleControlContainer.centerXAnchor),
            petScaleCloseButton.widthAnchor.constraint(equalToConstant: Self.scaleControlCloseButtonSize),
            petScaleCloseButton.heightAnchor.constraint(equalToConstant: Self.scaleControlCloseButtonSize),

            petScaleControl.topAnchor.constraint(
                equalTo: petScaleCloseButton.bottomAnchor,
                constant: Self.scaleControlSpacing
            ),
            petScaleControl.centerXAnchor.constraint(equalTo: petScaleControlContainer.centerXAnchor),
            petScaleControl.widthAnchor.constraint(equalToConstant: Self.scaleControlWidth),
            petScaleControl.heightAnchor.constraint(equalToConstant: Self.scaleControlTrackHeight),
            petScaleControl.bottomAnchor.constraint(equalTo: petScaleControlContainer.bottomAnchor)
        ])
    }

    @objc private func closePetResizeControl() {
        setPetResizeControlVisible(false)
    }

    private func updateFloatingSurfacePlacement(forPetScreenFrame petScreenFrame: NSRect? = nil) {
        guard let window else {
            return
        }

        layoutSubtreeIfNeeded()
        let referenceFrame = petScreenFrame ?? self.petScreenFrame() ?? window.frame
        let screen = NSScreen.screens.first { screen in
            screen.visibleFrame.intersects(referenceFrame)
        } ?? window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return
        }

        let petCenter = referenceFrame.center
        horizontalPlacement = petCenter.x < visibleFrame.midX ? .leading : .trailing
        threadPanelVerticalPlacement = petCenter.y < visibleFrame.midY ? .abovePet : .belowPet
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
        scaleControlLeadingConstraint?.isActive = false
        scaleControlTrailingConstraint?.isActive = false
        flashLeadingFromPetConstraint?.isActive = false
        flashLeadingFromScaleControlConstraint?.isActive = false
        flashTrailingFromPetConstraint?.isActive = false
        flashTrailingFromScaleControlConstraint?.isActive = false

        if horizontalPlacement == .leading {
            petLeadingConstraint?.isActive = true
            scaleControlLeadingConstraint?.isActive = true
            if hasMessages {
                if isPetResizeControlVisible {
                    flashLeadingFromScaleControlConstraint?.isActive = true
                } else {
                    flashLeadingFromPetConstraint?.isActive = true
                }
            }
        } else {
            petTrailingConstraint?.isActive = true
            scaleControlTrailingConstraint?.isActive = true
            if hasMessages {
                if isPetResizeControlVisible {
                    flashTrailingFromScaleControlConstraint?.isActive = true
                } else {
                    flashTrailingFromPetConstraint?.isActive = true
                }
            }
        }
    }

    private func applyThreadPanelPlacement() {
        petTopConstraint?.isActive = false
        petBelowThreadPanelConstraint?.isActive = false
        petBelowThreadBadgeConstraint?.isActive = false
        threadPanelTopConstraint?.isActive = false
        threadPanelBelowPetConstraint?.isActive = false
        threadPanelBelowThreadBadgeConstraint?.isActive = false
        threadPanelLeadingConstraint?.isActive = false
        threadPanelTrailingConstraint?.isActive = false
        threadBadgeTopConstraint?.isActive = false
        threadBadgeBelowPetConstraint?.isActive = false
        threadBadgeBelowThreadPanelConstraint?.isActive = false
        threadBadgeLeadingConstraint?.isActive = false
        threadBadgeTrailingConstraint?.isActive = false

        let hasBadge = isThreadBadgeVisible
        let hasPanel = isThreadPanelVisible

        if threadPanelVerticalPlacement == .abovePet {
            if hasPanel {
                threadPanelTopConstraint?.isActive = true
                if hasBadge {
                    threadBadgeBelowThreadPanelConstraint?.isActive = true
                    petBelowThreadBadgeConstraint?.isActive = true
                } else {
                    petBelowThreadPanelConstraint?.isActive = true
                }
            } else if hasBadge {
                threadBadgeTopConstraint?.isActive = true
                petBelowThreadBadgeConstraint?.isActive = true
            } else {
                petTopConstraint?.isActive = true
            }
        } else {
            petTopConstraint?.isActive = true
            if hasBadge {
                threadBadgeBelowPetConstraint?.isActive = true
                if hasPanel {
                    threadPanelBelowThreadBadgeConstraint?.isActive = true
                }
            } else if hasPanel {
                threadPanelBelowPetConstraint?.isActive = true
            }
        }

        switch horizontalPlacement {
        case .leading:
            threadPanelLeadingConstraint?.isActive = true
            threadBadgeLeadingConstraint?.isActive = true
        case .trailing:
            threadPanelTrailingConstraint?.isActive = true
            threadBadgeTrailingConstraint?.isActive = true
        }
    }

    private func applyFloatingSurfacePlacement(preservingPetPosition: Bool = false) {
        guard preservingPetPosition else {
            applyThreadPanelPlacement()
            applyFlashVisibilityAndPlacement()
            return
        }

        let originalPetOrigin = petScreenFrame()?.origin
        applyThreadPanelPlacement()
        applyFlashVisibilityAndPlacement()

        if let originalPetOrigin {
            placePet(at: originalPetOrigin, display: false)
        }
    }

    private func petScreenFrame() -> NSRect? {
        guard let window else {
            return nil
        }

        layoutSubtreeIfNeeded()
        let petFrameInWindow = convert(petView.frame, to: nil)
        return NSRect(
            x: window.frame.minX + petFrameInWindow.minX,
            y: window.frame.minY + petFrameInWindow.minY,
            width: petFrameInWindow.width,
            height: petFrameInWindow.height
        )
    }

    private func petResizeAnchor() -> PetResizeAnchor? {
        guard let petFrame = petScreenFrame() else {
            return nil
        }

        switch horizontalPlacement {
        case .leading:
            return PetResizeAnchor(
                horizontalPlacement: .leading,
                edgeX: petFrame.minX,
                midY: petFrame.midY
            )
        case .trailing:
            return PetResizeAnchor(
                horizontalPlacement: .trailing,
                edgeX: petFrame.maxX,
                midY: petFrame.midY
            )
        }
    }

    private func placePet(at screenOrigin: NSPoint, display: Bool) {
        guard let window else {
            return
        }

        layoutSubtreeIfNeeded()
        let petFrameInWindow = convert(petView.frame, to: nil)
        let nextFrame = NSRect(
            x: screenOrigin.x - petFrameInWindow.minX,
            y: screenOrigin.y - petFrameInWindow.minY,
            width: window.frame.width,
            height: window.frame.height
        )
        window.setFrame(FloatingPetWindow.constrainedFrame(nextFrame), display: display)
    }

    private func placePet(at anchor: PetResizeAnchor, display: Bool) {
        guard let window else {
            return
        }

        layoutSubtreeIfNeeded()
        let petFrameInWindow = convert(petView.frame, to: nil)
        let nextOriginX: CGFloat
        switch anchor.horizontalPlacement {
        case .leading:
            nextOriginX = anchor.edgeX - petFrameInWindow.minX
        case .trailing:
            nextOriginX = anchor.edgeX - petFrameInWindow.maxX
        }
        let nextFrame = NSRect(
            x: nextOriginX,
            y: anchor.midY - petFrameInWindow.midY,
            width: window.frame.width,
            height: window.frame.height
        )
        window.setFrame(FloatingPetWindow.constrainedFrame(nextFrame), display: display)
    }

    private func updateThreadBadge() {
        let summary = threadSnapshot?.statusSummary ?? .empty
        threadBadgeButton.update(summary: summary, isExpanded: isThreadPanelExpanded)
    }

    private func rebuildThreadPanel() {
        threadStackView.arrangedSubviews.forEach { view in
            threadStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let threads = threadSnapshot?.displayRows ?? []
        for thread in threads {
            threadStackView.addArrangedSubview(makeThreadRow(for: thread))
        }
    }

    private func makeThreadRow(for thread: ThreadDisplayRow) -> NSView {
        let row = ThreadMessageRowView(
            thread: thread,
            onOpen: { [weak self] thread in
                self?.onThreadClick?(thread)
            },
            onDismiss: { [weak self] thread in
                self?.onThreadDismiss?(thread)
            },
            onSendMessage: { [weak self] thread, message in
                self?.onAgentMessageSubmit?(thread, message)
            }
        )
        row.heightAnchor.constraint(equalToConstant: Self.threadRowHeight).isActive = true
        row.widthAnchor.constraint(equalToConstant: Self.threadPanelMaxWidth).isActive = true

        return row
    }

    private func applyThreadPanelVisibility() {
        threadPanelView.isHidden = !isThreadPanelVisible
    }

    private var isThreadPanelVisible: Bool {
        isThreadPanelExpanded && (threadSnapshot?.activeCount ?? 0) > 0
    }

    private var isThreadBadgeVisible: Bool {
        (threadSnapshot?.activeCount ?? 0) > 0
    }

    private var currentThreadPanelHeight: CGFloat {
        guard isThreadPanelExpanded else {
            return Self.threadPanelMinHeight
        }

        let rows = threadSnapshot?.displayRows ?? []
        let threadCount = max(rows.count, 1)
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

private final class PetScaleControlView: NSView {
    private static let verticalPadding: CGFloat = 10
    private static let trackWidth: CGFloat = 4
    private static let knobSize: CGFloat = 15

    var onScaleChanged: ((Double) -> Void)?
    private var storedScale = UserInterfacePreferences.defaultPetScale

    var scale: Double {
        get {
            storedScale
        }
        set {
            storedScale = UserInterfacePreferences(petScale: newValue).clamped().petScale
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        updateScale(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateScale(from: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let travelHeight = max(1, bounds.height - Self.verticalPadding * 2)
        let normalized = CGFloat(
            (scale - UserInterfacePreferences.minimumPetScale)
                / (UserInterfacePreferences.maximumPetScale - UserInterfacePreferences.minimumPetScale)
        )
        let knobCenterY = Self.verticalPadding + normalized * travelHeight
        let trackX = bounds.midX - Self.trackWidth / 2
        let trackRect = NSRect(
            x: trackX,
            y: Self.verticalPadding,
            width: Self.trackWidth,
            height: travelHeight
        )
        let activeRect = NSRect(
            x: trackX,
            y: Self.verticalPadding,
            width: Self.trackWidth,
            height: max(2, knobCenterY - Self.verticalPadding)
        )
        let knobRect = NSRect(
            x: bounds.midX - Self.knobSize / 2,
            y: knobCenterY - Self.knobSize / 2,
            width: Self.knobSize,
            height: Self.knobSize
        )

        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 2, yRadius: 2).fill()

        NSColor.systemTeal.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: activeRect, xRadius: 2, yRadius: 2).fill()

        NSColor.black.withAlphaComponent(0.32).setFill()
        NSBezierPath(ovalIn: knobRect.insetBy(dx: -2, dy: -2)).fill()

        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: knobRect).fill()

        NSColor.systemTeal.withAlphaComponent(0.95).setStroke()
        let knobPath = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.5, dy: 0.5))
        knobPath.lineWidth = 1.5
        knobPath.stroke()
    }

    private func updateScale(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let travelHeight = max(1, bounds.height - Self.verticalPadding * 2)
        let normalized = min(
            1,
            max(0, (point.y - Self.verticalPadding) / travelHeight)
        )
        let nextScale = UserInterfacePreferences.minimumPetScale
            + Double(normalized) * (UserInterfacePreferences.maximumPetScale - UserInterfacePreferences.minimumPetScale)

        scale = nextScale
        onScaleChanged?(scale)
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

private enum ThreadVisualEffectStyle {
    @MainActor static func configureBadge(_ effectView: NSVisualEffectView, cornerRadius: CGFloat) {
        configure(effectView, cornerRadius: cornerRadius, material: .hudWindow, borderAlpha: 0.26)
    }

    @MainActor static func configurePanelRow(_ effectView: NSVisualEffectView, cornerRadius: CGFloat) {
        configure(effectView, cornerRadius: cornerRadius, material: .hudWindow, borderAlpha: 0.28)
    }

    @MainActor static func configureReplyControl(_ effectView: NSVisualEffectView, cornerRadius: CGFloat) {
        configure(effectView, cornerRadius: cornerRadius, material: .hudWindow, borderAlpha: 0.12)
    }

    @MainActor private static func configure(
        _ effectView: NSVisualEffectView,
        cornerRadius: CGFloat,
        material: NSVisualEffectView.Material,
        borderAlpha: CGFloat
    ) {
        effectView.material = material
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
    }
}

private final class PassthroughVisualEffectView: NSVisualEffectView {
    var contentView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let contentView {
                addSubview(contentView)
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point) else {
            return nil
        }

        if hitView.isDescendant(ofType: NSButton.self)
            || hitView.isDescendant(ofType: NSTextField.self) {
            return hitView
        }

        return nil
    }
}

private final class ThreadBadgeEffectButton: NSView {
    private static let cornerRadius: CGFloat = 10
    private static let chevronSize: CGFloat = 10

    var onPress: (() -> Void)?

    private let effectView = PassthroughVisualEffectView()
    private let contentView = NSView()
    private let stackView = NSStackView()
    private let failedSegment = ThreadStatusCountSegmentView(color: .systemRed)
    private let runningSegment = ThreadStatusCountSegmentView(color: .systemYellow)
    private let successSegment = ThreadStatusCountSegmentView(color: .systemGreen)
    private let chevronView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseUp(with event: NSEvent) {
        onPress?()
    }

    func update(summary: ThreadStatusSummary, isExpanded: Bool) {
        isHidden = summary.totalCount == 0
        failedSegment.update(count: summary.failedCount)
        runningSegment.update(count: summary.runningCount)
        successSegment.update(count: summary.successCount)
        chevronView.isHidden = !isExpanded
        toolTip = isExpanded ? "Hide thread details. \(summary.tooltip)" : "Show thread details. \(summary.tooltip)"
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(effectView)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        ThreadVisualEffectStyle.configureBadge(effectView, cornerRadius: Self.cornerRadius)
        effectView.contentView = contentView

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
        contentView.layer?.cornerRadius = Self.cornerRadius
        contentView.layer?.masksToBounds = true

        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 6
        stackView.addArrangedSubview(failedSegment)
        stackView.addArrangedSubview(runningSegment)
        stackView.addArrangedSubview(successSegment)
        stackView.addArrangedSubview(chevronView)

        chevronView.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: "Hide thread details"
        )
        chevronView.contentTintColor = NSColor.white.withAlphaComponent(0.86)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.isHidden = true

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: effectView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            chevronView.widthAnchor.constraint(equalToConstant: Self.chevronSize),
            chevronView.heightAnchor.constraint(equalToConstant: Self.chevronSize)
        ])
    }
}

private final class ThreadStatusCountSegmentView: NSView {
    private static let dotSize: CGFloat = 6
    private static let labelWidth: CGFloat = 15

    private let dotView = NSView()
    private let textField = NSTextField(labelWithString: "0")
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(count: Int) {
        textField.stringValue = "\(min(count, 99))"
        textField.toolTip = count > 99 ? "\(count)" : nil
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = color.cgColor
        dotView.layer?.cornerRadius = Self.dotSize / 2
        addSubview(dotView)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.alignment = .left
        textField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        textField.textColor = NSColor.white.withAlphaComponent(0.92)
        addSubview(textField)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: Self.dotSize),
            dotView.heightAnchor.constraint(equalToConstant: Self.dotSize),

            textField.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 3),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: Self.labelWidth),

            heightAnchor.constraint(equalToConstant: 16)
        ])
    }
}

private final class ThreadMessageRowView: NSView {
    private static let cornerRadius: CGFloat = 12
    private static let statusBadgeSize: CGFloat = 24
    private static let closeButtonSize: CGFloat = 18
    private static let actionReserveWidth: CGFloat = 24
    private static let fixedHeight: CGFloat = 58
    private static let replyControlRadius: CGFloat = 10
    private static let replyControlHeight: CGFloat = 28
    private static let replyButtonWidth: CGFloat = 66
    private static let replyInputWidth: CGFloat = 230
    private static let replyRestingFillAlpha: CGFloat = 0.07
    private static let replyActiveFillAlpha: CGFloat = 0.13
    private static let replyRestingBorderAlpha: CGFloat = 0.18
    private static let replyActiveBorderAlpha: CGFloat = 0.34

    private let thread: ThreadDisplayRow
    private let onOpen: (ThreadDisplayRow) -> Void
    private let onDismiss: (ThreadDisplayRow) -> Void
    private let onSendMessage: (ThreadDisplayRow, String) -> Void
    private let effectView: PassthroughVisualEffectView
    private let contentView = ThreadRowContentView()
    private let statusBadgeView: ThreadStatusBadgeView
    private let textView: ThreadMessageTextView
    private let replyControlEffectView = PassthroughVisualEffectView()
    private let replyControlContentView = NSView()
    private let replyButton = ReplyTextButton()
    private let messageField = ReplyTextField()
    private let sendButton = ReplySendButton()
    private let closeButton = NSButton()
    private var hoverTrackingArea: NSTrackingArea?
    private var replyControlWidthConstraint: NSLayoutConstraint?
    private var isReplying = false

    init(
        thread: ThreadDisplayRow,
        onOpen: @escaping (ThreadDisplayRow) -> Void,
        onDismiss: @escaping (ThreadDisplayRow) -> Void,
        onSendMessage: @escaping (ThreadDisplayRow, String) -> Void
    ) {
        self.thread = thread
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        self.onSendMessage = onSendMessage
        self.effectView = PassthroughVisualEffectView()
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateReplyControlChrome()
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
        if thread.canSendMessage, !isReplying {
            setReplyOverlayVisible(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
        if !isReplying {
            setReplyOverlayVisible(false)
        }
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

        addSubview(effectView)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        ThreadVisualEffectStyle.configurePanelRow(effectView, cornerRadius: Self.cornerRadius)
        effectView.contentView = contentView

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
        contentView.layer?.cornerRadius = Self.cornerRadius
        contentView.layer?.masksToBounds = true

        contentView.addSubview(statusBadgeView)
        statusBadgeView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false

        if thread.canSendMessage {
            contentView.addSubview(replyControlEffectView)
            replyControlEffectView.translatesAutoresizingMaskIntoConstraints = false
            ThreadVisualEffectStyle.configureReplyControl(replyControlEffectView, cornerRadius: Self.replyControlRadius)
            replyControlEffectView.contentView = replyControlContentView
            replyControlEffectView.isHidden = true

            replyControlContentView.translatesAutoresizingMaskIntoConstraints = false
            replyControlContentView.wantsLayer = true
            replyControlContentView.layer?.cornerRadius = Self.replyControlRadius
            replyControlContentView.layer?.masksToBounds = true

            replyControlContentView.addSubview(replyButton)
            replyButton.translatesAutoresizingMaskIntoConstraints = false
            replyButton.onPress = { [weak self] in
                self?.beginReply()
            }

            replyControlContentView.addSubview(messageField)
            messageField.translatesAutoresizingMaskIntoConstraints = false
            messageField.placeholderString = "Message"
            messageField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            messageField.lineBreakMode = .byTruncatingTail
            messageField.target = self
            messageField.action = #selector(sendMessage)
            messageField.isHidden = true

            replyControlContentView.addSubview(sendButton)
            sendButton.translatesAutoresizingMaskIntoConstraints = false
            sendButton.target = self
            sendButton.action = #selector(sendMessage)
            sendButton.isHidden = true

            updateReplyControlChrome()
        }

        contentView.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = true
        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Dismiss notification"
        )
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(dismissNotification)
        closeButton.setButtonType(.momentaryPushIn)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: effectView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -7),
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            closeButton.widthAnchor.constraint(equalToConstant: Self.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Self.closeButtonSize),

            statusBadgeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            statusBadgeView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusBadgeView.widthAnchor.constraint(equalToConstant: Self.statusBadgeSize),
            statusBadgeView.heightAnchor.constraint(equalToConstant: Self.statusBadgeSize),

            textView.leadingAnchor.constraint(equalTo: statusBadgeView.trailingAnchor, constant: 10),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.actionReserveWidth),
            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        if thread.canSendMessage {
            let widthConstraint = replyControlEffectView.widthAnchor.constraint(equalToConstant: Self.replyButtonWidth)
            replyControlWidthConstraint = widthConstraint
            NSLayoutConstraint.activate([
                replyControlEffectView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
                replyControlEffectView.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: -6),
                widthConstraint,
                replyControlEffectView.heightAnchor.constraint(equalToConstant: Self.replyControlHeight),

                replyControlContentView.leadingAnchor.constraint(equalTo: replyControlEffectView.leadingAnchor),
                replyControlContentView.trailingAnchor.constraint(equalTo: replyControlEffectView.trailingAnchor),
                replyControlContentView.topAnchor.constraint(equalTo: replyControlEffectView.topAnchor),
                replyControlContentView.bottomAnchor.constraint(equalTo: replyControlEffectView.bottomAnchor),

                replyButton.leadingAnchor.constraint(equalTo: replyControlContentView.leadingAnchor),
                replyButton.trailingAnchor.constraint(equalTo: replyControlContentView.trailingAnchor),
                replyButton.topAnchor.constraint(equalTo: replyControlContentView.topAnchor),
                replyButton.bottomAnchor.constraint(equalTo: replyControlContentView.bottomAnchor),

                messageField.leadingAnchor.constraint(equalTo: replyControlContentView.leadingAnchor, constant: 10),
                messageField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6),
                messageField.centerYAnchor.constraint(equalTo: replyControlContentView.centerYAnchor),

                sendButton.trailingAnchor.constraint(equalTo: replyControlContentView.trailingAnchor, constant: -8),
                sendButton.centerYAnchor.constraint(equalTo: messageField.centerYAnchor),
                sendButton.widthAnchor.constraint(equalToConstant: 24),
                sendButton.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
    }

    @objc private func dismissNotification() {
        onDismiss(thread)
    }

    @objc private func beginReply() {
        isReplying = true
        setReplyOverlayVisible(true)
        replyControlWidthConstraint?.constant = Self.replyInputWidth
        replyButton.isHidden = true
        messageField.isHidden = false
        sendButton.isHidden = false
        updateReplyControlChrome()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(messageField)
    }

    @objc private func sendMessage() {
        let message = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return
        }
        messageField.stringValue = ""
        isReplying = false
        replyControlWidthConstraint?.constant = Self.replyButtonWidth
        messageField.isHidden = true
        sendButton.isHidden = true
        replyButton.isHidden = false
        updateReplyControlChrome()
        setReplyOverlayVisible(false)
        onSendMessage(thread, message)
    }

    private func setReplyOverlayVisible(_ isVisible: Bool) {
        guard thread.canSendMessage else {
            return
        }
        replyControlEffectView.isHidden = !isVisible
        if isVisible, !isReplying {
            replyControlWidthConstraint?.constant = Self.replyButtonWidth
            replyButton.isHidden = false
            messageField.isHidden = true
            sendButton.isHidden = true
        }
        updateReplyControlChrome()
    }

    private func updateReplyControlChrome() {
        guard thread.canSendMessage else {
            return
        }

        let fillAlpha = isReplying ? Self.replyActiveFillAlpha : Self.replyRestingFillAlpha
        let borderAlpha = isReplying ? Self.replyActiveBorderAlpha : Self.replyRestingBorderAlpha
        let borderWidth: CGFloat = isReplying ? 1.2 : 1.0
        var fillColor = NSColor.labelColor.withAlphaComponent(fillAlpha).cgColor
        var borderColor = NSColor.labelColor.withAlphaComponent(borderAlpha).cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fillColor = NSColor.labelColor.withAlphaComponent(fillAlpha).cgColor
            borderColor = NSColor.labelColor.withAlphaComponent(borderAlpha).cgColor
        }

        replyControlContentView.layer?.backgroundColor = fillColor
        replyControlEffectView.layer?.borderWidth = borderWidth
        replyControlEffectView.layer?.borderColor = borderColor
    }
}

private final class ReplyTextButton: NSView {
    var onPress: (() -> Void)?

    private let textField = NSTextField(labelWithString: "Reply")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseUp(with event: NSEvent) {
        onPress?()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        textField.textColor = NSColor.labelColor
        textField.alignment = .center
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class ReplyTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupField()
    }

    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    private func setupField() {
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        textColor = NSColor.labelColor
        placeholderAttributedString = NSAttributedString(
            string: "Message",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 12, weight: .regular)
            ]
        )
    }
}

private final class ReplySendButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
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
        contentTintColor = NSColor.controlAccentColor
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = NSColor.labelColor
    }

    private func setupButton() {
        isBordered = false
        image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send message")
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = NSColor.labelColor
        setButtonType(.momentaryPushIn)
    }
}

private final class ThreadRowContentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point) else {
            return nil
        }

        if hitView.isDescendant(ofType: NSButton.self)
            || hitView.isDescendant(ofType: NSTextField.self) {
            return hitView
        }

        return nil
    }
}

private extension NSView {
    func isDescendant<T: NSView>(ofType type: T.Type) -> Bool {
        var view: NSView? = self
        while let currentView = view {
            if currentView is T {
                return true
            }
            view = currentView.superview
        }
        return false
    }
}

private final class ThreadStatusBadgeView: NSView {
    private static let iconSize: CGFloat = 14

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
        layer?.cornerRadius = 12
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

    init(thread: ThreadDisplayRow) {
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

        let textRect = bounds.insetBy(dx: 0, dy: 8)
        let titleRect = NSRect(
            x: textRect.minX,
            y: textRect.minY,
            width: textRect.width,
            height: 17
        )
        let messageRect = NSRect(
            x: textRect.minX,
            y: titleRect.maxY + 2,
            width: textRect.width,
            height: 26
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
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
            .paragraphStyle: paragraphStyle
        ]
    }

    private static var messageAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.78),
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
