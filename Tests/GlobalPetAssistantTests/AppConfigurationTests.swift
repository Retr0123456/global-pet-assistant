import Foundation
import Testing
@testable import GlobalPetAssistant

struct AppConfigurationTests {
    @Test
    func testDefaultConfigurationIncludesCodexPetImportSource() {
        let configuration = AppConfiguration.defaultConfiguration

        #expect(configuration.petImportSourceDirectories.contains {
            $0.hasSuffix("/.codex/pets")
        })
    }

    @Test
    func testLegacyConfigurationDecodesWithDefaultPetImportSource() throws {
        let data = Data("""
        {
          "trustedSources": {
            "codex-cli": {
              "actions": ["open_url"],
              "urlHosts": ["github.com"],
              "folderRoots": [],
              "appBundleIds": []
            }
          }
        }
        """.utf8)

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
            .migratedForCurrentDefaults()

        #expect(configuration.trustedSources["codex-cli"]?.actions == ["open_url"])
        #expect(configuration.petImportSourceDirectories.contains {
            $0.hasSuffix("/.codex/pets")
        })
    }
}
