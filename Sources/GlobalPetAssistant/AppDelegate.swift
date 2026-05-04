import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindow: FloatingPetWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try AppStorage.ensureLayout()
            let package: PetPackage
            if let installedCodexPet = PetPackage.loadFirstInstalledCodexPet() {
                package = installedCodexPet
            } else {
                package = try PetPackage.loadBundledSample()
            }
            let atlas = try PetAtlas(contentsOf: package.spritesheetURL)
            let spriteView = PetSpriteView(atlas: atlas)
            let window = FloatingPetWindow(contentView: spriteView)

            self.petWindow = window
            installStatusMenu()
            window.show()
            spriteView.play(.idle)
        } catch {
            showStartupError(error)
            NSApp.terminate(nil)
        }
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Pet"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Pet", action: #selector(showPet), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Pet", action: #selector(hidePet), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Pet Folder", action: #selector(openPetFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showStartupError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Global Pet Assistant could not start"
        alert.informativeText = String(describing: error)
        alert.alertStyle = .critical
        alert.runModal()
    }
}
