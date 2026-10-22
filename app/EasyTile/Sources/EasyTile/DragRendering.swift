import AppKit
import SwiftUI
import QuartzCore

private func withoutAnimation(_ body: () -> Void) {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

@MainActor
final class NativeDragPaletteView: NSView {
    override var isFlipped: Bool { true }
    private(set) var choice: DragChoice?
    private(set) var zoneLayers: [DragChoice: CAShapeLayer] = [:]
    private var cards: [CALayer] = []
    private var names: [NSTextField] = []
    private let heading = NSTextField(labelWithString:"Où veux-tu placer cette fenêtre ?")
    private let escape = NSTextField(labelWithString:"ÉCHAP POUR ANNULER")
    private let icon = NSImageView()
    private var geometry = DragPaletteGeometry(columns:8,count:8)

    init() {
        super.init(frame:.zero)
        wantsLayer = true; layer?.isGeometryFlipped = true
        layer?.cornerRadius = 18; layer?.borderWidth = 1
        heading.font = .systemFont(ofSize:12,weight:.semibold)
        escape.font = .systemFont(ofSize:8,weight:.medium); escape.alignment = .right
        icon.image = NSImage(systemSymbolName:"rectangle.3.group.fill",accessibilityDescription:nil)
        for view in [heading,escape,icon] { addSubview(view) }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { geometry.size }

    func configure(layouts:[TileLayout],geometry:DragPaletteGeometry) {
        self.geometry = geometry; choice = nil
        withoutAnimation {
            zoneLayers.values.forEach { $0.removeFromSuperlayer() }; zoneLayers.removeAll(keepingCapacity:true)
            cards.forEach { $0.removeFromSuperlayer() }; cards.removeAll(keepingCapacity:true)
            names.forEach { $0.removeFromSuperview() }; names.removeAll(keepingCapacity:true)
            for (index,layout) in layouts.prefix(geometry.count).enumerated() {
                let rect = geometry.card(index)
                let card = CALayer(); card.frame = rect; card.cornerRadius = 10
                layer?.addSublayer(card); cards.append(card)
                for (zoneIndex,zone) in layout.zones.enumerated() {
                    let r = geometry.zoneFrame(layoutIndex:index,zone:zone)
                    let shape = CAShapeLayer(); shape.frame = r
                    shape.path = CGPath(roundedRect:CGRect(origin:.zero,size:r.size).insetBy(dx:1,dy:1),cornerWidth:3,cornerHeight:3,transform:nil)
                    layer?.addSublayer(shape)
                    zoneLayers[DragChoice(layoutIndex:index,zoneIndex:zoneIndex)] = shape
                }
                let label = NSTextField(labelWithString:layout.name)
                label.font = .systemFont(ofSize:9,weight:.medium); label.alignment = .center
                label.lineBreakMode = .byTruncatingTail
                label.frame = CGRect(x:rect.minX+4,y:rect.minY+62,width:82,height:14)
                addSubview(label); names.append(label)
            }
            heading.stringValue = "Où veux-tu placer cette fenêtre ?"
            refreshColors()
        }
        invalidateIntrinsicContentSize(); needsLayout = true
    }

    override func layout() {
        super.layout()
        icon.frame = CGRect(x:19,y:16,width:16,height:16)
        heading.frame = CGRect(x:44,y:16,width:max(0,bounds.width-215),height:18)
        escape.frame = CGRect(x:max(44,bounds.width-160),y:19,width:141,height:12)
    }

    func select(_ newChoice:DragChoice?) {
        let valid = newChoice.flatMap { zoneLayers[$0] == nil ? nil : $0 }
        guard valid != choice else { return }
        let previous = choice; choice = valid
        withoutAnimation {
            if let previous { style(previous,active:false) }
            if let valid { style(valid,active:true) }
            if previous?.layoutIndex != valid?.layoutIndex {
                if let index = previous?.layoutIndex { names[index].textColor = NSColor(Theme.muted) }
                if let index = valid?.layoutIndex { names[index].textColor = NSColor(Theme.mint) }
            }
            if (previous == nil) != (valid == nil) {
                heading.stringValue = valid == nil ? "Où veux-tu placer cette fenêtre ?" : "Relâche pour placer la fenêtre"
            }
        }
    }

    private func color(_ color:Color,alpha:CGFloat = 1) -> CGColor {
        var result = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = NSColor(color).withAlphaComponent(alpha).cgColor }
        return result
    }
    private func style(_ key:DragChoice,active:Bool) {
        let shape = zoneLayers[key], tint = Theme.colors[key.zoneIndex % Theme.colors.count]
        shape?.fillColor = color(tint,alpha:active ? 0.85 : 0.16)
        shape?.strokeColor = color(tint,alpha:active ? 1 : 0.3)
        shape?.lineWidth = active ? 2 : 1
    }
    private func refreshColors() {
        layer?.backgroundColor = color(Theme.panel,alpha:0.98); layer?.borderColor = color(Theme.ink,alpha:0.17)
        cards.forEach { $0.backgroundColor = color(Theme.bg,alpha:0.8) }
        for key in zoneLayers.keys { style(key,active:key == choice) }
        for (index,label) in names.enumerated() { label.textColor = NSColor(choice?.layoutIndex == index ? Theme.mint : Theme.muted) }
        heading.textColor = NSColor(Theme.ink); escape.textColor = NSColor(Theme.muted); icon.contentTintColor = NSColor(Theme.mint)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        withoutAnimation { refreshColors() }
    }
}

@MainActor
final class DragPreviewView: NSView {
    let shape = CAShapeLayer()
    private(set) var target: CGRect?
    init() {
        super.init(frame:.zero)
        wantsLayer = true; layer?.addSublayer(shape); shape.lineWidth = 3; shape.isHidden = true
        refreshColors()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        withoutAnimation { shape.frame = bounds }
    }
    func show(_ rect:CGRect?) {
        guard rect != target else { return }
        target = rect
        withoutAnimation {
            shape.isHidden = rect == nil
            shape.path = rect.map { CGPath(roundedRect:$0.insetBy(dx:3.5,dy:3.5),cornerWidth:14,cornerHeight:14,transform:nil) }
        }
    }
    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            shape.fillColor = NSColor(Theme.mint).withAlphaComponent(0.13).cgColor
            shape.strokeColor = NSColor(Theme.mint).withAlphaComponent(0.85).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        withoutAnimation { refreshColors() }
    }
}

/// One backing surface per destination screen, not a resized window per tile.
@MainActor
final class DragPreviewController {
    private(set) var panel: NSPanel?
    let view = DragPreviewView()
    func show(target:CGRect,screen:CGRect,orderFront:Bool = true) {
        if panel == nil {
            let p = NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isOpaque = false; p.backgroundColor = .clear; p.level = .floating
            p.ignoresMouseEvents = true; p.hasShadow = false; p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; p.contentView = view
            panel = p
        }
        if panel?.frame != screen { panel?.setFrame(screen,display:false,animate:false) }
        view.show(target.offsetBy(dx:-screen.minX,dy:-screen.minY))
        if orderFront, panel?.isVisible != true { panel?.orderFrontRegardless() }
    }
    func hideTarget() { view.show(nil) }
    func close() { hideTarget(); panel?.orderOut(nil) }
}
