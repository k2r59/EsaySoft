import SwiftUI

/// Observes changes once through SwiftUI; no manual preferences reads per frame.
@propertyWrapper struct ThemePalette: DynamicProperty {
    @AppStorage(GlassTint.defaultsKey) private var stored = GlassTint.blue.rawValue
    var wrappedValue: GlassTint { GlassTint.resolve(stored) }
}

enum GlassTint: String, CaseIterable, Identifiable {
    case blue, mint, lavender, rose, graphite
    static let defaultsKey = "quickBarGlassTint"
    var id: Self { self }
    var title: String {
        switch self {
        case .blue: return "Bleu glacé"
        case .mint: return "Menthe"
        case .lavender: return "Lavande"
        case .rose: return "Rosé"
        case .graphite: return "Graphite"
        }
    }
    static func resolve(_ value: String) -> Self { Self(rawValue: value) ?? .blue }
    var colors: [Color] { Self.palettes[self]! }
    var accent: Color { Self.accents[self]![0] }
    var accentEnd: Color { Self.accents[self]![1] }
    var controlPlate: Color { Self.accents[self]![2] }
    var actionGradient: LinearGradient {
        LinearGradient(colors: [accent, accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var windowColors: [Color] { Self.canvases[self]! }
    var chromeAccent: Color { Self.chromeAccents[self]! }
    var markColors: [Color] { Self.marks[self]! }
    var markGradient: LinearGradient {
        LinearGradient(colors: markColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private static let chromeAccents: [Self: Color] = [
        .blue: Theme.adaptive("chrome.blue", light: 0x06418F, dark: 0xA7CEFF),
        .mint: Theme.adaptive("chrome.mint", light: 0x004B32, dark: 0x9CF7CC),
        .lavender: Theme.adaptive("chrome.lavender", light: 0x56308D, dark: 0xD0B9FF),
        .rose: Theme.adaptive("chrome.rose", light: 0x7A2152, dark: 0xFFB5D1),
        .graphite: Theme.adaptive("chrome.graphite", light: 0x264052, dark: 0xBDD4E5)
    ]
    private static let marks: [Self: [Color]] = [
        .blue: [Theme.adaptive("mark.blue.1", light: 0x0D2C61, dark: 0xD6E8FF), Theme.adaptive("mark.blue.2", light: 0x163875, dark: 0xA7CEFF)],
        .mint: [Theme.adaptive("mark.mint.1", light: 0x0B4334, dark: 0xDAFFF0), Theme.adaptive("mark.mint.2", light: 0x104F3F, dark: 0xA9F1D0)],
        .lavender: [Theme.adaptive("mark.lavender.1", light: 0x432069, dark: 0xEDE3FF), Theme.adaptive("mark.lavender.2", light: 0x59367F, dark: 0xD0B9FF)],
        .rose: [Theme.adaptive("mark.rose.1", light: 0x6C2043, dark: 0xFFE4EE), Theme.adaptive("mark.rose.2", light: 0x842B4C, dark: 0xFFBED7)],
        .graphite: [Theme.adaptive("mark.graphite.1", light: 0x253846, dark: 0xE6F1FA), Theme.adaptive("mark.graphite.2", light: 0x344A5A, dark: 0xBDD4E5)]
    ]
    private static let accents: [Self: [Color]] = [
        .blue: [Theme.adaptive("accent.blue", light: 0x0E5BD6, dark: 0xA7CEFF), Theme.adaptive("accent.blue.end", light: 0x124FC0, dark: 0x83ADF2), Theme.adaptive("plate.blue", light: 0xE6EFFB, dark: 0x1B2C40)],
        .mint: [Theme.adaptive("accent.mint", light: 0x11694F, dark: 0x9CF7CC), Theme.adaptive("accent.mint.end", light: 0x0B513E, dark: 0x6BD8AB), Theme.adaptive("plate.mint", light: 0xE3F5ED, dark: 0x112B25)],
        .lavender: [Theme.adaptive("accent.lavender", light: 0x6A45B0, dark: 0xD0B9FF), Theme.adaptive("accent.lavender.end", light: 0x50318F, dark: 0xAF90E5), Theme.adaptive("plate.lavender", light: 0xF1E9FB, dark: 0x2C2340)],
        .rose: [Theme.adaptive("accent.rose", light: 0xA93F70, dark: 0xFFB5D1), Theme.adaptive("accent.rose.end", light: 0x842C54, dark: 0xE693B7), Theme.adaptive("plate.rose", light: 0xFFF1F6, dark: 0x3D2532)],
        .graphite: [Theme.adaptive("accent.graphite", light: 0x405B6D, dark: 0xBDD4E5), Theme.adaptive("accent.graphite.end", light: 0x2F4658, dark: 0x95B2C9), Theme.adaptive("plate.graphite", light: 0xE8EEF3, dark: 0x18232C)]
    ]
    private static let canvases: [Self: [Color]] = [
        .blue: [Theme.adaptive("canvas.blue.1", light: 0xD1E4FF, dark: 0x172B4A), Theme.adaptive("canvas.blue.2", light: 0xE0F7F5, dark: 0x173D47), Theme.adaptive("canvas.blue.3", light: 0xE5DBFA, dark: 0x292544)],
        .mint: [Theme.adaptive("canvas.mint.1", light: 0xC9F0E5, dark: 0x153D32), Theme.adaptive("canvas.mint.2", light: 0xE5F5D0, dark: 0x2B3E2A), Theme.adaptive("canvas.mint.3", light: 0xCBE8F8, dark: 0x183B47)],
        .lavender: [Theme.adaptive("canvas.lavender.1", light: 0xDED4FF, dark: 0x2F2449), Theme.adaptive("canvas.lavender.2", light: 0xF5E0F5, dark: 0x41283E), Theme.adaptive("canvas.lavender.3", light: 0xD2E5FC, dark: 0x213B54)],
        .rose: [Theme.adaptive("canvas.rose.1", light: 0xF8D6E5, dark: 0x452737), Theme.adaptive("canvas.rose.2", light: 0xFFE5CE, dark: 0x483527), Theme.adaptive("canvas.rose.3", light: 0xE7DCF9, dark: 0x302641)],
        .graphite: [Theme.adaptive("canvas.graphite.1", light: 0xD6E2E7, dark: 0x24343F), Theme.adaptive("canvas.graphite.2", light: 0xEAF0F1, dark: 0x303E42), Theme.adaptive("canvas.graphite.3", light: 0xD8DFF1, dark: 0x272F46)]
    ]
    private static let palettes: [Self: [Color]] = [
        .blue: [GlassAppearance.ice, GlassAppearance.blue, GlassAppearance.aqua],
        .mint: [
            Theme.adaptive("glass.mint.ice", light: 0x92CABD, dark: 0x254E48),
            Theme.adaptive("glass.mint.blue", light: 0x68BDB9, dark: 0x1B3E43),
            Theme.adaptive("glass.mint.aqua", light: 0xB4D4BC, dark: 0x2C5045)
        ],
        .lavender: [
            Theme.adaptive("glass.lavender.ice", light: 0xABB0DF, dark: 0x3C3D64),
            Theme.adaptive("glass.lavender.blue", light: 0x9098D6, dark: 0x303451),
            Theme.adaptive("glass.lavender.aqua", light: 0xC9BEDC, dark: 0x48415C)
        ],
        .rose: [
            Theme.adaptive("glass.rose.ice", light: 0xD5ADB7, dark: 0x573C4B),
            Theme.adaptive("glass.rose.blue", light: 0xBEA3CB, dark: 0x44334E),
            Theme.adaptive("glass.rose.aqua", light: 0xE5CEBB, dark: 0x56463E)
        ],
        .graphite: [
            Theme.adaptive("glass.graphite.ice", light: 0xA9BAC8, dark: 0x354653),
            Theme.adaptive("glass.graphite.blue", light: 0x91A8B9, dark: 0x263645),
            Theme.adaptive("glass.graphite.aqua", light: 0xC9D4D6, dark: 0x3B4C50)
        ]
    ]
}
