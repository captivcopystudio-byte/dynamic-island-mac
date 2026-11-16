# Progress Log

A running record of what's built, what's next, and the decisions behind it.
Update this file at the end of every work session.

---

## Status: v0.1 working build ✅ (2026-11-15)

### Done
- [x] Swift Package app (SwiftUI + AppKit), builds with **Command Line Tools only** (no Xcode needed)
- [x] `scripts/build-app.sh` → `build/Dynamic Island.app` (Info.plist, generated icon, ad-hoc signed)
- [x] `Makefile`: `make run`, `make install`, `make clean`
- [x] Borderless panel above the menu bar, centred on the notch, on all Spaces and over full-screen apps
- [x] Exact notch size detection (MacBook Air M5: **185 × 33.5 pt**)
- [x] `NotchShape`: concave top flares + rounded bottom, with animated radii
- [x] Spring morph between idle → compact → expanded, with blur/fade content transitions
- [x] Hover to expand (0.12 s delay), collapse on leave or outside click, clicks pass through everywhere else
- [x] Haptic feedback on expand
- [x] **Now Playing** (Apple Music + Spotify): title, artist, artwork, album-tinted waveform, scrubber with seek, play/pause/next/previous
- [x] "Nothing Playing" state with Open Music/Spotify buttons, plus an Automation-permission hint
- [x] **Timer**: 8 presets, countdown live activity, pause/resume/cancel, "Done" alert with chime
- [x] Split island: timer bubble beside music
- [x] **Volume HUD** (CoreAudio listener, follows output device changes)
- [x] **Battery**: charging alert on plug-in, low-battery alert at ≤20%, % + glyph in header
- [x] Menu bar item: toggles for hover, haptics, volume HUD, battery alerts, Launch at Login, Quit
- [x] `--snapshot <dir>` mode renders every state to PNG (README screenshots)
- [x] Verified: idle CPU 0%, ~70 MB RAM

### Not yet verified on device
- [ ] Hover/click interactions by hand (couldn't screen-record from the terminal)
- [ ] Music permission prompt flow + real track/artwork with Music.app playing
- [ ] Spotify (not installed on the dev machine)

---

## Next ideas (roadmap)
- [ ] **Browser / any-app now playing** (YouTube, etc.) via the `mediaremote-adapter` approach (Perl-hosted MediaRemote) since macOS 15.4 blocks direct MediaRemote access
- [ ] Brightness HUD (DisplayServices private API)
- [ ] Calendar: next event + "starting in 5 min" live activity (EventKit)
- [ ] AirPods / Bluetooth connect animation with battery levels
- [ ] File shelf: drag files onto the notch to hold them temporarily
- [ ] Clipboard history tab
- [ ] Swipe gestures on the island (two-finger swipe = next/prev track)
- [ ] Settings window (SwiftUI) instead of only the menu
- [ ] Custom timer duration input
- [ ] Notarized release + GitHub Releases download (needs Apple Developer account)
- [ ] Homebrew cask

---

## Decisions & gotchas
- **No `@State` in views**: on the macOS 27 SDK, `@State` is a macro and the Command Line Tools don't ship the SwiftUI macro plugin. Views use small `ObservableObject` holders with `@StateObject` instead (`HoverState`, `ScrubState`). Keep this rule unless the project moves to full Xcode.
- **Swift language mode 5** (`swift-tools-version:5.10`) to avoid Swift 6 strict-concurrency churn.
- **AppleScript, not MediaRemote**: MediaRemote is blocked for third-party apps since macOS 15.4. Updates are instant through the players' distributed notifications (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`), with a 3 s poll while playing to keep the scrubber in sync. Scripts only run when the player is **already running**, so they never launch it.
- **Mouse pass-through**: the panel is 680×320 but `ignoresMouseEvents` is toggled from a global mouse-move monitor, so only the island itself is clickable (no Accessibility permission needed).
- The build script runs `xattr -cr` before `codesign` because the Desktop folder adds Finder metadata that breaks signing.
- Ad-hoc signing means macOS may re-ask for the Automation permission after each rebuild.
