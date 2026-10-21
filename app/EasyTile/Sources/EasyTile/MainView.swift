import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var store: TileStore
    @ObservedObject var engine: WindowEngine
    @ObservedObject var updates: AppUpdates
    @ObservedObject var login: LoginLaunch
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Rectangle().fill(Theme.ink.opacity(0.06)).frame(width: 1)
            GeometryReader { bounds in
              VStack(spacing: 0) {
                topbar
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if store.page == "layouts" { layoutPage }
                        else if store.page == "shortcuts" { shortcutsPage }
                        else { PreferencesView(store: store, engine: engine, updates: updates, login: login) }
                    }.padding(28).frame(maxWidth: 1050, alignment: .leading).frame(maxWidth: .infinity)
                }
                footer
              }.frame(width: bounds.size.width, height: bounds.size.height)
            }
        }.background(Theme.bg).foregroundStyle(Theme.ink)
        .frame(minWidth: 1000, minHeight: 740)
        .sheet(isPresented: $store.showEditor) { LayoutEditor(store: store) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.split.2x2.fill").font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.mint)
                Text("EasyTile").font(.system(size: 23,weight: .bold,design: .rounded)).tracking(-0.8)
            }.padding(.top, 49).padding(.bottom, 7)
            Text("DE LA PLACE POUR TES IDÉES").font(.system(size: 8,weight: .semibold)).tracking(1.4).foregroundStyle(Theme.muted).padding(.bottom, 37)
            nav("layouts", "Dispositions", "rectangle.3.group")
            nav("shortcuts", "Raccourcis", "command")
            nav("settings", "Préférences", "slider.horizontal.3")
            Spacer()
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: "sparkle").foregroundStyle(Theme.mint)
                Text("Ton bureau.\nÀ ta façon.").font(.system(size: 19,weight: .medium)).lineSpacing(3)
                Text("Une palette, quelques touches.\nTout trouve sa place.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
                Button { store.showPalette?() } label: { HStack { Text("Palette rapide"); Spacer(); Image(systemName: "arrow.up.right") } }.buttonStyle(TileButtonStyle())
                HStack { KeyCap(text: "⌃"); KeyCap(text: "⌥"); KeyCap(text: "espace") }
            }.padding(15).background(LinearGradient(colors: [Theme.mint.opacity(0.08),.clear],startPoint: .topLeading,endPoint: .bottomTrailing),in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink.opacity(0.065)))
            HStack { Circle().fill(engine.trusted ? Theme.mint : Theme.warning).frame(width: 5,height: 5); Text(engine.trusted ? "Prêt à organiser" : "Autorisation nécessaire"); Spacer(); Text(AppVersion.current) }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.top, 21).padding(.bottom, 22)
        }.padding(.horizontal, 18).background(Theme.panel.opacity(0.45))
    }
    private func nav(_ id: String, _ title: String, _ icon: String) -> some View {
        Button { store.page = id } label: {
            HStack(spacing: 12) { Image(systemName: icon).frame(width: 20); Text(title); Spacer(); if store.page == id { Circle().fill(Theme.mint).frame(width: 5,height: 5) } }
                .font(.system(size: 12,weight: store.page == id ? .semibold : .regular)).padding(.horizontal, 12).padding(.vertical, 12)
                .foregroundStyle(store.page == id ? Theme.ink : Theme.muted).background(store.page == id ? Theme.ink.opacity(0.065) : .clear,in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(TilePlainButtonStyle()).padding(.bottom, 5)
    }
    private var topbar: some View {
        HStack {
            Text(store.page == "layouts" ? "ESPACE DE TRAVAIL" : store.page == "shortcuts" ? "À PORTÉE DE MAIN" : "LES DÉTAILS QUI COMPTENT").font(.system(size: 9,weight: .semibold)).tracking(1.8).foregroundStyle(Theme.muted)
            Spacer()
            Image(systemName: "display").foregroundStyle(Theme.mint)
            Picker("Écran", selection: $engine.screenIndex) { ForEach(Array(engine.screens.enumerated()), id: \.offset) { i, s in Text(s.localizedName).tag(i) } }.labelsHidden().pickerStyle(.menu).fixedSize().help("Écran sur lequel placer la fenêtre")
        }.padding(.horizontal,32).frame(height: 56).padding(.top, 20).overlay(alignment: .bottom) { Rectangle().fill(Theme.ink.opacity(0.06)).frame(height: 1) }
    }
    private var layoutPage: some View {
        Group {
            HStack(alignment: .center) {
                VStack(alignment: .leading,spacing: 9) {
                    Text("Chaque fenêtre à sa place.").font(.system(size: 31,weight: .semibold)).tracking(-1.1).lineSpacing(0)
                    Text("Choisis une disposition, puis une zone pour ta fenêtre.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { store.showEditor = true } label: { Label("Créer une disposition",systemImage: "plus") }.buttonStyle(TileButtonStyle())
            }
            if !engine.trusted { accessBanner }
            HStack(spacing: 12) {
                Image(systemName: "macwindow").foregroundStyle(Theme.mint).font(.system(size: 18))
                VStack(alignment: .leading,spacing: 3) { Text("FENÊTRE À PLACER").font(.system(size: 8,weight: .semibold)).tracking(1.4).foregroundStyle(Theme.muted)
                    if engine.windows.isEmpty { Text(engine.trusted ? "Ouvre une fenêtre pour commencer" : "Connecte EasyTile à tes fenêtres").font(.system(size: 12)) }
                    else { Picker("Fenêtre à placer",selection: $engine.selectedID) { ForEach(engine.windows) { w in Text("\(w.name) — \(w.title)").tag(Optional(w.id)) } }.labelsHidden().frame(maxWidth: 420) }
                }
                Spacer()
                Button { engine.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(TileButtonStyle()).help("Actualiser les fenêtres")
            }.padding(16).surface()
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("CHOISIS TON ESPACE").font(.system(size: 9,weight: .semibold)).tracking(1.5).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("Fais défiler pour découvrir les \(store.layouts.count) dispositions →").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 10) {
                        ForEach(store.layouts) { layout in
                            LayoutCard(layout: layout, selected: layout.id == store.selectedLayoutID) {
                                withAnimation(.easeInOut(duration: 0.18)) { store.selectedLayoutID = layout.id }
                            }.frame(width: 132)
                        }
                    }.padding(.bottom, 7)
                }
            }
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading,spacing: 4) { Text(store.layout.name).font(.system(size: 18,weight: .semibold)); Text(store.layout.subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                    Spacer()
                    Text("\(store.layout.zones.count) ZONE\(store.layout.zones.count > 1 ? "S" : "")").font(.system(size: 8,weight: .semibold)).tracking(1.3).foregroundStyle(Theme.mint).padding(8).background(Theme.mint.opacity(0.08),in: Capsule())
                    if store.layout.custom { Button { store.removeCurrent() } label: { Image(systemName: "trash") }.buttonStyle(TileButtonStyle()).help("Supprimer cette disposition personnalisée") }
                }.padding(.horizontal,23).padding(.top,21)
                MonitorView(layout: store.layout, gap: store.gap, aspect: aspect, enabled: engine.trusted && engine.selected != nil) { zone in engine.apply(zone, gap: store.gap) }.padding(.horizontal,34).padding(.top,23).padding(.bottom,15)
                HStack(spacing: 7) { Image(systemName: "cursorarrow.rays").foregroundStyle(Theme.mint); Text("Clique sur une zone pour y envoyer la fenêtre sélectionnée.").foregroundStyle(Theme.muted) }.font(.system(size: 10)).padding(.bottom,21)
            }.surface()
            HStack(spacing: 18) {
                Label("Espacement",systemImage: "arrow.left.and.right").font(.system(size: 12))
                Slider(value: $store.gap,in: 0...32,step: 2).tint(Theme.mint).frame(maxWidth: 210).accessibilityLabel("Espacement entre les fenêtres")
                Text("\(Int(store.gap)) pt").font(.system(size: 11,design: .monospaced)).foregroundStyle(Theme.mint).frame(width: 42)
                Spacer()
                Button { engine.undo() } label: { Label("Annuler",systemImage: "arrow.uturn.backward") }.buttonStyle(TileButtonStyle()).disabled(engine.undoCount == 0)
                if engine.screens.count > 1 { Button { engine.nextScreen() } label: { Label("Écran suivant",systemImage: "display.2") }.buttonStyle(TileButtonStyle()) }
            }.padding(17).surface()
        }
    }
    private var aspect: CGFloat { guard let s = engine.screen else { return 1.7 }; return s.visibleFrame.width / max(s.visibleFrame.height,1) }
    private var accessBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill").font(.system(size: 22)).foregroundStyle(Theme.mint)
            VStack(alignment: .leading,spacing: 5) { Text("Une autorisation, et tout se met en place.").font(.system(size: 13,weight: .semibold)); Text("Active EasyTile dans Réglages Système → Confidentialité et sécurité → Accessibilité.\nCette autorisation permet de déplacer et redimensionner tes fenêtres.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(3) }
            Spacer()
            Button("Autoriser EasyTile") { engine.requestAccess() }.buttonStyle(TileButtonStyle(primary: true))
        }.padding(18).background(Theme.mint.opacity(0.045),in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.mint.opacity(0.2)))
    }
    private var shortcutsPage: some View {
        VStack(alignment: .leading,spacing: 25) {
            heading("Moins de clics.\nPlus de fluidité.", "Garde les mains sur le clavier, les idées sur l’écran.")
            VStack(spacing: 0) {
                shortcut("La palette rapide", "Toutes les zones de la disposition active, au-dessus de ton bureau.","⌃ ⌥ espace","rectangle.3.group")
                Divider().overlay(Theme.ink.opacity(0.05))
                shortcut("Moitié gauche / droite", "Un raccourci direct pour tes deux placements les plus utiles.","⌃ ⌥ ← / →","rectangle.split.2x1")
                Divider().overlay(Theme.ink.opacity(0.05))
                shortcut("Agrandir / centrer", "Vers le haut pour agrandir, vers le bas pour centrer à 80 %.","⌃ ⌥ ↑ / ↓","arrow.up.left.and.arrow.down.right")
                Divider().overlay(Theme.ink.opacity(0.05))
                shortcut("Annuler le placement", "Retrouve la taille et la position précédentes.","⌃ ⌥ ⌫","arrow.uturn.backward")
            }.surface()
            VStack(alignment: .leading,spacing: 14) {
                Label("Dans la palette",systemImage: "keyboard").font(.system(size: 15,weight: .semibold))
                Text("Appuie sur 1 à 9 pour choisir une zone. Échap ferme la palette. La fenêtre qui était active reste la cible du placement.").font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(5)
                Button("Essayer la palette") { store.showPalette?() }.buttonStyle(TileButtonStyle(primary: true))
            }.padding(24).surface()
            Text("Si un raccourci est déjà utilisé par une autre application, EasyTile te le signale dans la barre d’état. Désactive les raccourcis concurrents pour l’utiliser.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
        }
    }
    private func shortcut(_ title: String,_ desc: String,_ key: String,_ icon: String) -> some View {
        HStack(spacing: 17) { Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.mint).frame(width: 34); VStack(alignment: .leading,spacing: 6) { Text(title).font(.system(size: 14,weight: .medium)); Text(desc).font(.system(size: 11)).foregroundStyle(Theme.muted) }; Spacer(); KeyCap(text: key) }.padding(23)
    }
    private func heading(_ title: String,_ subtitle: String) -> some View { VStack(alignment: .leading,spacing: 12) { Text(title).font(.system(size: 35,weight: .semibold)).tracking(-1); Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted) } }
    private var footer: some View {
        HStack(spacing: 8) { Image(systemName: engine.isError ? "exclamationmark.circle" : "circle.dotted").foregroundStyle(engine.isError ? Theme.warning : Theme.mint); Text(engine.message).lineLimit(2); Spacer(); Text("LOCAL · NATIF · MIT").font(.system(size: 8,weight: .medium)).tracking(1.4) }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal,25).frame(minHeight: 40).background(Theme.panel.opacity(0.7)).accessibilityElement(children: .combine)
    }
}

struct MonitorView: View {
    let layout: TileLayout
    var gap: Double = 12
    var aspect: CGFloat = 1.7
    var enabled = true
    var compact = false
    var action: (TileZone) -> Void
    @State private var hovered: UUID?
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: compact ? 9 : 13).fill(LinearGradient(colors: [Theme.mint.opacity(0.06),Theme.colors[1].opacity(0.06),Theme.bg],startPoint: .topLeading,endPoint: .bottomTrailing))
                    ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                        let inset: CGFloat = compact ? 4 : CGFloat(4 + gap * 0.17)
                        let color = Theme.colors[index % Theme.colors.count]
                        Button { action(zone) } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: compact ? 5 : 10).fill(color.opacity(hovered == zone.id ? 0.26 : 0.11))
                                RoundedRectangle(cornerRadius: compact ? 5 : 10).strokeBorder(color.opacity(hovered == zone.id ? 0.9 : 0.3),lineWidth: hovered == zone.id ? 1.5 : 1)
                                VStack(spacing: compact ? 4 : 9) {
                                    Text("\(index+1)").font(.system(size: compact ? 11 : 19,weight: .medium,design: .rounded)).foregroundStyle(color)
                                    if !compact { Text(zone.label).font(.system(size: 11,weight: .medium)).foregroundStyle(Theme.ink); if hovered == zone.id { Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(color) } }
                                }
                            }.contentShape(Rectangle())
                        }.buttonStyle(TilePlainButtonStyle()).disabled(!enabled).onHover { over in hovered = over ? zone.id : nil }
                            .frame(width: max(1,geo.size.width * zone.width-inset*2),height: max(1,geo.size.height * zone.height-inset*2)).offset(x: geo.size.width*zone.x+inset,y: geo.size.height*zone.y+inset)
                            .accessibilityLabel("Zone \(index+1), \(zone.label)").help("Placer la fenêtre : \(zone.label)")
                    }
                }
            }.aspectRatio(min(max(aspect,1.25),2.5),contentMode: .fit).frame(maxHeight: compact ? 180 : 230)
                .padding(compact ? 5 : 7).background(Theme.raised,in: RoundedRectangle(cornerRadius: compact ? 12 : 19)).overlay(RoundedRectangle(cornerRadius: compact ? 12 : 19).strokeBorder(Theme.ink.opacity(0.13)))
            if !compact { UnevenRoundedRectangle(bottomLeadingRadius: 6,bottomTrailingRadius: 6).fill(LinearGradient(colors: [Theme.ink.opacity(0.12),Theme.ink.opacity(0.025)],startPoint: .top,endPoint: .bottom)).frame(width: 65,height: 13); Capsule().fill(Theme.ink.opacity(0.1)).frame(width: 110,height: 4) }
        }
    }
}
struct LayoutCard: View {
    let layout: TileLayout
    let selected: Bool
    let action: () -> Void
    private func miniZone(_ z: TileZone, index: Int, size: CGSize) -> some View {
        let color = Theme.colors[index % 4]
        let fill = selected ? color.opacity(0.38) : Theme.ink.opacity(0.09)
        let stroke = selected ? color.opacity(0.6) : Theme.ink.opacity(0.1)
        return RoundedRectangle(cornerRadius: 3).fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(stroke))
            .frame(width: max(1,size.width*z.width-4),height: max(1,size.height*z.height-4))
            .offset(x: size.width*z.x+2,y: size.height*z.y+2)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading,spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(layout.zones.enumerated()),id: \.element.id) { index,z in
                            miniZone(z, index: index, size: geo.size)
                        }
                    }
                }.frame(height: 55)
                HStack { Text(layout.name).font(.system(size: 11,weight: .medium)).lineLimit(1); Spacer(); if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint).font(.system(size: 12)) } }
            }.padding(13).background(selected ? Theme.mint.opacity(0.055) : Theme.panel,in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.mint.opacity(0.6) : Theme.ink.opacity(0.07)))
        }.buttonStyle(TilePlainButtonStyle()).accessibilityLabel("Disposition \(layout.name)\(selected ? ", sélectionnée" : "")")
    }
}
