import SwiftUI

/// Server address, username and password form shown while signed out.
struct SignInView: View {
    @Environment(SessionStore.self) private var session

    @AppStorage("lastServerAddress") private var serverAddress = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case server, username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server address", text: $serverAddress)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .server)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
                } header: {
                    Text("Server")
                } footer: {
                    Text("The address you use for Audiobookshelf in a browser, including any sub-path, such as abs.example.com.")
                }

                Section("Account") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                }

                Section {
                    Button(action: signIn) {
                        HStack {
                            Text("Sign In")
                            Spacer()
                            if isSigningIn { ProgressView() }
                        }
                    }
                    .disabled(!canSubmit)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sign In")
            .disabled(isSigningIn)
        }
    }

    private var canSubmit: Bool {
        !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSigningIn
    }

    private func signIn() {
        guard canSubmit else { return }
        focusedField = nil
        errorMessage = nil
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await session.signIn(serverAddress: serverAddress, username: username, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    SignInView()
        .environment(SessionStore(tokenStore: PreviewTokenStore()))
}
