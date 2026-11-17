//
//  Recorder.swift
//  Quik2Lsn Watch App
//
//  Records the meeting from the watch microphone as 16 kHz mono AAC — small
//  files that transfer quickly and are plenty for speech recognition.
//

import AVFoundation
import Foundation

@MainActor
final class Recorder: NSObject, ObservableObject {
    struct Recording {
        let id: UUID
        let url: URL
        let startedAt: Date
        let duration: TimeInterval
    }

    enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "The microphone couldn't start recording." }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Input level, 0…1, for the live meter.
    @Published private(set) var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentID: UUID?
    private var startedAt: Date?

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() throws {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let id = UUID()
        let url = MeetingStore.audioURL(for: id)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            try? session.setActive(false)
            throw RecorderError.couldNotStart
        }

        self.recorder = recorder
        currentID = id
        startedAt = Date()
        elapsed = 0
        isRecording = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Stops recording and returns the finished file.
    func stop() -> Recording? {
        guard isRecording, let recorder, let id = currentID, let startedAt else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        cleanUp()
        return Recording(id: id, url: MeetingStore.audioURL(for: id), startedAt: startedAt,
                         duration: duration)
    }

    /// Stops recording and throws the audio away.
    func discard() {
        guard isRecording, let recorder, let id = currentID else { return }
        recorder.stop()
        recorder.deleteRecording()
        MeetingStore.deleteAudio(for: id)
        cleanUp()
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        elapsed = recorder.currentTime
        recorder.updateMeters()
        // averagePower is in dBFS (-160…0); map roughly -50…0 dB onto 0…1.
        let power = recorder.averagePower(forChannel: 0)
        level = max(0, min(1, (power + 50) / 50))
    }

    private func cleanUp() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        currentID = nil
        startedAt = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
