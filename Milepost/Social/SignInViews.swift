import AuthenticationServices
import SwiftUI

/// Apple's own button; App Review expects it rather than a lookalike.
struct AppleSignInButton: View {
    @Environment(SocialStore.self) private var social

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            social.prepareAppleRequest(request)
        } onCompletion: { result in
            Task { await social.completeAppleSignIn(result) }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 48)
        .frame(maxWidth: 360)
        .accessibilityIdentifier("signin.apple")
    }
}

/// What the Friends feed shows before there is an account. Only reached by
/// choosing Friends; nothing asks on launch.
struct SignInCard: View {
    @Environment(SocialStore.self) private var social

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.orange)
            Text("Run with friends")
                .font(.title2.weight(.bold))
            Text("See your friends' runs, walks and rides here, and let them see yours.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if social.isAvailable {
                AppleSignInButton()
            } else {
                Text(SocialError.notConfigured.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = social.lastError {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Text("Your routes stay on this phone. Friends see an activity's sport, title, distance, pace and time — never the map.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// First sign-in: pick the username friends search for.
struct UsernameSetupSheet: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var displayName = ""
    @State private var available: Bool?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("@").foregroundStyle(.secondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("setup.username")
                            .onChange(of: username) { _, value in
                                let clean = Username.normalize(value)
                                if clean != value { username = clean }
                                available = nil
                            }
                        if let available {
                            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(available ? .green : .red)
                                .accessibilityLabel(available ? "Available" : "Taken")
                        }
                    }
                    TextField("Display name (optional)", text: $displayName)
                        .accessibilityIdentifier("setup.displayName")
                } header: {
                    Text("Pick a username")
                } footer: {
                    Text("3–20 lowercase letters, numbers or underscores. Friends find you as @\(username.isEmpty ? "username" : username).")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Done", action: save)
                        .disabled(saving || available != true)
                        .accessibilityIdentifier("setup.done")
                }
            }
            .task(id: username) { await check() }
            .onAppear { displayName = social.suggestedDisplayName }
        }
    }

    private func check() async {
        let candidate = username
        guard Username.isValid(candidate) else {
            available = candidate.isEmpty ? nil : false
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, candidate == username else { return }
        available = await social.isUsernameAvailable(candidate)
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                try await social.createProfile(username: username,
                                               displayName: String(displayName.trimmingCharacters(in: .whitespaces).prefix(40)))
                dismiss()
            } catch {
                self.error = "That username is taken or not allowed. Try another."
                available = false
            }
            saving = false
        }
    }
}
