# Progress Log

A running record of what's built, what's next, and the decisions behind it.
Update this file at the end of every work session.

---

## Status: v1.1.2 (2026-11-16)

- **Repo:** https://github.com/captivcopystudio-byte/dynamic-island-mac (public)
- **Releases:** v1.0.0 (source only), v1.1.0 and v1.1.1 (superseded), **v1.1.2 (latest)**
- **Downloads per release:** `DynamicIsland-Notch.zip` (MacBooks with a notch) and `DynamicIsland-NoNotch.zip` (floating pill)
- **Requires:** macOS 14.2+, Apple silicon
- **Dev machine:** MacBook Air M5, macOS 27, notch 185 × 33.5 pt, Command Line Tools only (no Xcode)

## What the app does today

### The island
- Borderless panel above the menu bar, on all Spaces and over full-screen apps
- **Notch style:** grows out of the hardware notch; expanded content sits fully below the notch
- **Floating pill style** (no notch): capsule detached from the top edge, hidden when idle, all corners rounded when expanded. Toggle in the menu bar: "Floating Pill Style (No Notch)"
- Expanded size 400 pt wide (Apple's is 371-408), continuous corners, bouncy open and calm close
- Hover to expand (0.12 s delay) or click; collapses on leave or outside click; clicks pass through everywhere else
- Haptic feedback on expand

### Now Playing
- Works with **any app**: Apple Music, Spotify, YouTube and other browser audio
- Title, artist, album art (glides from compact into expanded), scrubber with seek, play/pause/next/previous
- Explicit **"E" badge**
- Source app icon in the player; click to open that app. Live streams show "LIVE"
- **One thing plays at a time:** starting audio in another app pauses the previous one (menu toggle)
- **No waveform** (removed at the user's request; see Removed)

### Timer
- 8 presets, countdown in the notch, pause/resume/cancel, "Done" alert with chime
- Timer bubble beside the island while music is showing
- **Clock app timers show in the island** (read-only, with an "open Clock" button)

### Other activities (each has a menu toggle)
- Volume HUD
- Battery: charging alert, low-battery alert at ≤20%, % in the expanded header
- Calendar: countdown when an event is within 10 minutes; Calendar tab with the next two events
- Headphones: name + battery on connect, "Disconnected" on disconnect
- Camera / mic in-use indicator
- Focus and Caps Lock alerts

### Menu bar item
Toggles for: floating pill style, expand on hover, haptics, volume HUD, battery alerts, calendar, headphones, camera/mic, Focus & Caps Lock, pause other audio, Launch at Login. Plus Quit.

---

## Not yet verified by hand

Everything below was checked only in rendered snapshots or by reading system data, never seen working on the real screen:

- [ ] Hover / click / animations on the real notch
- [ ] YouTube (browser) audio showing and being controlled
- [ ] Music-to-browser handover (previous app pausing)
- [ ] **Clock app timer mirroring**: the data format for a *running* timer is assumed (fire date under `$MTTimerDate`; paused = state 2). Only stopped timers were observed. If a Clock timer doesn't appear, read `defaults read com.apple.mobiletimerd MTTimers` while one runs and fix `TimerService.syncWithClockApp()`
- [ ] Calendar countdown with a real event; Calendar "Allow" button flow
- [ ] Headphone connect/disconnect and battery read
- [ ] Camera / mic indicator
- [ ] Focus alert (likely needs Full Disk Access; may not work at all)
- [ ] Caps Lock alert
- [ ] Floating pill style on a Mac that really has no notch
- [ ] Spotify (not installed on the dev machine)
- [ ] CPU while music plays (was 8-10% of a core with the waveform; not re-measured since it was removed)

---

## Removed (do not re-add without asking)

- **Waveform, entirely.** First the audio-reactive version (`AudioTap.swift`, a Core Audio process tap) was removed because macOS showed the "record your system audio" prompt every time music started. Then the user asked for no waveform at all, so `WaveformView` was deleted too. Compact music shows album art only.
- **Focus authorization request** (`INFocusStatusCenter.requestAuthorization`): removed as part of stopping launch-time prompts.

---

## Fix history

- **2026-11-16 · Calendar unreachable while music plays.** The player view replaces the tab bar, and it only had a timer shortcut. It now has timer and calendar shortcuts at the bottom-left (calendar turns red when an event is within 10 minutes). Rule: any new tab needs a shortcut in `MediaPlayerView` too. Not yet in a release (latest is v1.1.2).
- **2026-11-15 · Repeated permission prompts.** Causes: (1) at launch `refresh()` ran the AppleScript fallback before the media helper had reported, triggering "control Music"; AppleScript is now used only if the helper is missing or has failed for good (`bridge.isUsable`). (2) Calendar and Focus access were requested at every launch; Calendar is now requested only from the "Allow" button in the Calendar tab. (3) The app is ad-hoc signed, so every rebuild is a "new app" to macOS and loses earlier grants.
- **2026-11-15 · Notch collisions.** At 400 pt wide the island left only ~77 pt beside the 185 pt notch: the title sat jammed under it and the third tab was hidden behind it. Expanded content now starts below the notch (`contentTop`). Found by drawing the notch into snapshots: `SHOW_NOTCH=1 DynamicIsland --snapshot <dir>`.
- **2026-11-15 · Artwork not updating between albums.** `-[NSData hash]` only looks at the first bytes, which match across JPEGs. The helper now sends a change counter.
- **2026-11-15 · Play/pause flicker + Next pausing the song.** Explicit `play`/`pause` instead of the toggle; stale status results dropped (generation counter); a short window that trusts the user's click over transitional reports; skip resumes playback if it was playing.

---

## Release history

| Version | What changed |
|---|---|
| v1.0.0 | First public version: notch island, Music/Spotify via AppleScript, timer, volume, battery |
| v1.1.0 | Any-app audio (browser/YouTube), Apple-style redesign, E badge, pause previous player, calendar, headphones, camera/mic, Focus/Caps Lock, notch fix, Notch + NoNotch downloads |
| v1.1.1 | Removed the audio-reactive waveform (system audio prompt) |
| v1.1.2 | Waveform removed entirely; Clock app timers in the island; no permission requests at launch |

How to release: bump `VERSION` in `scripts/build-app.sh`, run `make release`, tag, push, then `gh release create <tag> build/release/*.zip`.

---

## Next ideas (roadmap)

- [ ] Stable code-signing identity (Apple Developer account) so permission grants survive updates; also enables notarization
- [ ] Start/pause/cancel Clock app timers from the island (no public API; would need Shortcuts)
- [ ] Brightness HUD (DisplayServices private API)
- [ ] File shelf: drag files onto the notch to hold them temporarily
- [ ] Clipboard history tab
- [ ] Swipe gestures on the island (two-finger swipe = next/previous track)
- [ ] Settings window instead of only the menu
- [ ] Custom timer duration input
- [ ] Homebrew cask
- Not possible: showing the iPhone's Live Activities (Apple provides no API)

---

## Decisions & gotchas

- **Never request a permission at launch.** Ask only when the user clicks something that needs it.
- **Privacy:** commits use the GitHub noreply identity (set in this repo's local git config). Check `git log --format='%ae'` before every push; no personal paths or emails in files.
- **No `@State` in views:** on the macOS 27 SDK, `@State` is a macro and the Command Line Tools don't ship the SwiftUI macro plugin. Views use small `ObservableObject` holders with `@StateObject` (`HoverState`, `ScrubState`).
- **Swift language mode 5** (`swift-tools-version:5.10`) to avoid Swift 6 strict-concurrency churn.
- **MediaRemote through perl:** direct MediaRemote calls are blocked for third-party apps since macOS 15.4, but Apple-signed `/usr/bin/perl` is allowed, so `bridge/MediaRemoteAdapter.m` (dylib) is loaded there by `bridge/mr-bridge.pl`. JSON lines out; commands in on stdin (`play`, `pause`, `next`, `previous`, `seek <s>`, `pauseapp <bundle>`, `refresh`). Paths passed to perl must be absolute.
- **AppleScript is fallback only** (Music/Spotify), used when the helper is missing or has failed more than 5 times. Scripts only run when the player is already running, so they never launch it.
- **Two variants, one codebase:** the downloads differ only in the Info.plist key `DIDefaultStyle` (`auto` / `pill`), which sets the default of the pill-style toggle.
- **Clock timers** are read from the `com.apple.mobiletimerd` preferences (polled every 1.5 s). Read-only.
- **Headphones** are detected from the default audio output's transport type (no Bluetooth permission); battery comes from `system_profiler SPBluetoothDataType -json`.
- **Mouse pass-through:** the panel is 680×320 but `ignoresMouseEvents` is toggled from a global mouse-move monitor, so only the island is clickable (no Accessibility permission).
- **Snapshots:** `DynamicIsland --snapshot <dir>` renders every state to PNG; add `SHOW_NOTCH=1` to draw the physical notch and catch collisions. Always check new layouts with the notch drawn.
- The build script runs `xattr -cr` before `codesign` because the Desktop folder adds Finder metadata that breaks signing.
- **Ad-hoc signing:** every rebuild looks like a new app to macOS, so previously granted permissions are forgotten after an update.
- **Testing caution:** commands sent to the media helper act on the user's real playback. Use read-only probes unless a test needs otherwise, and say so.
