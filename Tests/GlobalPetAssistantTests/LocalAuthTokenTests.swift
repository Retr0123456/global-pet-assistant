import Testing
@testable import GlobalPetAssistant

struct LocalAuthTokenTests {
    @Test
    func testGeneratedTokenHasExpectedLength() {
        let token = LocalAuthToken.generate()

        #expect(token.count >= LocalAuthToken.byteCount * 2)
        #expect(token.allSatisfy { $0.isHexDigit })
    }

    @Test
    func testExtractsBearerToken() {
        #expect(LocalAuthToken.bearerToken(from: "Bearer abc123") == "abc123")
        #expect(LocalAuthToken.bearerToken(from: "bearer abc123") == "abc123")
        #expect(LocalAuthToken.bearerToken(from: "Basic abc123") == nil)
        #expect(LocalAuthToken.bearerToken(from: nil) == nil)
    }

    @Test
    func testConstantTimeComparisonResult() {
        #expect(LocalAuthToken.constantTimeEquals("secret", "secret") == true)
        #expect(LocalAuthToken.constantTimeEquals("secret", "SECRET") == false)
        #expect(LocalAuthToken.constantTimeEquals("secret", "secret-longer") == false)
    }
}
