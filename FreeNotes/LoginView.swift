import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var appeared = false
    @State private var floating = false

    private let violet = Color(red: 0.42, green: 0.36, blue: 0.91)
    private let sky = Color(red: 0.18, green: 0.53, blue: 1.0)

    var body: some View {
        ZStack {
            LoginBackground(violet: violet, sky: sky, floating: floating)

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 32)
                        hero
                        featureCard.padding(.top, 32)
                        Spacer(minLength: 28)
                        buttons
                        errorBanner
                        footer.padding(.top, 20)
                        Spacer().frame(height: 12)
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { appeared = true }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { floating = true }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 18) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 112, height: 112)
                .background(
                    LinearGradient(colors: [violet, sky],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: violet.opacity(0.45), radius: 24, y: 12)

            VStack(spacing: 8) {
                Text("Free Notes")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Handwrite, record and organise,\nall in one beautiful place.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .loginReveal(appeared, delay: 0.05)
    }

    // MARK: Features

    private var featureCard: some View {
        VStack(spacing: 0) {
            LoginFeatureRow(icon: "pencil.tip.crop.circle", tint: violet,
                            title: "Natural handwriting",
                            detail: "Pens, highlighter and lasso, made for Apple Pencil.")
            Divider().padding(.leading, 64)
            LoginFeatureRow(icon: "waveform", tint: .orange,
                            title: "Record while you write",
                            detail: "Tap your writing to replay what was said.")
            Divider().padding(.leading, 64)
            LoginFeatureRow(icon: "icloud.fill", tint: sky,
                            title: "Sync with Google Drive",
                            detail: "Your notes follow you from device to device.")
        }
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.quaternary))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        .loginReveal(appeared, delay: 0.2)
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                auth.handleApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Haptics.tap()
                auth.signInWithGoogle()
            } label: {
                HStack(spacing: 10) {
                    Image(uiImage: GoogleLogo.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("Sign in with Google")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Color.black)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.gray.opacity(0.35)))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
            }
            .buttonStyle(LoginPressStyle())

            Button {
                Haptics.tap()
                auth.continueAsGuest()
            } label: {
                Text("Continue without an account")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(LoginPressStyle())
        }
        .loginReveal(appeared, delay: 0.35)
    }

    // MARK: Error

    @ViewBuilder
    private var errorBanner: some View {
        if let message = auth.errorMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.3)))
            .padding(.top, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text("Notes are saved on this device. Signing in with Google also syncs them to your Drive.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .loginReveal(appeared, delay: 0.5)
    }
}

// MARK: - Pieces

private struct LoginFeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct LoginPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A small paper page used as decoration.
private struct LoginPage: View {
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 3).fill(accent).frame(width: 46, height: 6)
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.28))
                    .frame(width: index == 4 ? 48 : 90, height: 4)
            }
        }
        .padding(16)
        .frame(width: 122, height: 156, alignment: .topLeading)
        .background(colorScheme == .dark ? Color.white.opacity(0.09) : Color.white,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
    }
}

private struct LoginBackground: View {
    let violet: Color
    let sky: Color
    let floating: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var baseColors: [Color] {
        if colorScheme == .dark {
            return [Color(red: 0.07, green: 0.07, blue: 0.14), Color(red: 0.05, green: 0.10, blue: 0.20)]
        }
        return [Color(red: 0.96, green: 0.95, blue: 1.0), Color(red: 0.90, green: 0.95, blue: 1.0)]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: baseColors, startPoint: .topLeading, endPoint: .bottomTrailing)

                Circle()
                    .fill(violet.opacity(colorScheme == .dark ? 0.35 : 0.25))
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .position(x: geo.size.width * 0.1, y: geo.size.height * 0.08)

                Circle()
                    .fill(sky.opacity(colorScheme == .dark ? 0.30 : 0.22))
                    .frame(width: 360, height: 360)
                    .blur(radius: 80)
                    .position(x: geo.size.width * 0.95, y: geo.size.height * 0.92)

                LoginGrid(color: colorScheme == .dark ? Color.white.opacity(0.05)
                                                       : Color.black.opacity(0.045))

                LoginPage(accent: violet)
                    .rotationEffect(.degrees(-12))
                    .position(x: geo.size.width * 0.12, y: geo.size.height * 0.2 + (floating ? -8 : 8))
                LoginPage(accent: sky)
                    .rotationEffect(.degrees(10))
                    .position(x: geo.size.width * 0.9, y: geo.size.height * 0.14 + (floating ? 8 : -8))
                LoginPage(accent: .orange)
                    .rotationEffect(.degrees(8))
                    .position(x: geo.size.width * 0.08, y: geo.size.height * 0.82 + (floating ? 8 : -8))
                LoginPage(accent: .pink)
                    .rotationEffect(.degrees(-9))
                    .position(x: geo.size.width * 0.92, y: geo.size.height * 0.8 + (floating ? -8 : 8))
            }
            .opacity(1)
        }
        .ignoresSafeArea()
    }
}

private struct LoginGrid: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let step: CGFloat = 32
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(color), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    /// Fades and slides a section in when the screen appears.
    func loginReveal(_ shown: Bool, delay: Double) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(delay), value: shown)
    }
}
