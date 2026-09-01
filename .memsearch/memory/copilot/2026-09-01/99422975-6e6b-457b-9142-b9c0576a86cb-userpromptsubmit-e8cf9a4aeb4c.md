# Copilot user prompt

- Captured at: 2026-09-01T17:08:57.887000Z
- Copilot session: `99422975-6e6b-457b-9142-b9c0576a86cb`
- Event: `UserPromptSubmit`

You are the scoped dev agent for the macbar project (a macOS menubar app controlling speaker + microphone volume). Implement the approved v0.2.0 feature: a REAL sound-level VU meter driving the popover's level bars.

## Working directory (IMPORTANT)
Work ONLY inside the git worktree: /Users/edward_oo/temp/macbar-wt/vu-meter (branch feat-vu-meter, already checked out).
Do NOT touch /Users/edward_oo/temp/macbar (main checkout) except reading docs for context. NEVER push.

## Read first
- /Users/edward_oo/temp/macbar/PLAN.md (SOT; see the v0.2.0 section — your scope is exactly this)
- /Users/edward_oo/temp/macbar/AGENTS.md and /Users/edward_oo/temp/macbar/docs/AI-DEVELOPMENT.md
- Existing code in the worktree Sources/macbar/ (4 files: main.swift, AppDelegate.swift, AudioController.swift, PopoverView.swift)

## Feature spec (approved by user 2026-09-02)
1. REAL loudness drives the level bars in the popover (both Speaker and Microphone rows). Bar must move only with actual sound, decay to zero when silent.
2. Microphone: AVAudioEngine input tap. Compute RMS level (~30-60fps), publish to UI. Requesting mic permission triggers the TCC prompt on first use: add `NSMicrophoneUsageDescription` ("macbar needs microphone access to show the live input level.") to the Info.plist heredoc inside Scripts/make-app.sh. Handle denied permission: publish a `micPermissionDenied` state; UI falls back to set-volume mode (current behavior) without crashing.
3. Speaker/system output: CoreAudio Process Tap API (`AudioHardwareCreateProcessTap`), macOS 14.4+ only, gated with `if #available(macOS 14.4, *)` (deployment target stays macOS 13). Sketch: create a process tap description (pid 0 = all processes, tap point post-mix/post-effects), create it via AudioHardwareCreateProcessTap; create a PRIVATE aggregate device whose sub-devices include the tap (kAudioSubTapUIDKey / tapList dictionary); attach an IOProc (AudioDeviceCreateIOProcID) on the aggregate and start it (AudioDeviceStart); in the IO callback compute RMS from the AudioBufferList; destroy/stop everything when the popover closes. IMPORTANT: reference Apple's official sample "Capturing system audio with Core Audio taps" (WWDC24 / developer.apple.com) — search the web if API details are fuzzy. The first tap activation shows a system consent dialog; handle the user declining by falling back to set-volume mode.
4. Level bars switch source: real loudness when metering is active and permitted; otherwise fall back to current set-volume behavior (v0.1.1 semantics). Both bars decay smoothly (e.g., attack fast, release ~0.2-0.4s) so it reads like a VU meter.
5. Tap lifecycle: metering runs ONLY while the popover is open; stop the engine/tap when it closes (battery). Keep CPU tiny (downsample before RMS if needed).

## Hard constraints
- Pure SwiftPM, Swift language mode 5 (swift-tools-version:5.9 in Package.swift — do not change), no third-party dependencies, no sandbox entitlements.
- Do not rename existing symbols; keep changes surgical. New files allowed under Sources/macbar/ (e.g., MicLevelMonitor.swift, OutputLevelMonitor.swift).
- The level bar view (VolumeLevelBar in PopoverView.swift) gets its source switched via the audio controller's published state; keep the shimmer sweep left-to-right behavior.
- Conventional commit message, and ABSOLUTELY NO Co-Authored-By or any AI marker in the commit.
- Do NOT modify the version in Scripts/make-app.sh or make-dmg.sh (the human will bump/release).
- Do NOT modify PLAN.md (human owns it).

## Definition of done (verify yourself, in order)
1. `cd /Users/edward_oo/temp/macbar-wt/vu-meter && swift build -c release` — zero errors.
2. `./Scripts/make-app.sh` — succeeds; `codesign --verify --strict build/macbar.app` passes.
3. `swift Scripts/smoke-coreaudio.swift` — 7/7 PASS.
4. Commit everything in the worktree on branch feat-vu-meter.
5. Report: files changed, how each fallback path behaves, what you could NOT verify (you cannot click UI or grant TCC — say so).

If after honest effort the process-tap part cannot compile or is unworkable, implement the mic side fully and the output side as a clean fallback (set-volume mode) with the tap code isolated behind availability checks, and report exactly what failed — partial correct delivery beats a broken build.
