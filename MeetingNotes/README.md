# Meeting Notes for Apple Watch

Record a meeting from your watch face. Your iPhone transcribes it and Claude
writes a title, summary, key points, decisions and action items, which sync
back to the watch, where you can tick off action items.

## How it works

```
Apple Watch                         iPhone                                 Claude API
───────────                         ──────                                 ──────────
Tap complication ─► record (AAC) ─► WatchConnectivity file transfer
                                    Speech framework transcription
                                    (on-device when supported)
                                    transcript ──────────────────────────► claude-opus-5-5
                                                                           structured JSON notes
                                    notes ◄───────────────────────────────
notes + action items ◄───────────── WatchConnectivity user info
```

- **Why the iPhone transcribes.** Claude's API takes text and images, not
  audio, and watchOS has no speech-to-text API for recordings. The iPhone uses
  Apple's Speech framework, on-device when your language supports it, so the
  audio never leaves your devices. Only the transcript goes to Claude.
- **Claude call.** One Messages API request (`iOS/ClaudeClient.swift`) with
  `output_config.format` set to a JSON schema, so the reply always parses into
  title, summary, key points, decisions and action items (task, owner, due,
  priority). Effort is `medium`. Server-side refusal fallback is on
  (`fallbacks: "default"`), so a request a safety classifier declines is re-run
  on a fallback model instead of failing. Rate limits and overloads are retried.
- **Sync.** Each device keeps its own JSON copy. The newer edit wins, so action
  items you tick off on the watch show up on the iPhone and the other way round.

## Watch-face shortcut

- **Complication** (`WatchWidget/`): circular, corner, rectangular and inline
  styles. Tapping it opens the app and **starts recording immediately**. To add
  it, touch and hold the watch face › Edit › Complications › Meeting Notes.
- **Siri / Shortcuts / Action button**: "Start a meeting in Meeting Notes" and
  "Stop the meeting in Meeting Notes" (`Watch/StartMeetingIntent.swift`). On
  Apple Watch Ultra, assign *Start Meeting Notes* to the Action button.

## Setup

Requires a Mac with Xcode 15 or later, an iPhone on iOS 17+, and an Apple Watch
on watchOS 10+.

1. `brew install xcodegen`, then run `xcodegen generate` in this folder.
2. Open `MeetingNotes.xcodeproj`. In `project.yml` (or each target's Signing
   tab) set your Team and replace `com.example` with your own bundle ID prefix
   in all three bundle IDs and in `WKCompanionAppBundleIdentifier`.
3. Build and run the **MeetingNotes** scheme on your iPhone. The watch app
   installs with it.
4. In the iPhone app, tap the gear and paste a Claude API key from
   console.anthropic.com. Allow speech recognition.
5. Add the complication to your watch face and tap it to start.

If you'd rather not use XcodeGen: create an iOS App project in Xcode, add a
watchOS app target ("Watch App for Existing iOS App") and a Widget Extension
for it, then drag in `iOS/`, `Watch/`, `WatchWidget/` and `Shared/` (Shared
goes in both app targets) and copy the Info.plist keys from `project.yml`.

## Things to know

- **Keep the app open while recording.** Recording keeps going when your wrist
  is down (the audio background mode is on), but if you open another app,
  watchOS may stop it.
- **Processing happens on the iPhone.** iOS gives a background app only a short
  time. For long meetings, if notes stay at "Waiting for iPhone" or
  "Transcribing", open the iPhone app and processing will resume.
- **No speaker labels.** Apple's speech recognizer doesn't tell speakers
  apart. Claude assigns owners to action items only when the conversation makes
  it clear.
- **Costs.** Each meeting is one Claude Opus 5.5 request (about $4 per million
  input tokens and $20 per million output tokens). An hour of conversation is
  roughly 10–15k input tokens, so around 5–15 cents per meeting.
- **Consent.** Check recording-consent laws where you are, and tell
  participants you're recording.

## Files

| Path | What it is |
|---|---|
| `Shared/` | `Meeting` model, JSON store, sync messages, Markdown export (in both apps) |
| `Watch/` | Watch app: recorder, recording screen, meeting list and notes, App Intents |
| `WatchWidget/` | Watch-face complication |
| `iOS/` | iPhone app: transcription, Claude client, processing queue, Keychain, UI |
| `project.yml` | XcodeGen project definition |
