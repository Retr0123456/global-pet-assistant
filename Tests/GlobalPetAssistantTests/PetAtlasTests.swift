import Foundation
import Testing
@testable import GlobalPetAssistant

struct PetAtlasTests {
    @Test
    func testAnimationStatesMatchResourceContract() {
        #expect(PetAnimationState.allCases.map(\.rawValue) == [
            "idle",
            "running-right",
            "running-left",
            "waving",
            "jumping",
            "failed",
            "waiting",
            "running",
            "review"
        ])
        #expect(PetAnimationState.allCases.map(\.row) == Array(0...8))
        #expect(PetAnimationState.allCases.map(\.frameCount) == [6, 8, 8, 4, 5, 8, 6, 6, 6])
    }

    @Test
    func testPreviewMenuExcludesGenericRunningState() {
        #expect(PetAnimationState.previewMenuStates.map(\.rawValue) == [
            "idle",
            "waiting",
            "failed",
            "review",
            "waving",
            "jumping",
            "running-left",
            "running-right"
        ])
        #expect(!PetAnimationState.previewMenuStates.contains(.running))
    }

    @Test
    func testFrameMetadataUsesNormalizedAtlasRects() {
        let frames = PetAtlas.makeFrames(for: .waiting)

        #expect(frames.count == 6)
        #expect(frames[0].column == 0)
        #expect(frames[0].row == 6)
        #expect(frames[0].contentsRect == CGRect(
            x: 0,
            y: 2.0 / 9.0,
            width: 1.0 / 8.0,
            height: 1.0 / 9.0
        ))
        #expect(frames[5].column == 5)
        #expect(frames[5].row == 6)
        #expect(frames[5].contentsRect == CGRect(
            x: 5.0 / 8.0,
            y: 2.0 / 9.0,
            width: 1.0 / 8.0,
            height: 1.0 / 9.0
        ))
    }

    @Test
    func testContentsRectsConvertTopBasedResourceRowsForCoreAnimation() {
        #expect(PetAtlas.makeFrames(for: .idle)[0].contentsRect.origin.y == 8.0 / 9.0)
        #expect(PetAtlas.makeFrames(for: .runningRight)[0].contentsRect.origin.y == 7.0 / 9.0)
        #expect(PetAtlas.makeFrames(for: .runningLeft)[0].contentsRect.origin.y == 6.0 / 9.0)
        #expect(PetAtlas.makeFrames(for: .waving)[0].contentsRect.origin.y == 5.0 / 9.0)
        #expect(PetAtlas.makeFrames(for: .jumping)[0].contentsRect.origin.y == 4.0 / 9.0)
        #expect(PetAtlas.makeFrames(for: .failed)[0].contentsRect.origin.y == 3.0 / 9.0)
        #expect(PetAtlas.makeFrames(for: .waiting)[0].contentsRect.origin.y == 2.0 / 9.0)
        #expect(PetAtlas.makeFrames(for: .running)[0].contentsRect.origin.y == 1.0 / 9.0)
        #expect(PetAtlas.makeFrames(for: .review)[0].contentsRect.origin.y == 0.0 / 9.0)
    }

    @Test
    func testFrameCountsMatchAnimationRows() {
        #expect(PetAtlas.makeFrames(for: .idle).count == 6)
        #expect(PetAtlas.makeFrames(for: .runningRight).count == 8)
        #expect(PetAtlas.makeFrames(for: .runningLeft).count == 8)
        #expect(PetAtlas.makeFrames(for: .waving).count == 4)
        #expect(PetAtlas.makeFrames(for: .jumping).count == 5)
        #expect(PetAtlas.makeFrames(for: .failed).count == 8)
        #expect(PetAtlas.makeFrames(for: .waiting).count == 6)
        #expect(PetAtlas.makeFrames(for: .running).count == 6)
        #expect(PetAtlas.makeFrames(for: .review).count == 6)
    }
}
