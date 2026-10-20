import SwiftUI
import AppKit

struct ShootPreferenceToggle: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack {
                Text(title).foregroundStyle(.white)
                Spacer(minLength: 20)
                Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
                    .tint(.esAccent).allowsHitTesting(false).accessibilityHidden(true)
            }.frame(minHeight: 36).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(title, isOn: $isOn).toggleStyle(.switch) }
    }
}

struct ShootSettingsView: View {
    let owner: AppDelegate
    @ObservedObject var sounds: SoundFeedback
    @ObservedObject var updates: AppUpdates
    @State private var tab = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Réglages").font(.system(size: 30, weight: .semibold))
            HStack(spacing: 6) {
                tabButton("Général", symbol: "slider.horizontal.3", index: 0)
                tabButton("Mises à jour", symbol: "arrow.triangle.2.circlepath", index: 1)
            }.padding(5).background(Color.esSurface, in: RoundedRectangle(cornerRadius: 12))
            if tab == 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Sons", systemImage: "speaker.wave.2").foregroundStyle(Color.esAccent)
                    ShootPreferenceToggle(title: "Son à la copie", isOn: $sounds.copies)
                    Divider()
                    ShootPreferenceToggle(title: "Son à la capture d’image ou de texte", isOn: $sounds.captures)
                    Text("Silencieux pendant un enregistrement vidéo.").foregroundStyle(Color.esMuted)
                }.modifier(Surface())
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Label("Capturer une zone", systemImage: "viewfinder"); Spacer(); KeyCap(label: "⌃ ⌥ ⌘ 2") }
                    HStack { Label("Extraire le texte", systemImage: "text.viewfinder"); Spacer(); KeyCap(label: "⌃ ⌥ ⌘ T") }
                    Divider()
                    row("Accès à l’écran", "lock.shield", "Gérer l’autorisation") { owner.openScreenPermissions() }
                    row("Captures locales", "internaldrive", "Ouvrir le dossier") { NSWorkspace.shared.open(owner.store) }
                    row("MCP local", "point.3.connected.trianglepath.dotted", "Copier la configuration") { owner.copyMCPConfiguration() }
                }.modifier(Surface())
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("EasyShoot \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")",
                              systemImage: "checkmark.shield").font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    ShootPreferenceToggle(title: "Vérifier automatiquement", isOn: Binding(
                        get: { updates.automaticChecks }, set: updates.setAutomaticChecks
                    )).disabled(!updates.available)
                    Divider()
                    ActionButton(title: updates.waitingToInstall ? "Installer et relancer" : "Rechercher une mise à jour…",
                                 symbol: "arrow.triangle.2.circlepath", primary: true) {
                        if updates.waitingToInstall { updates.installWhenReady() } else { updates.check() }
                    }.disabled(!updates.waitingToInstall && !updates.canCheck)
                    Text(updates.message.isEmpty ? "Tu choisis quand installer. Tes captures restent sur le Mac." : updates.message)
                        .foregroundStyle(Color.esMuted).fixedSize(horizontal: false, vertical: true)
                    if let date = updates.lastCheck {
                        Text("Dernière vérification : \(date.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(Color.esMuted)
                    }
                }.modifier(Surface())
            }
        }.font(.system(size: 12))
    }
    private func tabButton(_ title: String, symbol: String, index: Int) -> some View {
        Button { tab = index } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 40)
                .foregroundStyle(tab == index ? Color.esAccent : Color.esMuted)
                .background(tab == index ? Color.esAccent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(tab == index ? .isSelected : [])
    }
    private func row(_ title: String, _ symbol: String, _ actionTitle: String,
                     action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer(minLength: 20)
            ActionButton(title: actionTitle, symbol: "arrow.up.right", action: action)
        }
    }
}
