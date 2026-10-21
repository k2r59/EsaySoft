import AppKit
import SwiftUI

struct BitwardenSettings: View {
    @ObservedObject var model: BitwardenModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreferenceToggle("Activer Bitwarden", isOn: Binding(get: { model.enabled }, set: model.setEnabled))
            if model.enabled {
                Divider().opacity(0.3)
                PreferenceToggle("Lien public uniquement", isOn: $model.publicOnly)
                Text("Création immédiate · 7 jours · date et heure en titre · lien copié").font(.system(size: 11)).foregroundStyle(Theme.muted)
                PreferenceRow(model.account.isEmpty ? "Compte Bitwarden" : model.account) {
                    Button(model.account.isEmpty ? "Connecter…" : "Gérer…") { model.showAccount() }.buttonStyle(PasteButtonStyle())
                }
                SettingsDetails("À propos du partage") {
                    Text("Seuls les éléments que tu choisis sont envoyés, chiffrés, à Bitwarden. Les adresses des destinataires sont transmises pour vérifier leur accès.")
                    Text("Fichiers et accès par e-mail : abonnement Bitwarden compatible requis. « Partager avec options… » reste disponible en mode rapide.")
                    Text("Désactiver Bitwarden oublie la connexion sur ce Mac. Les liens existants restent actifs jusqu’à leur expiration ou leur suppression.")
                }
            }
        }
    }
}

struct BitwardenClipMenu: View {
    @ObservedObject var model: BitwardenModel
    let clip: Clip
    var body: some View {
        if model.enabled {
            Menu("Bitwarden") {
                Button(model.publicOnly ? "Copier un lien" : "Créer un lien…") { model.share(clip) }
                if model.publicOnly { Button("Partager avec options…") { model.share(clip, forceOptions: true) } }
                Divider()
                Button("Mes partages…") { model.showSends() }
            }.disabled(!model.canShare)
        }
    }
}

@MainActor final class BitwardenWindowController: NSObject, NSWindowDelegate {
    private let model: BitwardenModel
    private var panel: NSPanel?
    private var toast: NSPanel?
    private var toastTask: Task<Void, Never>?
    init(model: BitwardenModel) {
        self.model = model; super.init()
        model.present = { [weak self] in self?.show() }
        model.dismiss = { [weak self] in self?.hide() }
        model.quickFeedback = { [weak self] in self?.showToast($0) }
    }
    private func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil // Drop SecureField state when the panel is dismissed.
        panel = nil
    }
    private func showToast(_ text: String) {
        toastTask?.cancel(); toast?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 58), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: HStack(spacing: 10) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint); Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink) }.frame(width: 290, height: 58).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14)))
        let frame = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrameOrigin(CGPoint(x: frame.midX - 145, y: frame.maxY - 90)); panel.orderFrontRegardless(); toast = panel
        toastTask = Task { [weak self] in do { try await Task.sleep(for: .seconds(3)) } catch { return }; self?.toast?.close(); self?.toast = nil }
    }
    private func show() {
        guard model.enabled else { return }
        hide()
        let compact = model.quickPresentation && model.unlocked && model.page == .create
        let size = compact ? NSSize(width: 380, height: 240) : NSSize(width: 540, height: 620)
        do {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: compact ? [.titled, .closable, .nonactivatingPanel] : [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Bitwarden · EasyPaste"; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            panel.backgroundColor = NSColor(Theme.bg); panel.delegate = self
            if compact { panel.contentView = NSHostingView(rootView: BitwardenQuickView(model: model)); panel.level = .floating }
            else { panel.contentView = NSHostingView(rootView: BitwardenWindowView(model: model)) }
            self.panel = panel; panel.center()
        }
        if compact { panel?.orderFrontRegardless() }
        else { panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.busy { model.cancel(); return false }
        model.close(); return true
    }
}

/// One-click sharing keeps focus in the user's app; only progress and cancellation
/// are shown. Configuration stays in the separate full-sized options panel.
struct BitwardenQuickView: View {
    @ObservedObject var model: BitwardenModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(Theme.mint).accessibilityHidden(true)
                Text("Copier un lien").font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            Text("Lien public · 7 jours").font(.system(size: 12)).foregroundStyle(Theme.muted)
            if let error = model.error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
            } else {
                if model.busy {
                    if let progress = model.progress { ProgressView(value: progress) }
                    else { ProgressView().controlSize(.small) }
                }
                Text(model.status).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            HStack {
                Button(model.busy ? "Annuler" : "Fermer") { if model.busy { model.cancel() } else { model.close() } }.buttonStyle(PasteButtonStyle())
                Spacer()
                if !model.busy {
                    Button("Mes partages") { model.showSends() }.buttonStyle(PasteButtonStyle())
                    if let created = model.created { Button("Copier") { model.recopy(created) }.buttonStyle(PasteButtonStyle(primary: true)) }
                    else { Button("Réessayer") { model.create() }.buttonStyle(PasteButtonStyle(primary: true)).disabled(model.content == nil) }
                }
            }
        }.padding(22).frame(width: 380, height: 240).background(Theme.bg).foregroundStyle(Theme.ink)
    }
}

struct BitwardenWindowView: View {
    @ObservedObject var model: BitwardenModel
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var provider = 0
    @State private var deleteCandidate: BWSend?
    @FocusState private var focus: Field?
    private enum Field { case email, password, code }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.system(size: 22)).foregroundStyle(Theme.mint)
                    .frame(width: 44, height: 44).background(Theme.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 21, weight: .semibold))
                    Text("Bitwarden Send · \(model.unlocked ? model.region.domain : BWRegion.international.domain)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if model.unlocked && !model.busy { Button { model.lock() } label: { Image(systemName: "lock") }.buttonStyle(FullAreaButtonStyle(minimumSize: 32)).help("Verrouiller Bitwarden").accessibilityLabel("Verrouiller Bitwarden") }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.enabled { Text("Bitwarden est désactivé.") }
                    else if !model.unlocked { accountView }
                    else if let created = model.created { resultView(created) }
                    else if model.page == .create { createView }
                    else if model.page == .account { connectedView }
                    else { sendsView }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if model.busy {
                VStack(alignment: .leading, spacing: 8) {
                    if let progress = model.progress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) }
                    HStack { Text(model.status).font(.system(size: 12)).foregroundStyle(Theme.muted); Spacer(); Button("Annuler") { model.cancel() }.buttonStyle(PasteButtonStyle()) }
                }.accessibilityElement(children: .combine)
            }
            Divider().opacity(0.3)
            footer
        }.padding(26).frame(width: 540, height: 620).background(Theme.bg).foregroundStyle(Theme.ink)
            .onAppear { email = model.account; focus = .email }
            .onChange(of: model.unlocked) { _, unlocked in password = ""; code = ""; if !unlocked { focus = .password } }
            .onChange(of: model.enabled) { _, _ in password = ""; code = "" }
            .onChange(of: model.providers) { _, values in code = ""; provider = values.first ?? 0; focus = .code }
            .onChange(of: model.needsDeviceCode) { _, value in if value { code = ""; focus = .code } }
            .onDisappear { password = ""; code = "" }
            .confirmationDialog("Supprimer ce partage ? Le lien cessera de fonctionner.", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
                Button("Supprimer le partage", role: .destructive) { if let value = deleteCandidate { model.delete(value) }; deleteCandidate = nil }
                Button("Annuler", role: .cancel) { deleteCandidate = nil }
            }
    }
    private var title: String {
        if !model.unlocked { return "Connecter Bitwarden" }
        if model.created != nil { return model.copied ? "Lien copié" : "Lien créé" }
        if model.page == .create { return model.quickPresentation ? "Création du lien" : "Partager" }
        return model.page == .account ? "Compte Bitwarden" : "Mes partages"
    }
    private var accountView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.account.isEmpty {
                Label(model.account, systemImage: "person.crop.circle").font(.system(size: 14, weight: .medium)).textSelection(.enabled)
                Text("Déverrouille la connexion avec Touch ID ou le mot de passe de ce Mac.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Button("Déverrouiller") { model.unlock() }.buttonStyle(PasteButtonStyle(primary: true)).disabled(model.busy)
                Button("Utiliser un autre compte") { model.disconnect(); password = ""; code = "" }.buttonStyle(PasteButtonStyle()).disabled(model.busy)
            } else {
                field("Adresse e-mail") { TextField("nom@exemple.fr", text: $email).focused($focus, equals: .email).textContentType(.username) }
                field("Mot de passe maître") { SecureField("Mot de passe", text: $password).focused($focus, equals: .password).textContentType(.password) }
                if !model.providers.isEmpty || model.needsDeviceCode {
                    if model.providers.count > 1 { Picker("Vérification", selection: $provider) { ForEach(model.providers, id: \.self) { Text($0 == 0 ? "Application d’authentification" : "Code par e-mail").tag($0) } } }
                    field(provider == 0 && !model.needsDeviceCode ? "Code d’authentification" : "Code reçu par e-mail") { TextField("Code", text: $code).focused($focus, equals: .code).textContentType(.oneTimeCode) }
                    if provider == 1 && !model.needsDeviceCode {
                        Button("Envoyer un code par e-mail") { model.sendEmailCode(email: email, password: password) }.buttonStyle(PasteButtonStyle())
                        if model.status == "Code envoyé par e-mail" { Text(model.status).font(.system(size: 11)).foregroundStyle(Theme.mint) }
                    }
                }
                Button("Connecter") { model.login(email: email, password: password, code: code, provider: provider) }
                    .buttonStyle(PasteButtonStyle(primary: true)).disabled(model.busy || email.isEmpty || password.isEmpty).keyboardShortcut(.defaultAction)
                Text("La connexion est conservée dans le trousseau de ce Mac. Le mot de passe maître n’est pas enregistré.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                SettingsDetails("Compatibilité") {
                    Text("Intégration indépendante, sans CLI. Connexion par mot de passe, avec code de vérification si nécessaire. SSO, passkeys et clés de sécurité ne sont pas pris en charge dans cette fenêtre.")
                    Button("Ouvrir Bitwarden") { NSWorkspace.shared.open(BWRegion.international.vault) }.buttonStyle(PasteButtonStyle())
                }
            }
        }.textFieldStyle(.roundedBorder).disabled(model.busy)
    }
    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(model.account, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.mint)
            Text(model.region.label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Button("Mes partages") { model.showSends() }.buttonStyle(PasteButtonStyle(primary: true))
            Button("Déconnecter ce Mac", role: .destructive) { model.disconnect() }.buttonStyle(PasteButtonStyle())
            Text("La déconnexion conserve les liens déjà créés.").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }
    private var createView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: model.content?.isFile == true ? "doc" : "text.alignleft").foregroundStyle(Theme.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.contentLabel.isEmpty ? "Préparation du contenu…" : model.contentLabel).fontWeight(.medium).lineLimit(2)
                    Text(model.quickPresentation ? "Lien public · 7 jours · copie automatique" : "Chiffrement sur ce Mac").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).surface()
            if !model.quickPresentation {
                field("Titre") { TextField("Titre du partage", text: $model.options.name) }
                field("Qui peut ouvrir le lien ?") { Picker("Accès", selection: $model.options.audience) { ForEach(BWAudience.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden() }
                if model.options.audience == .emails {
                    field("Adresses autorisées") { TextField("alice@exemple.fr, bob@exemple.fr", text: $model.options.emails, axis: .vertical).lineLimit(2...3) }
                    Text("Un code sera envoyé aux destinataires à l’ouverture du lien. Bitwarden Premium requis.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                } else {
                    field("Mot de passe · facultatif") { SecureField("Sans mot de passe", text: $model.options.password) }
                }
                PreferenceRow("Expiration") { Picker("Expiration", selection: $model.options.days) { ForEach([1, 3, 7, 14, 30], id: \.self) { Text("\($0) jour\($0 > 1 ? "s" : "")").tag($0) } }.labelsHidden().frame(width: 140) }
            }
            if model.content?.isFile == true { Text("L’envoi de fichiers nécessite Bitwarden Premium ou un abonnement compatible.").font(.system(size: 11)).foregroundStyle(Theme.muted) }
        }.textFieldStyle(.roundedBorder).disabled(model.busy)
    }
    private func resultView(_ send: BWSend) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 42)).foregroundStyle(Theme.mint)
            Text(send.name).font(.system(size: 17, weight: .medium))
            Text("Colle le lien avec ⌘V pour le partager.").foregroundStyle(Theme.muted)
            Text(send.link.absoluteString).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).lineLimit(3)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).surface()
            if let date = send.deletion { Text("Expire le \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            Button("Copier à nouveau") { model.recopy(send) }.buttonStyle(PasteButtonStyle(primary: true))
        }
    }
    private var sendsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(model.account).font(.system(size: 11)).foregroundStyle(Theme.muted); Spacer(); Button { model.showSends() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(FullAreaButtonStyle(minimumSize: 30)).help("Actualiser").accessibilityLabel("Actualiser les partages").disabled(model.busy) }
            if model.sends.isEmpty && !model.busy { Text("Aucun partage actif.").foregroundStyle(Theme.muted).padding(.vertical, 24) }
            LazyVStack(spacing: 10) {
                ForEach(model.sends) { send in
                    HStack(spacing: 12) {
                        Image(systemName: send.isFile ? "doc" : "text.alignleft").foregroundStyle(Theme.mint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(send.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            if let date = send.deletion { Text("Jusqu’au \(date.formatted(date: .abbreviated, time: .omitted)) · \(send.accessCount) vues").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                        Button { model.recopy(send) } label: { Image(systemName: "link") }.buttonStyle(FullAreaButtonStyle(minimumSize: 32)).help("Copier le lien").accessibilityLabel("Copier le lien de \(send.name)")
                        Button { deleteCandidate = send } label: { Image(systemName: "trash") }.buttonStyle(FullAreaButtonStyle(minimumSize: 32)).help("Supprimer le partage").accessibilityLabel("Supprimer \(send.name)")
                    }.padding(12).surface().disabled(model.busy)
                }
            }
        }
    }
    private var footer: some View {
        HStack {
            Button("Fermer") { model.close() }.buttonStyle(PasteButtonStyle()).keyboardShortcut(.cancelAction).disabled(model.busy)
            Spacer()
            if model.unlocked && model.page == .create && model.created == nil && !model.quickPresentation {
                Button("Créer et copier le lien") { model.create() }.buttonStyle(PasteButtonStyle(primary: true))
                    .disabled(model.busy || model.content == nil || (try? model.options.validate()) == nil).keyboardShortcut(.defaultAction)
            } else if model.unlocked && model.page == .create && !model.busy && model.quickPresentation {
                Button("Mes partages") { model.showSends() }.buttonStyle(PasteButtonStyle())
                Button("Réessayer") { model.create() }.buttonStyle(PasteButtonStyle(primary: true)).disabled(model.content == nil)
            } else if model.unlocked && model.page != .account && !model.busy {
                Button("Compte") { model.showAccount() }.buttonStyle(PasteButtonStyle())
            }
        }
    }
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted); content().accessibilityLabel(label) }
    }
}
