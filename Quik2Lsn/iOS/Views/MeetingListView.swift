//
//  MeetingListView.swift
//  Quik2Lsn (iPhone)
//

import SwiftUI

struct MeetingListView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var processor: MeetingProcessor
    @State private var showingSettings = false
    @State private var hasAPIKey = KeychainStore.apiKey != nil

    var body: some View {
        NavigationStack {
            List {
                if !hasAPIKey {
                    Section {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Add your Claude API key to start getting notes",
                                  systemImage: "key.fill")
                        }
                    }
                }

                ForEach(store.meetings) { meeting in
                    NavigationLink(value: meeting.id) {
                        MeetingListRow(meeting: meeting)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let id = store.meetings[index].id
                        store.delete(id)
                        PhoneConnectivityManager.shared.send(.delete(id))
                    }
                }
            }
            .overlay {
                if store.meetings.isEmpty {
                    ContentUnavailableView(
                        "No Meetings Yet",
                        systemImage: "applewatch",
                        description: Text(
                            "Tap the Quik2Lsn complication on your watch face to record a meeting. "
                                + "It's transcribed here and Claude writes the summary and action items."))
                }
            }
            .navigationTitle("Quik2Lsn")
            .navigationDestination(for: UUID.self) { id in
                MeetingDetailView(meetingID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                hasAPIKey = KeychainStore.apiKey != nil
            }) {
                SettingsView()
            }
        }
    }
}

private struct MeetingListRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title).font(.headline)
            HStack(spacing: 6) {
                Text(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(meeting.duration.clockString)
                Spacer()
                StatusBadge(meeting: meeting)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let meeting: Meeting

    var body: some View {
        if meeting.status.isInProgress {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(meeting.status.label)
            }
        } else if meeting.status == .failed {
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if meeting.openActionItemCount > 0 {
            Label("\(meeting.openActionItemCount) open", systemImage: "checklist")
        }
    }
}
