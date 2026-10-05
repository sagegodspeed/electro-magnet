# Testing

## Core tests

```sh
zsh Tools/test.sh
```

Recorded local verification on 2026-10-05: 16 core tests passed. Coverage includes layout persistence and CRUD, corrupt/future-format preservation, failed writes, changed browser titles, duplicate/ambiguous matches, process identity reuse, missing windows, disconnected-monitor geometry and minimum-size visibility.

## Disposable live tests

`Tools/TestWindows.swift` creates two ordinary windows and an unsupported panel in a separate fixture app. `Tools/SpaceProbe.swift` is a standalone feasibility probe. The app's `--integration-test` mode accepts only a PID whose bundle identifier is `com.jeremyscott.ElectroMagnet.Fixture`, restricts inventory to that PID, and writes test layouts to the supplied evidence directory.

Build with `zsh Tools/build-fixture.sh`, then launch the fixture with absolute paths for a state JSON file and a command file. Start Electro Magnet test mode with `--integration-test PID EVIDENCE_DIRECTORY`. The fixture and app need a live macOS desktop session, and Electro Magnet must have its own Accessibility approval. This test mode moves and resizes disposable windows; use it only with the fixture.

Recorded local verification on 2026-10-05: eight integration checks passed on macOS 27 / Apple Silicon. They covered two-monitor capture, inactive-Space capture, restoration after reloading the store/engine and changing titles, switching layouts, a missing window, application minimum sizes, simulated missing-monitor fallback, and returning to the remembered destination. Geometry and Space assignment were read back.

Reloading a store and engine inside a test process does not replace a complete menu-driven quit/relaunch test. The developer also reports successful use of the working utility; a broad compatibility matrix is not claimed. Machine-specific raw evidence and saved layouts are excluded from this repository.

## Physical acceptance

Before a general-public release, check:

1. Arrange representative apps and browsers with Magnet across two monitors and several Spaces; remember, move and restore them.
2. Switch between two saved layouts.
3. Quit and relaunch the utility, then restore still-open windows.
4. Physically disconnect/reconnect a monitor and verify fallback visibility and original destinations.
5. Exercise display sleep/wake and confirm Magnet works before and after Restore.
6. Include changed/duplicate browser titles, missing windows, minimum sizes and denied/revoked Accessibility permission.

The icon has been compiled into ICNS, unpacked and checked at all ten standard sizes. Resource/Info.plist packaging and strict signing were verified in an isolated copy of the previously tested executable. The artwork update did not change Swift source. A fresh local Swift build on 2026-10-06 was blocked by an unaccepted Xcode license; the installed working app was not replaced.
