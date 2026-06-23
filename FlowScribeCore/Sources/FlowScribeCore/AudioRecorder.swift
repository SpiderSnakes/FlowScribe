import Foundation

public protocol AudioRecorder: Sendable {
    func start() throws
    func stop() async -> AudioRecording
}
