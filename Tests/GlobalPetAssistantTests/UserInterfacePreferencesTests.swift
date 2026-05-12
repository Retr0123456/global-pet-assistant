import Testing
@testable import GlobalPetAssistant

struct UserInterfacePreferencesTests {
    @Test
    func clampedKeepsPetScaleInSupportedRange() {
        let preferences = UserInterfacePreferences(petScale: 4.0).clamped()

        #expect(preferences.petScale == UserInterfacePreferences.maximumPetScale)
    }

    @Test
    func defaultsMatchInitialDesktopUi() {
        let preferences = UserInterfacePreferences()

        #expect(preferences.petScale == UserInterfacePreferences.defaultPetScale)
    }
}
