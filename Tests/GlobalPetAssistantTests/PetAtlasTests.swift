import Foundation
import Testing
@testable import GlobalPetAssistant

struct PetAtlasTests {
    @Test
    func testFrameMetadataUsesNormalizedAtlasRects() {
        let frames = PetAtlas.makeFrames(for: .waiting)

        #expect(frames.count == 6)
        #expect(frames[0].column == 0)
        #expect(frames[0].row == 6)
        #expect(frames[0].contentsRect == CGRect(
            x: 0,
            y: 6.0 / 9.0,
            width: 1.0 / 8.0,
            height: 1.0 / 9.0
        ))
        #expect(frames[5].column == 5)
        #expect(frames[5].row == 6)
        #expect(frames[5].contentsRect == CGRect(
            x: 5.0 / 8.0,
            y: 6.0 / 9.0,
            width: 1.0 / 8.0,
            height: 1.0 / 9.0
        ))
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
