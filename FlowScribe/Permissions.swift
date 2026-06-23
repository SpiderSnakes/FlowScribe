import AVFoundation
import Speech
import AppKit
import ApplicationServices

enum PermissionState: Sendable, Equatable { case granted, denied, notDetermined }

enum Permissions {
    // MARK: Micro
    static func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }
    @discardableResult
    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
        }
    }

    // MARK: Reconnaissance vocale (requise par SpeechTranscriber)
    static func speechState() -> PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }
    @discardableResult
    static func requestSpeech() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    // MARK: Accessibilité (nécessaire au collage Cmd+V)
    static func accessibilityTrusted() -> Bool { AXIsProcessTrusted() }

    /// Affiche l'invite système d'Accessibilité (propose d'ouvrir les Réglages).
    /// On utilise la valeur littérale de `kAXTrustedCheckOptionPrompt` (global var
    /// non concurrency-safe sous Swift 6).
    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
