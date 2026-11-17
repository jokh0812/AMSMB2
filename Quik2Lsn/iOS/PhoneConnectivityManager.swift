//
//  PhoneConnectivityManager.swift
//  Quik2Lsn (iPhone)
//
//  Receives recordings from the watch and sends notes back.
//

import Foundation
import WatchConnectivity

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneConnectivityManager()

    @Published private(set) var isWatchAppInstalled = false

    private var store: MeetingStore { .shared }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ message: SyncMessage) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isWatchAppInstalled
        else { return }
        session.transferUserInfo(message.userInfo())
    }

    fileprivate func didActivate(watchAppInstalled: Bool) {
        isWatchAppInstalled = watchAppInstalled
    }

    fileprivate func receivedRecording(_ meeting: Meeting) {
        if let existing = store.meeting(id: meeting.id), existing.status == .ready { return }
        var queued = meeting
        queued.status = .queued
        queued.errorMessage = nil
        queued.updatedAt = Date()
        store.upsert(queued)
        send(.upsert(queued))
        MeetingProcessor.shared.enqueue(meeting.id)
    }

    fileprivate func handle(_ message: SyncMessage) {
        switch message {
        case .upsert(let meeting):
            // Edits from the watch (e.g. ticking off an action item).
            store.upsert(meeting, onlyIfNewer: true)
        case .delete(let id):
            store.delete(id)
        case .reprocess(let id):
            MeetingProcessor.shared.retry(id)
        case .requestSync:
            for meeting in store.meetings.prefix(50) {
                send(.upsert(meeting))
            }
        }
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let installed = session.isWatchAppInstalled
        Task { @MainActor in self.didActivate(watchAppInstalled: installed) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to a different watch; reconnect to it.
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let installed = session.isWatchAppInstalled
        Task { @MainActor in self.isWatchAppInstalled = installed }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this method returns, so move it synchronously.
        guard case .upsert(let meeting)? = SyncMessage(userInfo: file.metadata) else { return }
        let destination = MeetingStore.audioURL(for: meeting.id)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: MeetingStore.audioDirectory, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: destination)
        do {
            try fileManager.moveItem(at: file.fileURL, to: destination)
        } catch {
            print("PhoneConnectivityManager: couldn't save recording – \(error)")
            return
        }
        Task { @MainActor in self.receivedRecording(meeting) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let message = SyncMessage(userInfo: userInfo) else { return }
        Task { @MainActor in self.handle(message) }
    }
}
