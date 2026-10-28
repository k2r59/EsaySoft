import XCTest
import AppKit
import AVFoundation
import ScreenCaptureKit
import CryptoKit
@testable import EasyPaste

final class RecordingWriterTests: XCTestCase {
    @MainActor func testPreviewPlaysSeeksPausesAndReleasesItsObserver() async throws {
        let folder = try makeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let writer = try RecordingWriter(url: folder.appendingPathComponent("player.mp4"), width: 128, height: 72, systemAudio: false, microphone: false)
        let first = CMClockGetTime(CMClockGetHostTimeClock()), buffer = try pixel(red: 160)
        writer.queue.sync { writer.appendVideo(buffer, at: first) }
        let url = try await writer.finish(at: first + CMTime(seconds: 3, preferredTimescale: 600))
        let player = AVPlayer(url: url)
        var model: VideoPlayback? = VideoPlayback(player: player)
        weak var released: VideoPlayback?
        released = model
        for _ in 0..<100 where model!.duration == 0 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertGreaterThan(model!.duration, 2.9)
        model!.toggle()
        for _ in 0..<100 where model!.position < 0.2 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertGreaterThan(model!.position, 0.1)
        model!.toggle(); XCTAssertFalse(model!.playing); XCTAssertEqual(player.rate, 0)
        model!.scrub(true); model!.position = 2; model!.scrub(false)
        for _ in 0..<100 where model!.scrubbing { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(model!.scrubbing); XCTAssertEqual(player.currentTime().seconds, 2, accuracy: 0.08)
        XCTAssertEqual(player.rate, 0)
        model = nil; XCTAssertNil(released)
        player.replaceCurrentItem(with: nil)
    }
    func testIdleTimerKeepsFourKTrackAliveWithoutNewScreenFrames() async throws {
        let folder = try makeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let writer = try RecordingWriter(url: folder.appendingPathComponent("4k-still.mp4"), width: 3840, height: 2160, systemAudio: false, microphone: false)
        var raw: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 3840, 2160, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &raw), kCVReturnSuccess)
        let buffer = try XCTUnwrap(raw)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 255, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        writer.queue.sync { writer.appendVideo(buffer, at: CMClockGetTime(CMClockGetHostTimeClock())) }
        try await Task.sleep(for: .milliseconds(1200))
        let url = try await writer.finish()
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video), track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize), range = try await track.load(.timeRange)
        XCTAssertEqual(size, CGSize(width: 3840, height: 2160)); XCTAssertGreaterThan(range.end.seconds, 1.1)
        XCTAssertGreaterThanOrEqual(try frameCount(asset, track: track), 4)
        let frame = try await AVAssetImageGenerator(asset: asset).image(at: CMTime(seconds: range.end.seconds - 0.08, preferredTimescale: 600)).image
        XCTAssertGreaterThan(rgb(frame)[0], 220)
    }
    func testStaticScreenRemainsVisibleUntilStopAndSeeksNearEnd() async throws {
        let folder = try makeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let writer = try RecordingWriter(url: folder.appendingPathComponent("still.mp4"), width: 128, height: 72, systemAudio: false, microphone: false)
        let first = CMClockGetTime(CMClockGetHostTimeClock()), red = try pixel(red: 255)
        writer.queue.sync { writer.appendVideo(red, at: first) }
        let url = try await writer.finish(at: first + CMTime(seconds: 4, preferredTimescale: 600))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let range = try await track.load(.timeRange)
        XCTAssertGreaterThanOrEqual(range.end.seconds, 3.98)
        let generator = AVAssetImageGenerator(asset: asset)
        for time in [0.0, 1.5, 3.85] {
            let result = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            let rgb = rgb(result.image); XCTAssertGreaterThan(rgb[0], 210); XCTAssertLessThan(rgb[2], 35)
        }
        let count = try frameCount(asset, track: track)
        XCTAssertGreaterThanOrEqual(count, 2)
    }
    func testChangingScreenHasDistinctFramesAndEndsWithLastImage() async throws {
        let folder = try makeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let writer = try RecordingWriter(url: folder.appendingPathComponent("motion.mp4"), width: 128, height: 72, systemAudio: false, microphone: false)
        let first = CMClockGetTime(CMClockGetHostTimeClock())
        for (time, red) in [(0.0, UInt8(20)), (0.3, 120), (0.7, 240)] {
            let buffer = try pixel(red: red)
            writer.queue.sync { writer.appendVideo(buffer, at: first + CMTime(seconds: time, preferredTimescale: 600)) }
            try await Task.sleep(for: .milliseconds(30))
        }
        let url = try await writer.finish(at: first + CMTime(seconds: 1.2, preferredTimescale: 600))
        let asset = AVURLAsset(url: url), generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        var reds: [Int] = []
        for time in [0.0, 0.3, 0.7] {
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            reds.append(Int(rgb(image)[0]))
        }
        XCTAssertLessThan(reds[0], 60); XCTAssertGreaterThan(reds[1] - reds[0], 50); XCTAssertGreaterThan(reds[2] - reds[1], 50)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertGreaterThanOrEqual(try frameCount(asset, track: XCTUnwrap(tracks.first)), 4)
    }
    func testMicrophoneAndSystemSoundAreMixedIntoOneAudibleTrack() async throws {
        let folder = try makeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let writer = try RecordingWriter(url: folder.appendingPathComponent("sound.mp4"), width: 128, height: 72, systemAudio: true, microphone: true)
        let first = CMClockGetTime(CMClockGetHostTimeClock()), buffer = try pixel(red: 180)
        writer.queue.sync { writer.appendVideo(buffer, at: first) }
        for index in 0..<15 {
            let time = first + CMTime(value: Int64(index * 4800), timescale: 48000)
            let system = try audio(at: time, channels: 2, frequency: 440), microphone = try audio(at: time, channels: 1, frequency: 880)
            writer.queue.sync { writer.appendAudio(system, type: .audio); writer.appendAudio(microphone, type: .microphone) }
            try await Task.sleep(for: .milliseconds(15))
        }
        let url = try await writer.finish(at: first + CMTime(seconds: 1.5, preferredTimescale: 600))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let data = try decodedAudio(asset, track: XCTUnwrap(tracks.first))
        XCTAssertGreaterThan(data.count, 24000)
        for frequency in [440.0, 880.0] { XCTAssertGreaterThan(amplitude(data, frequency: frequency), 0.015, "Both sources must survive mixing") }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let videoRange = try await XCTUnwrap(videoTracks.first).load(.timeRange)
        XCTAssertGreaterThanOrEqual(videoRange.end.seconds, 1.48)
    }
    func testNoFramesFailsInsteadOfPublishingEmptyVideo() async throws {
        let folder = try makeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let writer = try RecordingWriter(url: folder.appendingPathComponent("empty.mp4"), width: 128, height: 72, systemAudio: false, microphone: false)
        do { _ = try await writer.finish(); XCTFail("Empty recording was accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("image")) }
    }
    func testCancelRemovesAbandonedFileAndRejectsFinish() async throws {
        let folder = try makeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("cancelled.mp4")
        let writer = try RecordingWriter(url: url, width: 128, height: 72, systemAudio: false, microphone: false)
        let frame = try pixel(red: 120)
        writer.queue.sync { writer.appendVideo(frame, at: CMClockGetTime(CMClockGetHostTimeClock())) }
        writer.cancel(removeFile: true); writer.queue.sync { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        do { _ = try await writer.finish(); XCTFail("Cancelled recording must not be published") } catch { }
    }
    func testAudioBeforeFirstVideoFrameIsDiscardedAndTimestampsRebased() throws {
        let epoch = CMTime(seconds: 10, preferredTimescale: 48000)
        XCTAssertNil(RecordingWriter.retime(try audio(at: epoch - CMTime(seconds: 1, preferredTimescale: 48000), channels: 1, frequency: 440), relativeTo: epoch))
        let sample = try XCTUnwrap(RecordingWriter.retime(try audio(at: epoch + CMTime(seconds: 2, preferredTimescale: 48000), channels: 1, frequency: 440), relativeTo: epoch))
        XCTAssertEqual(sample.presentationTimeStamp.seconds, 2, accuracy: 0.0001)
    }
    func testOverlayGeometryStaysOnSelectedScreenAndCameraWithinArea() {
        for screen in [CGRect(x: 0, y: 0, width: 5120, height: 1440), CGRect(x: -2560, y: -300, width: 2560, height: 1440)] {
            for area in [screen, CGRect(x: screen.minX + 100, y: screen.minY + 100, width: 500, height: 300)] {
                for corner in CameraCorner.allCases { XCTAssertTrue(area.contains(RecordingOverlayGeometry.cameraFrame(in: area, corner: corner))) }
                XCTAssertTrue(screen.contains(RecordingOverlayGeometry.toolbarFrame(area: area, screen: screen, size: CGSize(width: 470, height: 68))))
            }
        }
    }
    private func makeFolder() throws -> URL { let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true); return f }
    private func pixel(red: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 128, 72, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let b = try XCTUnwrap(buffer); CVPixelBufferLockBaseAddress(b, []); defer { CVPixelBufferUnlockBaseAddress(b, []) }
        let bytes = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(b)
        for y in 0..<72 { for x in 0..<128 { let i = y * stride + x * 4; bytes[i] = 0; bytes[i+1] = 0; bytes[i+2] = red; bytes[i+3] = 255 } }
        return b
    }
    private func rgb(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { p in let c = CGContext(data: p.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!; c.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1)) }
        return bytes
    }
    private func frameCount(_ asset: AVAsset, track: AVAssetTrack) throws -> Int {
        let reader = try AVAssetReader(asset: asset), output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); XCTAssertTrue(reader.startReading()); var count = 0
        while let sample = output.copyNextSampleBuffer() { if sample.imageBuffer != nil { count += 1 } }
        XCTAssertEqual(reader.status, .completed); return count
    }
    private func audio(at time: CMTime, channels: Int, frequency: Double) throws -> CMSampleBuffer {
        let count = 4800
        var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: UInt32(channels * 4), mFramesPerPacket: 1, mBytesPerFrame: UInt32(channels * 4), mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format), noErr)
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: count * channels * 4, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: count * channels * 4, flags: 0, blockBufferOut: &block), noErr)
        var values = (0..<(count * channels)).map { Float(0.2 * sin(2 * Double.pi * frequency * Double($0 / channels) / 48000)) }
        values.withUnsafeMutableBytes { XCTAssertEqual(CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: $0.count), noErr) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: time, decodeTimeStamp: .invalid), sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
    private func decodedAudio(_ asset: AVAsset, track: AVAssetTrack) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false])
        reader.add(output); XCTAssertTrue(reader.startReading()); var values: [Float] = []
        while let sample = output.copyNextSampleBuffer(), let block = sample.dataBuffer {
            let size = CMBlockBufferGetDataLength(block); var part = [Float](repeating: 0, count: size / 4)
            part.withUnsafeMutableBytes { XCTAssertEqual(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!), noErr) }; values += part
        }
        XCTAssertEqual(reader.status, .completed); return values
    }
    private func amplitude(_ samples: [Float], frequency: Double) -> Double {
        let n = min(samples.count, 48000), values = samples.prefix(n)
        var re = 0.0, im = 0.0
        for (i, value) in values.enumerated() { let angle = 2 * Double.pi * frequency * Double(i) / 48000; re += Double(value) * cos(angle); im += Double(value) * sin(angle) }
        return hypot(re, im) * 2 / Double(max(1, n))
    }
}

@MainActor final class ImageVariantTests: XCTestCase {
    func testConcurrentMetadataChangesDoNotAffectSavedImageVariant() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        let history = History(vault: vault, monitor: false, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        defer { history.stopMonitoring(); try? FileManager.default.removeItem(at: folder) }
        let original = try await history.saveImage(DemoArtwork.png())
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let png = try CaptureImage.png(XCTUnwrap(context.makeImage()))
        var started = false
        let replacement = Task { @MainActor in started = true; return try await history.saveImage(png, parent: original) }
        while !started { await Task.yield() }
        let board = UUID()
        history.mutate(original.id) { $0.title = "Renommée pendant l’annotation"; $0.boards = [board]; $0.pinned = true }
        let result = try await replacement.value
        await history.flush()
        let reloaded = try await history.fullClip(result)
        XCTAssertEqual(reloaded.imageData, png)
        XCTAssertEqual(reloaded.fingerprint, Clip.fingerprint(reloaded.payload))
        XCTAssertNotEqual(reloaded.id, original.id); XCTAssertFalse(reloaded.pinned)
        let source = try await history.fullClip(original)
        XCTAssertEqual(source.title, "Renommée pendant l’annotation"); XCTAssertEqual(source.boards, [board]); XCTAssertTrue(source.pinned)
        XCTAssertEqual(source.imageData, DemoArtwork.png())
        XCTAssertEqual(history.clips.first?.fingerprint, reloaded.fingerprint)
    }
    func testImageSaveAlwaysPreservesOriginalAndEarlierVariants() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        let history = History(vault: vault, monitor: false, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        defer { history.stopMonitoring(); try? FileManager.default.removeItem(at: folder) }
        let original = try await history.saveImage(DemoArtwork.png())
        let copy = try await history.saveImage(DemoArtwork.png(), parent: original)
        let board = UUID(); history.mutate(original.id) { $0.pinned = true; $0.boards = [board]; $0.title = "Mon image"; $0.ocr = "ancien texte confidentiel" }; await history.flush()
        let old = try await history.fullClip(original)
        history.surface = "shelf"; history.openPreview(old)
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let newPNG = try CaptureImage.png(XCTUnwrap(context.makeImage()))
        let result = try await history.saveImage(newPNG, parent: old), reloaded = try await history.fullClip(result)
        XCTAssertEqual(history.clips.count, 3); XCTAssertNotEqual(reloaded.id, original.id); XCTAssertEqual(reloaded.parentID, original.id)
        XCTAssertFalse(reloaded.pinned); XCTAssertEqual(reloaded.boards, [board]); XCTAssertEqual(reloaded.ocr, "")
        let source = try await history.fullClip(old)
        XCTAssertEqual(source.payload, old.payload); XCTAssertEqual(source.date, old.date); XCTAssertEqual(source.title, old.title)
        XCTAssertTrue(source.pinned); XCTAssertEqual(source.ocr, old.ocr)
        XCTAssertEqual(reloaded.imageData, newPNG); XCTAssertEqual(reloaded.byteCount, newPNG.count)
        XCTAssertEqual(reloaded.imageMetadata?.dimensions, "64 × 64 px")
        XCTAssertEqual(history.shelfPreview?.fingerprint, old.fingerprint, "The source preview must keep the original raster")
        XCTAssertEqual(history.shelfPreview?.imageMetadata, old.imageMetadata)
        let untouched = try await history.fullClip(copy); XCTAssertEqual(untouched.imageData, old.imageData)
        let repeated = try await history.saveImage(newPNG, parent: old)
        XCTAssertNotEqual(repeated.id, result.id); XCTAssertEqual(history.clips.count, 4)
        do { _ = try await history.saveImage(Data("invalid".utf8), parent: result); XCTFail("Invalid image must be rejected") } catch { }
        let afterFailure = try await history.fullClip(result); XCTAssertEqual(afterFailure.imageData, newPNG)
        await history.flush()
    }
}
