import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var petWindow: FloatingPetWindow?
    private var spriteView: PetSpriteView?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try AppStorage.ensureLayout()
            eventPreferences = AppStorage.loadEventPreferences()
            let package = try PetPackage.loadFirstInstalledPet()
            NSLog("GlobalPetAssistant loaded pet '\(package.id)' from \(package.directoryURL.path)")
            let atlas = try PetAtlas(contentsOf: package.spritesheetURL)
            let spriteView = PetSpriteView(atlas: atlas)
            let window = FloatingPetWindow(
                contentView: spriteView,
                savedOrigin: AppStorage.loadWindowOrigin()
            )
            window.onPetClick = { [weak self] in
                self?.performCurrentAction()
            }
            window.onMoveEnded = { origin in
                try? AppStorage.saveWindowOrigin(StoredWindowOrigin(
                    x: origin.x,
                    y: origin.y
                ))
            }

            self.petWindow = window
            self.spriteView = spriteView
            installStatusMenu()
            installEventRouter()
            startEventServer()
            window.show()
            spriteView.play(.idle)
        } catch {
            showStartupError(error)
            NSApp.terminate(nil)
        }
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
        eventRouter = EventRouter { [weak self] state in
            self?.petWindow?.show()
            self?.spriteView?.play(state)
        }
    }

    private func startEventServer() {
        let server = LocalEventServer(
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
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        pauseEventsItem?.state = eventPreferences.isPaused ? .on : .off
        launchAtLoginItem?.state = launchAtLoginController.isEnabled ? .on : .off

        let currentSource = eventRouter?.snapshot.currentSource
        muteCurrentSourceItem?.title = currentSource.map { "Mute \($0)" } ?? "Mute Current Source"
        muteCurrentSourceItem?.isEnabled = currentSource != nil
        unmuteAllSourcesItem?.isEnabled = !eventPreferences.mutedSources.isEmpty
    }

    @objc private func showPet() {
        petWindow?.show()
    }

    @objc private func hidePet() {
        petWindow?.orderOut(nil)
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

        return eventRouter.accept(event)
    }

    private func performCurrentAction() {
        guard let action = eventRouter?.currentAction else {
            return
        }

        actionHandler.perform(action)
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
}
