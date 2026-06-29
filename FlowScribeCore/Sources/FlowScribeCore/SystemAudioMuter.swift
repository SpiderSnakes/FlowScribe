import Foundation
import CoreAudio

/// Contrôle de la sortie audio système (mute, avec le volume comme repli). Toutes les opérations ciblent
/// un `AudioDeviceID` EXPLICITE, capturé une seule fois au début de la dictée : on doit restaurer le
/// périphérique réellement coupé, même si la sortie par défaut change ensuite (casque/HDMI/AirPods).
public protocol SystemOutputControlling: Sendable {
    /// Périphérique de sortie PAR DÉFAUT courant, ou `nil` s'il est introuvable. Résolu une seule fois
    /// au mute pour figer la cible (toutes les autres méthodes opèrent sur cet ID, pas sur le défaut courant).
    func defaultOutputDevice() -> AudioDeviceID?
    /// État de mute courant du périphérique, ou `nil` s'il n'expose pas de mute réglable.
    func currentMute(_ device: AudioDeviceID) -> Bool?
    func setMute(_ muted: Bool, on device: AudioDeviceID)
    /// Volume courant (0…1) du périphérique, ou `nil` si non réglable. Repli quand le mute n'est pas dispo.
    func currentVolume(_ device: AudioDeviceID) -> Float?
    func setVolume(_ volume: Float, on device: AudioDeviceID)
    /// `true` si le périphérique de sortie sert AUSSI d'entrée (casque/AirPods = un seul périphérique
    /// CoreAudio combiné). Couper sa sortie pendant qu'on capte son micro corrompt le flux partagé (HFP
    /// Bluetooth) → audio inexploitable. Dans ce cas on NE coupe PAS. (Les HP intégrés sont un périphérique
    /// distinct du micro intégré → couper reste sûr.)
    func outputAlsoCapturesInput(_ device: AudioDeviceID) -> Bool
}

/// Coupe la sortie audio système (haut-parleurs/casque par défaut) pendant la dictée et restaure
/// EXACTEMENT l'état précédent à la fin — pour qu'aucun son tiers (jeu, vidéo…) ne sorte des
/// haut-parleurs pendant l'enregistrement. N'agit que si l'option est activée dans les Réglages.
@MainActor
public final class SystemAudioMuter {
    /// Ce qu'on a modifié au début de la dictée, pour le restaurer à l'identique. On mémorise l'ID du
    /// périphérique concret coupé : la restauration agit dessus même si la sortie par défaut a changé entre-temps.
    private enum Saved: Equatable {
        case mute(device: AudioDeviceID, was: Bool)
        case volume(device: AudioDeviceID, was: Float)
    }
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
        // Le périphérique cible est résolu UNE SEULE FOIS ici et mémorisé : la restauration agira sur CE
        // périphérique, pas sur la sortie par défaut courante (qui peut changer pendant la dictée si
        // l'utilisateur branche un casque/HDMI ou que des AirPods se connectent).
        guard let dev = output.defaultOutputDevice() else {
            AppLog.warn("Audio", "aucun périphérique de sortie par défaut — mute ignoré")
            return
        }
        // Ne JAMAIS couper la sortie du périphérique qui sert aussi de micro (AirPods/casque) : cela
        // corromprait la capture (flux HFP partagé) → enregistrement inexploitable.
        if output.outputAlsoCapturesInput(dev) {
            AppLog.info("Audio", "sortie = périphérique d'entrée (casque/AirPods) — coupure ignorée (préserve le micro)")
            return
        }
        if let wasMuted = output.currentMute(dev) {
            saved = .mute(device: dev, was: wasMuted)
            if !wasMuted { output.setMute(true, on: dev) }
            AppLog.info("Audio", "sortie système coupée (mute) pour la dictée")
        } else if let vol = output.currentVolume(dev) {
            saved = .volume(device: dev, was: vol)
            if vol > 0 { output.setVolume(0, on: dev) }
            AppLog.info("Audio", "sortie système coupée (volume 0) pour la dictée")
        } else {
            AppLog.warn("Audio", "aucun contrôle de sortie disponible — mute ignoré")
        }
    }

    /// Restaure exactement l'état d'avant la dictée (ne réactive le son que si on l'avait coupé), sur le
    /// périphérique réellement coupé au départ. Si ce périphérique a disparu/n'est plus réglable, l'opération
    /// CoreAudio est ignorée silencieusement (cf. gardes dans `CoreAudioOutput`).
    public func restoreAfterDictation() {
        switch saved {
        case .mute(let device, let was): if !was { output.setMute(false, on: device) }
        case .volume(let device, let was): output.setVolume(was, on: device)
        case nil: return
        }
        AppLog.info("Audio", "sortie système restaurée")
        saved = nil
    }
}

/// Implémentation CoreAudio : agit sur un périphérique de sortie EXPLICITE (élément principal).
public struct CoreAudioOutput: SystemOutputControlling {
    public init() {}

    public func defaultOutputDevice() -> AudioDeviceID? {
        Self.defaultOutputDevice()
    }

    public func currentMute(_ dev: AudioDeviceID) -> Bool? {
        var addr = Self.address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(dev, &addr), Self.isSettable(dev, &addr) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    public func setMute(_ muted: Bool, on dev: AudioDeviceID) {
        var addr = Self.address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(dev, &addr), Self.isSettable(dev, &addr) else { return }
        var value: UInt32 = muted ? 1 : 0
        _ = AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    public func currentVolume(_ dev: AudioDeviceID) -> Float? {
        var addr = Self.address(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(dev, &addr), Self.isSettable(dev, &addr) else { return nil }
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &vol) == noErr else { return nil }
        return Float(vol)
    }

    public func setVolume(_ volume: Float, on dev: AudioDeviceID) {
        var addr = Self.address(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(dev, &addr), Self.isSettable(dev, &addr) else { return }
        var value = Float32(max(0, min(1, volume)))
        _ = AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    public func outputAlsoCapturesInput(_ dev: AudioDeviceID) -> Bool {
        Self.hasInputStreams(dev)
    }

    // MARK: - Helpers CoreAudio

    /// `true` si le périphérique possède au moins un canal d'ENTRÉE (donc combiné I/O : casque/AirPods).
    private static func hasInputStreams(_ dev: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioObjectPropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                    alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, data) == noErr else { return false }
        let abl = UnsafeMutableAudioBufferListPointer(data.assumingMemoryBound(to: AudioBufferList.self))
        for buffer in abl where buffer.mNumberChannels > 0 { return true }
        return false
    }

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
