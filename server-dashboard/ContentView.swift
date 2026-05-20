import SwiftUI

struct ContentView: View {
    @State private var state = AppState()

    var body: some View {
        Group {
            if state.isAuthenticated {
                TabView {
                    ServersView()
                        .tabItem { Label("Services", systemImage: "server.rack") }

                    SpecsView()
                        .tabItem { Label("Server", systemImage: "cpu") }

                    FilesView()
                        .tabItem { Label("Files", systemImage: "folder") }

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gear") }
                }
            } else {
                LoginView()
            }
        }
        .environment(state)
        .biometricLock()
    }
}

#Preview {
    ContentView()
}
