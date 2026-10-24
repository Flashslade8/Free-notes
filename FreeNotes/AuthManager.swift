import SwiftUI
import AuthenticationServices
import GoogleSignIn

enum AuthProvider: String, Codable {
    case apple, google, guest
}

struct AppUser: Codable, Equatable {
    var id: String          // also used in the notes file name, so letters/numbers/dashes only
    var name: String
    var email: String?
    var provider: AuthProvider
    var providerUserID: String? = nil   // Apple's own user id, used to check the sign-in is still valid
}

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var user: AppUser?
    @Published var errorMessage: String?

    private let userKey = "currentUser"
    private let appleProfilesKey = "appleProfiles"   // Apple only sends the name once

    init() {
        if let data = UserDefaults.standard.data(forKey: userKey),
           let saved = try? JSONDecoder().decode(AppUser.self, from: data) {
            user = saved
            if saved.provider == .apple { verifyAppleCredential(saved) }
        }
    }

    // MARK: Guest

    func continueAsGuest() {
        setUser(AppUser(id: "guest", name: "Guest", email: nil, provider: .guest))
    }

    // MARK: Sign in with Apple

    func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Apple sign-in failed. This needs a paid Apple Developer account, "
                         + "so it usually won't work in sideloaded apps. (\(error.localizedDescription))"
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let id = clean("apple-" + credential.user)

            var profiles = UserDefaults.standard.dictionary(forKey: appleProfilesKey)
                as? [String: [String: String]] ?? [:]
            var profile = profiles[id] ?? [:]
            if let components = credential.fullName {
                let name = PersonNameComponentsFormatter().string(from: components)
                if !name.isEmpty { profile["name"] = name }
            }
            if let email = credential.email { profile["email"] = email }
            profiles[id] = profile
            UserDefaults.standard.set(profiles, forKey: appleProfilesKey)

            setUser(AppUser(id: id,
                            name: profile["name"] ?? "Apple User",
                            email: profile["email"],
                            provider: .apple,
                            providerUserID: credential.user))
        }
    }

    private func verifyAppleCredential(_ saved: AppUser) {
        guard let rawID = saved.providerUserID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: rawID) { [weak self] state, _ in
            if state == .revoked {
                Task { @MainActor in self?.signOut() }
            }
        }
    }

    // MARK: Google

    func signInWithGoogle() {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty, !clientID.hasPrefix("YOUR_") else {
            errorMessage = "Google sign-in isn't set up yet. Add your Google client ID to project.yml."
            return
        }
        guard let presenter = rootViewController() else {
            errorMessage = "Couldn't open the Google sign-in screen."
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil,
                                           additionalScopes: [DriveClient.scope, DriveClient.fileScope]) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    // Error code -5 means the person closed the window.
                    if (error as NSError).code != -5 {
                        self.errorMessage = "Google sign-in failed: \(error.localizedDescription)"
                    }
                    return
                }
                guard let gUser = result?.user else { return }
                let rawID = gUser.userID ?? gUser.profile?.email ?? UUID().uuidString
                self.setUser(AppUser(id: self.clean("google-" + rawID),
                                     name: gUser.profile?.name ?? "Google User",
                                     email: gUser.profile?.email,
                                     provider: .google))
            }
        }
    }

    // MARK: Sign out

    func signOut() {
        if user?.provider == .google { GIDSignIn.sharedInstance.signOut() }
        user = nil
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    // MARK: Helpers

    private func setUser(_ newUser: AppUser) {
        errorMessage = nil
        user = newUser
        if let data = try? JSONEncoder().encode(newUser) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    /// Keep only characters that are safe in a file name.
    private func clean(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
