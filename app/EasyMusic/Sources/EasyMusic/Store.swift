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
    @Published var notice: String?
    var noticeIsWarning: Bool {
        let text = notice?.lowercased() ?? ""
        return ["impossible", "aucune version", "protégé", "indisponible", "erreur", "dépassé", "plusieurs versions"].contains { text.contains($0) }
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
    @Published var previewLoadingID: String?
    @Published var pending: [Track] = []
    @Published var playing: LocalTrack?
    @Published var previewing: Track?
    @Published var isPlaying = false
    @Published var shuffle = false
    @Published var repeatMode = 0
    @Published var playbackQueue: [LocalTrack] = []
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
    private var searchID = UUID()
    private var inspectID = UUID()
    var checkedBitrates = Set<UUID>()
    let storage: URL
    var downloadWorker: ((Track, String, String, URL) async throws -> (Track, String))?
    private var queueFormats: [String: String] = [:]
    private var queueExports: [String: String] = [:]
    var canConvert: Bool { Engine.executable("ffmpeg") != nil }
    var visibleResults: [Track] { sourceFilter == "Tout" ? results : results.filter { $0.source == sourceFilter } }
    var currentPlaylist: Playlist? { library.playlists.first { $0.id.uuidString == section } }
    var visibleLocal: [LocalTrack] {
        if let list = currentPlaylist {
            var seen = Set<UUID>()
            let imported = (list.importedTracks ?? []).compactMap { downloaded($0) }
            let local = list.trackIDs.compactMap { id in library.tracks.first { $0.id == id } }
            return (imported + local).filter { seen.insert($0.id).inserted }
        }
        return library.tracks
    }
    init(storageURL: URL? = nil, downloadFolder: URL? = nil, observePlayback: Bool = true) {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyMusic", isDirectory: true)
        storage = storageURL ?? appSupport.appendingPathComponent("library.json")
        folder = downloadFolder ?? UserDefaults.standard.string(forKey: "downloadFolder").map { URL(fileURLWithPath: $0) }
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Music/EasyMusic", isDirectory: true)
        do {
            try fm.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: storage.path) { library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: storage)) }
        } catch { notice = "La bibliothèque n’a pas pu être chargée : \(error.localizedDescription)" }
        player.volume = volume
        guard observePlayback else { return }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let tick = Date()
                let elapsed = tick.timeIntervalSince(self.lastListeningTick)
                self.lastListeningTick = tick
                if self.player.timeControlStatus == .playing { self.accountForListening(seconds: min(1, max(0, elapsed))) }
                self.position = time.seconds.isFinite ? time.seconds : 0
                let duration = self.player.currentItem?.duration.seconds ?? 0
                self.playerDuration = duration.isFinite ? (self.previewing != nil ? min(30, duration) : duration) : 0
                if self.previewing != nil && self.position >= 30 { self.player.pause(); self.isPlaying = false }
                if self.player.currentItem?.status == .failed {
                    self.notice = "Lecture impossible pour ce format. Le fichier reste accessible dans le Finder."
                    self.isPlaying = false
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.playbackEnded() }
        }
    }
    func loadDiscoveries(force: Bool = false) async {
        guard !homeLoading, force || discoveries.isEmpty || loadedInterestsRevision != interestsRevision else { return }
        let revision = interestsRevision
        let terms = Recommendations.queries(library.interests ?? [])
        homeLoading = true
        async let hits = try? Catalog.charts()
        async let mixes = Catalog.homeMixes()
        async let personal = Catalog.homeMixes(queries: terms, limit: 2)
        async let genres = try? Catalog.search("", mode: .genres)
        discoveries = await hits ?? []
        homeMixes = await mixes
        homeGenres = await genres ?? []
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
        guard !listeningRecorded, seconds.isFinite, seconds > 0, let track = playing?.track ?? previewing else { return }
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
        catch { notice = "Impossible d’enregistrer la bibliothèque : \(error.localizedDescription)" }
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
                } catch { if searchID == id { notice = error.localizedDescription; searching = false }; return }
            }
            let resolvedSpotify = URL(string: text)?.host == "open.spotify.com"
            if mode != .tracks && mode != .all && !resolvedSpotify {
                do {
                    let items = try await Catalog.search(actual, mode: mode)
                    if searchID == id { catalogItems = items; searching = false; if !items.isEmpty { rememberInterest(actual, weight: 1) } }
                } catch { if searchID == id { notice = error.localizedDescription; searching = false } }
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
                if !failures.isEmpty { notice = "Sources momentanément indisponibles : \(failures.joined(separator: ", ")). Les autres résultats restent utilisables." }
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
        let id = UUID(); searchID = id; section = "search"; searching = true; searched = true; notice = nil
        var recent = library.recentCollections ?? []
        recent.removeAll { $0.id == item.id }; recent.insert(item, at: 0)
        library.recentCollections = Array(recent.prefix(12)); save()
        collectionTitle = item.name; openedCollection = item; results = []; catalogItems = []; selected = nil; inspectID = UUID(); sourceFilter = "Tout"
        Task {
            do {
                if item.kind == "genre" {
                    let items = try await Catalog.artists(in: item)
                    if searchID == id { catalogItems = items; if !items.isEmpty { rememberInterest(item.name, weight: 1) } }
                } else {
                    let tracks = try await Catalog.tracks(in: item)
                    if searchID == id { results = tracks; if !tracks.isEmpty { rememberInterest(item.kind == "album" && !item.subtitle.isEmpty ? item.subtitle : item.name, weight: 1) } }
                }
            } catch { if searchID == id { notice = error.localizedDescription } }
            if searchID == id { searching = false }
        }
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
            } catch { if inspectID == id { inspecting = false; notice = error.localizedDescription } }
        }
    }
    @discardableResult func importPlaylist(_ link: String) async -> Bool {
        guard !importingPlaylist else { return false }
        importingPlaylist = true; notice = nil
        defer { importingPlaylist = false }
        do { acceptImport(try await PlaylistImport.load(link)); return true }
        catch { notice = error.localizedDescription; return false }
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
        return ((playlist.importedTracks ?? []) + playlist.trackIDs.compactMap { id in library.tracks.first { $0.id == id }?.track }).filter { seen.insert($0.id).inserted }
    }
    func downloadPlaylist(_ playlist: Playlist) {
        for track in playlist.importedTracks ?? [] where downloaded(track) == nil { enqueue(track) }
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
                    return try await AudioDownload.transfer(source, format: format, folder: destination, export: export) { value in
                        Task { @MainActor [weak self] in
                            self?.updateDownload(requested.id, progress: value, phase: value >= 1 ? "Finalisation du fichier…" : nil)
                        }
                    }
                }, status: { [weak self] phase in
                    self?.updateDownload(requested.id, progress: 0, phase: phase)
                    if phase.hasPrefix("Autre source") { self?.notice = "Une source audio a échoué pour « \(requested.title) ». \(phase)" }
                })
            }
            let (source, path) = result
            var saved = requested
            saved.url = source.url; saved.source = source.source
            let bitrate = downloadWorker == nil ? await AudioMetadata.bitrate(URL(fileURLWithPath: path)) : nil
            if !library.tracks.contains(where: { $0.path == path }) { library.tracks.insert(LocalTrack(track: saved, path: path, bitrateKbps: bitrate), at: 0) }
            save(); notice = "« \(requested.title) » est dans votre bibliothèque."
        } catch {
            downloadErrors[requested.id] = error.localizedDescription; notice = error.localizedDescription
        }
    }
    @discardableResult func createPlaylist(_ name: String, navigate: Bool = true) -> UUID? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let playlist = Playlist(name: String(clean.prefix(160))); library.playlists.append(playlist)
        if navigate { section = playlist.id.uuidString }; save(); return playlist.id
    }
    func add(_ track: LocalTrack, to id: UUID) {
        guard let index = library.playlists.firstIndex(where: { $0.id == id }), !library.playlists[index].trackIDs.contains(track.id) else { return }
        library.playlists[index].trackIDs.append(track.id); save()
    }
    func remove(_ track: LocalTrack, from id: UUID) {
        guard let index = library.playlists.firstIndex(where: { $0.id == id }) else { return }
        library.playlists[index].trackIDs.removeAll { $0 == track.id }; save()
    }
    func play(_ track: LocalTrack, keepQueue: Bool = false) {
        if !keepQueue {
            let candidates = visibleLocal.contains(where: { $0.id == track.id }) ? visibleLocal : library.tracks
            playbackQueue = shuffle ? [track] + candidates.filter { $0.id != track.id }.shuffled() : candidates
        }
        guard FileManager.default.fileExists(atPath: track.path) else { notice = "Ce fichier a été déplacé ou supprimé : \(track.path)"; return }
        let id = UUID(); playbackID = id; previewLoadingID = nil
        player.pause(); isPlaying = false
        playing = track; previewing = nil
        Task {
            do {
                var url = URL(fileURLWithPath: track.path)
                if ["webm", "opus", "ogg"].contains(url.pathExtension.lowercased()) {
                    let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyMusic", isDirectory: true)
                    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                    let decoded = cache.appendingPathComponent(track.id.uuidString + ".wav")
                    if !FileManager.default.fileExists(atPath: decoded.path) {
                        notice = "Préparation de la lecture… Le fichier original est conservé."
                        try await Engine.convert(url, to: decoded, title: track.track.title, artist: track.track.artist, lossless: true)
                    }
                    url = decoded
                }
                guard playbackID == id else { return }
                listeningSeconds = 0; listeningRecorded = false; lastListeningTick = Date()
                player.replaceCurrentItem(with: AVPlayerItem(url: url)); player.play(); isPlaying = true
            } catch { if playbackID == id { notice = error.localizedDescription } }
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
            } catch { notice = error.localizedDescription }
            exporting = false
        }
    }

    func downloaded(_ track: Track) -> LocalTrack? {
        library.tracks.first { ($0.track.id == track.id || $0.track.url == track.url || Matching.sameRecording($0.track, track)) && FileManager.default.fileExists(atPath: $0.path) }
    }
    func isQueued(_ track: Track) -> Bool { activeDownloads.contains { $0.id == track.id } || pending.contains { $0.id == track.id } }
    func preview(_ track: Track) {
        if previewing?.id == track.id && isPlaying { player.pause(); isPlaying = false; return }
        let id = UUID(); playbackID = id
        player.pause(); isPlaying = false; previewLoadingID = track.id
        Task {
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
                guard playbackID == id else { return }
                playing = nil; previewing = track; previewLoadingID = nil; position = 0
                listeningSeconds = 0; listeningRecorded = false; lastListeningTick = Date()
                player.replaceCurrentItem(with: AVPlayerItem(url: url)); player.play(); isPlaying = true
            } catch { if playbackID == id { previewLoadingID = nil; notice = error.localizedDescription } }
        }
    }
    func togglePlayback() {
        guard player.currentItem != nil else { return }
        if isPlaying { player.pause() } else { if (previewing != nil && position >= 30) || (position >= playerDuration && playerDuration > 0) { seek(0) }; player.play() }
        isPlaying.toggle()
    }
    func seek(_ time: Double) { player.seek(to: CMTime(seconds: time, preferredTimescale: 600)) }
    func toggleShuffle() {
        shuffle.toggle()
        if shuffle, let playing { playbackQueue = [playing] + playbackQueue.filter { $0.id != playing.id }.shuffled() }
        else if !shuffle { playbackQueue.sort { a, b in
            (library.tracks.firstIndex { $0.id == a.id } ?? 0) < (library.tracks.firstIndex { $0.id == b.id } ?? 0)
        } }
    }
    func toggleMute() {
        if volume > 0 { unmutedVolume = volume; volume = 0 } else { volume = max(0.01, unmutedVolume) }
    }
    func playbackEnded() {
        guard playing != nil else { isPlaying = false; return }
        if repeatMode == 2 { seek(0); player.play(); isPlaying = true }
        else { next() }
    }
    func next(_ offset: Int = 1) {
        if offset < 0 && position > 3 { seek(0); return }
        guard let playing, let index = playbackQueue.firstIndex(where: { $0.id == playing.id }),
              let nextIndex = PlaybackOrder.nextIndex(index, count: playbackQueue.count, offset: offset, repeats: repeatMode == 1) else {
            isPlaying = false; player.pause(); return
        }
        play(playbackQueue[nextIndex], keepQueue: true)
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
