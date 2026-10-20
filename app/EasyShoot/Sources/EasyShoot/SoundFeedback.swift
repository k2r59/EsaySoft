import AppKit
import Combine
import SwiftUI

enum FeedbackSound: String { case copy, capture }

/// Two tiny, cached local sounds. No process, network, polling or queued playback.
@MainActor final class SoundFeedback: ObservableObject {
    @Published var copies: Bool { didSet { defaults.set(copies, forKey: "sound.copies") } }
    @Published var captures: Bool { didSet { defaults.set(captures, forKey: "sound.captures") } }
    private let defaults: UserDefaults
    private let clock: () -> TimeInterval
    private let playback: @MainActor (FeedbackSound) -> Void
    private var lastPlayed = -Double.infinity
    var muted: () -> Bool = { false }

    init(defaults: UserDefaults = .standard, playback: @escaping @MainActor (FeedbackSound) -> Void = { NativeFeedback.play($0) },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults; self.playback = playback; self.clock = clock
        copies = defaults.object(forKey: "sound.copies") as? Bool ?? true
        captures = defaults.object(forKey: "sound.captures") as? Bool ?? true
    }

    func play(_ sound: FeedbackSound) {
        guard !muted(), (sound == .copy ? copies : captures) else { return }
        let now = clock()
        guard now - lastPlayed >= 0.15 else { return }
        lastPlayed = now
        playback(sound)
    }
}

@MainActor private enum NativeFeedback {
    private static var sounds: [FeedbackSound: NSSound] = [:]
    static func play(_ kind: FeedbackSound) {
        if sounds[kind] == nil, let url = Bundle.main.url(forResource: "feedback-\(kind.rawValue)", withExtension: "wav") {
            sounds[kind] = NSSound(contentsOf: url, byReference: false)
            sounds[kind]?.volume = 0.32
        }
        for sound in sounds.values where sound.isPlaying { sound.stop() }
        sounds[kind]?.play()
    }
}

