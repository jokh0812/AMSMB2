//
//  WatchConnectivityManager.swift
//  Quik2Lsn Watch App
//
//  Sends recordings to the iPhone and merges the notes the iPhone sends back.
//

import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    private var store: MeetingStore { .shared }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Queues the meeting's audio for transfer. WatchConnectivity keeps trying
    /// in the background until the iPhone is reachable.
    func sendRecording(_ meeting: Meeting) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }  // resent on activation
        let url = MeetingStore.audioURL(for: meeting.id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            store.update(meeting.id) {
                $0.status = .failed
                $0.errorMessage = "The recording is no longer on this watch."
            }
            return
        }
        if isTransferring(meeting.id) { return }
        store.update(meeting.id) {
            $0.status = .uploading
            $0.errorMessage = nil
        }
        session.transferFile(url, metadata: SyncMessage.upsert(meeting).userInfo())
    }

    func send(_ message: SyncMessage) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(message.userInfo())
    }

    /// Retry from the watch: resend audio if we still have it, otherwise ask the
    /// iPhone (which keeps the audio) to process it again.
    func retry(_ meeting: Meeting) {
        if MeetingStore.hasAudio(for: meeting.id), meeting.transcript == nil {
            sendRecording(meeting)
        } else {
            store.update(meeting.id) {
                $0.status = .queued
                $0.errorMessage = nil
            }
            send(.reprocess(meeting.id))
        }
    }

    private func isTransferring(_ id: UUID) -> Bool {
        WCSession.default.outstandingFileTransfers.contains {
            if case .upsert(let m)? = SyncMessage(userInfo: $0.file.metadata) { return m.id == id }
            return false
        }
    }

    fileprivate func didActivate() {
        // Resend anything recorded before the session was ready.
        for meeting in store.meetings where meeting.status == .uploading {
            sendRecording(meeting)
        }
        send(.requestSync)
    }

    fileprivate func handle(_ message: SyncMessage) {
        switch message {
        case .upsert(let meeting):
            guard store.upsert(meeting, onlyIfNewer: true) else { return }
            // Once the iPhone has the audio, the watch copy isn't needed.
            if meeting.status != .uploading {
                MeetingStore.deleteAudio(for: meeting.id)
            }
        case .delete(let id):
            store.delete(id)
        case .reprocess, .requestSync:
            break  // iPhone-side messages
        }
    }

    fileprivate func fileTransferFinished(meetingID: UUID, error: Error?) {
        guard let meeting = store.meeting(id: meetingID), meeting.status == .uploading else { return }
        if let error {
            store.update(meetingID) {
                $0.status = .failed
                $0.errorMessage = "Couldn't send the recording to iPhone: \(error.localizedDescription)"
            }
        } else {
            store.update(meetingID) { $0.status = .queued }
            MeetingStore.deleteAudio(for: meetingID)
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.didActivate() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let message = SyncMessage(userInfo: userInfo) else { return }
        Task { @MainActor in self.handle(message) }
    }

    nonisolated func session(
        _ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?
    ) {
        guard case .upsert(let meeting)? = SyncMessage(userInfo: fileTransfer.file.metadata) else {
            return
        }
        Task { @MainActor in self.fileTransferFinished(meetingID: meeting.id, error: error) }
    }
}
