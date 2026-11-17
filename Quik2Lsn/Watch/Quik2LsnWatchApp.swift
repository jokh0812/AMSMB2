//
//  Quik2LsnWatchApp.swift
//  Quik2Lsn Watch App
//

import SwiftUI

/// Deep link the complication opens: tapping it starts a recording right away.
enum DeepLink {
    static let scheme = "quik2lsn"
    static let record = URL(string: "quik2lsn://record")!
}

@main
struct Quik2LsnWatchApp: App {
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
