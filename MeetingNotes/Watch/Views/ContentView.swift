//
//  ContentView.swift
//  MeetingNotes Watch App
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var coordinator: RecordingCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await coordinator.startRecording() }
                    } label: {
                        Label("New Meeting", systemImage: "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red))
                }

                Section("Meetings") {
                    if store.meetings.isEmpty {
                        Text("Recorded meetings appear here with Claude's summary and action items.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.meetings) { meeting in
                        NavigationLink(value: meeting.id) {
                            MeetingRow(meeting: meeting)
                        }
                    }
                }
            }
            .navigationTitle("Meetings")
            .navigationDestination(for: UUID.self) { id in
                MeetingDetailView(meetingID: id)
            }
        }
        .fullScreenCover(isPresented: $coordinator.isShowingRecorder) {
            RecordingView(coordinator: coordinator, recorder: coordinator.recorder)
        }
        .alert(
            "Meeting Notes",
            isPresented: Binding(
                get: { coordinator.alertMessage != nil },
                set: { if !$0 { coordinator.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.alertMessage ?? "")
        }
    }
}

struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 4) {
                if meeting.status.isInProgress {
                    ProgressView().frame(width: 14, height: 14)
                    Text(meeting.status.label)
                } else if meeting.status == .failed {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Needs attention")
                } else if meeting.openActionItemCount > 0 {
                    Image(systemName: "checklist")
                    Text("\(meeting.openActionItemCount) to do")
                } else {
                    Text(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
