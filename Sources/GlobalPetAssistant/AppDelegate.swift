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
    private var launchAtLoginItem: NSMenuItem?
    private var eventRouter: EventRouter?
    private var eventServer: LocalEventServer?
    private let actionHandler = ActionHandler()
    private let launchAtLoginController = LaunchAtLoginController()
    private var eventPreferences = EventPreferences()
    private var appConfiguration = AppConfiguration.defaultConfiguration

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try AppStorage.ensureLayout()
            AuditLogger.appendRuntime(status: "app_launching", message: "GlobalPetAssistant applicationDidFinishLaunching")
            appConfiguration = AppStorage.loadConfiguration()
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
            installStatusMenu()
            installEventRouter()
            startEventServer()
            window.show()
            AuditLogger.appendRuntime(status: "pet_window_shown", message: "Initial pet window shown")
        } catch {
            AuditLogger.appendRuntime(status: "startup_failed", message: String(describing: error))
            showStartupError(error)
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(launchAtLoginItem)
        self.launchAtLoginItem = launchAtLoginItem

        menu.addItem(NSMenuItem(title: "Move to Next Display", action: #selector(moveToNextDisplay), keyEquivalent: ""))
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

    func menuWillOpen(_ menu: NSMenu) {
        pauseEventsItem?.title = eventPreferences.isPaused ? "Resume Events" : "Pause Events"
        pauseEventsItem?.state = eventPreferences.isPaused ? .on : .off
        launchAtLoginItem?.state = launchAtLoginController.isEnabled ? .on : .off

        let currentSource = eventRouter?.snapshot.currentSource
        muteCurrentSourceItem?.title = currentSource.map { "Mute \($0)" } ?? "Mute Current Source"
        muteCurrentSourceItem?.isEnabled = currentSource != nil
        unmuteAllSourcesItem?.isEnabled = !eventPreferences.mutedSources.isEmpty
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

    @objc private func moveToNextDisplay() {
        petWindow?.moveToNextScreen()
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

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchAtLoginController.setEnabled(!launchAtLoginController.isEnabled)
        } catch {
            showError(title: "Launch at Login could not be changed", error: error)
        }
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
        return eventRouter.accept(event)
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

        return actionHandler.perform(
            action,
            source: eventRouter.currentSource,
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
        for package in PetPackage.loadInstalledPets() {
            do {
                return (package, try PetAtlas(contentsOf: package.spritesheetURL))
            } catch {
                NSLog("GlobalPetAssistant could not load installed pet '\(package.id)': \(String(describing: error))")
            }
        }

        let bundledPackage = try PetPackage.loadBundledSample()
        return (bundledPackage, try PetAtlas(contentsOf: bundledPackage.spritesheetURL))
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
        menu.addItem(NSMenuItem(title: "Open Pet Folder", action: #selector(openPetFolder), keyEquivalent: ""))

        menu.items
            .filter { $0.action != nil }
            .forEach { $0.target = self }
        return menu
    }
}
