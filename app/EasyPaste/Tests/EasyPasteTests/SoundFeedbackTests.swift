import XCTest
import AppKit
@testable import EasyPaste

@MainActor final class SoundFeedbackTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        suite = "EasyPaste.sounds.tests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testSettingsAreIndependentAndPersist() {
        var played: [FeedbackSound] = []
        let sounds = SoundFeedback(defaults: defaults, playback: { played.append($0) })
        sounds.copies = false
        sounds.play(.copy); sounds.play(.capture)
        XCTAssertEqual(played, [.capture])
        let restored = SoundFeedback(defaults: defaults, playback: { _ in })
        XCTAssertFalse(restored.copies); XCTAssertTrue(restored.captures)
        restored.captures = false
        XCTAssertFalse(SoundFeedback(defaults: defaults, playback: { _ in }).captures)
    }

    func testBurstDoesNotQueueOrDoublePlayAndRecordingIsSilent() {
        var now: TimeInterval = 1
        var played: [FeedbackSound] = []
        let sounds = SoundFeedback(defaults: defaults, playback: { played.append($0) }, clock: { now })
        sounds.play(.capture)
        for _ in 0..<100 { sounds.play(.copy) }
        XCTAssertEqual(played, [.capture])
        now += 1; sounds.muted = { true }
        sounds.play(.copy); sounds.play(.capture)
        XCTAssertEqual(played, [.capture])
        sounds.muted = { false }; sounds.play(.copy)
        XCTAssertEqual(played, [.capture, .copy])
    }

    func testGeneratedSoundsAreShortUnclippedAndLoadable() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/EasyPaste/Resources")
        for name in ["copy", "capture"] {
            let url = resources.appendingPathComponent("feedback-\(name).wav")
            let data = try Data(contentsOf: url)
            XCTAssertLessThan(data.count, 8_000)
            let pcm = [UInt8](data.dropFirst(44))
            let peak = stride(from: 0, to: pcm.count - 1, by: 2).map {
                abs(Int(Int16(bitPattern: UInt16(pcm[$0]) | UInt16(pcm[$0 + 1]) << 8)))
            }.max() ?? 0
            XCTAssertLessThan(peak, 25_000)
            XCTAssertGreaterThan(peak, 1_000)
            let sound = try XCTUnwrap(NSSound(contentsOf: url, byReference: false))
            XCTAssertGreaterThan(sound.duration, 0.04)
            XCTAssertLessThan(sound.duration, 0.2)
        }
    }
}
