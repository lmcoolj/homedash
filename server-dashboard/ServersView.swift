import SwiftUI

struct ServersView: View {
    @Environment(AppState.self) private var state
    @State private var services: [Service] = []
    @State private var error: String?
    @State private var pending = Set<String>()
    @State private var didInitialLoad = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                ForEach(services) { service in
                    ServiceRow(
                        service: service,
                        isPending: pending.contains(service.id),
                        onAction: { action in act(id: service.id, action: action) }
                    )
                }
                if services.isEmpty && error == nil && didInitialLoad == false {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Services")
            .refreshable { await refresh() }
            .task {
                while !Task.isCancelled {
                    await refresh()
                    didInitialLoad = true
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func refresh() async {
        do {
            services = try await HomeDashAPI.shared.servers()
            error = nil
        } catch APIError.notAuthenticated {
            await state.logout()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func act(id: String, action: String) {
        pending.insert(id)
        Task {
            defer { pending.remove(id) }
            do {
                try await HomeDashAPI.shared.control(serviceID: id, action: action)
                try? await Task.sleep(for: .milliseconds(400)) // give systemd a beat
                await refresh()
            } catch APIError.notAuthenticated {
                await state.logout()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private struct ServiceRow: View {
    let service: Service
    let isPending: Bool
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StatusDot(status: service.status)
                Text(service.name).font(.headline)
                Spacer()
                Text(service.status.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(StatusDot.color(for: service.status).opacity(0.18),
                                in: Capsule())
                    .foregroundStyle(StatusDot.color(for: service.status))
            }
            Text(service.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if service.controllable {
                HStack(spacing: 8) {
                    actionButton("Start",   "play.fill",       "start", tint: .green)
                    actionButton("Stop",    "stop.fill",       "stop",  tint: .red)
                    actionButton("Restart", "arrow.clockwise", "restart", tint: .orange)
                    Spacer()
                    if isPending { ProgressView() }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func actionButton(_ label: String, _ icon: String, _ action: String, tint: Color) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(label, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .disabled(isPending)
    }
}

private struct StatusDot: View {
    let status: String
    var body: some View {
        Circle().fill(Self.color(for: status)).frame(width: 10, height: 10)
    }
    static func color(for status: String) -> Color {
        switch status {
        case "up":              return .green
        case "starting":        return .yellow
        case "stopped":         return .gray
        case "failed", "down":  return .red
        default:                return .gray
        }
    }
}
