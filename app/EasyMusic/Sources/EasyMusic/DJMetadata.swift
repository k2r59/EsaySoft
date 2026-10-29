import Foundation
import Accelerate
import CoreFoundation

struct DJInfo {
    var bpm: Double? = nil
    var key: MusicalKey? = nil
    var bpmSource: String? = nil
    var keySource: String? = nil
}

struct MusicalKey: Codable, Hashable {
    let note: Int
    let minor: Bool
    private static let majorNumbers = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]
    private static let minorNumbers = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]
    var camelot: String {
        guard (0..<12).contains(note) else { return "" }
        return String((minor ? Self.minorNumbers : Self.majorNumbers)[note]) + (minor ? "A" : "B")
    }
    var name: String {
        guard (0..<12).contains(note) else { return "" }
        return ["Do", "Do♯", "Ré", "Mi♭", "Mi", "Fa", "Fa♯", "Sol", "La♭", "La", "Si♭", "Si"][note] + (minor ? " mineur" : " majeur")
    }
    static func parse(_ raw: String) -> MusicalKey? {
        let text = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = text.range(of: #"^(?:[1-9]|1[0-2])[ab]$"#, options: .regularExpression), match == text.startIndex..<text.endIndex,
           let number = Int(text.dropLast()) {
            let minor = text.last == "a", numbers = minor ? minorNumbers : majorNumbers
            if let note = numbers.firstIndex(of: number) { return MusicalKey(note: note, minor: minor) }
        }
        guard let regex = try? NSRegularExpression(pattern: #"^(do|re|mi|fa|sol|la|si|[a-g])\s*(#|b|diese|bemol)?\s*(major|majeur|maj|minor|mineur|min|m)?$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func part(_ n: Int) -> String { Range(match.range(at: n), in: text).map { String(text[$0]) } ?? "" }
        let roots = ["c": 0, "do": 0, "d": 2, "re": 2, "e": 4, "mi": 4, "f": 5, "fa": 5, "g": 7, "sol": 7, "a": 9, "la": 9, "b": 11, "si": 11]
        guard let root = roots[part(1)] else { return nil }
        let accidental = part(2), mode = part(3)
        let offset = ["#", "diese"].contains(accidental) ? 1 : ["b", "bemol"].contains(accidental) ? -1 : 0
        return MusicalKey(note: (root + offset + 12) % 12, minor: ["m", "min", "minor", "mineur"].contains(mode))
    }
}

actor DJMetadata {
    static let shared = DJMetadata()
    private var cache: [String: DJInfo] = [:]
    private static let sampleRate = 22_050.0
    private static let analysisVersion = "1"

    func info(for track: Track, localPath: String?, analyzeRemote: Bool = false) async throws -> DJInfo {
        try Task.checkCancellation()
        let attributes = localPath.flatMap { try? FileManager.default.attributesOfItem(atPath: $0) }
        let fingerprint = localPath.map { path in
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970
            return path + "|" + String(describing: attributes?[.size]) + "|" + String(describing: modified)
        } ?? "remote"
        let identity = [track.id, track.url, track.title, track.artist, String(describing: track.duration), fingerprint, Self.analysisVersion].joined(separator: "|")
        if let value = cache[identity], !analyzeRemote || (value.bpm != nil && value.key != nil) { return value }
        var result = cache[identity] ?? DJInfo(), duration = track.duration
        if let path = localPath, attributes?[.type] as? FileAttributeType == .typeRegular,
           let probe = Engine.executable("ffprobe") {
            do {
                let data = try await DJProcess.run(probe, ["-v", "error", "-select_streams", "a:0", "-show_entries", "format=duration:format_tags:stream_tags", "-of", "json", path], timeout: 8)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let tagged = Self.tags(json)
                    if tagged.bpm != nil { result.bpm = tagged.bpm; result.bpmSource = tagged.bpmSource }
                    if tagged.key != nil { result.key = tagged.key; result.keySource = tagged.keySource }
                    if let format = json["format"] as? [String: Any], let seconds = Self.validBPM(format["duration"]) { duration = seconds }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        if result.bpm == nil, track.id.hasPrefix("deezer:"), let id = Int(track.id.dropFirst(7)), id > 0 {
            do {
                let row = try await Catalog.trackMetadata(id)
                if let value = Self.validBPM(row["bpm"]) { result.bpm = value; result.bpmSource = "Deezer" }
            } catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        if result.key == nil || result.bpm == nil {
            var input: String?, userAgent: String?, analysisDuration = duration, provenance = "Estimation · audio"
            if let path = localPath, attributes?[.type] as? FileAttributeType == .typeRegular { input = path }
            else if analyzeRemote {
                if let preview = track.preview, let url = URL(string: preview), url.scheme == "https", url.host != nil {
                    input = preview; analysisDuration = 30; provenance = "Estimation · extrait"
                } else {
                    do {
                        let stream = try await AudioStreaming.resolve(track)
                        input = stream.url.absoluteString; userAgent = stream.userAgent
                        analysisDuration = stream.source.duration ?? duration
                    } catch is CancellationError { throw CancellationError() }
                    catch { try Task.checkCancellation() }
                }
            }
            if let input, let ffmpeg = Engine.executable("ffmpeg") {
                do {
                    let segments = try await Self.decode(input, duration: analysisDuration, ffmpeg: ffmpeg, userAgent: userAgent)
                    let analysis = Task.detached(priority: .utility) {
                        try Self.analyzeSegments(segments, sampleRate: Self.sampleRate)
                    }
                    let estimation = try await withTaskCancellationHandler {
                        try await analysis.value
                    } onCancel: { analysis.cancel() }
                    try Task.checkCancellation()
                    if result.bpm == nil, let value = estimation.bpm { result.bpm = value; result.bpmSource = provenance }
                    if result.key == nil, let value = estimation.key { result.key = value; result.keySource = provenance }
                } catch is CancellationError { throw CancellationError() }
                catch { try Task.checkCancellation() }
            }
        }
        try Task.checkCancellation()
        if cache.count >= 128 { cache.removeAll(keepingCapacity: true) }
        cache[identity] = result
        return result
    }

    nonisolated static func validBPM(_ raw: Any?) -> Double? {
        if let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { return nil }
        let value = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    nonisolated static func tags(_ json: [String: Any]) -> DJInfo {
        var result = DJInfo()
        let streams = json["streams"] as? [[String: Any]] ?? []
        let containers = streams + ((json["format"] as? [String: Any]).map { [$0] } ?? [])
        for container in containers {
            guard let tags = container["tags"] as? [String: Any] else { continue }
            for name in ["TBPM", "BPM"] where result.bpm == nil {
                if let raw = tags.first(where: { $0.key.uppercased() == name })?.value,
                   let value = validBPM(raw) { result.bpm = value; result.bpmSource = "Fichier" }
            }
            for name in ["TKEY", "INITIAL_KEY", "KEY"] where result.key == nil {
                if let raw = tags.first(where: { $0.key.uppercased() == name })?.value as? String,
                   let value = MusicalKey.parse(raw) { result.key = value; result.keySource = "Fichier" }
            }
        }
        return result
    }

    private nonisolated static func decode(_ input: String, duration: Double?, ffmpeg: String, userAgent: String?) async throws -> [[Float]] {
        let knownDuration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let length = min(20, max(4, (knownDuration ?? 60) / 3))
        let starts: [Double]
        if let duration = knownDuration, duration > length * 3 {
            starts = [0.12, 0.45, 0.75].map { min(duration - length, duration * $0) }
        } else { starts = [0, length, length * 2] }
        var segments: [[Float]] = []
        for start in starts {
            try Task.checkCancellation()
            var args = ["-v", "error", "-nostdin"]
            if input.hasPrefix("https://"), let userAgent,
               !userAgent.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }) { args += ["-user_agent", userAgent] }
            args += ["-ss", String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), start), "-i", input, "-t", String(length), "-vn", "-sn", "-dn", "-ac", "1", "-ar", "22050", "-c:a", "pcm_s16le", "-f", "wav", "pipe:1"]
            let data = try await DJProcess.run(ffmpeg, args, timeout: 12)
            let samples = try pcm16Wave(data)
            if samples.count >= Int(sampleRate * 4) { segments.append(samples) }
        }
        return segments
    }

    nonisolated static func pcm16Wave(_ data: Data) throws -> [Float] {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | (Int(bytes[i + 1]) << 8) }
        func u32(_ i: Int) -> Int { u16(i) | (u16(i + 2) << 16) }
        func label(_ i: Int) -> String { String(bytes: bytes[i..<i + 4], encoding: .ascii) ?? "" }
        guard bytes.count >= 12, label(0) == "RIFF", label(8) == "WAVE" else { throw AudioFailure.unavailable }
        var offset = 12, validFormat = false
        while offset + 8 <= bytes.count {
            let kind = label(offset), size = u32(offset + 4), start = offset + 8
            if kind == "fmt ", size >= 16, start + min(size, 40) <= bytes.count {
                let format = u16(start)
                let pcm = format == 1 || (format == 0xfffe && size >= 40 && u16(start + 24) == 1)
                validFormat = pcm && u16(start + 2) == 1 && u32(start + 4) == Int(sampleRate) && u16(start + 14) == 16
            }
            if kind == "data" {
                guard validFormat else { throw AudioFailure.unavailable }
                let count = min(size, bytes.count - start) / 2
                return (0..<count).map { Float(Int16(bitPattern: UInt16(u16(start + $0 * 2)))) / 32768 }
            }
            guard size <= bytes.count - start else { break }
            offset = start + size + (size % 2)
        }
        throw AudioFailure.unavailable
    }

    nonisolated static func analyze(samples: [Float], sampleRate: Double) throws -> DJInfo {
        guard sampleRate.isFinite, sampleRate > 0, samples.count >= Int(sampleRate * 12) else { return DJInfo() }
        let count = samples.count / 3
        let segments = (0..<3).map { Array(samples[$0 * count..<($0 + 1) * count]) }
        return try analyzeSegments(segments, sampleRate: sampleRate)
    }

    private nonisolated static func analyzeSegments(_ segments: [[Float]], sampleRate: Double) throws -> DJInfo {
        guard segments.count >= 2 else { return DJInfo() }
        var keys: [MusicalKey] = [], tempos: [Double] = []
        for samples in segments {
            try Task.checkCancellation()
            if let key = try tonalKey(samples, sampleRate: sampleRate) { keys.append(key) }
            if let tempo = try tempo(samples, sampleRate: sampleRate) { tempos.append(tempo) }
        }
        var result = DJInfo()
        if keys.count >= 2, Set(keys).count == 1 { result.key = keys[0]; result.keySource = "Estimation · audio" }
        if tempos.count >= 2 {
            let sorted = tempos.sorted(), median = sorted[sorted.count / 2]
            if sorted.allSatisfy({ abs($0 - median) <= max(1.5, median * 0.015) }) {
                result.bpm = tempos.reduce(0, +) / Double(tempos.count); result.bpmSource = "Estimation · audio"
            }
        }
        return result
    }

    private nonisolated static func tonalKey(_ samples: [Float], sampleRate: Double) throws -> MusicalKey? {
        let n = 8192, hop = 2048
        guard samples.count >= n, let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD) else { return nil }
        defer { vDSP_DFT_DestroySetup(setup) }
        let window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n - 1))) }
        var real = [Float](repeating: 0, count: n), imaginary = real, outReal = real, outImaginary = real
        var chroma = [Double](repeating: 0, count: 12), magnitude = [Float](repeating: 0, count: n / 2)
        var frames = 0
        for start in stride(from: 0, through: samples.count - n, by: hop) {
            try Task.checkCancellation()
            var energy: Float = 0
            for i in 0..<n { real[i] = samples[start + i] * window[i]; energy += real[i] * real[i] }
            guard energy / Float(n) > 0.0000001 else { continue }
            vDSP_DFT_Execute(setup, real, imaginary, &outReal, &outImaginary)
            for i in 0..<n / 2 { magnitude[i] = hypot(outReal[i], outImaginary[i]) }
            let low = max(2, Int(70 * Double(n) / sampleRate)), high = min(n / 2 - 2, Int(4000 * Double(n) / sampleRate))
            guard low < high else { return nil }
            let peak = magnitude[low...high].max() ?? 0
            guard peak > 0 else { continue }
            for bin in low...high where magnitude[bin] > peak * 0.08 && magnitude[bin] > magnitude[bin - 1] && magnitude[bin] >= magnitude[bin + 1] {
                let left = Double(magnitude[bin - 1]), center = Double(magnitude[bin]), right = Double(magnitude[bin + 1])
                let divisor = left - 2 * center + right
                let correction = abs(divisor) > 1e-12 ? max(-0.5, min(0.5, 0.5 * (left - right) / divisor)) : 0
                let frequency = (Double(bin) + correction) * sampleRate / Double(n)
                let midi = 69 + 12 * log2(frequency / 440), nearest = midi.rounded()
                guard abs(midi - nearest) < 0.4 else { continue }
                let note = (Int(nearest) % 12 + 12) % 12
                let tuningWeight = pow(cos((midi - nearest) * .pi), 2)
                chroma[note] += sqrt(center) * tuningWeight
            }
            frames += 1
        }
        guard frames >= 8, let maximum = chroma.max(), maximum > 0,
              chroma.filter({ $0 > maximum * 0.18 }).count >= 3 else { return nil }
        // Krumhansl pitch-class profiles; correlate the complete profile, not the loudest note.
        let profiles = [[6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88],
                        [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]]
        let mean = chroma.reduce(0, +) / 12, centered = chroma.map { $0 - mean }
        let energy = centered.reduce(0) { $0 + $1 * $1 }
        guard energy > 1e-12 else { return nil }
        var scores: [(MusicalKey, Double)] = []
        for mode in 0..<2 {
            let profile = profiles[mode], average = profile.reduce(0, +) / 12
            for tonic in 0..<12 {
                var product = 0.0, norm = 0.0
                for note in 0..<12 {
                    let value = profile[(note - tonic + 12) % 12] - average
                    product += centered[note] * value; norm += value * value
                }
                scores.append((MusicalKey(note: tonic, minor: mode == 1), product / sqrt(energy * norm)))
            }
        }
        scores.sort { $0.1 > $1.1 }
        guard scores[0].1 >= 0.65, scores[0].1 - scores[1].1 >= 0.08 else { return nil }
        return scores[0].0
    }

    private nonisolated static func tempo(_ samples: [Float], sampleRate: Double) throws -> Double? {
        let hop = 256, alpha = 1 - exp(-2 * .pi * 180 / sampleRate)
        guard samples.count >= Int(sampleRate * 4) else { return nil }
        var low = 0.0, previous = 0.0, envelope: [Double] = []
        for start in stride(from: 0, to: samples.count - hop, by: hop) {
            if start % (hop * 128) == 0 { try Task.checkCancellation() }
            var energy = 0.0
            for sample in samples[start..<start + hop] { low += alpha * (Double(sample) - low); energy += low * low }
            let rms = sqrt(energy / Double(hop))
            envelope.append(max(0, rms - previous)); previous = rms
        }
        guard let maximum = envelope.max(), maximum > 0.0001 else { return nil }
        let mean = envelope.reduce(0, +) / Double(envelope.count)
        let variance = envelope.reduce(0) { $0 + pow($1 - mean, 2) } / Double(envelope.count)
        let threshold = max(maximum * 0.22, mean + sqrt(variance))
        let refractory = max(1, Int(0.12 * sampleRate / Double(hop)))
        var peaks: [Int] = []
        for i in 1..<envelope.count - 1 where envelope[i] >= threshold && envelope[i] > envelope[i - 1] && envelope[i] >= envelope[i + 1] {
            if let last = peaks.last, i - last < refractory {
                if envelope[i] > envelope[last] { peaks[peaks.count - 1] = i }
            } else { peaks.append(i) }
        }
        guard peaks.count >= 8 else { return nil }
        let intervals = zip(peaks.dropFirst(), peaks).map { Double($0 - $1) }.sorted()
        let median = intervals[intervals.count / 2]
        guard intervals.allSatisfy({ abs($0 - median) <= max(2, median * 0.12) }), let first = peaks.first, let last = peaks.last else { return nil }
        let period = Double(last - first) / Double(peaks.count - 1), lag = Int(period.rounded())
        guard lag > 0, lag < envelope.count else { return nil }
        var product = 0.0, firstEnergy = 0.0, secondEnergy = 0.0
        for i in lag..<envelope.count {
            let a = envelope[i] - mean, b = envelope[i - lag] - mean
            product += a * b; firstEnergy += a * a; secondEnergy += b * b
        }
        guard firstEnergy > 0, secondEnergy > 0, product / sqrt(firstEnergy * secondEnergy) >= 0.45 else { return nil }
        let bpm = 60 * sampleRate / (period * Double(hop))
        return (40...300).contains(bpm) ? bpm : nil
    }
}

private enum DJProcess {
    static func run(_ binary: String, _ arguments: [String], timeout: TimeInterval) async throws -> Data {
        let holder = DJProcessHolder()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: binary); process.arguments = arguments
            process.standardOutput = output; process.standardError = errors
            try holder.start(process)
            defer { holder.stop() }
            async let stdout = read(output.fileHandleForReading, limit: 12_000_000)
            async let stderr = read(errors.fileHandleForReading, limit: 65_536)
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { holder.stop(); throw AudioFailure.network }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            let bytes = await stdout
            _ = await stderr
            try Task.checkCancellation()
            guard process.terminationStatus == 0, !bytes.overflow else { throw AudioFailure.unavailable }
            return bytes.data
        } onCancel: { holder.stop() }
    }
    private static func read(_ handle: FileHandle, limit: Int) async -> (data: Data, overflow: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var data = Data(), overflow = false
                while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
                    if data.count + chunk.count <= limit { data.append(chunk) } else { overflow = true }
                }
                try? handle.close()
                continuation.resume(returning: (data, overflow))
            }
        }
    }
}
private final class DJProcessHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    func start(_ value: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw CancellationError() }
        try value.run(); process = value
    }
    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        if process?.isRunning == true { process?.terminate() }
    }
}
