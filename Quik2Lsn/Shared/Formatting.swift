//
//  Formatting.swift
//  Quik2Lsn (shared)
//

import Foundation

extension TimeInterval {
    /// "4:07" or "1:02:45".
    var clockString: String {
        let total = Int(self.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

extension ActionItem {
    /// "Owner · due Friday" or nil when neither is known.
    var detailLine: String? {
        let parts = [owner, due.isEmpty ? "" : "due \(due)"].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension Meeting {
    /// Plain Markdown version of the notes, for sharing or pasting elsewhere.
    var markdown: String {
        var lines: [String] = ["# \(title)", ""]
        lines.append(
            "_\(createdAt.formatted(date: .long, time: .shortened)) · \(duration.clockString)_")
        lines.append("")
        if let summary, !summary.isEmpty {
            lines += ["## Summary", summary, ""]
        }
        if !actionItems.isEmpty {
            lines.append("## Action items")
            for item in actionItems {
                var line = "- [\(item.isDone ? "x" : " ")] \(item.task)"
                if let detail = item.detailLine { line += " (\(detail))" }
                lines.append(line)
            }
            lines.append("")
        }
        if !decisions.isEmpty {
            lines.append("## Decisions")
            lines += decisions.map { "- \($0)" }
            lines.append("")
        }
        if !keyPoints.isEmpty {
            lines.append("## Key points")
            lines += keyPoints.map { "- \($0)" }
            lines.append("")
        }
        if let transcript, !transcript.isEmpty {
            lines += ["## Transcript", transcript]
        }
        return lines.joined(separator: "\n")
    }
}
