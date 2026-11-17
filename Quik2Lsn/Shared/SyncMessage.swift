//
//  SyncMessage.swift
//  Quik2Lsn (shared)
//
//  Messages exchanged between the watch and the iPhone over WatchConnectivity.
//

import Foundation

enum SyncMessage: Codable {
    /// Create or replace a meeting (the copy with the newer `updatedAt` wins).
    case upsert(Meeting)
    /// Remove a meeting on the other device.
    case delete(UUID)
    /// Watch → iPhone: run the transcription/summary pipeline again.
    case reprocess(UUID)
    /// Watch → iPhone: send me every meeting you have.
    case requestSync

    private static let key = "syncMessage"

    func userInfo() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: data]
    }

    init?(userInfo: [String: Any]?) {
        guard let data = userInfo?[Self.key] as? Data,
              let message = try? JSONDecoder().decode(SyncMessage.self, from: data)
        else { return nil }
        self = message
    }
}
