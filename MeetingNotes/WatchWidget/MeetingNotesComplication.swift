//
//  MeetingNotesComplication.swift
//  MeetingNotes Complication (watchOS widget extension)
//
//  A watch-face complication that starts a meeting recording with one tap.
//  Add it from the watch face editor (long-press the face › Edit › Complications)
//  or from the Watch app on iPhone.
//

import SwiftUI
import WidgetKit

private let recordURL = URL(string: "meetingnotes://record")!

struct LaunchEntry: TimelineEntry {
    let date: Date
}

struct LaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry { LaunchEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        completion(LaunchEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        // The complication is a static launcher, so it never needs refreshing.
        completion(Timeline(entries: [LaunchEntry(date: Date())], policy: .never))
    }
}

struct MeetingNotesComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .widgetAccentable()
            }
        case .accessoryCorner:
            Image(systemName: "mic.fill")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel("Meeting")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.circle.fill")
                    .font(.title)
                    .widgetAccentable()
                VStack(alignment: .leading) {
                    Text("Meeting Notes").font(.headline)
                    Text("Tap to record").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label("Start Meeting", systemImage: "mic.fill")
        default:
            Image(systemName: "mic.fill")
        }
    }
}

@main
struct MeetingNotesComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MeetingNotesLauncher", provider: LaunchProvider()) { _ in
            MeetingNotesComplicationView()
                .widgetURL(recordURL)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Start Meeting")
        .description("Tap to start recording meeting notes.")
        .supportedFamilies([
            .accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline,
        ])
    }
}
