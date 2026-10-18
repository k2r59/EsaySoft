import SwiftUI
import AppKit

struct CloudSettingsView: View {
    @ObservedObject var cloud: CloudSync
    @State private var changing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ton historique, sur tes Macs", systemImage: "icloud")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.mint)
            PreferenceToggle("Synchroniser avec iCloud", isOn: Binding(get: { cloud.enabled }, set: change))
                .disabled(!cloud.available || changing)
            Text("Retrouve tes textes, images, captures et vidéos dans EasyPaste sur tes Macs connectés au même compte Apple. Les favoris et les collections suivent aussi. La qualité des originaux est conservée.")
                .font(.system(size: 12)).lineSpacing(4)
            HStack(spacing: 10) {
                Image(systemName: cloud.enabled ? "icloud" : "internaldrive").foregroundStyle(Theme.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cloud.available ? cloud.message : "iCloud sera disponible dans la version configurée et signée pour ce service.")
                        .fixedSize(horizontal: false, vertical: true)
                    if cloud.enabled, let date = cloud.lastSync {
                        Text("Dernière synchronisation : \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 8)
                if cloud.enabled {
                    Button(cloud.working ? "En cours…" : "Synchroniser") { Task { await cloud.synchronize() } }
                        .buttonStyle(PasteButtonStyle()).disabled(cloud.working || changing)
                }
            }.font(.system(size: 11)).padding(14)
                .background(Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            Text("Les suppressions et la corbeille se synchronisent. La durée de conservation réglée sur chaque Mac s’applique aussi aux copies iCloud : choisis la même durée sur tes Macs. Les favoris et les collections restent protégés de l’expiration.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(3)
            Text("Les fichiers copiés depuis le Finder sont des références locales et restent sur leur Mac. Les exclusions d’applications, les raccourcis et les autorisations MCP restent propres à chaque Mac. Désactiver iCloud conserve les copies locales et en ligne.")
                .font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(3)
        }.font(.system(size: 12)).padding(24).frame(maxWidth: .infinity, alignment: .leading).surface()
    }
    private func change(_ value: Bool) {
        if value {
            let alert = NSAlert()
            alert.messageText = "Synchroniser tout ton historique avec iCloud ?"
            alert.informativeText = "Tes textes, images, vidéos, favoris et collections seront envoyés dans la base iCloud privée du compte Apple connecté à ce Mac, puis fusionnés avec les autres Macs. Les références de fichiers Finder restent locales. Les suppressions et l’expiration de l’historique se répercuteront sur les Macs synchronisés. Tu peux désactiver la synchronisation à tout moment."
            alert.addButton(withTitle: "Activer iCloud"); alert.addButton(withTitle: "Annuler")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        changing = true
        Task { await cloud.setEnabled(value); changing = false }
    }
}

struct CloudPrivacyLabel: View {
    @ObservedObject var cloud: CloudSync
    var body: some View { Text(cloud.enabled ? "Sur ce Mac, avec iCloud." : "Sur ce Mac. iCloud désactivé.").font(.system(size: 10)).foregroundStyle(Theme.muted) }
}
