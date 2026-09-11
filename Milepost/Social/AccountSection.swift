import SwiftUI

/// The Friends section on You: sign in, username, sharing, sign out and
/// account deletion (App Store 5.1.1(v)).
struct AccountSection: View {
    @Environment(SocialStore.self) private var social
    @AppStorage(SocialStore.shareKey) private var share = true
    @State private var showSetup = false
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        Section {
            switch social.phase {
            case .restoring:
                ProgressView()
            case .signedOut:
                if social.isAvailable {
                    AppleSignInButton()
                        .frame(maxWidth: .infinity)
                    if let error = social.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } else {
                    Text(SocialError.notConfigured.localizedDescription).foregroundStyle(.secondary)
                }
            case .signedIn:
                if let profile = social.profile {
                    LabeledContent("Username", value: profile.handle)
                        .accessibilityIdentifier("you.username")
                    NavigationLink(value: FriendsRoute()) {
                        LabeledContent("Friends", value: "\(social.friends.count)")
                    }
                    .accessibilityIdentifier("you.friends")
                    Toggle("Share activities with friends", isOn: $share)
                        .accessibilityIdentifier("you.share")
                        .onChange(of: share) { _, on in
                            Task { await social.sharingChanged(to: on) }
                        }
                } else if social.profileLoaded {
                    Button("Choose a username") { showSetup = true }
                        .accessibilityIdentifier("you.pickUsername")
                }
                Button("Sign out") { Task { await social.signOut() } }
                    .accessibilityIdentifier("you.signOut")
                Button("Delete account", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("you.deleteAccount")
            }
        } header: {
            Text("Friends")
        } footer: {
            Text(footer)
        }
        .sheet(isPresented: $showSetup) { UsernameSetupSheet() }
        .confirmationDialog("Delete your Milepost account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    do {
                        try await social.deleteAccount()
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Your username, friends and everything you shared are deleted from the server. Activities on this phone stay.")
        }
        .alert("Couldn't delete the account", isPresented: present($deleteError)) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var footer: String {
        switch social.phase {
        case .signedIn where social.profile != nil:
            return share
                ? "Friends see each activity's sport, title, distance, pace and time. Routes and maps never leave this phone."
                : "Nothing is shared. Friends still show up in the Block tab."
        default:
            return "Sign in to add friends and see their activities in the Block tab. Routes and maps never leave this phone."
        }
    }
}
