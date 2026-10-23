import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 72))
                .foregroundStyle(.white)
                .frame(width: 128, height: 128)
                .background(
                    LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 0.91),
                                            Color(red: 0.18, green: 0.53, blue: 1.0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28))

            VStack(spacing: 6) {
                Text("Free Notes").font(.largeTitle.bold())
                Text("Sign in to keep your notes under your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 14) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    auth.handleApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)

                Button {
                    auth.signInWithGoogle()
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Sign in with Google").fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.black)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
                }

                Button("Continue without an account") {
                    auth.continueAsGuest()
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
            .frame(maxWidth: 380)

            if let message = auth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Spacer().frame(height: 24)
        }
        .padding(24)
    }
}
