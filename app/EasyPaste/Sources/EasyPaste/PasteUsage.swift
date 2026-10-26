import Foundation
import SwiftUI

/// A small encrypted index, separate from media payloads: recording a paste
/// never decrypts or rewrites a large image or video record.
struct PasteUsage: Codable, Equatable {
    private(set) var counts: [UUID: Int] = [:]

    func count(for id: UUID) -> Int { max(0, counts[id] ?? 0) }

    mutating func record(_ ids: Set<UUID>) {
        for id in ids {
            let previous = count(for: id)
            counts[id] = previous == Int.max ? previous : previous + 1
        }
    }

    mutating func retain(_ ids: Set<UUID>) {
        counts = counts.filter { ids.contains($0.key) && $0.value > 0 }
    }
}

extension ClipVault {
    static let pasteUsageFile = "paste-usage.json.enc"

    func loadPasteUsage() throws -> PasteUsage {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.pasteUsageFile).path) else { return PasteUsage() }
        return try read(PasteUsage.self, name: Self.pasteUsageFile)
    }
}

struct PasteCountBadge: View {
    @ThemePalette private var palette
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count.formatted()).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 19)
                .background(palette.accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(palette.accent.opacity(0.35), lineWidth: 0.75))
                .fixedSize().help("Collé \(count) fois depuis EasyPaste")
                .accessibilityLabel("Nombre de collages depuis EasyPaste")
                .accessibilityValue(count.formatted())
                .allowsHitTesting(false)
        }
    }
}
