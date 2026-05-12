import Testing
@testable import GlobalPetAssistant

struct PetBehaviorControllerTests {
    @Test
    func dragDirectionUsesOppositeRunningAnimation() {
        #expect(PetDragDirection.left.animationState == .runningRight)
        #expect(PetDragDirection.right.animationState == .runningLeft)
    }

    @Test
    func successFlashUsesReviewAnimation() {
        let event = LocalPetEvent(source: "terminal", type: "flash", level: .success)

        #expect(event.flashAnimationState == .review)
    }
}
