import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var state
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    enum Field { case username, password }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("HomeDash")
                    .font(.largeTitle.bold())
                Text("Sign in to control your server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { signIn() }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            if let err = state.loginError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button(action: signIn) {
                ZStack {
                    if state.isLoggingIn {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign in").bold()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .disabled(username.isEmpty || password.isEmpty || state.isLoggingIn)
            .opacity((username.isEmpty || password.isEmpty) ? 0.5 : 1)
            .padding(.horizontal)

            Spacer()
            Spacer()
        }
    }

    private func signIn() {
        focused = nil
        Task { await state.login(username: username, password: password) }
    }
}
