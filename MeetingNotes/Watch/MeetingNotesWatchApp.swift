//
//  MeetingNotesWatchApp.swift
//  MeetingNotes Watch App
//

import SwiftUI

/// Deep link the complication opens: tapping it starts a recording right away.
enum DeepLink {
    static let scheme = "meetingnotes"
    static let record = URL(string: "meetingnotes://record")!
}

@main
struct MeetingNotesWatchApp: App {
    @StateObject private var store = MeetingStore.shared
    @StateObject private var coordinator = RecordingCoordinator.shared

    init() {
        WatchConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(coordinator)
                .onOpenURL { url in
                    guard url.scheme == DeepLink.scheme, url.host == "record" else { return }
                    Task { await coordinator.startRecording() }
                }
        }
    }
}
