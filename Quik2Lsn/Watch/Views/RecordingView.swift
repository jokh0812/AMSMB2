//
//  RecordingView.swift
//  Quik2Lsn Watch App
//

import SwiftUI

struct RecordingView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    @ObservedObject var recorder: Recorder
    @State private var confirmDiscard = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulse ? 0.25 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                Text("Recording")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(recorder.elapsed.clockString)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()

            LevelMeter(level: recorder.level)
                .frame(height: 18)
                .padding(.horizontal)

            Button {
                coordinator.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 4)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    confirmDiscard = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Discard recording")
            }
        }
        .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { coordinator.discardRecording() }
            Button("Keep Recording", role: .cancel) {}
        }
        .interactiveDismissDisabled()
        .onAppear { pulse = true }
    }
}

private struct LevelMeter: View {
    let level: Float
    private let bars = 12

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                let lit = Float(index) / Float(bars) < level
                Capsule()
                    .fill(lit ? Color.red : Color.gray.opacity(0.3))
            }
        }
        .animation(.linear(duration: 0.15), value: level)
        .accessibilityHidden(true)
    }
}
