import SwiftUI

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
