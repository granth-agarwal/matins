import Testing
import Auth

struct AuthTests {
    @Test func devicePollingRespectsProviderBackoff() {
        #expect(DevicePoll.result(error: "slow_down", token: nil, interval: 5) == .wait(10))
        #expect(DevicePoll.result(error: "authorization_pending", token: nil, interval: 10) == .wait(10))
        #expect(DevicePoll.result(error: "access_denied", token: nil, interval: 5) == .denied)
        #expect(DevicePoll.result(error: nil, token: "fixture", interval: 5) == .authorized("fixture"))
    }
    @Test @MainActor func googleScopesAreReadOnly() {
        #expect(GoogleAuth.scopes.count == 3)
        #expect(GoogleAuth.scopes.allSatisfy { $0.hasSuffix(".readonly") })
    }
}
