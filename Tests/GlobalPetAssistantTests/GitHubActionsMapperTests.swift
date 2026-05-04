import Foundation
import PetWebhookBridgeCore
import Testing

struct GitHubActionsMapperTests {
    @Test func failurePayloadMapsToCIDangerEvent() throws {
        let payload = Data("""
        {
          "workflow_run": {
            "id": 12345,
            "name": "Release",
            "conclusion": "failure",
            "html_url": "https://github.com/Retr0123456/global-pet-assistant/actions/runs/12345"
          },
          "repository": {
            "full_name": "Retr0123456/global-pet-assistant"
          }
        }
        """.utf8)

        let event = try GitHubActionsMapper.event(from: payload)

        #expect(event.source == "ci")
        #expect(event.type == "ci.workflow")
        #expect(event.level == "danger")
        #expect(event.title == "Release failed")
        #expect(event.message == "Retr0123456/global-pet-assistant")
        #expect(event.dedupeKey == "github-actions:12345")
        #expect(event.action == BridgeAction(
            type: "open_url",
            url: "https://github.com/Retr0123456/global-pet-assistant/actions/runs/12345"
        ))
    }

    @Test func successPayloadUsesRepositoryActionsFallbackURL() throws {
        let payload = Data("""
        {
          "workflow": "CI",
          "status": "success",
          "repository": "Retr0123456/global-pet-assistant"
        }
        """.utf8)

        let event = try GitHubActionsMapper.event(from: payload)

        #expect(event.level == "success")
        #expect(event.title == "CI succeeded")
        #expect(event.ttlMs == 45_000)
        #expect(event.action?.url == "https://github.com/Retr0123456/global-pet-assistant/actions")
    }

    @Test func malformedPayloadThrowsInvalidJSON() {
        #expect(throws: PayloadMappingError.invalidJSON) {
            _ = try GitHubActionsMapper.event(from: Data("{".utf8))
        }
    }
}
