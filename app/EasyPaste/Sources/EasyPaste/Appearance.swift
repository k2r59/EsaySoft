import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark, automatic
    static let defaultsKey = "appAppearance"
    var id: Self { self }
    var title: String {
        switch self {
        case .light: return "Clair"
        case .dark: return "Sombre"
        case .automatic: return "Automatique"
        }
    }
    var icon: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .automatic: return "circle.lefthalf.filled"
        }
    }
    var native: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .automatic: return nil
        }
    }
    static func stored(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .light
    }
    @MainActor func apply(to application: NSApplication? = nil) {
        // A nil override inherits macOS, including live scheduled appearance changes.
        // Let AppKit propagate it to existing windows, sheets and future panels.
        (application ?? .shared).appearance = native
    }
}

struct AppearanceSettings: View {
    @ThemePalette private var palette
    @AppStorage(AppAppearance.defaultsKey) private var storedAppearance = AppAppearance.light.rawValue
    private var selection: AppAppearance { AppAppearance(rawValue: storedAppearance) ?? .light }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(AppAppearance.allCases) { mode in
                    Button {
                        storedAppearance = mode.rawValue
                        mode.apply()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.icon)
                            Text(mode.title)
                            Spacer(minLength: 4)
                            Image(systemName: "checkmark").opacity(selection == mode ? 1 : 0)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selection == mode ? palette.accent : Theme.ink)
                        .background(selection == mode ? palette.accent.opacity(0.1) : Theme.raised.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selection == mode ? palette.accent : Theme.border))
                        .contentShape(Rectangle())
                    }.buttonStyle(FullAreaButtonStyle())
                        .accessibilityLabel("Apparence : \(mode.title)")
                        .accessibilityAddTraits(selection == mode ? .isSelected : [])
                }
            }
            Text("Automatique suit l’apparence de macOS.").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }
}
