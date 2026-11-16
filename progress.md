# Progress Log

A running record of what's built, what's next, and the decisions behind it.
Update this file at the end of every work session.

---

## Status: v1.1 in progress (2026-11-15). v1.0.0 is tagged and public on GitHub

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

### Added after v1.0.0
- [x] **Browser / YouTube / any-app audio** via a MediaRemote bridge: `bridge/MediaRemoteAdapter.m` (dylib) loaded into `/usr/bin/perl` by `bridge/mr-bridge.pl`. JSON lines out, commands in on stdin. Confirmed working on macOS 27 with Music; **YouTube in a browser not yet tested by hand**.
- [x] Source app icon in the player (click to open that app); live streams show "LIVE"
- [x] **UI redesign to match Apple's HIG for Live Activities**:
  - Expanded island is now 400 × 150 pt (Apple's is 371-408 wide, max 160 tall); was 500 × 193
  - Continuous (squircle) bottom corners
  - Album art and waveform are single persistent views that glide and grow between compact and expanded ("expanded is an enlarged version of compact")
  - Art top-left and waveform top-right sit beside the camera; title/artist, scrubber, transport below
  - Bouncy spring on open, calmer spring on close
  - Timer view like iPhone's: round pause/cancel buttons left, big orange countdown right
  - Waveform at 20 fps instead of 30 to cut CPU while playing (was ~8-10% of a core; not re-measured)

- [x] **Waveform follows the music**: `Services/AudioTap.swift` uses a Core Audio process tap (macOS 14.2+) on the system output, FFT into 5 bands with auto-gain; bass in the middle bars. Runs only while something is playing. Needs the System Audio Recording permission (`NSAudioCaptureUsageDescription`); falls back to the generic animation when there's no signal. **Not yet tested with real audio.**
- [x] **Explicit "E" badge** next to the title (from `kMRMediaRemoteNowPlayingInfoIsExplicitTrack`; confirmed the flag arrives for Apple Music tracks)
- [x] **One thing plays at a time**: when a different app starts playing, the previous one is paused via `MRMediaRemoteSendCommandToApp` (`pauseapp <bundle>` helper command). Command confirmed not to crash the helper; **the actual Music-to-browser handover not yet tested by hand.**
- [x] Menu toggles: "Waveform Follows Music", "Pause Other Audio When Something New Plays"
- Minimum macOS is now 14.2

### Fixes
- **2026-11-15 · Play/pause flicker + Next pausing the song.** Causes: (1) the button flipped optimistically, then a status query that started *before* the click came back with the old state and flipped it back; (2) `next track` can leave Music paused, and Music briefly reports "Paused" mid-skip. Fix in `NowPlayingService`: explicit `play`/`pause` instead of the `playpause` toggle; a command generation counter that drops stale query results; a short "expected state" window that trusts the user's click over transitional reports; skip resumes playback if it was playing; distributed-notification `Player State` applied instantly.

### Not yet verified on device
- [ ] Hover/click interactions by hand (couldn't screen-record from the terminal)
- [ ] Music permission prompt flow + real track/artwork with Music.app playing
- [ ] Spotify (not installed on the dev machine)

---

## Next ideas (roadmap)
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
- **MediaRemote through perl**: direct MediaRemote calls are blocked for third-party apps since macOS 15.4, but Apple-signed `/usr/bin/perl` is allowed, so the adapter dylib is loaded there. Paths passed to perl must be absolute (hardened runtime rejects relative dylib paths). Artwork changes are tracked with a counter, not `-[NSData hash]` (it collides across JPEGs). When the bridge is alive, AppleScript is not used at all.
- **AppleScript fallback**: Updates are instant through the players' distributed notifications (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`), with a 3 s poll while playing to keep the scrubber in sync. Scripts only run when the player is **already running**, so they never launch it.
- **Mouse pass-through**: the panel is 680×320 but `ignoresMouseEvents` is toggled from a global mouse-move monitor, so only the island itself is clickable (no Accessibility permission needed).
- The build script runs `xattr -cr` before `codesign` because the Desktop folder adds Finder metadata that breaks signing.
- Ad-hoc signing means macOS may re-ask for the Automation permission after each rebuild.
