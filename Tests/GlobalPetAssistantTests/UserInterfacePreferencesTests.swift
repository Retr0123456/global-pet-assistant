import Testing
@testable import GlobalPetAssistant

struct UserInterfacePreferencesTests {
    @Test
    func clampedKeepsPanelOpacityAndPetScaleInSupportedRanges() {
        let preferences = UserInterfacePreferences(
            threadPanelOpacity: 0.1,
            petScale: 4.0,
            isPetResizeModeEnabled: true
        ).clamped()

        #expect(preferences.threadPanelOpacity == UserInterfacePreferences.minimumThreadPanelOpacity)
        #expect(preferences.petScale == UserInterfacePreferences.maximumPetScale)
        #expect(preferences.isPetResizeModeEnabled)
    }

    @Test
    func defaultsMatchInitialDesktopUi() {
        let preferences = UserInterfacePreferences()

        #expect(preferences.threadPanelOpacity == UserInterfacePreferences.defaultThreadPanelOpacity)
        #expect(preferences.petScale == UserInterfacePreferences.defaultPetScale)
        #expect(!preferences.isPetResizeModeEnabled)
    }
}
