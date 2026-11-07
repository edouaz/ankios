// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// `ContentUnavailableView` on iOS 17+, a plain equivalent on iOS 16.
struct UnavailableView<Actions: View>: View {
    let title: String
    let systemImage: String
    var description: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        if #available(iOS 17, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let description { Text(description) }
            } actions: {
                actions()
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(title).font(.title2.bold())
                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                actions()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension UnavailableView where Actions == EmptyView {
    init(_ title: String, systemImage: String, description: String? = nil) {
        self.init(title: title, systemImage: systemImage, description: description) { EmptyView() }
    }
}

/// Merges glass buttons on iOS 26+; there is nothing to merge before that.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 8) { content() }
        } else {
            content()
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26+, a flat rounded fill of the same tint before that.
    @ViewBuilder
    func glassSurface(tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            let glass = tint.map { Glass.regular.tint($0.opacity(0.3)) } ?? .regular
            glassEffect(glass.interactive(), in: RoundedRectangle(cornerRadius: 16))
        } else {
            background(
                tint?.opacity(0.3) ?? Color(.secondarySystemFill),
                in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
