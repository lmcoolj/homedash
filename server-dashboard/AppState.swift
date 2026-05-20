import SwiftUI
import Observation

@Observable
@MainActor
final class AppState {
    var isAuthenticated: Bool
    var loginError: String?
    var isLoggingIn = false

    init() {
        self.isAuthenticated = HomeDashAPI.shared.isLoggedIn()
    }

    func login(username: String, password: String) async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            try await HomeDashAPI.shared.login(username: username, password: password)
            isAuthenticated = true
        } catch {
            loginError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isAuthenticated = false
        }
    }

    func logout() async {
        await HomeDashAPI.shared.logout()
        isAuthenticated = false
    }
}
