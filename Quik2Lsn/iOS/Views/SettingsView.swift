//
//  SettingsView.swift
//  Quik2Lsn (iPhone)
//

import Speech
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectivity: PhoneConnectivityManager
    @State private var apiKey = KeychainStore.apiKey ?? ""
    @State private var speechStatus = SFSpeechRecognizer.authorizationStatus()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("Create a key at console.anthropic.com. It's stored in the iPhone Keychain and only sent to api.anthropic.com. Notes are written by \(ClaudeClient.model).")
                }

                Section("Speech Recognition") {
                    switch speechStatus {
                    case .authorized:
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .notDetermined:
                        Button("Allow Speech Recognition") {
                            Task { speechStatus = await Transcriber.requestAuthorization() }
                        }
                    default:
                        Button("Open Settings to Allow") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                Section("Apple Watch") {
                    LabeledContent("Watch app",
                                   value: connectivity.isWatchAppInstalled ? "Installed" : "Not installed")
                }

                Section("Watch Face Shortcut") {
                    Text("On your watch, touch and hold the watch face › Edit › Complications, then choose Quik2Lsn. One tap on it starts recording.")
                    Text("You can also say \"Start a meeting in Quik2Lsn\" to Siri, or on Apple Watch Ultra assign the Start Quik2Lsn shortcut to the Action button.")
                }
                .font(.callout)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                }
            }
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = trimmed != (KeychainStore.apiKey ?? "")
        KeychainStore.apiKey = trimmed.isEmpty ? nil : trimmed
        if changed, !trimmed.isEmpty {
            MeetingProcessor.shared.retryFailed()
        }
        dismiss()
    }
}
