import SwiftUI

/// Shared visual language. Semantic surfaces follow the user's appearance setting.
enum EpoStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.47, green: 0.84, blue: 0.77, alpha: 1)
        }
        return NSColor(red: 0.03, green: 0.50, blue: 0.45, alpha: 1)
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let radius: CGFloat = 12
}

struct LibraryEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(EpoStyle.accent)
                .frame(width: 72, height: 72)
                .background(EpoStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .padding(24)
    }
}

struct LibraryHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(EpoStyle.accent)
                .frame(width: 44, height: 44)
                .background(EpoStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
