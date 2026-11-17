//
//  ClaudeClient.swift
//  Quik2Lsn (iPhone)
//
//  Turns a transcript into a title, summary, key points, decisions and action
//  items with one call to the Claude Messages API. Swift has no official
//  Anthropic SDK, so this uses the REST API directly via URLSession.
//

import Foundation

struct MeetingNotesResult: Decodable {
    struct Item: Decodable {
        let task: String
        let owner: String
        let due: String
        let priority: String
    }

    let title: String
    let summary: String
    let keyPoints: [String]
    let decisions: [String]
    let actionItems: [Item]

    enum CodingKeys: String, CodingKey {
        case title, summary, decisions
        case keyPoints = "key_points"
        case actionItems = "action_items"
    }
}

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case refused(String?)
    case truncated
    case emptyResponse
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Claude API key in the iPhone app's Settings, then tap Try Again."
        case .http(let status, let message):
            switch status {
            case 401: return "Claude rejected the API key (401). Check it in Settings."
            case 429: return "Claude rate limit reached. Try again in a minute."
            default: return "Claude API error \(status): \(message)"
            }
        case .refused(let explanation):
            return "Claude declined to summarize this meeting" + (explanation.map { ": \($0)" } ?? ".")
        case .truncated:
            return "Claude's response was cut off. Try again."
        case .emptyResponse, .invalidJSON:
            return "Claude returned an unexpected response. Try again."
        }
    }
}

struct ClaudeClient {
    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2026-10-21"
    /// Lets the API re-run the request on a fallback model if a safety
    /// classifier declines it, instead of failing outright.
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    let apiKey: String

    init(apiKey: String? = KeychainStore.apiKey) throws {
        guard let apiKey, !apiKey.isEmpty else { throw ClaudeError.missingAPIKey }
        self.apiKey = apiKey
    }

    func generateNotes(transcript: String, recordedAt: Date, duration: TimeInterval) async throws
        -> MeetingNotesResult
    {
        let userPrompt = """
            Meeting recorded \(recordedAt.formatted(date: .complete, time: .shortened)), \
            length \(duration.clockString).

            <transcript>
            \(transcript)
            </transcript>
            """

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16_000,
            "fallbacks": "default",
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": userPrompt]],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Self.notesSchema] as [String: Any],
            ] as [String: Any],
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        let response = try JSONDecoder().decode(MessagesResponse.self, from: data)

        switch response.stopReason {
        case "refusal": throw ClaudeError.refused(response.stopDetails?.explanation)
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }

        // With output_config.format the reply is a text block of schema-valid JSON.
        guard let text = response.content.first(where: { $0.type == "text" })?.text else {
            throw ClaudeError.emptyResponse
        }
        guard let json = text.data(using: .utf8),
              let notes = try? JSONDecoder().decode(MeetingNotesResult.self, from: json)
        else { throw ClaudeError.invalidJSON }
        return notes
    }

    /// Sends the request, retrying rate limits, overloads and server errors.
    private func send(_ request: URLRequest, maxRetries: Int = 3) async throws -> Data {
        var attempt = 0
        while true {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where attempt < maxRetries
                && [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code)
            {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(pow(2, Double(attempt))) * 1_000_000_000)
                continue
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return data }

            let http = response as? HTTPURLResponse
            let shouldRetry = http?.value(forHTTPHeaderField: "x-should-retry")
                .map { $0 == "true" } ?? (status == 408 || status == 409 || status == 429 || status >= 500)
            if shouldRetry, attempt < maxRetries {
                attempt += 1
                let retryAfter = http?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
                let delay = retryAfter ?? pow(2, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(min(delay, 60) * 1_000_000_000))
                continue
            }

            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error.message
                ?? String(decoding: data, as: UTF8.self)
            throw ClaudeError.http(status: status, message: message)
        }
    }

    // MARK: Prompt and schema

    private static let systemPrompt = """
        You turn meeting transcripts into concise, useful notes for the person who recorded \
        the meeting on their Apple Watch. They will read the notes on a small screen, so \
        favor short, concrete sentences.

        The transcript comes from automatic speech recognition: it has no speaker labels and \
        may contain misheard words. Infer the intended meaning from context, and never invent \
        facts, names, numbers or deadlines that aren't supported by the transcript.

        Produce:
        - title: 3–8 words naming what the meeting was about.
        - summary: 2–5 sentences covering the purpose, main discussion and outcome.
        - key_points: the most important facts or discussion points, one short sentence each \
        (at most 8).
        - decisions: things the group agreed or decided. Empty if none were made.
        - action_items: concrete follow-up tasks that someone committed to or was asked to do. \
        Start each task with a verb. Set owner to the person's name only if the transcript makes \
        it clear (use "Me" when the speaker commits to it themselves), otherwise an empty string. \
        Set due to the deadline as stated ("Friday", "next sprint") or an empty string. Set \
        priority to high for urgent or blocking work, low for nice-to-haves, otherwise medium. \
        Empty if there are no follow-ups.

        If the transcript is empty, too short or not a conversation, say so in the summary and \
        return empty lists.
        """

    private static let notesSchema: [String: Any] = {
        let stringArray: [String: Any] = ["type": "array", "items": ["type": "string"]]
        let actionItem: [String: Any] = [
            "type": "object",
            "properties": [
                "task": ["type": "string"],
                "owner": ["type": "string"],
                "due": ["type": "string"],
                "priority": ["type": "string", "enum": ["high", "medium", "low"]] as [String: Any],
            ] as [String: Any],
            "required": ["task", "owner", "due", "priority"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "summary": ["type": "string"],
                "key_points": stringArray,
                "decisions": stringArray,
                "action_items": ["type": "array", "items": actionItem] as [String: Any],
            ] as [String: Any],
            "required": ["title", "summary", "key_points", "decisions", "action_items"],
            "additionalProperties": false,
        ]
    }()
}

// MARK: - Wire types

private struct MessagesResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }

    struct StopDetails: Decodable {
        let explanation: String?
    }

    let content: [Block]
    let stopReason: String?
    let stopDetails: StopDetails?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case stopDetails = "stop_details"
    }
}

private struct APIErrorResponse: Decodable {
    struct Body: Decodable {
        let type: String
        let message: String
    }

    let error: Body
}
