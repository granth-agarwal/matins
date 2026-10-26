import AppKit
@preconcurrency import AppAuth
import Foundation

@MainActor
public final class GoogleAuth {
    public static let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/drive.readonly"
    ]
    public private(set) var needsSignIn = false
    private let keychain: Keychain
    private var state: OIDAuthState?
    private var listener: OIDRedirectHTTPHandler?
    private var timeout: Task<Void, Never>?
    public init(keychain: Keychain = Keychain()) {
        self.keychain = keychain
        do {
            if let data = try keychain.read("google") {
                state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
            }
        } catch { needsSignIn = true }
    }
    public var isSignedIn: Bool { state?.isAuthorized == true }
    public func signIn(clientID: String?, window: NSWindow, scopes: [String] = GoogleAuth.scopes) async throws {
        guard let clientID, !clientID.isEmpty else { throw AuthError.missingClient }
        cancel()
        let listener = OIDRedirectHTTPHandler(successURL: nil)
        self.listener = listener
        var listenerError: NSError?
        let redirect = listener.startHTTPListener(&listenerError)
        if listenerError != nil { throw AuthError.network }
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!)
        let secret = try keychain.read("google_client_secret").flatMap { String(data: $0, encoding: .utf8) }
        let request = OIDAuthorizationRequest(configuration: configuration, clientId: clientID,
            clientSecret: secret, scopes: scopes, redirectURL: redirect, responseType: OIDResponseTypeCode,
            additionalParameters: ["access_type": "offline", "prompt": "consent"])
        defer { timeout?.cancel(); timeout = nil; self.listener = nil }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: window) { state, error in
                MainActor.assumeIsolated {
                    guard let state, error == nil else {
                        continuation.resume(throwing: AuthError.cancelled); return
                    }
                    do {
                        let data = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
                        try self.keychain.write(data, key: "google")
                        self.state = state
                        self.needsSignIn = false
                        continuation.resume()
                    } catch { continuation.resume(throwing: AuthError.keychain) }
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(300))
                if !Task.isCancelled { self?.cancel() }
            }
        }
    }
    public func accessToken() async throws -> String {
        guard let state, state.isAuthorized else { needsSignIn = true; throw AuthError.signInAgain }
        return try await withCheckedThrowingContinuation { continuation in
            state.performAction { token, _, error in
                MainActor.assumeIsolated {
                    if let error {
                        let ns = error as NSError
                        if ns.domain == OIDOAuthTokenErrorDomain || !state.isAuthorized {
                            self.needsSignIn = true
                            continuation.resume(throwing: AuthError.signInAgain)
                        } else { continuation.resume(throwing: AuthError.network) }
                        return
                    }
                    guard let token else { continuation.resume(throwing: AuthError.signInAgain); return }
                    do {
                        try self.keychain.write(NSKeyedArchiver.archivedData(withRootObject: state,
                            requiringSecureCoding: true), key: "google")
                        continuation.resume(returning: token)
                    } catch { continuation.resume(throwing: AuthError.keychain) }
                }
            }
        }
    }
    public func cancel() { listener?.cancelHTTPListener(); listener = nil }
    public func signOut() throws { cancel(); try keychain.delete("google"); state = nil; needsSignIn = false }
}
