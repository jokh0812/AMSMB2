//
//  MeetingStore.swift
//  Quik2Lsn (shared)
//
//  Keeps meetings in a JSON file in the app's Documents folder and audio files
//  in Documents/Audio.
//

import Foundation

@MainActor
final class MeetingStore: ObservableObject {
    static let shared = MeetingStore()

    @Published private(set) var meetings: [Meeting] = []

    private let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("meetings.json")
        try? FileManager.default.createDirectory(
            at: Self.audioDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: Audio files

    nonisolated static var audioDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audio", isDirectory: true)
    }

    nonisolated static func audioURL(for id: UUID) -> URL {
        audioDirectory.appendingPathComponent("\(id.uuidString).m4a")
    }

    nonisolated static func hasAudio(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: audioURL(for: id).path)
    }

    nonisolated static func deleteAudio(for id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(for: id))
    }

    // MARK: Reading

    func meeting(id: UUID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    // MARK: Writing

    /// Inserts or replaces a meeting. With `onlyIfNewer`, an existing copy that
    /// was changed more recently is kept (used when merging synced copies).
    @discardableResult
    func upsert(_ meeting: Meeting, onlyIfNewer: Bool = false) -> Bool {
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            if onlyIfNewer, meetings[index].updatedAt > meeting.updatedAt { return false }
            meetings[index] = meeting
        } else {
            meetings.append(meeting)
        }
        sortAndSave()
        return true
    }

    /// Applies a change and stamps `updatedAt`. Returns the updated meeting.
    @discardableResult
    func update(_ id: UUID, _ change: (inout Meeting) -> Void) -> Meeting? {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return nil }
        change(&meetings[index])
        meetings[index].updatedAt = Date()
        let updated = meetings[index]
        sortAndSave()
        return updated
    }

    func delete(_ id: UUID) {
        meetings.removeAll { $0.id == id }
        Self.deleteAudio(for: id)
        save()
    }

    // MARK: Persistence

    private func sortAndSave() {
        meetings.sort { $0.createdAt > $1.createdAt }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Meeting].self, from: data)
        else { return }
        meetings = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(meetings)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("MeetingStore: failed to save – \(error)")
        }
    }
}
