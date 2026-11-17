//
//  Transcriber.swift
//  Quik2Lsn (iPhone)
//
//  Speech-to-text with Apple's Speech framework. Claude's API takes text, not
//  audio, so the iPhone transcribes first. Recognition runs on-device when the
//  language supports it, which keeps the audio private and has no time limit.
//  Long recordings are split into chunks so server-based recognition (which is
//  limited to about a minute per request) also works.
//

import AVFoundation
import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Allow Speech Recognition for Quik2Lsn in iPhone Settings, then tap Try Again."
        case .recognizerUnavailable:
            return "Speech recognition isn't available right now. Try again shortly."
        }
    }
}

struct Transcriber {
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    func transcribe(
        fileURL: URL, locale: Locale = .current, progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> String {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined { status = await Self.requestAuthorization() }
        guard status == .authorized else { throw TranscriptionError.notAuthorized }

        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable
        else { throw TranscriptionError.recognizerUnavailable }

        let onDevice = recognizer.supportsOnDeviceRecognition
        let chunks = try Self.split(fileURL, chunkSeconds: onDevice ? 300 : 50)
        defer { chunks.forEach { try? FileManager.default.removeItem(at: $0) } }

        var parts: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let text = try await recognize(chunk, with: recognizer, onDevice: onDevice)
            if !text.isEmpty { parts.append(text) }
            progress(Double(index + 1) / Double(chunks.count))
        }
        return parts.joined(separator: " ")
    }

    private func recognize(_ url: URL, with recognizer: SFSpeechRecognizer, onDevice: Bool)
        async throws -> String
    {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = onDevice

        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.run { continuation.resume(returning: result.bestTranscription.formattedString) }
                } else if let error {
                    let nsError = error as NSError
                    // 1110 = "No speech detected" — a silent chunk, not a failure.
                    if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                        once.run { continuation.resume(returning: "") }
                    } else {
                        once.run { continuation.resume(throwing: error) }
                    }
                }
            }
        }
    }

    /// Splits audio into uncompressed chunks of at most `chunkSeconds`.
    private static func split(_ url: URL, chunkSeconds: Double) throws -> [URL] {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let framesPerChunk = AVAudioFrameCount(chunkSeconds * format.sampleRate)
        var urls: [URL] = []

        while input.framePosition < input.length {
            let remaining = AVAudioFrameCount(input.length - input.framePosition)
            let count = min(framesPerChunk, remaining)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { break }
            try input.read(into: buffer, frameCount: count)
            if buffer.frameLength == 0 { break }

            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("chunk-\(UUID().uuidString).caf")
            do {
                // The file is closed when `output` goes out of scope.
                let output = try AVAudioFile(
                    forWriting: chunkURL, settings: format.settings,
                    commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                try output.write(from: buffer)
            }
            urls.append(chunkURL)
        }
        return urls
    }
}

/// Guards a continuation against being resumed twice by the recognition callback.
private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
