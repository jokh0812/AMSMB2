//
//  RecordingCoordinator.swift
//  MeetingNotes Watch App
//
//  One place that starts and stops recordings, so the app UI, the complication
//  deep link and the "Start Meeting" App Intent all behave the same.
//

import Foundation
import WatchKit

@MainActor
final class RecordingCoordinator: ObservableObject {
    static let shared = RecordingCoordinator()

    let recorder = Recorder()
    @Published var isShowingRecorder = false
    @Published var alertMessage: String?

    /// Recordings shorter than this are treated as accidental taps.
    private let minimumDuration: TimeInterval = 3

    func startRecording() async {
        if recorder.isRecording {
            isShowingRecorder = true
            return
        }
        guard await recorder.requestPermission() else {
            alertMessage = "Allow microphone access for Meeting Notes in the Watch app on your iPhone (Privacy › Microphone)."
            return
        }
        do {
            try recorder.start()
            WKInterfaceDevice.current().play(.start)
            isShowingRecorder = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard let recording = recorder.stop() else { return }
        WKInterfaceDevice.current().play(.stop)
        isShowingRecorder = false

        guard recording.duration >= minimumDuration else {
            MeetingStore.deleteAudio(for: recording.id)
            alertMessage = "That recording was too short to keep."
            return
        }

        let meeting = Meeting(
            id: recording.id, createdAt: recording.startedAt, duration: recording.duration,
            status: .uploading)
        MeetingStore.shared.upsert(meeting)
        WatchConnectivityManager.shared.sendRecording(meeting)
    }

    func discardRecording() {
        recorder.discard()
        isShowingRecorder = false
    }
}
