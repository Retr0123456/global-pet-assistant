import Testing
@testable import GlobalPetAssistant

struct PetBehaviorControllerTests {
    @Test
    func dragDirectionUsesOppositeRunningAnimation() {
        #expect(PetDragDirection.left.animationState == .runningRight)
        #expect(PetDragDirection.right.animationState == .runningLeft)
    }

    @Test
    func successFlashUsesWavingAnimation() {
        let event = LocalPetEvent(source: "terminal", type: "flash", level: .success)

        #expect(event.flashAnimationState == .waving)
    }
}
