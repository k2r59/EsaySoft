import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var history: History
    @State private var trusted = AXIsProcessTrusted()
    @State private var launch = SMAppService.mainApp.status == .enabled
    @State private var message = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Réglages").font(.system(size: 27, weight: .semibold)).padding(.top, 43)
                section("Général", icon: "slider.horizontal.3") {
                    PreferenceToggle("Enregistrer les copies", isOn: $history.enabled).disabled(history.fault || history.loading)
                    PreferenceToggle("Lancer EasyPaste au démarrage", isOn: Binding(get: { launch }, set: { value in
                        do {
                            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launch = SMAppService.mainApp.status == .enabled
                            if SMAppService.mainApp.status == .requiresApproval { message = "Autorise EasyPaste dans Général → Ouverture et extensions."; SMAppService.openSystemSettingsLoginItems() }
                        } catch { message = "Ouverture à la connexion : \(error.localizedDescription)"; launch = SMAppService.mainApp.status == .enabled }
                    }))
                    PreferenceToggle("Barre rapide compacte", isOn: $history.compact)
                    PreferenceRow("Conserver l’historique") { Picker("Durée de conservation", selection: $history.retention) { Text("1 jour").tag(1); Text("7 jours").tag(7); Text("30 jours").tag(30); Text("1 an").tag(365); Text("Toujours").tag(0) }.labelsHidden().controlSize(.regular).frame(width: 155) }
                    Divider().opacity(0.3)
                    Text("Les favoris et les collections sont conservés sans limite de durée.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    SettingsDetails("Limites de stockage") {
                        Text("L’historique se met en pause à 1 Go. Maximum : 20 Mo par image ou texte. Les vidéos s’arrêtent avant 1 Go.")
                    }
                }
                section("Collage", icon: "cursorarrow.click.2") {
                    HStack(alignment: .center, spacing: 24) { VStack(alignment: .leading, spacing: 6) { Text(trusted ? "Collage direct autorisé" : "Collage direct").fontWeight(.medium); if !trusted { Text("Autorise l’Accessibilité pour coller directement. Sinon, utilise ⌘V après la copie.").font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) } }; Spacer(); Button(trusted ? "Vérifier" : "Autoriser…") { if !trusted { let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary; _ = AXIsProcessTrustedWithOptions(options) }; trusted = AXIsProcessTrusted() }.buttonStyle(PasteButtonStyle(primary: !trusted)) }
                    Divider().opacity(0.3)
                    SettingsDetails("Raccourcis clavier") {
                        shortcut("Barre rapide", "⇧⌘V")
                        shortcut("Capturer une zone", "⌃⌥⌘C")
                        shortcut("Arrêter la vidéo", "⌃⌥⌘S")
                        shortcut("Extraire du texte", "⌃⌥⌘X")
                        shortcut("Coller / en texte brut", "↩ / ⇧↩")
                        shortcut("Coller une des 9 premières cartes", "⌘1…9")
                        shortcut("Rechercher / modifier / aperçu", "⌘F / ⌘E / ⌘Y")
                        shortcut("Copier le suivant dans la pile", "⌃⌥⌘V")
                        Text("Pile : copie le suivant avec ⌃⌥⌘V, puis colle-le avec ⌘V.")
                    }
                }
                section("Confidentialité", icon: "lock.shield") {
                    Text("Historique chiffré sur ce Mac.").font(.system(size: 12))
                    SettingsDetails("Protection des données") {
                        Text("La clé reste dans le trousseau. L’historique reste local. Les intégrations facultatives ne partagent que les contenus que tu autorises.")
                        Text("Les copies signalées comme confidentielles ou temporaires et les principaux gestionnaires de mots de passe sont ignorés. Un secret non signalé peut être enregistré.")
                        Text("La lecture et le collage d’une vidéo créent une copie temporaire déchiffrée. Après 24 h, EasyPaste la supprime au lancement suivant.")
                    }
                    HStack { Text("Applications exclues").fontWeight(.medium); Spacer(); Button("Ajouter…") { addExclusion() }.buttonStyle(PasteButtonStyle()) }
                    ForEach(history.exclusions, id: \.self) { id in HStack { Text(appName(id)).font(.system(size: 11)); Spacer(); Button { history.exclusions.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }.buttonStyle(FullAreaButtonStyle(minimumSize: 24)).help("Retirer cette exclusion") } }
                    Text("Les exclusions s’appliquent aux prochaines copies.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    HStack { Text("\(ByteCountFormatter.string(fromByteCount: Int64(history.totalBytes), countStyle: .file)) de contenu · \(history.total) éléments").foregroundStyle(Theme.muted); Spacer(); Button("Effacer l’historique…") { clear() }.buttonStyle(PasteButtonStyle()) }.font(.system(size: 11))
                }
                section("Intégrations", icon: "puzzlepiece.extension") {
                    BitwardenSettings(model: history.bitwarden)
                }
                section("Assistants · MCP", icon: "point.3.connected.trianglepath.dotted") {
                    PreferenceToggle("Activer le connecteur local", isOn: $history.mcpEnabled)
                    Text("L’assistant peut lire uniquement les collections autorisées.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    if history.mcpEnabled {
                        if history.boards.isEmpty { Text("Crée une collection pour autoriser son accès.").font(.system(size: 11)) }
                        ForEach(history.boards) { board in PreferenceToggle(board.name, isOn: Binding(get: { history.boards.first { $0.id == board.id }?.shared ?? false }, set: { _ in history.toggleSharing(board.id) })) }
                        Button("Copier la configuration MCP") {
                            let exe = "/Applications/EasyPaste.app/Contents/MacOS/EasyPaste"
                            let data: [String: Any] = ["mcpServers": ["easypaste": ["command": exe, "args": ["--mcp"]]]]
                            if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]), let text = String(data: json, encoding: .utf8) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); message = "Configuration copiée. EasyPaste doit être installé dans Applications." }
                        }.buttonStyle(PasteButtonStyle())
                    }
                }
                Text("EasyPaste \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Développement") · Licence MIT").font(.system(size: 11)).foregroundStyle(Theme.muted)
                if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(Theme.mint) }
            }.padding(.horizontal, 32).padding(.bottom, 30)
        }.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted(); launch = SMAppService.mainApp.status == .enabled }
    }
    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Label(title, systemImage: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.mint).padding(.bottom, 4); content() }.font(.system(size: 12)).controlSize(.regular).padding(24).frame(maxWidth: .infinity, alignment: .leading).surface()
    }
    private func shortcut(_ title: String, _ keys: String) -> some View { PreferenceRow(title) { Text(keys).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.muted).frame(width: 106, height: 28).background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.ink.opacity(0.08))) } }
    private func appName(_ id: String) -> String { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id }
    private func addExclusion() { let panel = NSOpenPanel(); panel.title = "Choisir une application à ignorer"; panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = true; if panel.runModal() == .OK { for url in panel.urls { if let id = Bundle(url: url)?.bundleIdentifier, !history.exclusions.contains(id) { history.exclusions.append(id) } } } }
    private func clear() { let alert = NSAlert(); alert.messageText = "Effacer l’historique ?"; alert.informativeText = "Les copies ordinaires seront déplacées dans la corbeille pendant 7 jours. Tes favoris et collections sont conservés."; alert.addButton(withTitle: "Effacer"); alert.addButton(withTitle: "Annuler"); if alert.runModal() == .alertFirstButtonReturn { history.clearHistory() } }
}

/// The complete row toggles the help, including its empty space.
struct SettingsDetails<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                }.frame(maxWidth: .infinity, minHeight: 30).contentShape(Rectangle())
            }.buttonStyle(FullAreaButtonStyle()).foregroundStyle(Theme.ink)
                .accessibilityValue(expanded ? "Développé" : "Réduit")
            if expanded { content().fixedSize(horizontal: false, vertical: true) }
        }.font(.system(size: 11)).foregroundStyle(Theme.muted)
    }
}

/// A common trailing edge and row height keep controls stable as labels change.
struct PreferenceRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control
    init(_ title: String, @ViewBuilder control: @escaping () -> Control) {
        self.title = title; self.control = control
    }
    var body: some View {
        HStack(spacing: 24) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            control()
        }.frame(minHeight: 36)
    }
}
struct PreferenceToggle: View {
    let title: String
    @Binding var isOn: Bool
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; _isOn = isOn }
    var body: some View {
        PreferenceRow(title) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel(title)
        }
    }
}
