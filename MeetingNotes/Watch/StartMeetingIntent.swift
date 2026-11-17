//
//  StartMeetingIntent.swift
//  MeetingNotes Watch App
//
//  "Start Meeting" for Siri, the Shortcuts app, Smart Stack and — on Apple
//  Watch Ultra — the Action button (Settings › Action Button › Shortcut).
//

import AppIntents

struct StartMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Meeting Notes"
    static var description = IntentDescription(
        "Starts recording a meeting. Claude summarizes it and lists the action items when you stop.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await RecordingCoordinator.shared.startRecording()
        return .result()
    }
}

struct StopMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Meeting Notes"
    static var description = IntentDescription("Stops the current meeting recording and sends it for notes.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCoordinator.shared.stopRecording()
        return .result()
    }
}

struct MeetingNotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMeetingIntent(),
            phrases: [
                "Start a meeting in \(.applicationName)",
                "Record a meeting with \(.applicationName)",
                "Take meeting notes with \(.applicationName)",
            ],
            shortTitle: "Start Meeting",
            systemImageName: "mic.circle.fill")
        AppShortcut(
            intent: StopMeetingIntent(),
            phrases: [
                "Stop the meeting in \(.applicationName)",
                "End meeting notes in \(.applicationName)",
            ],
            shortTitle: "Stop Meeting",
            systemImageName: "stop.circle.fill")
    }
}
