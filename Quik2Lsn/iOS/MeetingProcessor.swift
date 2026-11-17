//
//  MeetingProcessor.swift
//  Quik2Lsn (iPhone)
//
//  Runs each recording through: transcribe on-device → Claude notes → sync to
//  the watch. Meetings are processed one at a time; anything unfinished is
//  picked up again the next time the app runs.
//

import Foundation
import UIKit

@MainActor
final class MeetingProcessor: ObservableObject {
    static let shared = MeetingProcessor()

    @Published private(set) var currentMeetingID: UUID?
    @Published private(set) var transcriptionProgress: Double = 0

    private var queue: [UUID] = []
    private var isRunning = false
    private var store: MeetingStore { .shared }

    func enqueue(_ id: UUID) {
        guard !queue.contains(id), currentMeetingID != id else { return }
        queue.append(id)
        Task { await runQueue() }
    }

    /// Re-queues meetings that were interrupted (e.g. the app was suspended).
    func resumeUnfinished() {
        for meeting in store.meetings.reversed()
        where [.queued, .transcribing, .summarizing].contains(meeting.status) {
            enqueue(meeting.id)
        }
    }

    /// Re-runs failed meetings, e.g. after the API key is added.
    func retryFailed() {
        for meeting in store.meetings where meeting.status == .failed {
            retry(meeting.id)
        }
    }

    /// Runs the pipeline again. Keeps an existing transcript and only redoes the
    /// Claude step unless `retranscribe` is set and the audio is still here.
    func retry(_ id: UUID, retranscribe: Bool = false) {
        guard let meeting = store.meeting(id: id) else { return }
        if retranscribe, MeetingStore.hasAudio(for: id) {
            update(id) { $0.transcript = nil }
        }
        guard meeting.transcript != nil || MeetingStore.hasAudio(for: id) else {
            update(id) {
                $0.status = .failed
                $0.errorMessage = "The audio for this meeting is no longer available."
            }
            return
        }
        update(id) {
            $0.status = .queued
            $0.errorMessage = nil
        }
        enqueue(id)
    }

    private func runQueue() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        while !queue.isEmpty {
            let id = queue.removeFirst()
            currentMeetingID = id
            transcriptionProgress = 0

            // Ask iOS for extra time in case the app was woken in the background
            // by a file arriving from the watch.
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ProcessMeeting")
            await process(id)
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }

            currentMeetingID = nil
        }
    }

    private func process(_ id: UUID) async {
        guard var meeting = store.meeting(id: id), meeting.status != .ready else { return }

        do {
            if meeting.transcript == nil {
                update(id) { $0.status = .transcribing }
                let transcript = try await Transcriber().transcribe(
                    fileURL: MeetingStore.audioURL(for: id)
                ) { [weak self] fraction in
                    Task { @MainActor in self?.transcriptionProgress = fraction }
                }
                meeting = update(id) { $0.transcript = transcript } ?? meeting
            }

            let transcript = meeting.transcript ?? ""
            guard transcript.split(separator: " ").count >= 3 else {
                update(id) {
                    $0.status = .ready
                    $0.summary = "No speech was detected in this recording."
                }
                return
            }

            update(id) { $0.status = .summarizing }
            let notes = try await ClaudeClient().generateNotes(
                transcript: transcript, recordedAt: meeting.createdAt, duration: meeting.duration)

            update(id) { meeting in
                if !notes.title.isEmpty { meeting.title = notes.title }
                meeting.summary = notes.summary
                meeting.keyPoints = notes.keyPoints
                meeting.decisions = notes.decisions
                meeting.actionItems = notes.actionItems.map { item in
                    ActionItem(
                        task: item.task, owner: item.owner, due: item.due,
                        priority: ActionItem.Priority(rawValue: item.priority) ?? .medium)
                }
                meeting.status = .ready
                meeting.errorMessage = nil
            }
        } catch {
            update(id) {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
    }

    /// Updates the store and pushes the new copy to the watch.
    @discardableResult
    private func update(_ id: UUID, _ change: (inout Meeting) -> Void) -> Meeting? {
        let updated = store.update(id, change)
        if let updated { PhoneConnectivityManager.shared.send(.upsert(updated)) }
        return updated
    }
}
