import XCTest
import AVFoundation
@testable import FlowScribeCore

final class AudioConverterTests: XCTestCase {
    private func makeCAF(_ url: URL, seconds: Double = 1) throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let frames = AVAudioFrameCount(16000 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames   // silence (données nulles) — suffisant pour le test
        // scope interne → le CAF est flushé avant la conversion
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        try file.write(from: buf)
    }

    func test_convertToWAV_producesReadableWAV_andDeletesSource() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ac-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = dir.appending(path: "rec.caf")
        try makeCAF(caf, seconds: 1)

        let wav = AudioConverter.convertToWAV(caf, deleteSourceOnSuccess: true)

        XCTAssertNotNil(wav)
        XCTAssertEqual(wav?.pathExtension, "wav")
        XCTAssertFalse(FileManager.default.fileExists(atPath: caf.path), "le CAF source doit être supprimé après succès")
        let check = try AVAudioFile(forReading: XCTUnwrap(wav))
        XCTAssertGreaterThan(check.length, 0, "le WAV doit contenir l'audio")
    }

    func test_convertToWAV_keepsSource_whenAskedNotToDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ac-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = dir.appending(path: "rec.caf")
        try makeCAF(caf, seconds: 0.5)

        _ = AudioConverter.convertToWAV(caf, deleteSourceOnSuccess: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: caf.path), "le CAF source doit rester si on ne demande pas sa suppression")
    }

    func test_convertToWAV_alreadyWav_returnsSame() {
        let url = FileManager.default.temporaryDirectory.appending(path: "x.wav")
        XCTAssertEqual(AudioConverter.convertToWAV(url, deleteSourceOnSuccess: true), url)
    }
}
