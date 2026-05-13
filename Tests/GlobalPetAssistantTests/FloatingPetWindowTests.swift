import AppKit
import Testing
@testable import GlobalPetAssistant

struct FloatingPetWindowTests {
    @MainActor
    @Test
    func resizeControlKeepsSliderFixedWhileScaling() throws {
        let window = try makeWindow()
        defer {
            window.close()
        }

        window.contentView?.layoutSubtreeIfNeeded()
        window.showPetResizeControl()
        window.contentView?.layoutSubtreeIfNeeded()
        let sliderCenterAfterShowingControl = try #require(window.scaleControlScreenFrameForTesting?.center)

        window.applyUserInterfacePreferences(UserInterfacePreferences(petScale: 1.6), display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        let sliderCenterAfterScaling = try #require(window.scaleControlScreenFrameForTesting?.center)

        #expect(sliderCenterAfterScaling.isClose(to: sliderCenterAfterShowingControl))
    }

    @MainActor
    @Test
    func threadBadgeStaysCenteredBelowScaledPet() throws {
        let window = try makeWindow()
        defer {
            window.close()
        }

        window.updateThreadPanelSnapshot(ThreadPanelSnapshot(genericThreads: [sampleThread()]))
        window.applyUserInterfacePreferences(UserInterfacePreferences(petScale: 1.6), display: true)
        window.contentView?.layoutSubtreeIfNeeded()

        let petCenter = try #require(window.petScreenFrameForTesting?.center)
        let badgeCenter = try #require(window.threadBadgeScreenFrameForTesting?.center)

        #expect(badgeCenter.x.isClose(to: petCenter.x))
    }

    @MainActor
    @Test
    func threadBadgeFitsInsideWindowWhenPetIsSmall() throws {
        let window = try makeWindow()
        defer {
            window.close()
        }

        window.updateThreadPanelSnapshot(ThreadPanelSnapshot(genericThreads: [sampleThread()]))
        window.applyUserInterfacePreferences(
            UserInterfacePreferences(petScale: UserInterfacePreferences.minimumPetScale),
            display: true
        )
        window.contentView?.layoutSubtreeIfNeeded()

        let badgeFrame = try #require(window.threadBadgeScreenFrameForTesting)

        #expect(badgeFrame.minX >= window.frame.minX - 0.5)
        #expect(badgeFrame.maxX <= window.frame.maxX + 0.5)
    }

    @MainActor
    @Test
    func expandedThreadPanelFitsInsideWindowWhenPetIsSmall() throws {
        let window = try makeWindow()
        defer {
            window.close()
        }

        window.updateThreadPanelSnapshot(ThreadPanelSnapshot(genericThreads: [sampleThread()]))
        window.applyUserInterfacePreferences(
            UserInterfacePreferences(petScale: UserInterfacePreferences.minimumPetScale),
            display: true
        )
        window.expandThreadPanelForTesting()
        window.contentView?.layoutSubtreeIfNeeded()

        let panelFrame = try #require(window.threadPanelScreenFrameForTesting)

        #expect(panelFrame.minX >= window.frame.minX - 0.5)
        #expect(panelFrame.maxX <= window.frame.maxX + 0.5)
    }

    @MainActor
    @Test
    func resizeControlHidesThreadBadgeAndExpandedPanel() throws {
        let window = try makeWindow()
        defer {
            window.close()
        }

        window.updateThreadPanelSnapshot(ThreadPanelSnapshot(genericThreads: [sampleThread()]))
        window.expandThreadPanelForTesting()
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(!window.isThreadBadgeHiddenForTesting)
        #expect(!window.isThreadPanelHiddenForTesting)

        window.showPetResizeControl()
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(window.isThreadBadgeHiddenForTesting)
        #expect(window.isThreadPanelHiddenForTesting)
    }

    @MainActor
    private func makeWindow() throws -> FloatingPetWindow {
        let package = try PetPackage.loadBundledDefaultPet()
        let atlas = try PetAtlas(contentsOf: package.spritesheetURL)
        return FloatingPetWindow(
            contentView: PetSpriteView(atlas: atlas),
            savedOrigin: StoredWindowOrigin(x: 220, y: 220)
        )
    }

    private func sampleThread() -> PetThreadSnapshot {
        PetThreadSnapshot(
            source: "codex-cli:test",
            title: "Test thread",
            context: "global-pet-assistant",
            directoryName: "global-pet-assistant",
            messagePreview: "Testing",
            action: nil,
            state: .running,
            status: .running
        )
    }
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}

private extension NSPoint {
    func isClose(to other: NSPoint, tolerance: CGFloat = 0.5) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

private extension CGFloat {
    func isClose(to other: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
        abs(self - other) <= tolerance
    }
}
