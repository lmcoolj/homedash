import SwiftUI

struct SpecsView: View {
    @Environment(AppState.self) private var state
    @State private var specs: Specs?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if let s = specs {
                    Section("Host") {
                        labelRow("Hostname", s.os.hostname ?? "—")
                        labelRow("OS", "\(s.os.distro ?? "?") \(s.os.release ?? "")".trimmingCharacters(in: .whitespaces))
                        labelRow("Kernel", s.os.kernel ?? "—")
                        labelRow("Uptime", uptime(s.uptimeSeconds))
                    }

                    Section("CPU") {
                        if let brand = s.cpu.brand { labelRow("Model", brand) }
                        if let cores = s.cpu.cores { labelRow("Cores", "\(cores)") }
                        if let load = s.cpu.load {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Load").foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f%%", load))
                                }
                                ProgressView(value: min(max(load / 100, 0), 1))
                                    .tint(loadTint(load))
                            }
                        }
                        if let t = s.cpu.tempC {
                            labelRow("Temp", String(format: "%.1f°C", t))
                        }
                    }

                    if let total = s.memory.total, let used = s.memory.used, total > 0 {
                        Section("Memory") {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(bytes(used)) / \(bytes(total))")
                                    Spacer()
                                    Text(String(format: "%.0f%%", Double(used) / Double(total) * 100))
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(used) / Double(total))
                            }
                        }
                    }

                    if !s.disks.isEmpty {
                        Section("Disks") {
                            ForEach(uniqueDisks(s.disks), id: \.fs) { d in
                                diskRow(d)
                            }
                        }
                    }

                    if !s.network.isEmpty {
                        Section("Network") {
                            ForEach(s.network, id: \.iface) { n in
                                HStack {
                                    Text(n.iface ?? "?").font(.subheadline)
                                    Spacer()
                                    Text(n.ip4 ?? "—").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if error == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Server")
            .refreshable { await refresh() }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        do {
            specs = try await HomeDashAPI.shared.specs()
            error = nil
        } catch APIError.notAuthenticated {
            await state.logout()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func labelRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func diskRow(_ d: Specs.Disk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(d.mount ?? d.fs ?? "?").font(.subheadline)
                Spacer()
                if let size = d.size, let used = d.used {
                    Text("\(bytes(used)) / \(bytes(size))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let size = d.size, let used = d.used, size > 0 {
                ProgressView(value: Double(used) / Double(size))
            }
        }
    }

    private func uniqueDisks(_ disks: [Specs.Disk]) -> [Specs.Disk] {
        var seen = Set<String>()
        return disks.filter { d in
            let key = d.fs ?? d.mount ?? UUID().uuidString
            return seen.insert(key).inserted
        }
    }

    private func loadTint(_ load: Double) -> Color {
        switch load {
        case ..<50:  return .green
        case ..<80:  return .yellow
        default:     return .red
        }
    }

    private func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB]
        f.countStyle = .binary
        return f.string(fromByteCount: n)
    }

    private func uptime(_ s: Double) -> String {
        let total = Int(s)
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
