import SwiftUI
import AVFoundation
import AppKit

@MainActor final class MusicStore: ObservableObject {
    @Published var query = ""
    @Published var searchMode: SearchMode = .all
    @Published var catalogItems: [CatalogItem] = []
    @Published var collectionTitle: String?
    @Published var openedCollection: CatalogItem?
    @Published var results: [Track] = []
    @Published var discoveries: [Track] = []
    @Published var homeChartsSource = "Classement Deezer"
    @Published var homeMixes: [CatalogItem] = []
    @Published var personalMixes: [CatalogItem] = []
    private var interestsRevision = 0
    private var loadedInterestsRevision = -1
    private var listeningSeconds = 0.0
    private var listeningRecorded = false
    private var lastListeningTick = Date()
    @Published var homeGenres: [CatalogItem] = []
    @Published var homeLoading = false
    @Published var checkingPlaylists = Set<UUID>()
    @Published var syncErrors: [UUID: String] = [:]
    @Published var importingPlaylist = false
    @Published var downloadErrors: [String: String] = [:]
    @Published var searching = false
    @Published var searched = false
    let notifications = MusicNotifications()
    @Published private var latestNotice: String?
    var notice: String? {
        get { latestNotice }
        set {
            latestNotice = newValue
            if let newValue { notifications.post(newValue) }
        }
    }
    func showError(_ message: String) {
        latestNotice = message
        notifications.post(message, warning: true)
    }
    @Published var selected: Track?
    @Published var formats: [AudioFormat] = []
    @Published var selectedFormat = "best"
    @Published var inspecting = false
    @Published var library = Library()
    @Published var section = "home"
    @Published var sourceFilter = "Tout"
    @Published var activeDownloads: [ActiveDownload] = []
    var activeTitle: String? { activeDownloads.first?.track.title }
    var activeID: String? { activeDownloads.first?.id }
    @Published var requestedPlayback: Track?
    private var orderedPlaybackQueue: [Track] = []
    @Published var previewLoadingID: String?
    @Published var pending: [Track] = []
    @Published var playing: LocalTrack?
    @Published var streaming: Track?
    @Published var isBuffering = false
    var currentTrack: Track? { streaming ?? playing?.track ?? previewing }
    var hasFullPlayback: Bool { requestedPlayback != nil || streaming != nil || playing != nil }
    private var playbackTask: Task<Void, Never>?
    private var streamPrefetchTask: Task<AudioStream?, Never>?
    private var streamPrefetchTarget: Track?
    private var streamPrefetchIsIntent = false
    private var bufferTimeout: Task<Void, Never>?
    private var itemObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var attemptedStreams = Set<String>()
    private var streamRecoveryCount = 0
    private var streamSource: Track?
    private let observesPlayback: Bool
    @Published var previewing: Track?
    @Published var isPlaying = false
    @Published var shuffle = false
    @Published var repeatMode = 0
    @Published var playbackQueue: [Track] = []
    private var unmutedVolume: Float = 0.8
    @Published var position: Double = 0
    @Published var playerDuration: Double = 0
    @Published var exporting = false
    @Published var exportFormat = "original"
    private var playbackID = UUID()
    @Published var folder: URL
    @Published var volume: Float = 0.8 { didSet { player.volume = volume } }
    let player = AVPlayer()
    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private struct CollectionPage {
        let section: String
        let query: String
        let mode: SearchMode
        let results: [Track]
        let items: [CatalogItem]
        let collection: CatalogItem?
        let title: String?
    }
    private var collectionHistory: [CollectionPage] = []
    private var searchID = UUID()
    private var inspectID = UUID()
    var checkedBitrates = Set<UUID>()
    let storage: URL
    var downloadWorker: ((Track, String, String, URL) async throws -> (Track, String))?
    var streamResolver: ((Track, Set<String>) async throws -> AudioStream)?
    var streamPrefetchResolver: ((Track) async throws -> AudioStream)?
    private var queueFormats: [String: String] = [:]
    private var queueExports: [String: String] = [:]
    var canConvert: Bool { Engine.executable("ffmpeg") != nil }
    var visibleResults: [Track] { sourceFilter == "Tout" ? results : results.filter { $0.source == sourceFilter } }
    var currentPlaylist: Playlist? { library.playlists.first { $0.id.uuidString == section } }
    var visibleLocal: [LocalTrack] {
        if let list = currentPlaylist {
            var seen = Set<UUID>()
            let imported = ((list.importedTracks ?? []) + (list.addedTracks ?? [])).compactMap { downloaded($0) }
            let local = list.trackIDs.compactMap { id in library.tracks.first { $0.id == id } }
            return (imported + local).filter { seen.insert($0.id).inserted }
        }
        return library.tracks
    }
    init(storageURL: URL? = nil, downloadFolder: URL? = nil, observePlayback: Bool = true) {
        observesPlayback = observePlayback
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyMusic", isDirectory: true)
        storage = storageURL ?? appSupport.appendingPathComponent("library.json")
        folder = downloadFolder ?? UserDefaults.standard.string(forKey: "downloadFolder").map { URL(fileURLWithPath: $0) }
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Music/EasyMusic", isDirectory: true)
        do {
            try fm.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: storage.path) { library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: storage)) }
        } catch { showError("La bibliothèque n’a pas pu être chargée : \(error.localizedDescription)") }
        player.volume = volume
        guard observePlayback else { return }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                self.playbackEnded()
            }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateBuffering() }
        }
    }
    func loadDiscoveries(force: Bool = false) async {
        guard !homeLoading, force || discoveries.isEmpty || loadedInterestsRevision != interestsRevision else { return }
        let revision = interestsRevision
        let terms = Recommendations.queries(library.interests ?? [])
        homeLoading = true
        async let hits = Catalog.homeCharts()
        async let mixes = Catalog.homeMixes()
        async let personal = Catalog.homeMixes(queries: terms, limit: 2)
        async let genres = try? Catalog.search("", mode: .genres)
        let chart = await hits
        discoveries = chart.tracks; homeChartsSource = chart.source
        homeGenres = await genres ?? []
        homeMixes = await mixes
        let personalized = await personal
        if revision == interestsRevision {
            personalMixes = personalized
            loadedInterestsRevision = revision
        }
        homeLoading = false
        if revision != interestsRevision { await loadDiscoveries() }
    }
    var homeShortcuts: [CatalogItem] {
        var seen = Set<String>()
        return Array((Array(personalMixes.prefix(4)) + homeMixes).filter { seen.insert($0.id).inserted }.prefix(8))
    }
    func rememberInterest(_ term: String, weight: Double) {
        library.interests = Recommendations.record(term, weight: weight, in: library.interests ?? [])
        interestsRevision += 1; save()
    }
    func accountForListening(seconds: Double) {
        guard !listeningRecorded, seconds.isFinite, seconds > 0, let track = currentTrack else { return }
        listeningSeconds += seconds
        guard listeningSeconds >= 10 else { return }
        listeningRecorded = true
        rememberInterest(track.artist.isEmpty ? track.title : track.artist, weight: 3)
    }
    func resetRecommendations() {
        library.interests = nil; personalMixes = []; interestsRevision += 1; save()
        Task { await loadDiscoveries() }
    }
    func showHomeTrack(_ track: Track) {
        searchID = UUID(); searching = false; catalogItems = []; collectionTitle = nil; openedCollection = nil
        sourceFilter = "Tout"; searchMode = .tracks; results = discoveries; searched = true; section = "search"; select(track)
    }
    func save() {
        do { try JSONEncoder().encode(library).write(to: storage, options: .atomic) }
        catch { showError("Impossible d’enregistrer la bibliothèque : \(error.localizedDescription)") }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { folder = url; UserDefaults.standard.set(url.path, forKey: "downloadFolder") }
    }
    func search(_ term: String? = nil) {
        if let term { query = term }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || searchMode == .genres else { return }
        if (try? PlaylistImport.source(text)) != nil {
            Task { await importPlaylist(text) }; return
        }
        collectionHistory = []
        let id = UUID(); searchID = id
        section = "search"; searching = true; searched = true; results = []; catalogItems = []; collectionTitle = nil; openedCollection = nil
        selected = nil; inspectID = UUID(); inspecting = false; notice = nil; sourceFilter = "Tout"
        let mode = searchMode
        Task {
            var actual = text
            if let url = URL(string: text), url.scheme != nil {
                do {
                    if url.host == "deezer.com" || url.host?.hasSuffix(".deezer.com") == true {
                        let (title, tracks) = try await Catalog.direct(url)
                        guard searchID == id else { return }
                        results = tracks; collectionTitle = title; searching = false
                        if let artist = tracks.first?.artist { rememberInterest(artist, weight: 1) }
                        return
                    } else if url.host == "open.spotify.com" {
                        actual = try await Engine.spotifyTitle(url)
                        guard searchID == id else { return }
                        query = actual
                        notice = "Titre identifié sur Spotify. Vérifiez la version proposée avant de la télécharger."
                    } else {
                        guard Engine.isSupported(url) else { throw MusicError.message("Ce lien n’est pas pris en charge. Essayez YouTube, SoundCloud, Bandcamp, Jamendo, Audiomack, Archive.org, Vimeo ou Mixcloud.") }
                        let (track, available) = try await Engine.inspect(url.absoluteString)
                        guard searchID == id else { return }
                        rememberInterest(track.artist.isEmpty ? track.title : track.artist, weight: 1)
                        results = [track]; selected = track; formats = available; selectedFormat = "best"; searching = false
                        return
                    }
                } catch { if searchID == id { showError(error.localizedDescription); searching = false }; return }
            }
            let resolvedSpotify = URL(string: text)?.host == "open.spotify.com"
            if mode != .tracks && mode != .all && !resolvedSpotify {
                do {
                    let items = try await Catalog.search(actual, mode: mode)
                    if searchID == id { catalogItems = items; searching = false; if !items.isEmpty { rememberInterest(actual, weight: 1) } }
                } catch { if searchID == id { showError(error.localizedDescription); searching = false } }
                return
            }
            await withTaskGroup(of: (String, [Track], [CatalogItem], String?).self) { group in
                let value = actual
                for source in (["Deezer", "YouTube", "SoundCloud"] + (mode == .all ? ["Albums", "Artistes", "Playlists"] : [])) {
                    group.addTask {
                        do {
                            if source == "Albums" || source == "Artistes" || source == "Playlists" {
                                let items = try await Catalog.search(value, mode: source == "Albums" ? .albums : source == "Playlists" ? .playlists : .artists)
                                return (source, [], Array(items.prefix(4)), nil)
                            }
                            let tracks = try await source == "Deezer" ? Engine.deezer(value) : Engine.search(value, source: source)
                            return (source, tracks, [], nil)
                        } catch { return (source, [], [], error.localizedDescription) }
                    }
                }
                var failures: [String] = []
                for await (source, tracks, items, error) in group {
                    guard searchID == id else { continue }
                    results += tracks; catalogItems += items
                    if error != nil { failures.append(source) }
                }
                guard searchID == id else { return }
                searching = false
                if !results.isEmpty || !catalogItems.isEmpty { rememberInterest(actual, weight: 1) }
                if !failures.isEmpty { showError("Sources momentanément indisponibles : \(failures.joined(separator: ", ")). Les autres résultats restent utilisables.") }
            }
        }
    }
    func changeMode(_ mode: SearchMode) {
        searchMode = mode
        results = []; catalogItems = []; selected = nil; collectionTitle = nil; openedCollection = nil
        searchID = UUID(); inspectID = UUID(); searching = false; inspecting = false; searched = false; sourceFilter = "Tout"
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mode == .genres { search() }
    }
    func openCollection(_ item: CatalogItem) {
        if section != "search" { collectionHistory = [] }
        collectionHistory.append(CollectionPage(section: section, query: query, mode: searchMode, results: results, items: catalogItems, collection: openedCollection, title: collectionTitle))
        let id = UUID(); searchID = id; section = "search"; searching = true; searched = true; notice = nil
        var recent = library.recentCollections ?? []
        recent.removeAll { $0.id == item.id }; recent.insert(item, at: 0)
        library.recentCollections = Array(recent.prefix(12)); save()
        collectionTitle = item.name; openedCollection = item; results = []; catalogItems = []; selected = nil; inspectID = UUID(); sourceFilter = "Tout"
        Task {
            do {
                if item.kind == "genre" {
                    let items = try await Catalog.albums(in: item)
                    if searchID == id { catalogItems = items; if !items.isEmpty { rememberInterest(item.name, weight: 1) } }
                } else {
                    let tracks = try await Catalog.tracks(in: item)
                    if searchID == id { results = tracks; if !tracks.isEmpty { rememberInterest(item.kind == "album" && !item.subtitle.isEmpty ? item.subtitle : item.name, weight: 1) } }
                }
            } catch { if searchID == id { showError(error.localizedDescription) } }
            if searchID == id { searching = false }
        }
    }
    func backFromCollection() {
        searchID = UUID(); inspectID = UUID(); searching = false; inspecting = false; selected = nil
        guard let previous = collectionHistory.popLast() else { section = "home"; openedCollection = nil; return }
        section = previous.section; query = previous.query; searchMode = previous.mode
        results = previous.results; catalogItems = previous.items; openedCollection = previous.collection; collectionTitle = previous.title
    }
    func select(_ track: Track) {
        selected = track; formats = []; selectedFormat = "best"
        let id = UUID(); inspectID = id; inspecting = !track.isCatalog && downloaded(track) == nil
        guard inspecting else { return }
        Task {
            do {
                let (_, available) = try await Engine.inspect(track.url)
                guard inspectID == id else { return }
                formats = available; inspecting = false
            } catch { if inspectID == id { inspecting = false; showError(error.localizedDescription) } }
        }
    }
    @discardableResult func importPlaylist(_ link: String) async -> Bool {
        guard !importingPlaylist else { return false }
        importingPlaylist = true; notice = nil
        defer { importingPlaylist = false }
        do { acceptImport(try await PlaylistImport.load(link)); return true }
        catch { showError(error.localizedDescription); return false }
    }
    func acceptImport(_ imported: ImportedPlaylist) {
        // Re-import updates the same playlist; existing local additions remain intact.
        if let index = library.playlists.firstIndex(where: { $0.sourceURL == imported.sourceURL }) {
            library.playlists[index].importedTracks = imported.tracks
            library.playlists[index].importWarning = imported.warning
            library.playlists[index].hasRemoteChanges = false
            library.playlists[index].lastSyncCheck = Date()
            section = library.playlists[index].id.uuidString
        } else {
            let playlist = Playlist(name: imported.name, importedTracks: imported.tracks,
                                    sourceURL: imported.sourceURL, importWarning: imported.warning)
            library.playlists.append(playlist); section = playlist.id.uuidString
        }
        selected = nil; save()
        notice = "\(imported.tracks.count) titres importés."
    }
    func playlistTracks(_ playlist: Playlist) -> [Track] {
        var seen = Set<String>()
        return ((playlist.importedTracks ?? []) + (playlist.addedTracks ?? []) + playlist.trackIDs.compactMap { id in library.tracks.first { $0.id == id }?.track }).filter { seen.insert($0.id).inserted }
    }
    func downloadPlaylist(_ playlist: Playlist) {
        for track in playlistTracks(playlist) where downloaded(track) == nil { enqueue(track) }
    }
    func enqueue(_ track: Track) {
        guard !isQueued(track) else { return }
        if downloaded(track) != nil {
            notice = "Ce morceau est déjà dans votre bibliothèque."; return
        }
        downloadErrors[track.id] = nil
        queueFormats[track.id] = selected?.id == track.id ? selectedFormat : "best"
        queueExports[track.id] = exportFormat
        pending.append(track)
        drainQueue()
    }
    private func drainQueue() {
        while activeDownloads.count < 2 && !pending.isEmpty {
            let requested = pending.removeFirst()
            let preferred = queueFormats.removeValue(forKey: requested.id) ?? "best"
            let export = queueExports.removeValue(forKey: requested.id) ?? "original"
            if downloaded(requested) != nil { continue }
            activeDownloads.append(ActiveDownload(track: requested))
            let destination = folder
            Task { await download(requested, preferred: preferred, export: export, destination: destination) }
        }
    }
    func updateDownload(_ id: String, progress: Double? = nil, phase: String? = nil) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == id }) else { return }
        if let progress { activeDownloads[index].progress = progress }
        if let phase { activeDownloads[index].phase = phase }
    }
    private func download(_ requested: Track, preferred: String, export: String, destination: URL) async {
        defer { activeDownloads.removeAll { $0.id == requested.id }; drainQueue() }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let result: (Track, String)
            if let downloadWorker { result = try await downloadWorker(requested, preferred, export, destination) }
            else { result = try await AudioDownload.run(target: requested,
                preferred: preferred == "best" || requested.isCatalog ? nil : preferred,
                search: { query, service in try await Engine.search(query, source: service, count: 5) },
                transfer: { [weak self] source, format in
                    self?.updateDownload(requested.id, progress: 0, phase: "Téléchargement audio depuis \(source.source)…")
                    let owner = self
                    return try await AudioDownload.transfer(source, format: format, folder: destination, export: export) { value in
                        Task { @MainActor in
                            owner?.updateDownload(requested.id, progress: value, phase: value >= 1 ? "Finalisation du fichier…" : nil)
                        }
                    }
                }, status: { [weak self] phase in
                    self?.updateDownload(requested.id, progress: 0, phase: phase)
                })
            }
            let (source, path) = result
            var saved = requested
            saved.url = source.url; saved.source = source.source
            let bitrate = downloadWorker == nil ? await AudioMetadata.bitrate(URL(fileURLWithPath: path)) : nil
            if !library.tracks.contains(where: { $0.path == path }) { library.tracks.insert(LocalTrack(track: saved, path: path, bitrateKbps: bitrate), at: 0) }
            save(); notice = "« \(requested.title) » est dans votre bibliothèque."
        } catch {
            downloadErrors[requested.id] = error.localizedDescription
            let reason = error.localizedDescription
            showError(reason.contains("« \(requested.title) »")
                      ? "Téléchargement impossible. \(reason)"
                      : "Téléchargement impossible pour « \(requested.title) ». \(reason)")
        }
    }
    @discardableResult func createPlaylist(_ name: String, navigate: Bool = true) -> UUID? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let playlist = Playlist(name: String(clean.prefix(160))); library.playlists.append(playlist)
        if navigate { section = playlist.id.uuidString }; save(); return playlist.id
    }
    func add(_ track: LocalTrack, to id: UUID) { setMembership(track.track, in: id, included: true) }
    func remove(_ track: LocalTrack, from id: UUID) { setMembership(track.track, in: id, included: false) }
    func matchesRecording(_ a: Track, _ b: Track) -> Bool {
        a.id == b.id || a.url == b.url || Matching.sameRecording(a, b)
    }
    func preparePlaybackQueue(for track: Track) {
        let candidates: [Track]
        if let playlist = currentPlaylist { candidates = playlistTracks(playlist) }
        else if section == "liked" { candidates = likedTracks }
        else if section == "search", results.contains(where: { matchesRecording($0, track) }) { candidates = visibleResults }
        else if section == "home", discoveries.contains(where: { matchesRecording($0, track) }) { candidates = discoveries }
        else { candidates = library.tracks.map(\.track) }
        var seen = Set<String>()
        var queue = candidates.filter { seen.insert($0.id).inserted }
        if !queue.contains(where: { matchesRecording($0, track) }) { queue = [track] }
        orderedPlaybackQueue = queue
        playbackQueue = shuffle ? [track] + queue.filter { !matchesRecording($0, track) }.shuffled() : queue
    }
    func requestPlayback(_ track: Track, keepQueue: Bool = false) {
        if notice?.hasPrefix("Lecture en ligne impossible") == true { notice = nil }
        if let requestedPlayback, matchesRecording(requestedPlayback, track) { cancelRequestedPlayback(); return }
        if previewing == nil, let currentTrack, matchesRecording(currentTrack, track), player.currentItem != nil {
            togglePlayback(); return
        }
        if let local = downloaded(track) { play(local, keepQueue: keepQueue); return }
        if !keepQueue { preparePlaybackQueue(for: track) }
        let preparation = streamPrefetchTarget.map { matchesRecording($0, track) } == true ? streamPrefetchTask : nil
        if preparation != nil { streamPrefetchTask = nil; streamPrefetchTarget = nil; streamPrefetchIsIntent = false }
        resetPlaybackRequest()
        playing = nil; previewing = nil; streaming = nil
        player.pause(); player.replaceCurrentItem(with: nil); isPlaying = false
        position = 0; playerDuration = track.duration ?? 0
        requestedPlayback = track; isBuffering = true
        resolveStream(track, id: playbackID, resumeAt: 0, preparation: preparation)
    }
    private func resetPlaybackRequest() {
        playbackTask?.cancel(); playbackTask = nil
        streamPrefetchTask?.cancel(); streamPrefetchTask = nil
        streamPrefetchTarget = nil
        streamPrefetchIsIntent = false
        bufferTimeout?.cancel(); bufferTimeout = nil
        itemObservation = nil; playbackID = UUID()
        requestedPlayback = nil; previewLoadingID = nil; isBuffering = false
        attemptedStreams = []; streamSource = nil; streamRecoveryCount = 0
    }
    func cancelRequestedPlayback() {
        resetPlaybackRequest()
        player.pause(); player.replaceCurrentItem(with: nil)
        playing = nil; streaming = nil; previewing = nil; isPlaying = false
        position = 0; playerDuration = 0
    }
    private func resolveStream(_ track: Track, id: UUID, resumeAt: Double, preparation: Task<AudioStream?, Never>? = nil) {
        let excluded = attemptedStreams
        playbackTask = Task {
            do {
                let prepared: AudioStream?
                if let preparation {
                    prepared = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
                    try Task.checkCancellation()
                } else { prepared = nil }
                let stream: AudioStream
                if let prepared { stream = prepared }
                else if let streamResolver { stream = try await streamResolver(track, excluded) }
                else { stream = try await AudioStreaming.resolve(track, excluding: excluded) }
                try Task.checkCancellation()
                guard playbackID == id else { return }
                streamSource = stream.source
                streaming = track; playing = nil; previewing = nil
                listeningSeconds = 0; listeningRecorded = false; lastListeningTick = Date()
                let item = AVPlayerItem(asset: stream.makeAsset())
                item.preferredForwardBufferDuration = 3
                installPlayerItem(item, resumeAt: resumeAt)
            } catch {
                guard playbackID == id, !Task.isCancelled else { return }
                requestedPlayback = nil; streaming = nil; isBuffering = false; isPlaying = false
                showError("Lecture en ligne impossible pour « \(track.title) ». \(error.localizedDescription)")
            }
        }
    }
    private func observePosition(of item: AVPlayerItem) {
        if let observer { player.removeTimeObserver(observer) }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, let item, self.player.currentItem === item else { return }
                let time = self.player.currentTime()
                let tick = Date()
                let elapsed = tick.timeIntervalSince(self.lastListeningTick)
                self.lastListeningTick = tick
                if self.player.timeControlStatus == .playing { self.accountForListening(seconds: min(1, max(0, elapsed))) }
                self.position = time.seconds.isFinite ? time.seconds : 0
                let duration = self.player.currentItem?.duration.seconds ?? 0
                self.playerDuration = duration.isFinite && duration > 0 ? (self.previewing != nil ? min(30, duration) : duration) : (self.previewing != nil ? 30 : self.currentTrack?.duration ?? 0)
                if self.previewing != nil && self.position >= 30 { self.player.pause(); self.isPlaying = false }

            }
        }
    }
    private func installPlayerItem(_ item: AVPlayerItem, resumeAt: Double = 0) {
        itemObservation = nil
        player.replaceCurrentItem(with: item)
        if observesPlayback {
            observePosition(of: item)
            itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self, self.player.currentItem === item else { return }
                    if item.status == .failed { self.playbackFailed(item) }
                    else if item.status == .readyToPlay {
                        self.requestedPlayback = nil
                        if resumeAt > 0 { self.seek(resumeAt) }
                        self.prepareNextStream()
                    }
                }
            }
        } else { requestedPlayback = nil }
        isPlaying = true; player.play()
        updateBuffering()
    }
    private func prepareNextStream() {
        streamPrefetchTask?.cancel(); streamPrefetchTask = nil
        streamPrefetchTarget = nil; streamPrefetchIsIntent = false
        guard observesPlayback, streamResolver == nil || streamPrefetchResolver != nil, previewing == nil, let currentTrack,
              let index = playbackQueue.firstIndex(where: { matchesRecording($0, currentTrack) }),
              index + 1 < playbackQueue.count else { return }
        let next = playbackQueue[index + 1]
        guard downloaded(next) == nil else { return }
        startStreamPreparation(next, intention: false)
    }
    func preparePlaybackIntent(_ track: Track, hovering: Bool) {
        if !hovering {
            guard streamPrefetchIsIntent, streamPrefetchTarget.map({ matchesRecording($0, track) }) == true else { return }
            prepareNextStream()
            return
        }
        guard observesPlayback, streamResolver == nil || streamPrefetchResolver != nil,
              requestedPlayback == nil, previewLoadingID == nil, previewing == nil,
              downloaded(track) == nil, currentTrack.map({ matchesRecording($0, track) }) != true else { return }
        guard streamPrefetchTarget.map({ matchesRecording($0, track) }) != true else { return }
        streamPrefetchTask?.cancel()
        startStreamPreparation(track, intention: true)
    }
    private func startStreamPreparation(_ track: Track, intention: Bool) {
        streamPrefetchTarget = track; streamPrefetchIsIntent = intention
        let resolver = streamPrefetchResolver
        // Only resolve metadata and prepare the audio stream. Never add media to the library.
        streamPrefetchTask = Task(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: intention ? 250_000_000 : 1_000_000_000)
                if let resolver { return try await resolver(track) }
                return try await AudioStreaming.resolve(track)
            } catch { return nil }
        }
    }
    private func updateBuffering() {
        isBuffering = isPlaying && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        bufferTimeout?.cancel(); bufferTimeout = nil
        guard isBuffering, let item = player.currentItem else { return }
        bufferTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 25_000_000_000) } catch { return }
            guard let self, self.player.currentItem === item, self.isBuffering else { return }
            self.playbackFailed(item)
        }
    }
    func playbackFailed(_ item: AVPlayerItem) {
        guard player.currentItem === item else { return }
        itemObservation = nil; bufferTimeout?.cancel(); bufferTimeout = nil
        player.pause(); player.replaceCurrentItem(with: nil); isPlaying = false; isBuffering = false
        guard let track = streaming, let source = streamSource else {
            showError(previewing != nil ? "Extrait indisponible. Réessayez dans un instant." : "Lecture impossible pour ce format. Le fichier reste accessible dans le Finder.")
            return
        }
        attemptedStreams.insert(source.url)
        streamRecoveryCount += 1
        if streamRecoveryCount <= 2 {
            requestedPlayback = track; isBuffering = true
            resolveStream(track, id: playbackID, resumeAt: position)
        } else {
            requestedPlayback = nil; streaming = nil
            showError("Lecture en ligne impossible : aucune autre source audio accessible pour « \(track.title) ». Réessayez dans un instant.")
        }
    }
    func play(_ track: LocalTrack, keepQueue: Bool = false) {
        guard FileManager.default.fileExists(atPath: track.path) else { showError("Ce fichier a été déplacé ou supprimé : \(track.path)"); return }
        if !keepQueue { preparePlaybackQueue(for: track.track) }
        resetPlaybackRequest()
        let id = playbackID
        player.pause(); player.replaceCurrentItem(with: nil); isPlaying = false
        playing = track; streaming = nil; previewing = nil; position = 0; playerDuration = track.track.duration ?? 0
        playbackTask = Task {
            do {
                var url = URL(fileURLWithPath: track.path)
                if ["webm", "opus", "ogg"].contains(url.pathExtension.lowercased()) {
                    let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyMusic", isDirectory: true)
                    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                    let decoded = cache.appendingPathComponent(track.id.uuidString + ".wav")
                    if !FileManager.default.fileExists(atPath: decoded.path) {
                        requestedPlayback = track.track; isBuffering = true
                        try await Engine.convert(url, to: decoded, title: track.track.title, artist: track.track.artist, lossless: true)
                    }
                    url = decoded
                }
                guard playbackID == id, !Task.isCancelled else { return }
                listeningSeconds = 0; listeningRecorded = false; lastListeningTick = Date()
                installPlayerItem(AVPlayerItem(url: url))
            } catch {
                if playbackID == id, !Task.isCancelled { requestedPlayback = nil; isBuffering = false; showError(error.localizedDescription) }
            }
        }
    }
    func exportForMobile() {
        guard !exporting, !visibleLocal.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Exporter ici"; panel.message = "Choisissez un dossier local ou iCloud Drive."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let tracks = visibleLocal, name = currentPlaylist?.name ?? "EasyMusic"
        exporting = true
        Task {
            do {
                let target = try await Transfer.export(tracks, name: name, into: parent)
                NSWorkspace.shared.open(target)
                notice = "Export prêt. Dans Offline Music sur iPhone : Import → Files ou Computer. Importez les fichiers audio ; les playlists doivent être recréées dans l’application."
            } catch { showError(error.localizedDescription) }
            exporting = false
        }
    }

    func downloaded(_ track: Track) -> LocalTrack? {
        library.tracks.first { ($0.track.id == track.id || $0.track.url == track.url || Matching.sameRecording($0.track, track)) && FileManager.default.fileExists(atPath: $0.path) }
    }
    func isQueued(_ track: Track) -> Bool { activeDownloads.contains { matchesRecording($0.track, track) } || pending.contains { matchesRecording($0, track) } }
    func preview(_ track: Track) {
        if previewing?.id == track.id && isPlaying { player.pause(); isPlaying = false; return }
        resetPlaybackRequest()
        let id = playbackID
        player.pause(); player.replaceCurrentItem(with: nil); isPlaying = false; previewLoadingID = track.id
        streaming = nil; playing = nil; previewing = nil
        playbackTask = Task {
            do {
                let url: URL
                if let local = downloaded(track) {
                    var localURL = URL(fileURLWithPath: local.path)
                    if ["webm", "opus", "ogg"].contains(localURL.pathExtension.lowercased()) {
                        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyMusic", isDirectory: true)
                        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                        let decoded = cache.appendingPathComponent(local.id.uuidString + ".wav")
                        if !FileManager.default.fileExists(atPath: decoded.path) { try await Engine.convert(localURL, to: decoded, title: track.title, artist: track.artist, lossless: true) }
                        localURL = decoded
                    }
                    url = localURL
                } else if let raw = track.preview, let candidate = URL(string: raw), !raw.isEmpty { url = candidate }
                else if !track.isCatalog { url = try await Engine.previewClip(track) }
                else { throw MusicError.message("Aucun extrait disponible pour ce titre.") }
                guard playbackID == id, !Task.isCancelled else { return }
                playing = nil; streaming = nil; previewing = track; previewLoadingID = nil; position = 0
                listeningSeconds = 0; listeningRecorded = false; lastListeningTick = Date()
                installPlayerItem(AVPlayerItem(url: url))
            } catch { if playbackID == id, !Task.isCancelled { previewLoadingID = nil; showError(error.localizedDescription) } }
        }
    }
    func togglePlayback() {
        if requestedPlayback != nil { cancelRequestedPlayback(); return }
        guard player.currentItem != nil else { return }
        if isPlaying { player.pause() } else { if (previewing != nil && position >= 30) || (position >= playerDuration && playerDuration > 0) { seek(0) }; player.play() }
        isPlaying.toggle(); updateBuffering()
    }
    func seek(_ time: Double) {
        guard time.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, min(time, playerDuration > 0 ? playerDuration : time)), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func toggleShuffle() {
        shuffle.toggle()
        if shuffle {
            orderedPlaybackQueue = playbackQueue
            if let track = requestedPlayback ?? currentTrack { playbackQueue = [track] + playbackQueue.filter { !matchesRecording($0, track) }.shuffled() }
        } else if !orderedPlaybackQueue.isEmpty { playbackQueue = orderedPlaybackQueue }
        prepareNextStream()
    }
    func toggleMute() {
        if volume > 0 { unmutedVolume = volume; volume = 0 } else { volume = max(0.01, unmutedVolume) }
    }
    func playbackEnded() {
        guard playing != nil || streaming != nil else { isPlaying = false; return }
        if repeatMode == 2 { seek(0); player.play(); isPlaying = true }
        else { next() }
    }
    func next(_ offset: Int = 1) {
        if offset < 0 && position > 3 { seek(0); return }
        guard let track = requestedPlayback ?? currentTrack, let index = playbackQueue.firstIndex(where: { matchesRecording($0, track) }),
              let nextIndex = PlaybackOrder.nextIndex(index, count: playbackQueue.count, offset: offset, repeats: repeatMode == 1) else {
            if requestedPlayback != nil { cancelRequestedPlayback() }
            else { isPlaying = false; player.pause() }
            return
        }
        let nextTrack = playbackQueue[nextIndex]
        // Repeat on a one-track queue must restart rather than toggle pause.
        if let currentTrack, matchesRecording(currentTrack, nextTrack), requestedPlayback == nil { seek(0); player.play(); isPlaying = true }
        else { requestPlayback(nextTrack, keepQueue: true) }
    }
}
enum PlaybackOrder {
    static func nextIndex(_ current: Int, count: Int, offset: Int, repeats: Bool) -> Int? {
        guard count > 0, (0..<count).contains(current) else { return nil }
        let next = current + offset
        if repeats { return (next % count + count) % count }
        return (0..<count).contains(next) ? next : nil
    }
}
