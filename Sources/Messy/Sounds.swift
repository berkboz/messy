import AVFoundation

/// Short interface sounds, synthesized by design/sfx/make-sfx.swift. Off with one switch in Settings.
enum Sound: String, CaseIterable {
    case scan, found, warn, done, trash, tick

    static let enabledKey = "soundEffects"

    private static var players: [Sound: AVAudioPlayer] = [:]

    var volume: Float { self == .tick ? 0.35 : 0.6 }

    func play() {
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        let player: AVAudioPlayer
        if let cached = Self.players[self] {
            player = cached
        } else {
            guard let url = Bundle.main.url(forResource: rawValue, withExtension: "wav"),
                  let p = try? AVAudioPlayer(contentsOf: url) else { return }
            p.volume = volume
            p.prepareToPlay()
            Self.players[self] = p
            player = p
        }
        player.currentTime = 0
        player.play()
    }
}
