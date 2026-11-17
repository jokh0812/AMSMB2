//
//  MeetingDetailView.swift
//  Quik2Lsn Watch App
//

import SwiftUI

struct MeetingDetailView: View {
    let meetingID: UUID
    @EnvironmentObject private var store: MeetingStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        if let meeting = store.meeting(id: meetingID) {
            content(for: meeting)
        } else {
            Text("This meeting was deleted.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(for meeting: Meeting) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title).font(.headline)
                    Text("\(meeting.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(meeting.duration.clockString)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if meeting.status.isInProgress {
                Section {
                    HStack {
                        ProgressView().frame(width: 20)
                        Text(meeting.status.label).font(.footnote)
                    }
                }
            }

            if meeting.status == .failed {
                Section {
                    Text(meeting.errorMessage ?? "Something went wrong.")
                        .font(.footnote)
                    Button("Try Again") {
                        WatchConnectivityManager.shared.retry(meeting)
                    }
                }
            }

            if !meeting.actionItems.isEmpty {
                Section("Action Items") {
                    ForEach(meeting.actionItems) { item in
                        ActionItemRow(item: item) { toggle(item, in: meeting) }
                    }
                }
            }

            if let summary = meeting.summary, !summary.isEmpty {
                Section("Summary") {
                    Text(summary).font(.footnote)
                }
            }

            if !meeting.decisions.isEmpty {
                Section("Decisions") {
                    ForEach(meeting.decisions, id: \.self) { Text($0).font(.footnote) }
                }
            }

            if !meeting.keyPoints.isEmpty {
                Section("Key Points") {
                    ForEach(meeting.keyPoints, id: \.self) { Text($0).font(.footnote) }
                }
            }

            if let transcript = meeting.transcript, !transcript.isEmpty {
                Section {
                    NavigationLink("Transcript") {
                        ScrollView {
                            Text(transcript).font(.footnote).padding(.horizontal, 4)
                        }
                        .navigationTitle("Transcript")
                    }
                }
            }

            Section {
                Button("Delete Meeting", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Notes")
        .confirmationDialog("Delete this meeting on both devices?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                store.delete(meeting.id)
                WatchConnectivityManager.shared.send(.delete(meeting.id))
                dismiss()
            }
        }
    }

    private func toggle(_ item: ActionItem, in meeting: Meeting) {
        let updated = store.update(meeting.id) { meeting in
            guard let index = meeting.actionItems.firstIndex(where: { $0.id == item.id }) else { return }
            meeting.actionItems[index].isDone.toggle()
        }
        if let updated {
            WatchConnectivityManager.shared.send(.upsert(updated))
        }
    }
}

private struct ActionItemRow: View {
    let item: ActionItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? .green : priorityColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.task)
                        .font(.footnote)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                    if let detail = item.detailLine {
                        Text(detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityLabel("\(item.task), \(item.isDone ? "done" : "not done")")
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high: return .orange
        case .medium: return .accentColor
        case .low: return .secondary
        }
    }
}
