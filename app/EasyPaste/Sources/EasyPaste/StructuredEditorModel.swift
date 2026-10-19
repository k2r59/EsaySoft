import AppKit
import SwiftUI

@MainActor final class StructuredEditorModel: ObservableObject {
    private(set) var original: Clip
    @Published var format: StructuredFormat
    @Published var presentation: TextPresentation = .formatted
    @Published var options = StructuredOptions()
    @Published private(set) var output = ""
    @Published private(set) var result: StructuredResult?
    @Published private(set) var issue: TextIssue?
    @Published private(set) var busy = false
    @Published var saving = false
    @Published var editing = false
    private(set) var editingTable = false
    @Published var hasEdits = false
    @Published var query = ""
    @Published private(set) var visibleRows: [Int] = []
    @Published var message: String?
    @Published var findRequest = 0
    @Published var revealIssueRequest = 0
    @Published private(set) var revision = 0
    private(set) var draft: String
    private var task: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var generation = UUID()
    private var returnToMarkdownPreview = false
    var presentations: [TextPresentation] {
        switch format {
        case .json: return [.original, .formatted, .compact]
        case .sql: return [.original, .formatted]
        case .csv: return [.original, .table]
        case .xml: return [.original, .formatted, .outline]
        case .markdown: return [.original, .source, .rendered]
        }
    }
    var displayed: String { StructuredText.prefix(output, bytes: StructuredText.displayLimit) }
    var truncated: Bool { output.utf8.count > StructuredText.displayLimit }
    var canUseOutput: Bool { !busy && !saving && (issue == nil || presentation == .original) }
    var canEdit: Bool { !busy && !saving && presentation != .original && presentation != .outline && (!truncated || result?.csv != nil) }
    init(clip: Clip, format: StructuredFormat? = nil) {
        original = clip; draft = clip.text; output = clip.text
        self.format = format ?? StructuredText.hint(clip.text) ?? .json
        if self.format == .csv { presentation = .table }
        if self.format == .markdown { presentation = .rendered }
    }
    func cancel() { task?.cancel(); searchTask?.cancel(); generation = UUID(); busy = false }
    func selectFormat(_ value: StructuredFormat) {
        format = value; editing = false; returnToMarkdownPreview = false; query = ""
        presentation = value == .csv ? .table : value == .markdown ? .rendered : .formatted; refresh()
    }
    func selectPresentation(_ value: TextPresentation) { editing = false; presentation = value; refresh() }
    func refresh(validateOnly: Bool = false, debounce: Bool = false) {
        task?.cancel(); let ticket = UUID(); generation = ticket; issue = nil; message = nil
        if presentation == .original, !validateOnly { output = original.text; result = nil; busy = false; revision += 1; return }
        let input = draft, format = format, mode = presentation, settings = options
        busy = true
        task = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(250)) }
                let worker = Task.detached(priority: .userInitiated) { try StructuredText.process(input, format: format, presentation: mode, options: settings) }
                let value = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, let self, generation == ticket else { return }
                result = value
                if !validateOnly { output = value.text; revision += 1 }
                busy = false; search()
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, let self, generation == ticket else { return }
                issue = (error as? TextIssue) ?? TextIssue(message: error.localizedDescription)
                if !validateOnly { output = input; revision += 1 }
                result = nil; busy = false
            }
        }
    }
    func beginEditing() {
        guard canEdit else { return }; editing = true
        returnToMarkdownPreview = format == .markdown && presentation == .rendered
        if returnToMarkdownPreview { presentation = .source }
        editingTable = presentation == .table && result?.csv != nil
        if !editingTable { draft = output }
    }
    func finishEditing() {
        editing = false
        if returnToMarkdownPreview { presentation = .rendered }
        returnToMarkdownPreview = false; refresh()
    }
    func changeText(_ value: String) {
        guard editing else { return }
        draft = value; output = value; hasEdits = true; revision += 1
        refresh(validateOnly: true, debounce: true)
    }
    func changeCell(row: Int, column: Int, value: String) {
        guard editing, var csv = result?.csv, csv.rows.indices.contains(row), csv.rows[row].indices.contains(column) else { return }
        csv.rows[row][column] = value; task?.cancel(); busy = true; hasEdits = true
        let ticket = UUID(); generation = ticket
        task = Task { [weak self] in
            do {
                let worker = Task.detached(priority: .userInitiated) { try csv.serialized() }
                let text = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, let self, generation == ticket else { return }
                draft = text; output = text; result = StructuredResult(text: text, csv: csv); issue = nil; busy = false; revision += 1; search()
            } catch {
                guard !Task.isCancelled, let self, generation == ticket else { return }
                issue = TextIssue(message: error.localizedDescription); busy = false
            }
        }
    }
    func search() {
        searchTask?.cancel()
        guard let rows = result?.csv?.rows else { visibleRows = []; return }
        let query = query
        if query.isEmpty { visibleRows = Array(rows.indices); return }
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            let worker = Task.detached(priority: .userInitiated) {
                rows.indices.filter { index in !Task.isCancelled && rows[index].contains { $0.localizedStandardContains(query) } }
            }
            let matches = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }; self?.visibleRows = matches
        }
    }
    func save(history: History, replacing: Bool) async {
        guard canUseOutput else { return }; saving = true; message = nil
        defer { saving = false }
        do {
            let saved = try await history.saveStructuredText(output, original: original, replacing: replacing)
            if replacing { original = saved; draft = output }
            hasEdits = false; message = replacing ? "Original remplacé." : "Copie ajoutée à l’historique."
        } catch { message = error.localizedDescription }
    }
    func copy(history: History, to pasteboard: NSPasteboard = .general) {
        guard canUseOutput else { return }
        message = history.copyStructuredText(output, to: pasteboard) ? "Copié · ⌘V pour coller" : "Copie impossible."
    }
    func export() {
        guard canUseOutput else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Copie." + format.fileExtension
        let text = output
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do { try await Task.detached { try text.write(to: url, atomically: true, encoding: .utf8) }.value; self?.message = "Fichier enregistré." }
                catch { self?.message = error.localizedDescription }
            }
        }
    }
}

actor StructuredPreviewCache {
    static let shared = StructuredPreviewCache()
    private var values: [String: String] = [:]
    private var order: [String] = []
    func preview(text: String, key: String, format: StructuredFormat) throws -> String {
        try Task.checkCancellation()
        if let value = values[key] { return value }
        let value: String
        if text.utf8.count <= StructuredText.previewLimit,
           let result = try? StructuredText.process(text, format: format) {
            value = StructuredText.prefix(result.markdown?.text ?? result.text, bytes: 1200)
        } else { value = StructuredText.prefix(text, bytes: 1200) }
        try Task.checkCancellation()
        if values.count >= 128, let first = order.first { values.removeValue(forKey: first); order.removeFirst() }
        values[key] = value; order.append(key)
        return value
    }
}

struct StructuredCardPreview: View {
    let clip: Clip
    let format: StructuredFormat
    var compact: Bool
    @State private var preview = ""
    @State private var colored = AttributedString("")
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(format.rawValue, systemImage: format.icon)
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.mint)
            Text(preview.isEmpty ? AttributedString(StructuredText.prefix(clip.text, bytes: 700)) : colored)
                .font(.system(size: compact ? 10 : 12, design: format == .markdown ? .default : .monospaced)).foregroundStyle(Theme.ink)
                .lineSpacing(3).lineLimit(compact ? 2 : 6).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .task(id: clip.fingerprint) {
            let value = (try? await StructuredPreviewCache.shared.preview(text: clip.text, key: clip.fingerprint, format: format)) ?? ""
            guard !Task.isCancelled else { return }
            var attributed = AttributedString(value)
            for span in format == .markdown ? [] : SyntaxColoring.spans(value, format: format) {
                if let stringRange = Range(span.range, in: value), let range = Range(stringRange, in: attributed) { attributed[range].foregroundColor = Theme.colors[span.color] }
            }
            preview = value; colored = attributed
        }
    }
}
