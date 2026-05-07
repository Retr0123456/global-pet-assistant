import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var petWindow: FloatingPetWindow?
    private var spriteView: PetSpriteView?
    private var petBehaviorController: PetBehaviorController?
    private var statusItem: NSStatusItem?
    private var pauseEventsItem: NSMenuItem?
    private var muteCurrentSourceItem: NSMenuItem?
    private var unmuteAllSourcesItem: NSMenuItem?
    private var focusTimerMenuItem: NSMenuItem?
    private var switchPetMenuItem: NSMenuItem?
    private var eventRouter: EventRouter?
    private var focusTimerController: FocusTimerController?
    private var eventServer: LocalEventServer?
    private var agentDiscoveryService: AgentDiscoveryService?
    private let actionHandler = ActionHandler()
    private var eventPreferences = EventPreferences()
    private var appConfiguration = AppConfiguration.defaultConfiguration
    private var authorizationToken = ""
    private var currentPetPackage: PetPackage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try AppStorage.ensureLayout()
            AuditLogger.appendRuntime(status: "app_launching", message: "GlobalPetAssistant applicationDidFinishLaunching")
            appConfiguration = AppStorage.loadConfiguration()
            authorizationToken = try AppStorage.loadOrCreateToken()
            eventPreferences = AppStorage.loadEventPreferences()
            let (package, atlas) = try loadDisplayPet()
            NSLog("GlobalPetAssistant loaded pet '\(package.id)' from \(package.directoryURL.path)")
            AuditLogger.appendRuntime(status: "pet_loaded", message: "\(package.id) \(package.directoryURL.path)")
            let spriteView = PetSpriteView(atlas: atlas)
            let behaviorController = PetBehaviorController(spriteView: spriteView)
            let window = FloatingPetWindow(
                contentView: spriteView,
                savedOrigin: AppStorage.loadWindowOrigin()
            )
            window.onPetClick = { [weak self] in
                self?.handlePetClick()
            }
            window.onThreadClick = { [weak self] thread in
                _ = self?.performAction(thread.action, source: thread.source)
            }
            window.onThreadDismiss = { [weak self] thread in
                self?.eventRouter?.clearSource(thread.source)
            }
            window.onFocusTimerCancel = { [weak self] in
                self?.cancelFocusTimer()
            }
            window.onPetHoverChanged = { [weak self] isInside in
                self?.petBehaviorController?.handleHoverChanged(isInside: isInside)
            }
            window.onPetDragChanged = { [weak self] direction in
                self?.petBehaviorController?.handleDragChanged(direction: direction)
            }
            window.contextMenuProvider = { [weak self] in
                self?.makePetContextMenu()
            }
            window.onMoveEnded = { origin in
                try? AppStorage.saveWindowOrigin(StoredWindowOrigin(
                    x: origin.x,
                    y: origin.y
                ))
            }

            self.petWindow = window
            self.spriteView = spriteView
            self.petBehaviorController = behaviorController
            self.currentPetPackage = package
            let focusTimerController = FocusTimerController(
                onSnapshotChange: { [weak self] snapshot in
                    self?.petWindow?.updateFocusTimerSnapshot(snapshot)
                    self?.rebuildFocusTimerMenu()
                },
                onCompleted: { [weak self] _ in
                    self?.petWindow?.show()
                    self?.petBehaviorController?.previewState(.waving, duration: 1.5)
                    AuditLogger.appendRuntime(status: "focus_timer_completed", message: "Focus timer completed")
                }
            )
            self.focusTimerController = focusTimerController
            installStatusMenu()
            installEventRouter()
            startEventServer()
            startAgentDiscoveryService()
            window.updateFocusTimerSnapshot(focusTimerController.snapshot)
            window.show()
            AuditLogger.appendRuntime(status: "pet_window_shown", message: "Initial pet window shown")
        } catch {
            AuditLogger.appendRuntime(status: "startup_failed", message: String(describing: error))
            showStartupError(error)
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        agentDiscoveryService?.stop()
        eventServer?.stop()
        AuditLogger.appendRuntime(status: "app_terminating", message: "GlobalPetAssistant applicationWillTerminate")
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(
            systemSymbolName: "pawprint.fill",
            accessibilityDescription: "Global Pet Assistant"
        ) {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "Pet"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Show Pet", action: #selector(showPet), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Pet", action: #selector(hidePet), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let pauseEventsItem = NSMenuItem(title: "Pause Events", action: #selector(togglePauseEvents), keyEquivalent: "")
        menu.addItem(pauseEventsItem)
        self.pauseEventsItem = pauseEventsItem

        let muteCurrentSourceItem = NSMenuItem(title: "Mute Current Source", action: #selector(muteCurrentSource), keyEquivalent: "")
        menu.addItem(muteCurrentSourceItem)
        self.muteCurrentSourceItem = muteCurrentSourceItem

        let unmuteAllSourcesItem = NSMenuItem(title: "Unmute All Sources", action: #selector(unmuteAllSources), keyEquivalent: "")
        menu.addItem(unmuteAllSourcesItem)
        self.unmuteAllSourcesItem = unmuteAllSourcesItem
        menu.addItem(NSMenuItem.separator())

        let focusTimerMenuItem = makeFocusTimerMenuItem()
        menu.addItem(focusTimerMenuItem)
        self.focusTimerMenuItem = focusTimerMenuItem
        menu.addItem(makePreviewStateMenuItem())
        let switchPetMenuItem = makeSwitchPetMenuItem()
        menu.addItem(switchPetMenuItem)
        self.switchPetMenuItem = switchPetMenuItem
        menu.addItem(NSMenuItem(title: "Open Pet Folder", action: #selector(openPetFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items
            .filter { $0.action != nil }
            .forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func installEventRouter() {
        eventRouter = EventRouter(
            onStateChange: { [weak self] state in
                self?.petWindow?.show()
                self?.petBehaviorController?.setBaseState(state)
            },
            onSnapshotChange: { [weak self] snapshot in
                self?.petWindow?.updateThreadSnapshot(snapshot)
            }
        )
        petWindow?.updateThreadSnapshot(eventRouter?.snapshot)
    }

    private func startEventServer() {
        let server = LocalEventServer(
            configuration: appConfiguration,
            authorizationToken: authorizationToken,
            onHealth: { [weak self] in
                self?.eventRouter?.snapshot
            },
            onEvent: { [weak self] event in
                self?.acceptEvent(event) ?? event.resolvedPetState
            }
        )

        do {
            try server.start()
            eventServer = server
        } catch {
            NSLog("GlobalPetAssistant event server failed to start: \(String(describing: error))")
            AuditLogger.appendRuntime(status: "event_server_failed", message: String(describing: error))
        }
    }

    private func startAgentDiscoveryService() {
        let service = AgentDiscoveryService()
        service.startHookSocket()
        agentDiscoveryService = service
    }

    func menuWillOpen(_ menu: NSMenu) {
        pauseEventsItem?.title = eventPreferences.isPaused ? "Resume Events" : "Pause Events"
        pauseEventsItem?.state = eventPreferences.isPaused ? .on : .off

        let currentSource = eventRouter?.snapshot.currentSource
        muteCurrentSourceItem?.title = currentSource.map { "Mute \($0)" } ?? "Mute Current Source"
        muteCurrentSourceItem?.isEnabled = currentSource != nil
        unmuteAllSourcesItem?.isEnabled = !eventPreferences.mutedSources.isEmpty
        rebuildFocusTimerMenu()
        rebuildSwitchPetMenu()
    }

    @objc private func showPet() {
        petWindow?.show()
        AuditLogger.appendRuntime(status: "pet_window_shown", message: "Show Pet menu item")
    }

    @objc private func hidePet() {
        petWindow?.orderOut(nil)
        AuditLogger.appendRuntime(status: "pet_window_hidden", message: "Hide Pet menu item")
    }

    @objc private func openPetFolder() {
        NSWorkspace.shared.open(AppStorage.petsDirectory)
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard let selectedPetID = sender.representedObject as? String else {
            return
        }

        do {
            let package = try loadPetPackage(id: selectedPetID)
            let atlas = try PetAtlas(contentsOf: package.spritesheetURL)
            try AppStorage.saveSelectedPetID(package.id)
            currentPetPackage = package
            petBehaviorController?.replaceAtlas(atlas)
            petWindow?.show()
            AuditLogger.appendRuntime(status: "pet_switched", message: "\(package.id) \(package.directoryURL.path)")
            rebuildSwitchPetMenu()
        } catch {
            showError(title: "Pet could not switch", error: error)
        }
    }

    @objc private func previewPetState(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let state = PetAnimationState(rawValue: rawValue)
        else {
            return
        }

        petWindow?.show()
        petBehaviorController?.previewState(state)
        AuditLogger.appendRuntime(status: "pet_preview_state", message: state.rawValue)
    }

    @objc private func showFocusTimerDialog() {
        let alert = NSAlert()
        alert.messageText = "Start Focus Timer"
        alert.informativeText = "Choose any duration."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let hoursField = Self.durationField(initialValue: 0)
        let minutesField = Self.durationField(initialValue: 25)
        let secondsField = Self.durationField(initialValue: 0)
        let accessoryView = makeFocusTimerAccessoryView(
            hoursField: hoursField,
            minutesField: minutesField,
            secondsField: secondsField
        )
        alert.accessoryView = accessoryView

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let durationSeconds = max(0, hoursField.integerValue) * 3_600
            + max(0, minutesField.integerValue) * 60
            + max(0, secondsField.integerValue)
        guard durationSeconds > 0 else {
            showError(title: "Focus Timer could not start", error: FocusTimerInputError.emptyDuration)
            return
        }

        startFocusTimer(durationSeconds: durationSeconds)
    }

    @objc private func startPresetFocusTimer(_ sender: NSMenuItem) {
        guard let durationSeconds = sender.representedObject as? Int else {
            return
        }

        startFocusTimer(durationSeconds: durationSeconds)
    }

    @objc private func cancelFocusTimer() {
        if focusTimerController?.cancel() == true {
            AuditLogger.appendRuntime(status: "focus_timer_cancelled", message: "Focus timer cancelled")
        }
    }

    @objc private func togglePauseEvents() {
        eventPreferences.isPaused.toggle()
        saveEventPreferences()
    }

    @objc private func openCurrentAction() {
        _ = performCurrentAction()
    }

    @objc private func clearCurrentEvent() {
        guard let currentSource = eventRouter?.snapshot.currentSource else {
            _ = eventRouter?.clear()
            return
        }

        eventRouter?.clearSource(currentSource)
    }

    @objc private func muteCurrentSource() {
        guard let source = eventRouter?.snapshot.currentSource else {
            return
        }

        var mutedSources = eventPreferences.mutedSourceSet
        mutedSources.insert(source)
        eventPreferences.mutedSources = mutedSources.sorted()
        saveEventPreferences()
        eventRouter?.clearSource(source)
    }

    @objc private func unmuteAllSources() {
        eventPreferences.mutedSources = []
        saveEventPreferences()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func acceptEvent(_ event: LocalPetEvent) -> PetAnimationState {
        guard let eventRouter else {
            return event.resolvedPetState
        }

        guard !event.clearsRouter else {
            return eventRouter.accept(event)
        }

        if eventPreferences.isPaused || eventPreferences.mutedSourceSet.contains(event.source) {
            return eventRouter.snapshot.currentState
        }

        petWindow?.show()
        AuditLogger.appendRuntime(status: "pet_window_shown", message: "Accepted event from \(event.source)")
        let selectedState = eventRouter.accept(event)
        if event.isFlashEvent {
            petBehaviorController?.handleFlash(
                level: event.level ?? .info,
                state: event.flashAnimationState
            )
        }
        return selectedState
    }

    private func handlePetClick() {
        let hasAction = eventRouter?.snapshot.hasAction == true
        petBehaviorController?.handleClick(hasAction: hasAction) { [weak self] in
            self?.performCurrentAction() ?? false
        }
    }

    private func performCurrentAction() -> Bool {
        guard let eventRouter, let action = eventRouter.currentAction else {
            return false
        }

        return performAction(action, source: eventRouter.currentSource)
    }

    @discardableResult
    private func performAction(_ action: LocalPetAction?, source: String?) -> Bool {
        return actionHandler.perform(
            action,
            source: source,
            configuration: appConfiguration
        )
    }

    private func saveEventPreferences() {
        do {
            try AppStorage.saveEventPreferences(eventPreferences)
        } catch {
            NSLog("GlobalPetAssistant failed to save event preferences: \(String(describing: error))")
        }
    }

    private func showStartupError(_ error: Error) {
        showError(title: "Global Pet Assistant could not start", error: error)
    }

    private func showError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(describing: error)
        alert.alertStyle = .critical
        alert.runModal()
    }

    private func loadDisplayPet() throws -> (PetPackage, PetAtlas) {
        do {
            try PetPackage.ensureBundledDefaultPetInstalled()
        } catch {
            NSLog("GlobalPetAssistant could not install bundled default pet: \(String(describing: error))")
        }

        let selectedPetID = AppStorage.loadSelectedPetID()
        let renderablePackages = loadRenderablePetPackages()
        let packages = renderablePackages.map { $0.package }
        if let preferredPackage = PetPackage.preferredPackage(from: packages, selectedPetID: selectedPetID),
           let renderablePackage = renderablePackages.first(where: { $0.package.id == preferredPackage.id }) {
            if let selectedPetID,
               selectedPetID != preferredPackage.id,
               selectedPetID != preferredPackage.directoryURL.lastPathComponent {
                NSLog("GlobalPetAssistant selected pet '\(selectedPetID)' was unavailable; using '\(preferredPackage.id)'")
            }
            return (renderablePackage.package, renderablePackage.atlas)
        }

        let bundledPackage = try PetPackage.loadBundledDefaultPet()
        return (bundledPackage, try PetAtlas(contentsOf: bundledPackage.spritesheetURL))
    }

    private func loadRenderablePetPackages() -> [(package: PetPackage, atlas: PetAtlas)] {
        PetPackage.loadInstalledPets().compactMap { package in
            do {
                return (package, try PetAtlas(contentsOf: package.spritesheetURL))
            } catch {
                NSLog("GlobalPetAssistant could not load installed pet '\(package.id)': \(String(describing: error))")
                return nil
            }
        }
    }

    private func loadPetPackage(id selectedPetID: String) throws -> PetPackage {
        let packages = loadRenderablePetPackages().map { $0.package }
        guard let package = packages.first(where: {
            $0.id == selectedPetID || $0.directoryURL.lastPathComponent == selectedPetID
        }) else {
            throw PetSwitchError.petNotFound(selectedPetID)
        }

        return package
    }

    private func makePetContextMenu() -> NSMenu {
        let menu = NSMenu()
        let snapshot = eventRouter?.snapshot

        let openActionItem = NSMenuItem(title: "Open Action", action: #selector(openCurrentAction), keyEquivalent: "")
        openActionItem.isEnabled = snapshot?.hasAction == true
        menu.addItem(openActionItem)

        let clearItem = NSMenuItem(title: "Clear Current Event", action: #selector(clearCurrentEvent), keyEquivalent: "")
        clearItem.isEnabled = snapshot?.currentSource != nil
        menu.addItem(clearItem)

        menu.addItem(NSMenuItem.separator())

        let muteItem = NSMenuItem(title: "Mute Source", action: #selector(muteCurrentSource), keyEquivalent: "")
        muteItem.isEnabled = snapshot?.currentSource != nil
        menu.addItem(muteItem)

        let unmuteItem = NSMenuItem(title: "Unmute All Sources", action: #selector(unmuteAllSources), keyEquivalent: "")
        unmuteItem.isEnabled = !eventPreferences.mutedSources.isEmpty
        menu.addItem(unmuteItem)

        let pauseTitle = eventPreferences.isPaused ? "Resume Events" : "Pause Events"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePauseEvents), keyEquivalent: "")
        pauseItem.state = eventPreferences.isPaused ? .on : .off
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeFocusTimerMenuItem())
        let cancelTimerItem = NSMenuItem(title: "Cancel Timer", action: #selector(cancelFocusTimer), keyEquivalent: "")
        cancelTimerItem.isEnabled = focusTimerController?.snapshot != nil
        menu.addItem(cancelTimerItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makePreviewStateMenuItem())
        menu.addItem(makeSwitchPetMenuItem())
        menu.addItem(NSMenuItem(title: "Open Pet Folder", action: #selector(openPetFolder), keyEquivalent: ""))

        menu.items
            .filter { $0.action != nil }
            .forEach { $0.target = self }
        return menu
    }

    private func makePreviewStateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Preview State", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for state in PetAnimationState.previewMenuStates {
            let stateItem = NSMenuItem(title: state.menuTitle, action: #selector(previewPetState(_:)), keyEquivalent: "")
            stateItem.representedObject = state.rawValue
            stateItem.target = self
            submenu.addItem(stateItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeSwitchPetMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Switch Pet", action: nil, keyEquivalent: "")
        item.submenu = makeSwitchPetSubmenu()
        return item
    }

    private func rebuildSwitchPetMenu() {
        switchPetMenuItem?.submenu = makeSwitchPetSubmenu()
    }

    private func makeSwitchPetSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let packages = PetPackage.sortedForDisplay(loadRenderablePetPackages().map { $0.package })

        guard !packages.isEmpty else {
            let emptyItem = NSMenuItem(title: "No Compatible Pets", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return submenu
        }

        let currentPetID = currentPetPackage?.id
        for package in packages {
            let title = package.displayName.isEmpty ? package.id : package.displayName
            let item = NSMenuItem(title: title, action: #selector(selectPet(_:)), keyEquivalent: "")
            item.representedObject = package.id
            item.target = self
            item.state = package.id == currentPetID ? .on : .off
            submenu.addItem(item)
        }

        return submenu
    }

    private func makeFocusTimerMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Focus Timer", action: nil, keyEquivalent: "")
        item.submenu = makeFocusTimerSubmenu()
        return item
    }

    private func rebuildFocusTimerMenu() {
        focusTimerMenuItem?.submenu = makeFocusTimerSubmenu()
    }

    private func makeFocusTimerSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let snapshot = focusTimerController?.snapshot

        let startItem = NSMenuItem(title: "Start Timer...", action: #selector(showFocusTimerDialog), keyEquivalent: "")
        startItem.target = self
        submenu.addItem(startItem)

        for preset in [(5, "5 min"), (25, "25 min"), (45, "45 min")] {
            let item = NSMenuItem(title: preset.1, action: #selector(startPresetFocusTimer(_:)), keyEquivalent: "")
            item.representedObject = preset.0 * 60
            item.target = self
            submenu.addItem(item)
        }

        submenu.addItem(NSMenuItem.separator())

        let remainingTitle = snapshot.map { "Remaining \($0.formattedRemaining)" } ?? "Remaining --:--"
        let remainingItem = NSMenuItem(title: remainingTitle, action: nil, keyEquivalent: "")
        remainingItem.isEnabled = false
        submenu.addItem(remainingItem)

        let cancelItem = NSMenuItem(title: "Cancel Timer", action: #selector(cancelFocusTimer), keyEquivalent: "")
        cancelItem.target = self
        cancelItem.isEnabled = snapshot != nil
        submenu.addItem(cancelItem)

        return submenu
    }

    private func startFocusTimer(durationSeconds: Int) {
        guard focusTimerController?.start(durationSeconds: durationSeconds) != nil else {
            return
        }

        petWindow?.show()
        AuditLogger.appendRuntime(status: "focus_timer_started", message: "\(durationSeconds)s")
    }

    private static func durationField(initialValue: Int) -> NSTextField {
        let field = NSTextField()
        field.integerValue = initialValue
        field.alignment = .right
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.formatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none
            formatter.minimum = 0
            formatter.maximum = 99_999
            formatter.allowsFloats = false
            return formatter
        }()
        field.widthAnchor.constraint(equalToConstant: 54).isActive = true
        return field
    }

    private func makeFocusTimerAccessoryView(
        hoursField: NSTextField,
        minutesField: NSTextField,
        secondsField: NSTextField
    ) -> NSView {
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Hours"), hoursField],
            [NSTextField(labelWithString: "Minutes"), minutesField],
            [NSTextField(labelWithString: "Seconds"), secondsField]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        return grid
    }
}

private enum FocusTimerInputError: LocalizedError {
    case emptyDuration

    var errorDescription: String? {
        "Duration must be greater than zero."
    }
}

private enum PetSwitchError: LocalizedError {
    case petNotFound(String)

    var errorDescription: String? {
        switch self {
        case .petNotFound(let petID):
            "No compatible installed pet named '\(petID)' was found."
        }
    }
}
