//
//  Quik2LsnApp.swift
//  Quik2Lsn (iPhone)
//
//  The iPhone app does the heavy lifting for the watch: it transcribes each
//  recording and asks Claude for the summary and action items.
//

import SwiftUI

@main
struct Quik2LsnApp: App {
    @StateObject private var store = MeetingStore.shared
    @StateObject private var processor = MeetingProcessor.shared
    @StateObject private var connectivity = PhoneConnectivityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Activate early: iOS may launch the app in the background just to
        // deliver a recording from the watch.
        PhoneConnectivityManager.shared.activate()
        MeetingProcessor.shared.resumeUnfinished()
    }

    var body: some Scene {
        WindowGroup {
            MeetingListView()
                .environmentObject(store)
                .environmentObject(processor)
                .environmentObject(connectivity)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { processor.resumeUnfinished() }
        }
    }
}
