import AppKit
import SwiftUI

struct StructuredEditorView: View {
    @ObservedObject var model: StructuredEditorModel
    @ObservedObject var history: History
    let close: () -> Void
    @FocusState private var searching: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: model.format.icon).font(.system(size: 23)).foregroundStyle(Theme.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.format == .svg ? "SVG" : model.format == .markdown ? "Markdown" : "Formater").font(.system(size: 21, weight: .semibold))
                    Text(model.original.source).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Picker("Format", selection: Binding(get: { model.format }, set: model.selectFormat)) {
                    ForEach(StructuredFormat.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 125).disabled(model.editing || model.saving)
                Button("Fermer", action: close).buttonStyle(PasteButtonStyle()).disabled(model.saving).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 12) {
                ForEach(model.presentations) { value in
                    Button { model.selectPresentation(value) } label: {
                        Text(value.rawValue).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 13).frame(height: 34)
                            .foregroundStyle(model.presentation == value ? Theme.bg : Theme.ink)
                            .background(model.presentation == value ? Theme.mint : Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(FullAreaButtonStyle()).disabled(model.editing || model.saving)
                        .accessibilityAddTraits(model.presentation == value ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Button { if model.presentation == .table { searching = true } else { model.findRequest += 1 } } label: { Image(systemName: "magnifyingglass").frame(width: 30, height: 34) }
                    .buttonStyle(FullAreaButtonStyle()).accessibilityLabel("Rechercher").help("Rechercher · ⌘F").keyboardShortcut("f")
                    .disabled(model.presentation == .outline || (model.presentation == .rendered && model.format == .svg))
                Button(model.editing ? "Terminer" : "Modifier") {
                    if model.editing { model.finishEditing() } else { model.beginEditing() }
                }.buttonStyle(PasteButtonStyle()).disabled(model.editing ? model.busy : !model.canEdit)
            }
            if model.format == .csv {
                HStack {
                    Picker("Séparateur", selection: $model.options.delimiter) {
                        Text("Automatique").tag(UInt8?.none)
                        Text("Virgule ,").tag(UInt8?.some(44)); Text("Point-virgule ;").tag(UInt8?.some(59))
                        Text("Tabulation").tag(UInt8?.some(9)); Text("Barre |").tag(UInt8?.some(124))
                    }.frame(width: 240).disabled(model.editing || model.saving)
                    if model.presentation == .table {
                        TextField("Rechercher dans les cellules", text: $model.query).textFieldStyle(.roundedBorder).focused($searching)
                    }
                }
            } else if model.format == .sql {
                Picker("Dialecte", selection: $model.options.dialect) { ForEach(SQLDialect.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 250).disabled(model.editing || model.saving)
            }
            ZStack {
                content
                if model.busy && !model.editing {
                    VStack(spacing: 12) {
                        ProgressView(model.format == .markdown ? "Préparation de l’aperçu…" : "Formatage…")
                        Button("Annuler") { model.selectPresentation(.original) }.buttonStyle(PasteButtonStyle())
                    }.padding(20).background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            HStack(alignment: .top) {
                if let issue = model.issue {
                    Button { model.revealIssueRequest += 1 } label: { Label(issue.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning) }
                        .buttonStyle(FullAreaButtonStyle()).help("Afficher la ligne concernée").disabled(issue.line == nil)
                }
                else if model.busy { Text("Vérification…") }
                else if let message = model.message { Text(message).foregroundStyle(Theme.mint) }
                else if let csv = model.result?.csv { Text("\(model.visibleRows.count) lignes · \(csv.columnCount) colonnes").help("Les cellules de plus de 16 Ko sont abrégées et consultables dans Original. La copie et l’export conservent leur contenu complet.") }
                else { Text(model.result?.note ?? "Traitement local") }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(model.output.utf8.count), countStyle: .file)).monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(Theme.muted).frame(minHeight: 30, alignment: .top)
            if model.presentation == .rendered && model.result?.markdown?.truncated == true {
                Text("Aperçu abrégé. Copie et export : Markdown complet.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else if model.truncated && model.presentation != .table && model.presentation != .outline && model.presentation != .rendered {
                Text("Aperçu et recherche limités à 128 Ko. Copie et export : texte complet.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            HStack {
                if model.hasEdits { Text("Modifications non enregistrées").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                Spacer()
                Button("Exporter…") { model.export() }
                    .buttonStyle(PasteButtonStyle()).disabled(!model.canUseOutput)
                Button(model.saving ? "Enregistrement…" : "Enregistrer") { Task { await model.save(history: history) } }
                    .buttonStyle(PasteButtonStyle()).disabled(!model.canUseOutput)
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Enregistrer une nouvelle entrée en conservant l’original")
                Button("Copier le \(model.format.rawValue)") { model.copy(history: history) }
                    .buttonStyle(PasteButtonStyle(primary: model.format != .svg)).disabled(!model.canUseOutput)
            }
        }.padding(22).frame(minWidth: 690, minHeight: 540)
            .chromeSurface(radius: 22).foregroundStyle(Theme.ink)
            .task { model.refresh() }.onDisappear { model.cancel() }
            .onChange(of: model.options) { _, _ in model.refresh() }
            .onChange(of: model.query) { _, _ in model.search() }
    }
    @ViewBuilder private var content: some View {
        if model.presentation == .rendered, let document = model.result?.svg {
            SVGPreviewView(document: document, history: history)
        } else if model.presentation == .rendered, let document = model.result?.markdown {
            MarkdownPreviewView(document: document, revision: model.revision, findRequest: model.findRequest)
        } else if model.presentation == .table, model.result?.csv != nil, !model.editing || model.editingTable {
            CSVTable(model: model)
        } else if model.presentation == .outline, let result = model.result {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    OutlineGroup(result.xml, children: \.outlineChildren) { branch in
                        Text(branch.label).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.mint).textSelection(.enabled).padding(.vertical, 3)
                    }
                    Text("Structure limitée à 2 000 balises. Le texte complet reste disponible dans Original.").font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 12)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else { StructuredCodeView(model: model) }
    }

}
extension XMLBranch { var outlineChildren: [XMLBranch]? { children.isEmpty ? nil : children } }

struct StructuredCodeView: NSViewRepresentable {
    @ObservedObject var model: StructuredEditorModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(), view = NSTextView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        view.isRichText = false; view.allowsUndo = true; view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false; view.isGrammarCheckingEnabled = false
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular); view.textColor = NSColor(Theme.ink)
        view.backgroundColor = NSColor(Theme.panel); view.insertionPointColor = NSColor(Theme.mint)
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = true
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("Contenu \(model.format.rawValue)"); view.delegate = context.coordinator
        context.coordinator.observeUndo(in: view)
        scroll.documentView = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let c = context.coordinator; c.model = model
        // Avoid decoding/slicing a large buffer again for unrelated UI updates.
        if c.revision != model.revision || c.lastFormat != model.format {
            let text = model.displayed
            if view.string != text { view.string = text; view.undoManager?.removeAllActions() }
            c.revision = model.revision; c.lastFormat = model.format; c.highlight(view)
        }
        view.isEditable = model.editing && !model.truncated
        if c.findRequest != model.findRequest {
            c.findRequest = model.findRequest
            let item = NSMenuItem(); item.tag = NSTextFinder.Action.showFindInterface.rawValue
            view.performTextFinderAction(item); view.window?.makeFirstResponder(view)
        }
        if c.revealIssueRequest != model.revealIssueRequest {
            c.revealIssueRequest = model.revealIssueRequest
            if let line = model.issue?.line {
                let text = view.string as NSString; var range = NSRange(location: 0, length: 0)
                for _ in 1..<max(1, line) {
                    range = text.lineRange(for: range); range = NSRange(location: NSMaxRange(range), length: 0)
                    if range.location >= text.length { break }
                }
                if range.location < text.length { range = text.lineRange(for: range); view.setSelectedRange(range); view.scrollRangeToVisible(range); view.window?.makeFirstResponder(view) }
            }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var model: StructuredEditorModel
        var revision = -1, findRequest = 0, revealIssueRequest = 0
        var lastFormat: StructuredFormat?
        private var highlightTask: Task<Void, Never>?
        private var undoObservers: [NSObjectProtocol] = []
        init(_ model: StructuredEditorModel) { self.model = model }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            model.changeText(view.string)
        }
        func observeUndo(in view: NSTextView) {
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                undoObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self, weak view] notification in
                    MainActor.assumeIsolated {
                        guard let self, let view, let manager = notification.object as? UndoManager,
                              manager === view.undoManager, self.model.editing, self.model.draft != view.string else { return }
                        self.model.changeText(view.string)
                    }
                })
            }
        }
        func highlight(_ view: NSTextView) {
            highlightTask?.cancel()
            let text = view.string, format = model.format
            highlightTask = Task { @MainActor [weak view] in
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                let worker = Task.detached(priority: .utility) { SyntaxColoring.spans(text, format: format) }
                let spans = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, let view, view.string == text, let storage = view.textStorage else { return }
                let undo = view.undoManager
                undo?.disableUndoRegistration()
                defer { undo?.enableUndoRegistration() }
                storage.beginEditing()
                storage.addAttribute(.foregroundColor, value: NSColor(Theme.ink), range: NSRange(location: 0, length: storage.length))
                for span in spans where NSMaxRange(span.range) <= storage.length {
                    storage.addAttribute(.foregroundColor, value: NSColor(Theme.colors[span.color]), range: span.range)
                }
                storage.endEditing()
            }
        }
        deinit { highlightTask?.cancel(); for observer in undoObservers { NotificationCenter.default.removeObserver(observer) } }
    }
}

enum SyntaxColoring {
    struct Span: Sendable { var range: NSRange; var color: Int }
    static func spans(_ text: String, format: StructuredFormat) -> [Span] {
        let text = StructuredText.prefix(text, bytes: 64 * 1024), range = NSRange(text.startIndex..., in: text)
        let patterns: [(String, Int)]
        switch format {
        case .json: patterns = [(#"\b(?:true|false|null|-?[0-9]+(?:\.[0-9]+)?)\b"#, 2), (#""(?:[^"\\]|\\.)*""#, 0)]
        case .sql: patterns = [(#"(?i)\b(?:select|from|where|join|left|right|inner|outer|on|group|order|by|having|limit|offset|insert|into|values|update|set|delete|create|table|as|and|or|null|with|returning)\b"#, 1), (#"'(?:[^']|'')*'"#, 0)]
        case .xml, .svg: patterns = [(#"</?[A-Za-z_:][\w:.-]*|/?>"#, 1), (#""[^"]*"|'[^']*'"#, 0)]
        case .csv: patterns = [(#""(?:[^"]|"")*""#, 0)]
        case .markdown: patterns = [(#"(?m)^ {0,3}#{1,6} .*$|^ {0,3}(?:>|[-+*] |[0-9]+[.)] ).*$"#, 1), (#"`[^`\n]+`|\*\*[^*\n]+\*\*|!??\[[^\]\n]+\]\([^\)\n]+\)"#, 0)]
        }
        var result: [Span] = []
        for (pattern, color) in patterns {
            guard !Task.isCancelled, let regex = try? NSRegularExpression(pattern: pattern) else { break }
            regex.enumerateMatches(in: text, range: range) { match, _, stop in
                if Task.isCancelled || result.count >= 2000 { stop.pointee = true; return }
                if let match { result.append(Span(range: match.range, color: color)) }
            }
        }
        return result
    }
}

struct CSVTable: NSViewRepresentable {
    @ObservedObject var model: StructuredEditorModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(), table = NSTableView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.documentView = table
        table.dataSource = context.coordinator; table.delegate = context.coordinator
        table.rowHeight = 30; table.usesAlternatingRowBackgroundColors = false; table.backgroundColor = NSColor(Theme.panel)
        table.gridStyleMask = [.solidHorizontalGridLineMask]; table.gridColor = NSColor(Theme.border)
        table.columnAutoresizingStyle = .noColumnAutoresizing; table.setAccessibilityLabel("Tableau CSV")
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView, let csv = model.result?.csv else { return }
        let c = context.coordinator; c.model = model
        if table.tableColumns.count != csv.columnCount {
            for column in table.tableColumns { table.removeTableColumn(column) }
            for index in 0..<csv.columnCount {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
                column.title = "Colonne \(index + 1)"; column.width = 170; column.minWidth = 65
                if let cell = column.dataCell as? NSTextFieldCell {
                    cell.font = .monospacedSystemFont(ofSize: 12, weight: .regular); cell.textColor = NSColor(Theme.ink)
                    cell.lineBreakMode = .byTruncatingTail; cell.isScrollable = true
                }
                table.addTableColumn(column)
            }
        }
        for column in table.tableColumns { column.isEditable = model.editing && !model.busy }
        if c.revision != model.revision || c.rows != model.visibleRows { c.revision = model.revision; c.rows = model.visibleRows; table.reloadData() }
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: StructuredEditorModel
        var revision = -1
        var rows: [Int] = []
        init(_ model: StructuredEditorModel) { self.model = model }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            guard let column = tableColumn.flatMap({ Int($0.identifier.rawValue) }), rows.indices.contains(row), let csv = model.result?.csv,
                  csv.rows.indices.contains(rows[row]), csv.rows[rows[row]].indices.contains(column) else { return nil }
            return StructuredText.prefix(csv.rows[rows[row]][column], bytes: 16 * 1024)
        }
        func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
            guard let column = tableColumn.flatMap({ Int($0.identifier.rawValue) }), rows.indices.contains(row), let value = object as? String else { return }
            model.changeCell(row: rows[row], column: column, value: value)
        }
        func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
            guard model.editing, !model.busy, let column = tableColumn.flatMap({ Int($0.identifier.rawValue) }), rows.indices.contains(row), let csv = model.result?.csv else { return false }
            return csv.rows[rows[row]][column].utf8.count <= 16 * 1024
        }
    }
}
