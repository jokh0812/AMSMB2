//
//  MeetingDetailView.swift
//  Quik2Lsn (iPhone)
//

import SwiftUI

struct MeetingDetailView: View {
    let meetingID: UUID
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var processor: MeetingProcessor
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        if let meeting = store.meeting(id: meetingID) {
            content(for: meeting)
        } else {
            ContentUnavailableView("Meeting Deleted", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func content(for meeting: Meeting) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title).font(.title2.bold())
                    Text("\(meeting.createdAt.formatted(date: .complete, time: .shortened)) · \(meeting.duration.clockString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if meeting.status.isInProgress {
                Section {
                    HStack {
                        ProgressView()
                        Text(meeting.status.label)
                        if meeting.status == .transcribing, processor.currentMeetingID == meeting.id {
                            Spacer()
                            Text(processor.transcriptionProgress, format: .percent.precision(.fractionLength(0)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if meeting.status == .failed {
                Section("Couldn't finish") {
                    Text(meeting.errorMessage ?? "Something went wrong.")
                    Button("Try Again") { processor.retry(meeting.id) }
                }
            }

            if let summary = meeting.summary, !summary.isEmpty {
                Section("Summary") {
                    Text(summary)
                }
            }

            if !meeting.actionItems.isEmpty {
                Section("Action Items") {
                    ForEach(meeting.actionItems) { item in
                        Button {
                            toggle(item, in: meeting)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(item.isDone ? Color.green : priorityColor(item.priority))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.task)
                                        .strikethrough(item.isDone)
                                        .foregroundStyle(item.isDone ? .secondary : .primary)
                                    if let detail = item.detailLine {
                                        Text(detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !meeting.decisions.isEmpty {
                Section("Decisions") {
                    ForEach(meeting.decisions, id: \.self) { Text($0) }
                }
            }

            if !meeting.keyPoints.isEmpty {
                Section("Key Points") {
                    ForEach(meeting.keyPoints, id: \.self) { Label($0, systemImage: "smallcircle.filled.circle") }
                }
            }

            if let transcript = meeting.transcript, !transcript.isEmpty {
                Section("Transcript") {
                    DisclosureGroup("Show transcript") {
                        Text(transcript)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if meeting.status == .ready {
                    ShareLink(item: meeting.markdown, subject: Text(meeting.title))
                }
                Menu {
                    Button {
                        processor.retry(meeting.id)
                    } label: {
                        Label("Regenerate Notes", systemImage: "sparkles")
                    }
                    .disabled(meeting.status.isInProgress || meeting.transcript == nil)

                    Button {
                        processor.retry(meeting.id, retranscribe: true)
                    } label: {
                        Label("Re-transcribe Audio", systemImage: "waveform")
                    }
                    .disabled(meeting.status.isInProgress || !MeetingStore.hasAudio(for: meeting.id))

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this meeting on iPhone and Apple Watch?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(meeting.id)
                PhoneConnectivityManager.shared.send(.delete(meeting.id))
                dismiss()
            }
        }
    }

    private func toggle(_ item: ActionItem, in meeting: Meeting) {
        let updated = store.update(meeting.id) { meeting in
            guard let index = meeting.actionItems.firstIndex(where: { $0.id == item.id }) else { return }
            meeting.actionItems[index].isDone.toggle()
        }
        if let updated { PhoneConnectivityManager.shared.send(.upsert(updated)) }
    }

    private func priorityColor(_ priority: ActionItem.Priority) -> Color {
        switch priority {
        case .high: return .orange
        case .medium: return .accentColor
        case .low: return .secondary
        }
    }
}
