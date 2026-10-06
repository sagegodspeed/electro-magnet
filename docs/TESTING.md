# Testing

## Core tests

```sh
zsh Tools/test.sh
```

Recorded local verification on 2026-10-05: 16 core tests passed. Coverage includes layout persistence and CRUD, corrupt/future-format preservation, failed writes, changed browser titles, duplicate/ambiguous matches, process identity reuse, missing windows, disconnected-monitor geometry and minimum-size visibility.

On 2026-10-06, all 36 core tests passed. Added regression cases cover Chrome/Edge profiles after relaunch and tab changes, identical URLs in different profiles, duplicate profile/account windows, account hints from open browser tabs, changed Outlook folders and Teams banners, Gemini conversation changes, legacy layout decoding and context persistence. No geometry or list-order fallback is used. The test scratch directory is outside Documents to prevent file-provider Finder metadata from invalidating signed XCTest bundles.

## Disposable live tests

`Tools/TestWindows.swift` creates two ordinary windows and an unsupported panel in a separate fixture app. `Tools/SpaceProbe.swift` is a standalone feasibility probe. The app's `--integration-test` mode accepts only a PID whose bundle identifier is `com.jeremyscott.ElectroMagnet.Fixture`, restricts inventory to that PID, and writes test layouts to the supplied evidence directory.

Build with `zsh Tools/build-fixture.sh`, then launch the fixture with absolute paths for a state JSON file and a command file. Start Electro Magnet test mode with `--integration-test PID EVIDENCE_DIRECTORY`. The fixture and app need a live macOS desktop session, and Electro Magnet must have its own Accessibility approval. This test mode moves and resizes disposable windows; use it only with the fixture.

Launch the fixture through macOS application services so its process launch date is available. Without arguments it uses `/private/tmp/electromagnet-fixture/fixture-state.json` and `fixture-command`, making that directory suitable for the integration evidence. Direct execution from a shell can omit the launch date and is not equivalent to a normal GUI launch.

Recorded local verification on 2026-10-05: eight integration checks passed on macOS 27 / Apple Silicon. They covered two-monitor capture, inactive-Space capture, restoration after reloading the store/engine and changing titles, switching layouts, a missing window, application minimum sizes, simulated missing-monitor fallback, and returning to the remembered destination. Geometry and Space assignment were read back.

On 2026-10-06, all 11 disposable integration checks passed. Three added checks verify ambiguous matches remain unmoved, a closed application gets a specific reason, and minimized windows get a specific reason. Cross-display Space transitions now wait for macOS to finish translating window coordinates before the next resize; the fixture's original geometry restored exactly.

The same update matched 16 of 19 windows in an existing local layout using read-only live diagnostics. The remaining three were a closed application, an application exposing no ordinary window and an inaccessible browser profile. This verifies discovery and matching, rather than movement of those working windows. The saved layout remained byte-for-byte unchanged. Machine-specific titles and account names are not included here.

Reloading a store and engine inside a test process does not replace a complete menu-driven quit/relaunch test. The developer also reports successful use of the working utility; a broad compatibility matrix is not claimed. Machine-specific raw evidence and saved layouts are excluded from this repository.

## Physical acceptance

Before a general-public release, check:

1. Arrange representative apps and browsers with Magnet across two monitors and several Spaces; remember, move and restore them.
2. Switch between two saved layouts.
3. Quit and relaunch the utility, then restore still-open windows.
4. Physically disconnect/reconnect a monitor and verify fallback visibility and original destinations.
5. Exercise display sleep/wake and confirm Magnet works before and after Restore.
6. Include changed/duplicate browser titles, missing windows, minimum sizes and denied/revoked Accessibility permission.

The icon has been compiled into ICNS, unpacked and checked at all ten standard sizes. Resource/Info.plist packaging and strict signing were verified in an isolated copy of the previously tested executable. The artwork update did not change Swift source. Xcode's license prompt initially blocked a fresh build on 2026-10-06; a later build using the separately installed Command Line Tools passed. The installed working app was not replaced.

For the 0.1.1 matching fix, Xcode subsequently became available and a fresh build and XCTest run passed. App and fixture signing now use temporary staging folders outside file-provider directories. The update was installed at the stable local Applications path with a backup of the previous app, strict signature verification and renewed Accessibility approval. Installed read-only diagnostics confirmed the same 16 matches; saved layouts remained unchanged. The user's working windows were not moved during this verification.

## Read-only local diagnostics

Run the app executable with `--diagnose-layout LAYOUT_NAME OUTPUT_FILE` to inspect matches without moving windows or saving the layout. The output contains private window titles, document identifiers and account hints, and is written with owner-only permissions. Keep it local and redact it before sharing; raw diagnostic exports are not release assets.

## Release privacy checks

On 2026-10-06, the preview download was replaced after its debug symbol metadata was found to include local build paths. The cleanup removed those paths; all 33 loaded Mach-O sections, including executable code, remained byte-for-byte identical. The replacement ZIP was downloaded from GitHub and checked for archive integrity, matching SHA-256, strict code signing, local home-directory paths and credential patterns. Saved layouts and raw machine-specific test records are excluded.

`Tools/build-app.sh` now strips debug metadata before signing and refuses to package an executable that still contains local home-directory paths. A fresh build passed this check and strict signature validation. Normal copyright attribution, the app identifier and public GitHub identity remain public metadata.
