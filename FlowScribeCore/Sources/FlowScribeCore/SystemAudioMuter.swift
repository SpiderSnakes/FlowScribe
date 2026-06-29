import Foundation
import CoreAudio

/// Contrôle de la sortie audio système PAR DÉFAUT (mute, avec le volume comme repli).
public protocol SystemOutputControlling: Sendable {
    /// État de mute courant, ou `nil` si le périphérique n'expose pas de mute réglable.
    func currentMute() -> Bool?
    func setMute(_ muted: Bool)
    /// Volume courant (0…1), ou `nil` si non réglable. Repli quand le mute n'est pas disponible.
    func currentVolume() -> Float?
    func setVolume(_ volume: Float)
}

/// Coupe la sortie audio système (haut-parleurs/casque par défaut) pendant la dictée et restaure
/// EXACTEMENT l'état précédent à la fin — pour qu'aucun son tiers (jeu, vidéo…) ne sorte des
/// haut-parleurs pendant l'enregistrement. N'agit que si l'option est activée dans les Réglages.
@MainActor
public final class SystemAudioMuter {
    /// Ce qu'on a modifié au début de la dictée, pour le restaurer à l'identique.
    private enum Saved: Equatable { case mute(Bool); case volume(Float) }
    private let output: SystemOutputControlling
    private let enabled: Bool
    private var saved: Saved?

    public init(output: SystemOutputControlling = CoreAudioOutput(), enabled: Bool) {
        self.output = output
        self.enabled = enabled
    }

    /// Coupe la sortie (mute si possible, sinon volume à 0), en mémorisant l'état précédent.
    /// Idempotent : un 2ᵉ appel sans restauration ne réécrase pas l'état mémorisé.
    public func muteForDictation() {
        guard enabled, saved == nil else { return }
        if let wasMuted = output.currentMute() {
            saved = .mute(wasMuted)
            if !wasMuted { output.setMute(true) }
            AppLog.info("Audio", "sortie système coupée (mute) pour la dictée")
        } else if let vol = output.currentVolume() {
            saved = .volume(vol)
            if vol > 0 { output.setVolume(0) }
            AppLog.info("Audio", "sortie système coupée (volume 0) pour la dictée")
        } else {
            AppLog.warn("Audio", "aucun contrôle de sortie disponible — mute ignoré")
        }
    }

    /// Restaure exactement l'état d'avant la dictée (ne réactive le son que si on l'avait coupé).
    public func restoreAfterDictation() {
        switch saved {
        case .mute(let was): if !was { output.setMute(false) }
        case .volume(let v): output.setVolume(v)
        case nil: return
        }
        AppLog.info("Audio", "sortie système restaurée")
        saved = nil
    }
}

/// Implémentation CoreAudio : agit sur le périphérique de sortie PAR DÉFAUT (élément principal).
public struct CoreAudioOutput: SystemOutputControlling {
    public init() {}

    public func currentMute() -> Bool? {
        guard let dev = Self.defaultOutputDevice() else { return nil }
        var addr = Self.address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(dev, &addr), Self.isSettable(dev, &addr) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    public func setMute(_ muted: Bool) {
        guard let dev = Self.defaultOutputDevice() else { return }
        var addr = Self.address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(dev, &addr), Self.isSettable(dev, &addr) else { return }
        var value: UInt32 = muted ? 1 : 0
        _ = AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    public func currentVolume() -> Float? {
        guard let dev = Self.defaultOutputDevice() else { return nil }
        var addr = Self.address(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(dev, &addr), Self.isSettable(dev, &addr) else { return nil }
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &vol) == noErr else { return nil }
        return Float(vol)
    }

    public func setVolume(_ volume: Float) {
        guard let dev = Self.defaultOutputDevice() else { return }
        var addr = Self.address(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(dev, &addr), Self.isSettable(dev, &addr) else { return }
        var value = Float32(max(0, min(1, volume)))
        _ = AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    // MARK: - Helpers CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func isSettable(_ dev: AudioDeviceID, _ addr: inout AudioObjectPropertyAddress) -> Bool {
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr && settable.boolValue
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr,
              dev != 0 else { return nil }
        return dev
    }
}
