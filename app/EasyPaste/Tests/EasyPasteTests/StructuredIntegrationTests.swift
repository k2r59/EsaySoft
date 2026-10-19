import XCTest
import AppKit
import CryptoKit
import SwiftUI
@testable import EasyPaste

@MainActor final class StructuredIntegrationTests: XCTestCase {
    private var folder: URL!
    private var vault: ClipVault!
    private var history: History!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-formats-" + UUID().uuidString)
        vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        suite = "EasyPaste.test." + UUID().uuidString; defaults = UserDefaults(suiteName: suite)!
        history = History(vault: vault, monitor: false, defaults: defaults)
    }
    override func tearDown() async throws {
        history.stopMonitoring(); await history.flush(); history = nil
        defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder)
    }
    private func insert(_ text: String) async -> Clip {
        let clip = makeClip(text); history.add(clip); await history.flush(); return clip
    }
    private func ready(_ model: StructuredEditorModel) async throws {
        for _ in 0..<500 { if !model.busy { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Formatting did not finish"); throw CancellationError()
    }
    func testFormattingCopyAndOriginalNeverMutateHistory() async throws {
        let clip = await insert(#"{"id":90071992547409931234,"a":2}"#)
        let model = StructuredEditorModel(clip: clip); model.refresh(); try await ready(model)
        XCTAssertNil(model.issue); XCTAssertTrue(model.output.contains("\n"))
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        model.copy(history: history, to: pb)
        XCTAssertEqual(pb.string(forType: .string), model.output)
        XCTAssertEqual(try vault.load().first?.payload, clip.payload)
        model.selectPresentation(.original); model.copy(history: history, to: pb)
        XCTAssertEqual(pb.string(forType: .string), clip.text)
        model.selectPresentation(.compact); try await ready(model)
        XCTAssertEqual(model.output, clip.text); XCTAssertEqual(history.clips.count, 1)
    }
    func testVariantIsAdjacentAndReplacementKeepsMetadata() async throws {
        let original = await insert(#"{"a":1}"#)
        history.togglePin(original); history.addBoard("Code"); history.toggleBoard(original, history.boards[0]); await history.flush()
        let full = try await history.fullClip(original)
        let formatted = try StructuredText.process(full.text, format: .json).text
        let copy = try await history.saveStructuredText(formatted, original: full, replacing: false)
        XCTAssertNotEqual(copy.id, full.id); XCTAssertEqual(copy.parentID, full.id); XCTAssertFalse(copy.pinned)
        XCTAssertEqual(copy.boards, full.boards); XCTAssertEqual(history.clips.count, 2)
        let ordered = ClipQuery().apply(history.clips)
        XCTAssertEqual(ordered.prefix(2).map(\.id), [full.id, copy.id])
        let saved = try await history.saveStructuredText(formatted, original: full, replacing: true)
        XCTAssertEqual(saved.id, full.id); XCTAssertTrue(saved.pinned); XCTAssertEqual(saved.boards, full.boards)
        XCTAssertEqual(saved.title, full.title); XCTAssertEqual(saved.date, full.date)
        let savedFull = try await history.fullClip(saved)
        XCTAssertEqual(savedFull.text, formatted)
        XCTAssertEqual(saved.payload.representations.count, 0, "Returned metadata must not retain the payload")
        let replacement = try await history.fullClip(saved)
        XCTAssertEqual(replacement.payload.representations[0].map(\.type), [NSPasteboard.PasteboardType.string.rawValue])
    }
    func testStaleAndTrashedOriginalsCannotBeOverwritten() async throws {
        let original = await insert(#"{"a":1}"#)
        history.edit(original.id, title: "Modifié", text: "autre contenu", rtf: nil); await history.flush()
        do { _ = try await history.saveStructuredText("{}", original: original, replacing: true); XCTFail("Must reject stale snapshot") } catch { }
        let stillCurrent = try await history.fullClip(original)
        XCTAssertEqual(stillCurrent.text, "autre contenu")
        let latest = try await history.fullClip(original); history.trash(latest); await history.flush()
        do { _ = try await history.saveStructuredText("{}", original: latest, replacing: false); XCTFail("Must reject trash") } catch { }
    }
    func testReplacementQueuesConcurrentFavoriteEdit() async throws {
        let original = await insert(#"{"a":1}"#)
        let replacement = Task { try await history.saveStructuredText("{\n  \"a\": 2\n}", original: original, replacing: true) }
        await Task.yield(); history.togglePin(original)
        let saved = try await replacement.value; await history.flush()
        let full = try await history.fullClip(saved)
        XCTAssertTrue(full.pinned); XCTAssertTrue(full.text.contains("2"))
    }
    func testMalformedJSONCanBeEditedAndValidated() async throws {
        let clip = await insert(#"{"a":}"#), model = StructuredEditorModel(clip: clip)
        model.refresh(); try await ready(model); XCTAssertNotNil(model.issue); XCTAssertTrue(model.canEdit); XCTAssertFalse(model.canUseOutput)
        model.beginEditing(); model.changeText(#"{"a":"Élodie"}"#); try await ready(model)
        XCTAssertNil(model.issue); XCTAssertEqual(model.output, #"{"a":"Élodie"}"#); XCTAssertTrue(model.hasEdits)
        model.editing = false; model.refresh(); try await ready(model)
        await model.save(history: history, replacing: true)
        XCTAssertFalse(model.hasEdits); XCTAssertTrue(model.message?.contains("remplacé") == true)
        model.selectPresentation(.original)
        XCTAssertTrue(model.output.contains("Élodie"), "Original now refers to the saved replacement")
    }
    func testChangingFormatAndModeDiscardsStaleWork() async throws {
        let clip = await insert("[" + Array(repeating: "1", count: 100_000).joined(separator: ",") + "]")
        let model = StructuredEditorModel(clip: clip); model.refresh()
        model.selectFormat(.xml); model.selectPresentation(.original)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.output, clip.text); XCTAssertNil(model.issue); XCTAssertFalse(model.busy)
        model.selectFormat(.json); model.refresh(); model.cancel()
        try await Task.sleep(for: .milliseconds(50)); XCTAssertFalse(model.busy)
    }
    func testCSVEditingSearchAndFullCopy() async throws {
        let clip = await insert("id;nom\n00123;Cyril\n00456;Élodie"), model = StructuredEditorModel(clip: clip)
        model.refresh(); try await ready(model); XCTAssertEqual(model.visibleRows, [0,1,2])
        model.query = "Cyril"; model.search(); try await Task.sleep(for: .milliseconds(220)); XCTAssertEqual(model.visibleRows, [1])
        model.beginEditing(); model.changeCell(row: 1, column: 1, value: "Cyril;\"test\""); try await ready(model)
        let csv = try CSVDocument.parse(model.output, delimiter: 59)
        XCTAssertEqual(csv.rows[1], ["00123", "Cyril;\"test\""])
        XCTAssertEqual(csv.rows.count, 3, "Search is a view filter, never a lossy export")
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }; model.copy(history: history, to: pb)
        XCTAssertEqual(pb.string(forType: .string), model.output)
    }
    func testPreviewTruncationDoesNotTruncateClipboard() async throws {
        let original = "{\"text\":\"" + String(repeating: "é😀", count: 30_000) + "\"}"
        let model = StructuredEditorModel(clip: await insert(original)); model.refresh(); try await ready(model)
        XCTAssertTrue(model.truncated); XCTAssertFalse(model.canEdit); XCTAssertLessThanOrEqual(model.displayed.utf8.count, StructuredText.displayLimit)
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }; model.copy(history: history, to: pb)
        XCTAssertEqual(pb.string(forType: .string), model.output); XCTAssertGreaterThan(model.output.utf8.count, StructuredText.displayLimit)
    }
    func testLargeFormatJobLeavesMainActorResponsive() async throws {
        let input = "[" + Array(repeating: #"{"id":12345678901234567890,"v":[1,2,3]}"#, count: 25_000).joined(separator: ",") + "]"
        let model = StructuredEditorModel(clip: await insert(input))
        var last = Date(), maxGap = 0.0, beats = 0
        model.refresh()
        while model.busy {
            try await Task.sleep(for: .milliseconds(5)); let now = Date()
            maxGap = max(maxGap, now.timeIntervalSince(last)); last = now; beats += 1
        }
        print("STRUCTURED_UI_HEARTBEAT max=\(maxGap)s beats=\(beats)")
        XCTAssertNil(model.issue); XCTAssertLessThan(maxGap, 0.2); XCTAssertGreaterThan(beats, 0)
    }
    func testNativeEditorsFitAndCSVUsesVirtualRows() async throws {
        let fixtures: [(StructuredFormat, String)] = [(.json, #"{"client":"Élodie","id":9007199254740993,"actif":true}"#), (.sql, "select id, nom from clients where actif = 1 order by nom;"), (.csv, "id;nom;ville\n00123;Cyril;Paris\n00456;Élodie;Lyon"), (.xml, "<clients><client id='001'><nom>Cyril</nom></client></clients>")]
        for (format, text) in fixtures {
            let clip = await insert(text), model = StructuredEditorModel(clip: clip, format: format)
            model.refresh(); try await ready(model)
            let host = NSHostingView(rootView: StructuredEditorView(model: model, history: history, close: {}))
            let size = CGSize(width: 690, height: 570)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(200)); try await ready(model); host.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(host.fittingSize.width, 690); XCTAssertLessThanOrEqual(host.fittingSize.height, 570)
            if format == .csv {
                let table: NSTableView? = descendants(host).compactMap { $0 as? NSTableView }.first
                XCTAssertEqual(table?.numberOfRows, 3); XCTAssertEqual(table?.tableColumns.count, 3)
            } else {
                let view = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
                XCTAssertEqual(view.string, model.displayed); XCTAssertFalse(view.isEditable)
                model.beginEditing(); host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(30))
                XCTAssertTrue(view.isEditable); XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled)
                model.editing = false
            }
            host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(30))
            if let folder = ProcessInfo.processInfo.environment["EASYPASTE_LAYOUT_SNAPSHOTS"] {
                try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent("format-\(format.rawValue).png"))
            }
            model.cancel(); window.close()
        }
    }
    func testNativeTextDelegateErrorNavigationAndUndo() async throws {
        let model = StructuredEditorModel(clip: await insert(#"{"a":1}"#))
        model.refresh(); try await ready(model)
        let host = NSHostingView(rootView: StructuredEditorView(model: model, history: history, close: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { model.cancel(); window.close() }
        host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(100)); try await ready(model)
        let view = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        model.beginEditing(); try await Task.sleep(for: .milliseconds(30))
        let malformed = "{\n  \"a\": }"
        view.insertText(malformed, replacementRange: NSRange(location: 0, length: (view.string as NSString).length))
        try await ready(model)
        XCTAssertEqual(model.draft, malformed); XCTAssertEqual(model.issue?.line, 2)
        model.revealIssueRequest += 1; try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(view.selectedRange().location, 2)
        XCTAssertTrue(view.undoManager?.canUndo == true)
        view.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(20)); try await ready(model)
        XCTAssertNil(model.issue)
        view.undoManager?.redo(); try await Task.sleep(for: .milliseconds(20)); try await ready(model)
        XCTAssertNotNil(model.issue)
        model.findRequest += 1; try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(view.enclosingScrollView?.isFindBarVisible == true)
    }
    func testCSVNativeEditDelegateKeepsLeadingZeroes() async throws {
        let model = StructuredEditorModel(clip: await insert("id;nom\n00123;Cyril"))
        model.refresh(); try await ready(model); model.beginEditing()
        let coordinator = CSVTable.Coordinator(model), table = NSTableView()
        coordinator.rows = model.visibleRows
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("1"))
        coordinator.tableView(table, setObjectValue: "Élodie;Lyon", for: column, row: 1)
        try await ready(model)
        XCTAssertEqual(model.result?.csv?.rows[1], ["00123", "Élodie;Lyon"])
    }
    func testOversizedDocumentStillCopiesOriginal() async throws {
        let text = "[\"" + String(repeating: "a", count: StructuredText.outputLimit + 1) + "\"]"
        let model = StructuredEditorModel(clip: makeClip(text)); model.refresh(); try await ready(model)
        XCTAssertNotNil(model.issue)
        model.selectPresentation(.original)
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        model.copy(history: history, to: pb); XCTAssertEqual(pb.string(forType: .string)?.utf8.count, text.utf8.count)
    }
    func testMalformedFormatsStayEditableAndNeverSaveInvalidOutput() async throws {
        let cases: [(StructuredFormat, String, String)] = [(.json, #"{"id":}"#, #"{"id":1}"#), (.csv, "a;b\n1;\"oops", "a;b\n1;valide"), (.xml, "<r><a></r>", "<r><a/></r>"), (.sql, "select 'oops from t", "select 'valide' from t")]
        for (format, invalid, corrected) in cases {
            let clip = await insert(invalid), model = StructuredEditorModel(clip: clip, format: format)
            model.refresh(); try await ready(model)
            XCTAssertNotNil(model.issue); XCTAssertFalse(model.canUseOutput); XCTAssertTrue(model.canEdit)
            let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }; pb.setString("inchangé", forType: .string)
            model.copy(history: history, to: pb); XCTAssertEqual(pb.string(forType: .string), "inchangé")
            await model.save(history: history, replacing: true)
            let original = try await history.fullClip(clip); XCTAssertEqual(original.text, invalid)
            model.beginEditing(); model.changeText(corrected); try await ready(model)
            XCTAssertNil(model.issue); XCTAssertTrue(model.canUseOutput)
            model.copy(history: history, to: pb); XCTAssertEqual(pb.string(forType: .string), corrected)
            model.selectPresentation(.original); XCTAssertEqual(model.output, invalid)
            model.cancel()
        }
    }
    func testClosingRepeatedEditorsReleasesModelsAndJobs() async throws {
        for _ in 0..<12 {
            var model: StructuredEditorModel? = StructuredEditorModel(clip: makeClip("[" + Array(repeating: "1", count: 10_000).joined(separator: ",") + "]"))
            weak var released = model
            var host: NSHostingView<StructuredEditorView>? = NSHostingView(rootView: StructuredEditorView(model: model!, history: history, close: {}))
            host?.frame = NSRect(x: 0, y: 0, width: 690, height: 570); host?.layoutSubtreeIfNeeded()
            model?.refresh(); model?.cancel(); host = nil; model = nil
            for _ in 0..<50 { if released == nil { break }; try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNil(released, "Closed editors must release their buffers and jobs")
        }
    }
    func testMarkdownPreviewSourceEditingAndReplacement() async throws {
        let clip = await insert(MarkdownFixtures.document), model = StructuredEditorModel(clip: clip)
        XCTAssertEqual(model.format, .markdown); XCTAssertEqual(model.presentation, .rendered)
        model.refresh(); try await ready(model)
        XCTAssertNil(model.issue); XCTAssertTrue(model.canUseOutput)
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        model.copy(history: history, to: pb); XCTAssertEqual(pb.string(forType: .string), clip.text)
        model.beginEditing(); XCTAssertEqual(model.presentation, .source)
        let changed = "# Modifié\n\n**Syntaxe incomplète"
        model.changeText(changed); try await ready(model); XCTAssertNil(model.issue)
        model.finishEditing(); try await ready(model); XCTAssertEqual(model.presentation, .rendered)
        XCTAssertTrue(model.result!.markdown!.text.contains("**Syntaxe incomplète"))
        await model.save(history: history, replacing: false)
        XCTAssertEqual(history.clips.count, 2)
        let unmodified = try await history.fullClip(clip); XCTAssertEqual(unmodified.text, clip.text)
        await model.save(history: history, replacing: true)
        let replaced = try await history.fullClip(clip); XCTAssertEqual(replaced.text, changed)
        model.selectPresentation(.original); XCTAssertEqual(model.output, changed)
    }
    func testLargeMarkdownCopyAndCancellation() async throws {
        let source = "# Un long document\n\n" + String(repeating: "**Texte** é😀\n\n", count: 20_000)
        let model = StructuredEditorModel(clip: await insert(source)); model.refresh()
        var beats = 0, maxGap = 0.0, last = Date()
        while model.busy {
            try await Task.sleep(for: .milliseconds(5)); let now = Date(); maxGap = max(maxGap, now.timeIntervalSince(last)); last = now; beats += 1
        }
        XCTAssertNil(model.issue); XCTAssertTrue(model.result?.markdown?.truncated == true)
        XCTAssertFalse(model.canEdit)
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        model.copy(history: history, to: pb); XCTAssertEqual(pb.string(forType: .string), source)
        XCTAssertLessThan(maxGap, 0.2); XCTAssertGreaterThan(beats, 0)
        print("MARKDOWN_UI_HEARTBEAT \(maxGap)s, \(beats) beats")
        model.refresh(); model.selectPresentation(.original)
        try await Task.sleep(for: .milliseconds(100)); XCTAssertNil(model.result); XCTAssertEqual(model.output, source)
        model.selectFormat(.json); model.selectFormat(.markdown); try await ready(model)
        XCTAssertNil(model.issue); XCTAssertNotNil(model.result?.markdown); model.cancel()
    }
    func testNativeMarkdownPreviewSearchEditingAndLayout() async throws {
        let model = StructuredEditorModel(clip: await insert(MarkdownFixtures.document))
        model.refresh(); try await ready(model)
        let host = NSHostingView(rootView: StructuredEditorView(model: model, history: history, close: {}))
        let size = CGSize(width: 690, height: 700)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.frame = CGRect(origin: .zero, size: size)
        defer { model.cancel(); window.close() }
        host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(200)); try await ready(model); host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, 690); XCTAssertLessThanOrEqual(host.fittingSize.height, 700)
        let view = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        XCTAssertEqual(view.string, model.result?.markdown?.text); XCTAssertFalse(view.isEditable)
        XCTAssertTrue(view.isSelectable); XCTAssertTrue(view.usesFindBar)
        XCTAssertEqual(view.textContainer?.widthTracksTextView, true)
        let layout = try XCTUnwrap(view.layoutManager), container = try XCTUnwrap(view.textContainer)
        layout.ensureLayout(for: container)
        XCTAssertGreaterThan(view.bounds.width, 400)
        XCTAssertLessThan(layout.usedRect(for: container).width, 690)
        if let folder = ProcessInfo.processInfo.environment["EASYPASTE_LAYOUT_SNAPSHOTS"] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent("format-Markdown.png"))
        }
        model.findRequest += 1; try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded()
        XCTAssertTrue(view.enclosingScrollView?.isFindBarVisible == true)
        model.beginEditing(); try await Task.sleep(for: .milliseconds(80)); host.layoutSubtreeIfNeeded()
        let source = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        XCTAssertTrue(source.isEditable); XCTAssertEqual(source.string, MarkdownFixtures.document)
        source.insertText("# Nouveau\n\n**gras**", replacementRange: NSRange(location: 0, length: (source.string as NSString).length))
        try await ready(model); model.finishEditing(); try await ready(model)
        try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded()
        let preview = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        XCTAssertEqual(preview.string, "Nouveau\ngras"); XCTAssertFalse(preview.isEditable)
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
