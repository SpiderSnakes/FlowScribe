import AppKit

/// Petits repères sonores système au début/à la fin de l'enregistrement.
enum SoundEffects {
    static func playStart() { NSSound(named: "Pop")?.play() }
    static func playStop() { NSSound(named: "Tink")?.play() }
}
