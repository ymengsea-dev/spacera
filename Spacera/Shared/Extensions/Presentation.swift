import SwiftUI

extension SafetyLevel {
    var title: String {
        switch self {
        case .safe: "Safe"
        case .review: "Review"
        case .userData: "Your Data"
        case .infoOnly: "Info"
        }
    }

    var color: Color {
        switch self {
        case .safe: Theme.sage
        case .review: Theme.mustard
        case .userData: Theme.rust
        case .infoOnly: Theme.stone
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.shield"
        case .review: "eye"
        case .userData: "person.crop.circle.badge.exclamationmark"
        case .infoOnly: "info.circle"
        }
    }
}

extension FootprintKind {
    var symbol: String {
        switch self {
        case .bundle: "app"
        case .container: "shippingbox"
        case .groupContainer: "square.stack.3d.up"
        case .applicationSupport: "folder"
        case .cache: "internaldrive"
        case .httpStorage, .webKit, .cookies: "globe"
        case .logs: "doc.text"
        case .savedState: "macwindow"
        case .preferences: "gearshape"
        case .backgroundItem: "gearshape.2"
        case .developer: "hammer"
        case .other: "doc"
        }
    }
}

extension MatchConfidence {
    var title: String {
        switch self {
        case .exact: "Exact match"
        case .group: "Shared group"
        case .likely: "Matched by name"
        }
    }
}

/// A raised panel, used sparingly: for content that sits apart from the page, such as banners and expandable groups.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.rule))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
