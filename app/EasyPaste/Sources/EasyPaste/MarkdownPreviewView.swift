import AppKit
import SwiftUI

/// A native, selectable TextKit preview. No WebView, HTML execution or remote media.
struct MarkdownPreviewView: NSViewRepresentable {
    let document: MarkdownDocument
    let revision: Int
    let findRequest: Int
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(), view = NSTextView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        view.isEditable = false; view.isSelectable = true; view.isRichText = true
        view.importsGraphics = false; view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.backgroundColor = NSColor(Theme.panel); view.textColor = NSColor(Theme.ink)
        view.textContainerInset = NSSize(width: 24, height: 22)
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        view.layoutManager?.allowsNonContiguousLayout = true
        view.linkTextAttributes = [.foregroundColor: NSColor(Theme.mint), .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.delegate = context.coordinator; view.setAccessibilityLabel("Aperçu Markdown")
        scroll.documentView = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let c = context.coordinator
        if c.revision != revision {
            view.textStorage?.setAttributedString(document.attributed())
            c.revision = revision
        }
        if c.findRequest != findRequest {
            c.findRequest = findRequest
            let item = NSMenuItem(); item.tag = NSTextFinder.Action.showFindInterface.rawValue
            view.performTextFinderAction(item); view.window?.makeFirstResponder(view)
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var revision = -1, findRequest = 0
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL, MarkdownDocument.allowedLink(url) { NSWorkspace.shared.open(url) }
            return true
        }
    }
}

extension MarkdownDocument {
    @MainActor func attributed() -> NSAttributedString {
        let output = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor(Theme.ink)])
        var tables: [Int: NSTextTable] = [:]
        for block in blocks where block.range.length > 0 {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4; style.paragraphSpacing = 12
            var size: CGFloat = 14
            if block.heading > 0 {
                size = [28, 23, 19, 17, 15, 14][min(block.heading, 6) - 1]
                style.paragraphSpacingBefore = block.range.location == 0 ? 0 : 12; style.paragraphSpacing = 10
            }
            let font = block.code ? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular) : NSFont.systemFont(ofSize: size, weight: block.heading > 0 ? .semibold : .regular)
            if block.listDepth > 0 {
                style.firstLineHeadIndent = CGFloat(min(block.listDepth - 1, 12)) * 20
                style.headIndent = style.firstLineHeadIndent + 24
                style.tabStops = [NSTextTab(textAlignment: .left, location: style.headIndent)]
                style.paragraphSpacing = 5
            }
            if block.quoteDepth > 0 {
                style.headIndent += CGFloat(min(block.quoteDepth, 12)) * 18
                style.firstLineHeadIndent += CGFloat(min(block.quoteDepth, 12)) * 18
                output.addAttribute(.foregroundColor, value: NSColor(Theme.muted), range: block.range)
            }
            if block.code {
                style.headIndent += 12; style.firstLineHeadIndent += 12
                style.paragraphSpacing = 0
                output.addAttribute(.backgroundColor, value: NSColor(Theme.raised), range: block.range)
            }
            if block.rule { output.addAttribute(.foregroundColor, value: NSColor(Theme.muted), range: block.range) }
            if let cell = block.cell {
                let table: NSTextTable
                if let existing = tables[cell.tableID] { table = existing }
                else {
                    table = NSTextTable(); table.numberOfColumns = cell.columns; table.layoutAlgorithm = .fixedLayoutAlgorithm
                    table.collapsesBorders = true; table.setValue(100, type: .percentageValueType, for: .width)
                    tables[cell.tableID] = table
                }
                let box = NSTextTableBlock(table: table, startingRow: cell.row, rowSpan: 1, startingColumn: cell.column, columnSpan: 1)
                box.setValue(100 / CGFloat(cell.columns), type: .percentageValueType, for: .width)
                box.setWidth(8, type: .absoluteValueType, for: .padding)
                box.setWidth(0.5, type: .absoluteValueType, for: .border)
                box.setBorderColor(NSColor(Theme.border))
                box.backgroundColor = NSColor(cell.header ? Theme.raised : Theme.panel)
                style.textBlocks = [box]; style.paragraphSpacing = 0; style.lineSpacing = 3
                switch cell.alignment { case .center: style.alignment = .center; case .right: style.alignment = .right; default: break }
            }
            output.addAttributes([.font: font, .paragraphStyle: style], range: block.range)
            if block.cell?.header == true { output.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: block.range) }
        }
        for span in spans where span.range.length > 0 {
            var font = output.attribute(.font, at: span.range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 14)
            if span.code { font = .monospacedSystemFont(ofSize: min(font.pointSize, 13), weight: .regular); output.addAttribute(.backgroundColor, value: NSColor(Theme.raised), range: span.range) }
            if span.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if span.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            output.addAttribute(.font, value: font, range: span.range)
            if span.strike { output.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.range) }
            if span.image { output.addAttribute(.foregroundColor, value: NSColor(Theme.muted), range: span.range) }
            if let link = span.link { output.addAttribute(.link, value: link, range: span.range) }
        }
        return output
    }
}
