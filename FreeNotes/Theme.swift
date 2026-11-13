import SwiftUI

/// One set of sizes and styles used everywhere, so the whole app feels consistent.
enum Theme {
    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

extension Font {
    /// Big rounded headings: the home screen and section titles.
    static func heading(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
}

private struct SoftShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        // Shadows are a little stronger in dark mode, where soft ones would disappear.
        content.shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.08), radius: radius, y: y)
    }
}

extension View {
    func softShadow(radius: CGFloat = 8, y: CGFloat = 3) -> some View {
        modifier(SoftShadow(radius: radius, y: y))
    }

    /// The look of every floating pill: frosted glass, a hairline edge and a soft shadow.
    func floatingCapsule() -> some View {
        background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.quaternary))
            .softShadow(radius: 10, y: 4)
    }

    /// The same look for larger floating panels such as the writing toolbar.
    func floatingPanel(cornerRadius: CGFloat = Theme.Radius.large) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.quaternary))
            .softShadow(radius: 10, y: 4)
    }
}

/// Light, dark, or follow the device.
enum Appearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Zoom-open transition from a note card into the editor

private struct NoteNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var noteNamespace: Namespace.ID? {
        get { self[NoteNamespaceKey.self] }
        set { self[NoteNamespaceKey.self] = newValue }
    }
}

private struct NoteTransitionSource: ViewModifier {
    @Environment(\.noteNamespace) private var namespace
    let id: UUID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct NoteTransitionDestination: ViewModifier {
    @Environment(\.noteNamespace) private var namespace
    let id: UUID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    /// Marks a note card as the starting point of the zoom-open animation.
    func noteTransitionSource(_ id: UUID) -> some View { modifier(NoteTransitionSource(id: id)) }
    /// Makes the editor grow out of that card.
    func noteTransitionDestination(_ id: UUID) -> some View { modifier(NoteTransitionDestination(id: id)) }
}

// MARK: - Page turn

/// Swings a page away around its left edge, like turning a page in a book.
struct PageFlip: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0),
                              anchor: .leading, perspective: 0.45)
            .shadow(color: .black.opacity(angle == 0 ? 0 : 0.3), radius: 16, x: 8)
    }
}

extension AnyTransition {
    /// Going to the next page: the current page turns away.
    static var flipForward: AnyTransition {
        .asymmetric(insertion: .identity,
                    removal: .modifier(active: PageFlip(angle: -105), identity: PageFlip(angle: 0)))
    }

    /// Going back: the previous page turns back over.
    static var flipBackward: AnyTransition {
        .asymmetric(insertion: .modifier(active: PageFlip(angle: -105), identity: PageFlip(angle: 0)),
                    removal: .identity)
    }
}
