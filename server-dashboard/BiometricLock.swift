import SwiftUI
import LocalAuthentication

struct BiometricLockModifier: ViewModifier {
    @AppStorage("biometricLock") private var biometricLock = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked = false
    @State private var armed = false  // once true, lock on every backgrounding

    func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(!isLocked)
                .blur(radius: isLocked ? 18 : 0)

            if isLocked {
                LockView(onUnlock: authenticate)
                    .transition(.opacity)
            }
        }
        .task {
            if biometricLock {
                isLocked = true
                armed = true
                authenticate()
            }
        }
        .onChange(of: biometricLock) { _, newValue in
            if newValue && !armed {
                armed = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                if biometricLock && armed { isLocked = true }
            case .active:
                if isLocked { authenticate() }
            @unknown default:
                break
            }
        }
    }

    private func authenticate() {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        var err: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard ctx.canEvaluatePolicy(policy, error: &err) else {
            isLocked = false
            return
        }
        ctx.evaluatePolicy(policy, localizedReason: "Unlock HomeDash") { ok, _ in
            DispatchQueue.main.async {
                if ok {
                    withAnimation(.easeInOut(duration: 0.2)) { isLocked = false }
                }
            }
        }
    }
}

private struct LockView: View {
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: iconName)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("HomeDash is locked")
                    .font(.title2.bold())
                Button(action: onUnlock) {
                    Label("Unlock", systemImage: iconName)
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var iconName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "lock.fill"
        }
    }
}

extension View {
    func biometricLock() -> some View {
        modifier(BiometricLockModifier())
    }
}
