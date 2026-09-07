# Project Lumina — Release Verification TODO

Last reviewed: 2026-09-07

## Reported app issues

- [x] Video surface must not render before initialization; prevent audio from outrunning the visible surface.
- [x] Video close/back must stop playback deterministically and invalidate in-flight initialization.
- [x] PiP entry must fall back to the in-app mini-player when the OS refuses PiP.
- [x] Dashboard subjects retry after reconnect and fall back to cached/local catalog subjects.
- [x] Add a dedicated Downloads entry to the Dashboard.
- [x] Make the Dashboard title fit-aware; never ellipsize the Project Lumina title.
- [x] Make back-to-exit a two-second state machine with explicit expiry.
- [x] Courses Browse reloads catalog data and clears stale course errors.
- [x] Separate Saved resources from Downloads; downloads do not imply saving.
- [x] Wiki download badges update immediately after a download completes.
- [x] Quiz answer-index grading is normalized correctly and post-submit results show server grading/correct answers.
- [x] Preserve study-time seconds and format as seconds/minutes/hours at presentation time.
- [x] Pause downloads on confirmed hub outage and resume partial files after reconnect.
- [x] PiP capability initialization is race-safe; immediate taps no longer silently fail while capability detection is still running.

## Remaining release verification

- [ ] Verify video first-frame/audio synchronization on physical Android devices (low-end device + network stream + local file). CI cannot prove decoder/texture timing.
- [ ] Verify OS PiP custom controls on physical Android devices across supported Android versions.
- [ ] Verify PiP expansion/return behavior using the system PiP UI; Android does not expose a generic `exitPictureInPictureMode()` API.
- [ ] Verify the deployed Debian server is running the same Git commit as `main` (requires access to the deployed host; GitHub alone cannot compare remote filesystem mtimes).
- [ ] Run end-to-end manual tests for: Dashboard subjects, Browse Courses, Downloads vs Saved, Wiki download state, Back-to-exit expiry, quiz review, and study-time formatting.
- [ ] Keep full CI green after all release changes.
