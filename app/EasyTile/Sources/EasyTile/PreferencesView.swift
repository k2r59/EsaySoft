import AppKit
import SwiftUI

struct PreferenceToggle: View {
    let title: String
    @Binding var isOn: Bool
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; _isOn = isOn }
    var body: some View {
        Toggle(isOn: $isOn) { Text(title).frame(maxWidth: .infinity, alignment: .leading) }
            .toggleStyle(.switch).tint(Theme.mint).font(.system(size: 12))
            .frame(minHeight: 32)
    }
}

struct PreferencesView: View {
    @ObservedObject var store: TileStore
    @ObservedObject var engine: WindowEngine
    @ObservedObject var updates: AppUpdates
    @ObservedObject var login: LoginLaunch

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Préférences").font(.system(size: 31, weight: .semibold)).tracking(-1)
            section("Apparence", icon: "circle.lefthalf.filled") { AppearanceSettings() }
            section("Au quotidien", icon: "slider.horizontal.3") {
                PreferenceToggle("Ouvrir EasyTile au démarrage", isOn: Binding(get: { login.enabled }, set: login.setEnabled))
                if login.requiresApproval {
                    HStack {
                        Text("À autoriser dans Ouverture et extensions.").foregroundStyle(Theme.warning)
                        Spacer()
                        Button("Ouvrir les réglages macOS", action: login.openSettings).buttonStyle(TileButtonStyle())
                    }.font(.system(size: 11))
                }
                if !login.errorMessage.isEmpty { Text(login.errorMessage).font(.system(size: 11)).foregroundStyle(Theme.warning) }
                Divider()
                PreferenceToggle("Menu de placement pendant le glissement", isOn: $store.dragEnabled)
                Text("Glisse une fenêtre vers une zone du menu, puis relâche. Échap annule le placement.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            section("Mises à jour", icon: "arrow.triangle.2.circlepath") {
                PreferenceToggle("Vérifier automatiquement", isOn: Binding(get: { updates.automaticChecks }, set: updates.setAutomaticChecks))
                    .disabled(!updates.available)
                PreferenceToggle("Télécharger et installer automatiquement", isOn: Binding(get: { updates.automaticInstall }, set: updates.setAutomaticInstall))
                    .disabled(!updates.available)
                Text("Vérification quotidienne. L’installation automatique se fait à la fermeture de l’app.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                Divider()
                HStack {
                    Text("EasyTile \(AppVersion.current)").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(updates.waitingToInstall ? "Installer et relancer" : "Rechercher une mise à jour…") {
                        if updates.waitingToInstall { updates.installWhenReady() } else { updates.check() }
                    }.buttonStyle(TileButtonStyle()).disabled(!updates.waitingToInstall && !updates.canCheck)
                }
                if !updates.message.isEmpty { Text(updates.message).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                if let date = updates.lastCheck {
                    Text("Dernière vérification : \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            section("Autorisations", icon: "hand.raised") {
                HStack {
                    Label(engine.trusted ? "Accessibilité autorisée" : "Accessibilité à autoriser",
                          systemImage: engine.trusted ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(engine.trusted ? Theme.mint : Theme.warning)
                    Spacer()
                    Button("Ouvrir les autorisations") { engine.requestAccess() }.buttonStyle(TileButtonStyle())
                }.font(.system(size: 12))
                Text("Dispositions et réglages conservés sur ce Mac. Les titres des fenêtres ne sont pas enregistrés.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            HStack {
                Text("macOS · Code source MIT").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Quitter EasyTile") { NSApp.terminate(nil) }.buttonStyle(TileButtonStyle())
            }
        }
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.mint).padding(.bottom, 3)
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).surface()
    }
}
