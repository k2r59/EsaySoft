import AppKit
import SwiftUI
import Vision
import ImageIO
import AVFoundation

struct ClipQuery {
    var text = "", collection = "all", source = ""
    var kind: ClipKind?
    var todayOnly = false
    var stack: [UUID] = []
    func apply(_ clips: [Clip]) -> [Clip] {
        let board = UUID(uuidString: collection)
        let positions = Dictionary(uniqueKeysWithValues: stack.enumerated().map { ($1, $0) })
        let terms = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let filtered = clips.filter { c in
            !Task.isCancelled && (collection == "trash" ? c.trashedAt != nil : c.trashedAt == nil)
            && (collection != "pinned" || c.pinned)
            && (collection != "stack" || positions[c.id] != nil)
            && (board == nil || c.boards.contains(board!))
            && (kind == nil || c.kind == kind)
            && (source.isEmpty || c.source == source)
            && (!todayOnly || Calendar.current.isDateInToday(c.date))
            && terms.allSatisfy { term in [c.title, c.text, c.source, c.ocr].contains { $0.localizedStandardContains(term) } }
        }
        if collection == "stack" { return filtered.sorted { (positions[$0.id] ?? 0) < (positions[$1.id] ?? 0) } }
        let ids = Set(filtered.map(\.id))
        func family(_ c: Clip) -> UUID { c.parentID.flatMap { ids.contains($0) ? $0 : nil } ?? c.id }
        var dates: [UUID: Date] = [:]
        for c in filtered { dates[family(c)] = max(dates[family(c)] ?? .distantPast, c.date) }
        return filtered.sorted {
            let a = family($0), b = family($1)
            if a != b { let da = dates[a]!, db = dates[b]!; return da == db ? a.uuidString < b.uuidString : da > db }
            if $0.id == a { return true }; if $1.id == b { return false }
            return $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }
}

@MainActor final class History: ObservableObject {
    let updates = AppUpdates()
    let sounds: SoundFeedback
    var updateBusy: Bool {
        AppUpdates.isBusy(recording: recording, capture: captureBusy, annotation: annotating,
                          editor: editing != nil || newSnippet, preview: previewing != nil || shelfPreview != nil,
                          sampling: samplingColor, sharing: bitwarden.busy)
    }
    let bitwarden: BitwardenModel
    @Published var loading = true
    @Published private(set) var clips: [Clip] = [] { didSet { refresh() } }
    @Published var boards: [Pinboard] = []
    @Published private(set) var visible: [Clip] = []
    @Published var query = "" { didSet { refresh(debounce: true) } }
    @Published var filter: ClipKind? { didSet { refresh() } }
    @Published var collection = "all" { didSet { selectedIDs = []; refresh() } }
    @Published var selected: UUID?
    @Published var selectedIDs: Set<UUID> = []
    @Published var page = "library"
    @Published var surface = "library"
    @Published var sourceFilter = "" { didSet { refresh() } }
    @Published var todayOnly = false { didSet { refresh() } }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "monitoring"); changeCount = NSPasteboard.general.changeCount } }
    @Published var retention: Int { didSet { defaults.set(retention, forKey: "retention"); prune() } }
    @Published var exclusions: [String] { didSet { defaults.set(exclusions, forKey: "exclusions") } }
    @Published var mcpEnabled: Bool { didSet { defaults.set(mcpEnabled, forKey: "mcpEnabled") } }
    @Published var compact: Bool { didSet { defaults.set(compact, forKey: "compact"); resizeShelf?() } }
    @Published var confirmTrash: Bool { didSet { defaults.set(confirmTrash, forKey: "confirmTrash") } }
    @Published var stack: [UUID] = [] { didSet { refresh() } }
    @Published var stackRecording = false
    @Published var recentlyTrashed: [UUID] = []
    @Published var notice = "Historique vide."
    @Published var fault = false
    @Published var captureBusy = false
    @Published var samplingColor = false
    @Published var recording = false
    @Published var annotating = false
    @Published var toast: String?
    @Published private(set) var originalIDs: Set<UUID> = []
    var capture: ((CaptureAction) -> Void)?
    var annotate: ((Clip) -> Void)?
    var stopRecording: (() -> Void)?
    private var toastTask: Task<Void, Never>?
    @Published var editing: Clip?
    @Published var previewing: Clip? { didSet { previewChanged?(previewing); structuredPreviewRequested = false } }
    @Published var shelfPreview: Clip? { didSet { if (oldValue == nil) != (shelfPreview == nil) { resizeShelf?() } } }
    @Published var shelfScreenHeight: CGFloat = 900
    func openPreview(_ clip: Clip) {
        guard clip.hasPreview else { return }
        if surface == "shelf" {
            selected = clip.id; selectedIDs = [clip.id]; shelfPreview = clip
        } else { previewing = clip }
    }
    func followShelfSelection() {
        guard shelfPreview != nil else { return }
        guard let clip = selectedClip, clip.hasPreview else { shelfPreview = nil; return }
        if shelfPreview?.id != clip.id { shelfPreview = clip }
    }
    private(set) var structuredPreviewRequested = false
    func openFormatter(_ clip: Clip) { shelfPreview = nil; structuredPreviewRequested = true; previewing = clip }
    var previewChanged: ((Clip?) -> Void)?
    @Published var newSnippet = false
    @Published var showNewBoard = false
    @Published var sources: [String] = []
    @Published var total = 0
    @Published var totalBytes = 0
    var paste: (([Clip], Bool) -> Void)?
    var openShelf: (() -> Void)?
    var closeShelf: (() -> Void)?
    var resizeShelf: (() -> Void)?
    var showLibrary: (() -> Void)?
    private let defaults: UserDefaults
    private var vault: ClipVault?
    private let disk = DispatchQueue(label: "EasyPaste.storage", qos: .userInitiated)
    private let ocrQueue = DispatchQueue(label: "EasyPaste.ocr", qos: .utility)
    private var timer: Timer?
    private var changeCount: Int
    private var searchTask: Task<Void, Never>?
    @Published private(set) var ocrTasks: Set<UUID> = []
    private var importInFlight = false
    // Keep a new copy pending when the current search/collection hides it.
    private var pendingClipboardSelection: UUID?
    private var stopping = false
    private var writes = 0
    private var replacingImages = Set<UUID>()
    private var pendingImageMutations: [UUID: [(inout Clip) -> Void]] = [:]
    var selectedClip: Clip? { clips.first { $0.id == selected } }
    var selection: [Clip] {
        !selectedIDs.isEmpty ? visible.filter { selectedIDs.contains($0.id) } : selectedClip.map { [$0] } ?? []
    }
    init(vault: ClipVault? = nil, monitor: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sounds = monitor ? SoundFeedback(defaults: defaults) : SoundFeedback(defaults: defaults, playback: { _ in })
        self.bitwarden = BitwardenModel(defaults: defaults)
        enabled = defaults.bool(forKey: "monitoring")
        retention = defaults.object(forKey: "retention") == nil ? 30 : defaults.integer(forKey: "retention")
        exclusions = defaults.stringArray(forKey: "exclusions") ?? []
        mcpEnabled = defaults.bool(forKey: "mcpEnabled")
        compact = defaults.bool(forKey: "compact")
        confirmTrash = defaults.object(forKey: "confirmTrash") == nil || defaults.bool(forKey: "confirmTrash")
        changeCount = NSPasteboard.general.changeCount
        sounds.muted = { [weak self] in self?.recording ?? true }
        if let vault {
            self.vault = vault
            do { clips = try vault.load(metadataOnly: true) } catch { storageError(error) }
            loading = false; refresh()
        } else {
            Task {
                do {
                    let loaded = try await Task.detached(priority: .userInitiated) { () -> (ClipVault, [Clip], [Pinboard]) in
                        let v = try ClipVault()
                        v.cleanPlaybackCache(); return (v, try v.load(metadataOnly: true), try v.loadBoards())
                    }.value
                    self.vault = loaded.0; clips = loaded.1; boards = loaded.2
                    loading = false; prune(); refresh()
                } catch { storageError(error); loading = false }
            }
        }
        if monitor {
            timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            timer?.tolerance = 0.15
        }
    }
    func report(_ text: String) {
        notice = text; toast = text; toastTask?.cancel()
        toastTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.toast = nil
        }
    }
    private func storageError(_ error: Error) { fault = true; enabled = false; notice = "Historique indisponible : \(error.localizedDescription)" }
    func refresh(debounce: Bool = false) {
        searchTask?.cancel()
        let snapshot = clips
        let request = ClipQuery(text: query, collection: collection, source: sourceFilter, kind: filter, todayOnly: todayOnly, stack: stack)
        searchTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: debounce ? 140_000_000 : 10_000_000) } catch { return }
            let worker = Task.detached(priority: .userInitiated) { () -> ([Clip], [String], Int, Int) in
                let active = snapshot.filter { $0.trashedAt == nil }
                return (request.apply(snapshot), Array(Set(active.map(\.source))).sorted(), active.count, snapshot.reduce(0) { $0 + $1.byteCount })
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, let self else { return }
            originalIDs = Set(snapshot.filter { $0.trashedAt == nil }.compactMap(\.parentID))
            visible = result.0; sources = result.1; total = result.2; totalBytes = result.3
            if let pending = pendingClipboardSelection, result.0.contains(where: { $0.id == pending }) {
                selected = pending; selectedIDs = [pending]; pendingClipboardSelection = nil
            } else if selected == nil || !result.0.contains(where: { $0.id == self.selected }) { selected = result.0.first?.id }
            selectedIDs.formIntersection(Set(result.0.map(\.id)))
        }
    }
    func prepareShelf() {
        // Read a copy made immediately before the shortcut, without waiting for
        // the polling timer. Processing stays asynchronous.
        poll()
        surface = "shelf"
        if collection != "all" { collection = "all" }
        if !query.isEmpty { query = "" }
        if filter != nil { filter = nil }
        if !sourceFilter.isEmpty { sourceFilter = "" }
        if todayOnly { todayOnly = false }
        if let pending = pendingClipboardSelection { selected = pending; selectedIDs = [pending] }
        refresh()
    }
    func select(_ clip: Clip, modifiers: NSEvent.ModifierFlags = []) {
        pendingClipboardSelection = nil
        if modifiers.contains(.shift), let start = visible.firstIndex(where: { $0.id == self.selected }), let end = visible.firstIndex(where: { $0.id == clip.id }) {
            selectedIDs.formUnion(visible[min(start,end)...max(start,end)].map(\.id))
        } else if modifiers.contains(.command) {
            if selectedIDs.isEmpty, let selected { selectedIDs.insert(selected) }
            if selectedIDs.contains(clip.id) { selectedIDs.remove(clip.id) } else { selectedIDs.insert(clip.id) }
            selected = selectedIDs.contains(clip.id) ? clip.id : visible.first { selectedIDs.contains($0.id) }?.id
            return
        } else { selectedIDs = [clip.id] }
        selected = clip.id
    }
    func moveSelection(_ delta: Int) {
        guard !visible.isEmpty else { return }
        let i = visible.firstIndex { $0.id == selected } ?? 0
        select(visible[max(0,min(visible.count-1,i+delta))])
    }
    func poll() {
        guard enabled, !stopping, !fault, !loading, !importInFlight, writes < 8 else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }; changeCount = pb.changeCount
        let app = NSWorkspace.shared.frontmostApplication
        guard app?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        do {
            guard let raw = try ClipboardReader.read(pb, source: app?.localizedName ?? "Application", sourceID: app?.bundleIdentifier ?? "unknown", exclusions: Set(exclusions)) else { return }
            importInFlight = true
            let sourcePID = app?.processIdentifier
            let clipboardRevision = pb.changeCount
            Task {
                var clip = await Task.detached(priority: .utility) { () -> Clip in
                    var c = raw
                    if c.sourceURL == nil, let pid = sourcePID { c.sourceURL = BrowserPageReader.read(pid: pid, bundleID: c.sourceID)?.sourceURL }
                    c.fingerprint = Clip.fingerprint(c.payload); c.prepareThumbnail(); return c
                }.value
                // Keep explicit clipboard provenance, but discard a native
                // lookup if the user copied again or changed application.
                if raw.sourceURL == nil, pb.changeCount != clipboardRevision || NSWorkspace.shared.frontmostApplication?.processIdentifier != sourcePID { clip.sourceURL = nil }
                importInFlight = false
                guard enabled, !stopping, !fault else { return }; add(clip)
                sounds.play(.copy)
            }
        } catch { report(error.localizedDescription) }
    }
    private func persist(_ clip: Clip) {
        guard let vault else { return }
        writes += 1
        disk.async { [weak self] in
            do {
                var value = clip
                if value.payload.representations.isEmpty { value.payload = try vault.read(Clip.self, name: value.id.uuidString + ".clip").payload }
                value.prepareThumbnail(); try vault.save(value)
                let thumb = value.thumbnail
                Task { @MainActor in
                    self?.writes -= 1
                    if let i = self?.clips.firstIndex(where: { $0.id == clip.id }), self?.clips[i].thumbnail != thumb { self?.clips[i].thumbnail = thumb }
                }
            } catch { Task { @MainActor in self?.writes -= 1; self?.storageError(error) } }
        }
    }
    func add(_ clip: Clip) {
        guard vault != nil, !fault else { return }
        var value = clip
        if let i = clips.firstIndex(where: { $0.fingerprint == clip.fingerprint && $0.trashedAt == nil }) {
            value.id = clips[i].id; value.date = Date(); value.pinned = clips[i].pinned
            value.boards = clips[i].boards; value.title = clips[i].title; value.ocr = clips[i].ocr; value.parentID = clips[i].parentID
            clips[i] = value.metadata()
        } else { clips.insert(value.metadata(), at: 0) }
        pendingClipboardSelection = value.id
        selected = value.id; selectedIDs = [value.id]
        persist(value)
        if stackRecording, !stack.contains(value.id) { stack.append(value.id) }
        prune(); indexOCR(value)
    }
    func mutate(_ id: UUID, _ body: @escaping (inout Clip) -> Void) {
        guard let i = clips.firstIndex(where: { $0.id == id }), vault != nil, !fault else { return }
        // Apply metadata edits after the image transaction, so a queued favorite,
        // rename or trash action cannot write back an obsolete image fingerprint.
        if replacingImages.contains(id) { pendingImageMutations[id, default: []].append(body); return }
        var c = clips[i]; body(&c); clips[i] = c.metadata(); persist(c)
    }
    func fullClip(_ c: Clip) async throws -> Clip {
        guard let vault else { throw CocoaError(.fileReadUnknown) }
        return try await withCheckedThrowingContinuation { continuation in
            disk.async {
                do { continuation.resume(returning: try vault.read(Clip.self, name: c.id.uuidString + ".clip")) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func stopMonitoring() { stopping = true; timer?.invalidate(); timer = nil }
    func flush() async { await withCheckedContinuation { c in disk.async { c.resume() } } }
    func copy(_ clips: [Clip], plain: Bool = false, to pb: NSPasteboard = .general, sound: FeedbackSound? = .copy) async -> Bool {
        guard !clips.isEmpty else { return false }
        do {
            var full: [Clip] = []
            for c in clips {
                var value = try await fullClip(c)
                if SVGDocument.looksLikeSVG(value.text) || value.payload.representations.flatMap({ $0 }).contains(where: { [SVGDocument.pasteboardType, "image/svg+xml"].contains($0.type) }) {
                    let source = value.text
                    let document = try await Task.detached { try SVGDocument.parse(source) }.value
                    value.text = document.canonical
                    value.payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(document.canonical.utf8)), .init(type: SVGDocument.pasteboardType, data: Data(document.canonical.utf8))]])
                }
                if value.kind == .file {
                    for path in value.text.split(separator: "\n").map(String.init) where SVGFile.isSVG(path) {
                        _ = try await Task.detached { try SVGDocument.parse(SVGFile.read(URL(fileURLWithPath: path))) }.value
                    }
                }
                if value.kind == .video, !plain {
                    let url = try await videoURL(value)
                    value.payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data(url.absoluteString.utf8))]])
                }
                full.append(value)
            }
            let items: [NSPasteboardItem]
            if plain || (full.count > 1 && full.allSatisfy { [.text,.link,.color].contains($0.kind) }) {
                let text = full.map { $0.kind == .image ? $0.ocr : $0.text }.filter { !$0.isEmpty }.joined(separator: "\n")
                guard !text.isEmpty else { report("Ce contenu n’a pas de version texte."); return false }
                let item = NSPasteboardItem(); item.setString(text, forType: .string); items = [item]
            } else {
                items = full.flatMap { $0.payload.representations }.map { reps in
                    let item = NSPasteboardItem(); for r in reps { item.setData(r.data, forType: NSPasteboard.PasteboardType(r.type)) }; return item
                }
            }
            guard !items.isEmpty else { return false }
            pb.clearContents(); let ok = pb.writeObjects(items)
            if pb.name == NSPasteboard.general.name { changeCount = pb.changeCount }
            if ok, pb.name == NSPasteboard.general.name, let sound { sounds.play(sound) }
            report(ok ? "Copié · ⌘V pour coller" : "Impossible d’écrire dans le presse-papiers.")
            return ok
        } catch { report("Copie impossible : \(error.localizedDescription)"); return false }
    }
    func copyStructuredText(_ text: String, to pb: NSPasteboard = .general) -> Bool {
        guard text.utf8.count <= ClipboardReader.limit else { return false }
        pb.clearContents(); let ok = pb.setString(text, forType: .string)
        if pb.name == NSPasteboard.general.name { changeCount = pb.changeCount }
        if ok, pb.name == NSPasteboard.general.name { sounds.play(.copy) }
        return ok
    }
    func copyPNG(_ data: Data, to pb: NSPasteboard = .general) -> Bool {
        guard data.count <= ClipboardReader.limit else { return false }
        pb.clearContents(); let ok = pb.setData(data, forType: .png)
        if pb.name == NSPasteboard.general.name { changeCount = pb.changeCount }
        if ok, pb.name == NSPasteboard.general.name { sounds.play(.copy) }
        return ok
    }
    func togglePin(_ c: Clip) { mutate(c.id) { $0.pinned.toggle() } }
    func addBoard(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let board = Pinboard(name: String(n.prefix(40)), color: boards.count % 4)
        boards.append(board); saveBoards(); collection = board.id.uuidString
    }
    func renameBoard(_ id: UUID, name: String) {
        guard let i = boards.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        boards[i].name = String(name.prefix(40)); saveBoards()
    }
    func deleteBoard(_ board: Pinboard) {
        for c in clips where c.boards.contains(board.id) { mutate(c.id) { $0.boards.removeAll { $0 == board.id } } }
        boards.removeAll { $0.id == board.id }; collection = "all"; saveBoards()
    }
    func toggleSharing(_ id: UUID) { guard let i = boards.firstIndex(where: { $0.id == id }) else { return }; boards[i].shared.toggle(); saveBoards() }
    private func saveBoards() {
        guard let vault else { return }; let value = boards
        disk.async { [weak self] in
            do { try vault.write(value, name: "boards.json.enc") }
            catch { Task { @MainActor in self?.storageError(error) } }
        }
    }
    func toggleBoard(_ clip: Clip, _ board: Pinboard) {
        mutate(clip.id) { c in if c.boards.contains(board.id) { c.boards.removeAll { $0 == board.id } } else { c.boards.append(board.id) } }
    }
    func trash(_ clip: Clip) { trashItems([clip]) }
    func trashItems(_ items: [Clip]) {
        guard !fault else { return }
        let ids = Set(items.filter { $0.trashedAt == nil }.map(\.id))
        guard !ids.isEmpty else { return }
        for id in ids { mutate(id) { $0.trashedAt = Date() } }
        recentlyTrashed = Array(ids); stack.removeAll { ids.contains($0) }; selectedIDs.subtract(ids)
        if let selected, ids.contains(selected) { self.selected = nil }
        report(ids.count == 1 ? "Élément déplacé dans la corbeille." : "\(ids.count) éléments déplacés dans la corbeille.")
    }
    func undoTrash() {
        let ids = Set(recentlyTrashed)
        for clip in clips where ids.contains(clip.id) && clip.trashedAt != nil { restore(clip) }
        recentlyTrashed = []; report("Suppression annulée.")
    }
    func restore(_ clip: Clip) { mutate(clip.id) { $0.trashedAt = nil } }
    func clearHistory() { trashItems(clips.filter { !$0.pinned && $0.boards.isEmpty && $0.trashedAt == nil }) }
    func emptyTrash() { delete(clips.filter { $0.trashedAt != nil }.map(\.id)) }
    func permanentlyDelete(_ items: [Clip]) { delete(items.filter { $0.trashedAt != nil }.map(\.id)) }
    private func delete(_ ids: [UUID]) {
        guard let vault, !ids.isEmpty else { return }
        let ids = Set(ids)
        disk.async { [weak self] in
            do {
                for id in ids { try vault.delete(id) }
                Task { @MainActor in self?.clips.removeAll { ids.contains($0.id) }; self?.stack.removeAll { ids.contains($0) }; self?.recentlyTrashed.removeAll { ids.contains($0) } }
            } catch { Task { @MainActor in self?.storageError(error) } }
        }
    }
    func queue(_ c: Clip) { if !stack.contains(c.id) { stack.append(c.id); report("Ajouté à la pile · \(stack.count) élément(s).") } }
    func nextInStack() { guard let id = stack.first, let c = clips.first(where: { $0.id == id }) else { report("La pile est vide."); return }; paste?([c], false) }
    func consumeStack(_ pasted: [Clip]) { let ids = Set(pasted.map(\.id)); stack.removeAll { ids.contains($0) } }
    func edit(_ id: UUID, title: String, text: String, rtf: Data?) {
        mutate(id) { c in
            c.title = String(title.prefix(150)); c.text = text
            var reps = [ClipRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]
            if let rtf { reps.append(.init(type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtf)) }
            c.payload = ClipPayload(representations: [reps]); c.storedBytes = nil
            c.fingerprint = Clip.fingerprint(c.payload); c.kind = Clip.kind(for: text)
        }
    }
    func makeSnippet(_ title: String, text: String, rtf: Data? = nil) {
        var reps = [ClipRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]
        if let rtf { reps.append(.init(type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtf)) }
        let payload = ClipPayload(representations: [reps])
        add(Clip(title: title, text: text, source: "EasyPaste", sourceID: "app.easypaste.mac", kind: Clip.kind(for: text), fingerprint: Clip.fingerprint(payload), payload: payload, pinned: true))
    }
    private func prune() {
        guard vault != nil, !fault else { return }
        let cutoff = retention > 0 ? Date().addingTimeInterval(-Double(retention)*86400) : .distantPast
        delete(clips.filter { c in (c.date < cutoff && !c.pinned && c.boards.isEmpty) || (c.trashedAt.map { Date().timeIntervalSince($0) > 7*86400 } ?? false) }.map(\.id))
        if clips.reduce(0, { $0 + $1.byteCount }) > 1_000_000_000 { enabled = false; report("Historique supérieur à 1 Go. Libère de l’espace puis reprends la collecte.") }
    }
    private func indexOCR(_ clip: Clip) {
        guard clip.kind == .image, clip.ocr.isEmpty, !ocrTasks.contains(clip.id), let data = clip.imageData else { return }
        ocrTasks.insert(clip.id)
        ocrQueue.async { [weak self] in
            let result: Result<String, Error> = autoreleasepool { Result { try ImageText.recognize(data) } }
            Task { @MainActor in
                self?.ocrTasks.remove(clip.id)
                guard self?.replacingImages.contains(clip.id) != true else { return }
                guard case .success(let text) = result else { self?.report("Le texte de cette image n’a pas pu être reconnu. L’image est conservée."); return }
                guard !text.isEmpty, self?.clips.first(where: { $0.id == clip.id })?.fingerprint == clip.fingerprint else { return }
                self?.mutate(clip.id) { $0.ocr = text }
            }
        }
    }
}


extension History {
    /// The same per-card transaction lock as image replacement queues concurrent
    /// metadata edits. Publish after the encrypted write, never before it succeeds.
    func saveStructuredText(_ text: String, original: Clip, replacing: Bool) async throws -> Clip {
        guard text.utf8.count <= StructuredText.outputLimit else { throw TextIssue(message: "Le résultat dépasse 8 Mo.") }
        guard let vault, !fault, !stopping, !replacingImages.contains(original.id),
              let current = clips.first(where: { $0.id == original.id }), current.kind == .text,
              current.trashedAt == nil, current.fingerprint == original.fingerprint else {
            throw TextIssue(message: "L’original a changé ou a été supprimé. Rouvre-le avant d’enregistrer.")
        }
        replacingImages.insert(original.id); writes += 1
        defer {
            writes -= 1; replacingImages.remove(original.id)
            for update in pendingImageMutations.removeValue(forKey: original.id) ?? [] { mutate(original.id, update) }
        }
        let saved: Clip = try await withCheckedThrowingContinuation { continuation in
            disk.async {
                do {
                    var clip = try vault.read(Clip.self, name: original.id.uuidString + ".clip")
                    guard clip.trashedAt == nil, clip.fingerprint == original.fingerprint else { throw TextIssue(message: "L’original a changé. Rouvre-le avant d’enregistrer.") }
                    let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]])
                    if !replacing { clip.id = UUID(); clip.parentID = original.parentID ?? original.id; clip.date = Date(); clip.title = String(original.title.prefix(130)) + " · formaté"; clip.source = "EasyPaste"; clip.sourceID = "app.easypaste.mac"; clip.pinned = false }
                    clip.text = text; clip.payload = payload; clip.fingerprint = Clip.fingerprint(payload)
                    clip.storedBytes = nil; clip.ocr = ""; clip.thumbnail = nil; clip.kind = .text
                    try vault.save(clip); continuation.resume(returning: clip)
                } catch { continuation.resume(throwing: error) }
            }
        }
        if replacing, let index = clips.firstIndex(where: { $0.id == saved.id }) { clips[index] = saved.metadata() }
        else { clips.insert(saved.metadata(), at: 0) }
        selected = saved.id; selectedIDs = [saved.id]; prune()
        return saved.metadata()
    }
    /// Publish only after the encrypted file is durable. Captures intentionally bypass fingerprint deduplication.
    func insertCapture(_ input: Clip, movie: URL? = nil) async throws -> Clip {
        guard let vault, !fault, !stopping else { throw CocoaError(.fileWriteUnknown) }
        writes += 1
        defer { writes -= 1 }
        let value: Clip = try await withCheckedThrowingContinuation { continuation in
            disk.async {
                do {
                    var clip = input
                    if let movie { clip.storedBytes = try vault.importVideo(movie, id: clip.id) }
                    clip.prepareThumbnail()
                    do { try vault.save(clip) }
                    catch { if movie != nil { try? FileManager.default.removeItem(at: vault.mediaURL(clip.id)) }; throw error }
                    continuation.resume(returning: clip)
                } catch { continuation.resume(throwing: error) }
            }
        }
        clips.insert(value.metadata(), at: 0)
        if stackRecording { stack.append(value.id) }
        collection = "all"; query = ""; filter = nil; sourceFilter = ""; todayOnly = false
        selected = value.id; selectedIDs = [value.id]
        indexOCR(value); prune()
        return value.metadata()
    }
    func saveImage(_ data: Data, parent: Clip? = nil, sourceURL: String? = nil) async throws -> Clip {
        guard data.count <= ClipboardReader.limit else { throw CaptureFailure.message("Cette image dépasse 20 Mo. Sélectionne une zone plus petite.") }
        let clip = await Task.detached(priority: .userInitiated) {
            let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.png.rawValue, data: data)]])
            var clip = Clip(title: parent.map { $0.title + " · modifiée" } ?? "Capture d’écran", text: "", source: "EasyPaste", sourceID: "app.easypaste.mac", kind: .image, fingerprint: Clip.fingerprint(payload), payload: payload)
            clip.parentID = parent.map { $0.parentID ?? $0.id }; clip.boards = parent?.boards ?? []
            clip.sourceURL = BrowserOrigin.url(sourceURL ?? parent?.sourceURL)?.absoluteString
            clip.prepareThumbnail(); return clip
        }.value
        return try await insertCapture(clip)
    }
    func saveOCR(_ text: String, sourceURL: String? = nil) async throws -> Clip {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureFailure.message("Aucun texte détecté. Essaie une zone plus nette ou plus grande.") }
        let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]])
        var clip = Clip(title: String(text.prefix(90)), text: text, source: "Capture de texte", sourceID: "app.easypaste.mac", kind: .text, fingerprint: Clip.fingerprint(payload), payload: payload)
        clip.sourceURL = BrowserOrigin.url(sourceURL)?.absoluteString
        return try await insertCapture(clip)
    }
    /// Replace the encrypted image atomically while retaining the card identity,
    /// title, ordering, favorites and collections. Never retain the old OCR text.
    func replaceImage(_ data: Data, original: Clip) async throws -> Clip {
        guard data.count <= ClipboardReader.limit else { throw CaptureFailure.message("Cette image dépasse 20 Mo.") }
        guard let vault, !fault, !stopping, !replacingImages.contains(original.id),
              let current = clips.first(where: { $0.id == original.id }), current.kind == .image,
              current.trashedAt == nil, current.fingerprint == original.fingerprint else {
            throw CaptureFailure.message("L’image a changé ou n’est plus disponible. Rouvre-la avant de la remplacer.")
        }
        replacingImages.insert(original.id)
        defer {
            replacingImages.remove(original.id)
            for update in pendingImageMutations.removeValue(forKey: original.id) ?? [] { mutate(original.id, update) }
        }
        let prepared = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw CaptureFailure.message("L’image modifiée n’est pas lisible.") }
            _ = try ImageRaster.dimensions(source)
            let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.png.rawValue, data: data)]])
            return (payload, Clip.fingerprint(payload), (try? ImageText.recognize(data)) ?? "")
        }.value
        writes += 1; defer { writes -= 1 }
        let saved: Clip = try await withCheckedThrowingContinuation { continuation in
            disk.async {
                do {
                    var clip = try vault.read(Clip.self, name: original.id.uuidString + ".clip")
                    guard clip.kind == .image, clip.trashedAt == nil, clip.fingerprint == original.fingerprint else { throw CaptureFailure.message("L’image a changé. Rouvre-la avant de la remplacer.") }
                    clip.payload = prepared.0; clip.fingerprint = prepared.1; clip.ocr = prepared.2
                    clip.text = ""; clip.storedBytes = nil; clip.thumbnail = nil; clip.prepareThumbnail()
                    try vault.save(clip)
                    continuation.resume(returning: clip)
                } catch { continuation.resume(throwing: error) }
            }
        }
        guard let index = clips.firstIndex(where: { $0.id == saved.id }) else { throw CaptureFailure.message("Cette image a été supprimée pendant l’enregistrement.") }
        clips[index] = saved.metadata()
        selected = saved.id; selectedIDs = [saved.id]
        return saved.metadata()
    }
    func saveVideo(_ url: URL) async throws -> Clip {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw CaptureFailure.message("L’enregistrement ne contient pas de vidéo lisible.") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 480, height: 360)
        let result = try await generator.image(at: .zero)
        let thumbnail = try await Task.detached { try CaptureImage.png(result.image) }.value
        var clip = Clip(title: "Enregistrement d’écran", text: "", source: "EasyPaste", sourceID: "app.easypaste.mac", kind: .video, fingerprint: UUID().uuidString, payload: ClipPayload(representations: []))
        clip.duration = duration; clip.thumbnail = thumbnail
        return try await insertCapture(clip, movie: url)
    }
    func videoURL(_ clip: Clip) async throws -> URL {
        guard let vault, clip.kind == .video else { throw CocoaError(.fileReadUnknown) }
        return try await withCheckedThrowingContinuation { continuation in
            disk.async { do { continuation.resume(returning: try vault.videoURL(clip.id)) } catch { continuation.resume(throwing: error) } }
        }
    }
    func exportVideo(_ clip: Clip) {
        let panel = NSSavePanel(); panel.title = "Enregistrer la vidéo"; panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "EasyPaste-" + clip.id.uuidString.prefix(8) + ".mp4"
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            Task { @MainActor in
                do {
                    let source = try await self.videoURL(clip)
                    try await Task.detached(priority: .userInitiated) {
                        let staging = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
                        defer { try? FileManager.default.removeItem(at: staging) }
                        try FileManager.default.copyItem(at: source, to: staging)
                        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging) }
                        else { try FileManager.default.moveItem(at: staging, to: destination) }
                    }.value
                    self.report("Vidéo enregistrée dans « \(destination.lastPathComponent) ».")
                } catch { self.report("Export impossible : \(error.localizedDescription)") }
            }
        }
    }
}
