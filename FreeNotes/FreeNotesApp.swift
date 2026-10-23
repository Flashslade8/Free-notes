import SwiftUI
import GoogleSignIn
 
@main
struct FreeNotesApp: App {
    @StateObject private var auth = AuthManager()
 
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                // Lets Google Sign-In hand control back to the app after the browser step.
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
 
/// Shows the login screen until someone signs in (or continues as guest).
struct RootView: View {
    @EnvironmentObject var auth: AuthManager
 
    var body: some View {
        if let user = auth.user {
            MainView(userID: user.id)
                .id(user.id)        // fresh note store whenever the account changes
        } else {
            LoginView()
        }
    }
}
 
/// Creates the note store for the signed-in account.
struct MainView: View {
    @StateObject private var store: NoteStore
 
    init(userID: String) {
        _store = StateObject(wrappedValue: NoteStore(userID: userID))
    }
 
    var body: some View {
        NoteListView()
            .environmentObject(store)
    }
}
 
