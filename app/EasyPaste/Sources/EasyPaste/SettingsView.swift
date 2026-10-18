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
                eyebrow("À TA MESURE").padding(.top, 43)
                Text("Simple, jusque dans les réglages.").font(.system(size: 27, weight: .semibold, design: .rounded))
                Text("Le nécessaire pour que l’app s’adapte à ta façon de travailler.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                section("Ton quotidien", icon: "sparkles") {
                    PreferenceToggle("Conserver mes prochaines copies", isOn: $history.enabled).disabled(history.fault || history.loading)
                    PreferenceToggle("Lancer EasyPaste au démarrage", isOn: Binding(get: { launch }, set: { value in
                        do {
                            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launch = SMAppService.mainApp.status == .enabled
                            if SMAppService.mainApp.status == .requiresApproval { message = "Autorise EasyPaste dans Général → Ouverture et extensions."; SMAppService.openSystemSettingsLoginItems() }
                        } catch { message = "Ouverture à la connexion : \(error.localizedDescription)"; launch = SMAppService.mainApp.status == .enabled }
                    }))
                    PreferenceToggle("Utiliser la barre en mode compact", isOn: $history.compact)
                    PreferenceRow("Conserver l’historique") { Picker("Durée de conservation", selection: $history.retention) { Text("1 jour").tag(1); Text("7 jours").tag(7); Text("30 jours").tag(30); Text("1 an").tag(365); Text("Toujours").tag(0) }.labelsHidden().controlSize(.regular).frame(width: 155) }
                    Divider().opacity(0.3)
                    Text("Les favoris et les collections sont conservés. Au-delà de 1 Go, la collecte se met en pause. Une image ou un texte peut contenir jusqu’à 20 Mo. Les vidéos s’arrêtent automatiquement avant 1 Go.").font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(3)
                }
                section("Coller sans détour", icon: "cursorarrow.click.2") {
                    HStack(alignment: .center, spacing: 24) { VStack(alignment: .leading, spacing: 6) { Text(trusted ? "Collage direct autorisé" : "Autoriser le collage direct").fontWeight(.medium); Text("L’Accessibilité permet à EasyPaste de coller dans l’application active. Sans elle, le contenu est copié : utilise ensuite ⌘V.").font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }; Spacer(); Button(trusted ? "Vérifier" : "Autoriser…") { if !trusted { let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary; _ = AXIsProcessTrustedWithOptions(options) }; trusted = AXIsProcessTrusted() }.buttonStyle(PasteButtonStyle(primary: !trusted)) }
                    Divider().opacity(0.3)
                    shortcut("Barre rapide", "⇧⌘V")
                    shortcut("Capture d’une zone", "⌃⌥⌘C")
                    shortcut("Extraire le texte d’une zone", "⌃⌥⌘X")
                    shortcut("Coller / coller en texte brut", "↩ / ⇧↩")
                    shortcut("Collage rapide des 9 premières cartes", "⌘1…9")
                    shortcut("Rechercher / modifier / aperçu", "⌘F / ⌘E / ⌘Y")
                    shortcut("Copier le prochain élément de la pile", "⌃⌥⌘V")
                    Text("Le raccourci de la pile prépare l’élément suivant. Colle-le avec ⌘V dans ton application.").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                CloudSettingsView(cloud: history.cloud)
                section("Ta vie privée", icon: "lock.shield") {
                    Text("Historique chiffré sur ce Mac, clé protégée dans le trousseau. Aucune publicité. Sans activation d’iCloud, ton historique reste local. Si tu actives iCloud, il est transféré vers la base privée de ton compte Apple ; Apple protège les données en transit et au repos. Les fichiers temporaires nécessaires à la synchronisation sont nettoyés après le transfert ou au prochain démarrage de la synchronisation. Pour lire ou coller une vidéo, une copie temporaire est déchiffrée sur ce Mac et nettoyée après 24 h au prochain lancement.").font(.system(size: 12)).lineSpacing(4)
                    Text("Les contenus signalés comme confidentiels ou temporaires et les principaux gestionnaires de mots de passe sont ignorés. Une extension qui ne signale pas ses secrets peut toutefois les laisser passer.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(3)
                    HStack { Text("Applications exclues").fontWeight(.medium); Spacer(); Button("Ajouter…") { addExclusion() }.buttonStyle(PasteButtonStyle()) }
                    ForEach(history.exclusions, id: \.self) { id in HStack { Text(appName(id)).font(.system(size: 11)); Spacer(); Button { history.exclusions.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }.buttonStyle(FullAreaButtonStyle(minimumSize: 24)).help("Retirer cette exclusion") } }
                    Text("Une exclusion concerne les nouvelles copies. Les éléments déjà enregistrés restent dans l’historique.").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    HStack { Text("\(ByteCountFormatter.string(fromByteCount: Int64(history.totalBytes), countStyle: .file)) de contenu · \(history.total) éléments").foregroundStyle(Theme.muted); Spacer(); Button("Effacer l’historique…") { clear() }.buttonStyle(PasteButtonStyle()) }.font(.system(size: 11))
                }
                section("Un lien avec tes assistants", icon: "point.3.connected.trianglepath.dotted") {
                    PreferenceToggle("Activer le connecteur MCP local", isOn: $history.mcpEnabled)
                    Text("L’assistant lance un processus local à la demande. Seules les collections que tu autorises ci-dessous sont lisibles. Désactive le connecteur pour couper tous les accès.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
                    if history.mcpEnabled {
                        if history.boards.isEmpty { Text("Crée une collection pour partager des éléments avec un assistant.").font(.system(size: 11)) }
                        ForEach(history.boards) { board in PreferenceToggle(board.name, isOn: Binding(get: { history.boards.first { $0.id == board.id }?.shared ?? false }, set: { _ in history.toggleSharing(board.id) })) }
                        Button("Copier la configuration MCP") {
                            let exe = "/Applications/EasyPaste.app/Contents/MacOS/EasyPaste"
                            let data: [String: Any] = ["mcpServers": ["easypaste": ["command": exe, "args": ["--mcp"]]]]
                            if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]), let text = String(data: json, encoding: .utf8) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); message = "Configuration copiée. EasyPaste doit être installé dans Applications." }
                        }.buttonStyle(PasteButtonStyle())
                    }
                }
                HStack { Text("EasyPaste 0.3.0 · Open source · Licence MIT"); Spacer(); Text("Pensé pour ton Mac.") }.font(.system(size: 10)).foregroundStyle(Theme.muted)
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
