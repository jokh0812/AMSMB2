//
//  Meeting.swift
//  Quik2Lsn (shared by the iPhone and Apple Watch apps)
//

import Foundation

/// Where a meeting is in the record → transcribe → summarize pipeline.
enum MeetingStatus: String, Codable, Hashable {
    /// Audio is on the watch and being sent to the iPhone.
    case uploading
    /// The iPhone has the audio and will process it shortly.
    case queued
    /// The iPhone is converting the audio to text.
    case transcribing
    /// Claude is writing the summary and action items.
    case summarizing
    /// Notes are ready.
    case ready
    /// Something went wrong; see `Meeting.errorMessage`.
    case failed

    var label: String {
        switch self {
        case .uploading: return "Sending to iPhone…"
        case .queued: return "Waiting for iPhone…"
        case .transcribing: return "Transcribing…"
        case .summarizing: return "Claude is summarizing…"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }

    var isInProgress: Bool {
        switch self {
        case .uploading, .queued, .transcribing, .summarizing: return true
        case .ready, .failed: return false
        }
    }
}

struct ActionItem: Codable, Identifiable, Hashable {
    enum Priority: String, Codable, CaseIterable, Hashable {
        case high, medium, low
    }

    var id: UUID
    var task: String
    /// Person responsible, or empty when the conversation didn't say.
    var owner: String
    /// Deadline as spoken in the meeting ("Friday", "end of Q3"), or empty.
    var due: String
    var priority: Priority
    var isDone: Bool

    init(
        id: UUID = UUID(), task: String, owner: String = "", due: String = "",
        priority: Priority = .medium, isDone: Bool = false
    ) {
        self.id = id
        self.task = task
        self.owner = owner
        self.due = due
        self.priority = priority
        self.isDone = isDone
    }
}

struct Meeting: Codable, Identifiable, Hashable {
    var id: UUID
    var createdAt: Date
    /// Last change on either device; the newer copy wins when syncing.
    var updatedAt: Date
    var duration: TimeInterval
    var status: MeetingStatus
    var title: String
    var transcript: String?
    var summary: String?
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [ActionItem]
    var errorMessage: String?

    init(
        id: UUID = UUID(), createdAt: Date = Date(), duration: TimeInterval,
        status: MeetingStatus, title: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = Date()
        self.duration = duration
        self.status = status
        self.title = title ?? Meeting.defaultTitle(for: createdAt)
        self.transcript = nil
        self.summary = nil
        self.keyPoints = []
        self.decisions = []
        self.actionItems = []
        self.errorMessage = nil
    }

    static func defaultTitle(for date: Date) -> String {
        "Meeting · " + date.formatted(date: .abbreviated, time: .shortened)
    }

    var openActionItemCount: Int {
        actionItems.filter { !$0.isDone }.count
    }
}
