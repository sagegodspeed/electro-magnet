# Compatibility and distribution

## Supported behavior

The current live verification is macOS 27.0 on Apple Silicon, with two displays, multiple ordinary desktop Spaces, separate Spaces per display and SIP enabled. The Swift package targets macOS 14+, but a deployment target does not establish full runtime compatibility. Earlier macOS versions have not been acceptance-tested.

The window geometry and UI use AppKit and Accessibility. Display identity uses UUIDs. Space topology and assignment, window ID lookup, and inactive-Space root discovery use dynamically resolved private APIs. These can change between macOS releases. Unsupported operations and windows are reported rather than silently treated as restored.

Space restoration requires `SLSBridgedMoveWindowsToManagedSpaceOperation`. If it is unavailable, windows that need a Space change are skipped. There is no SIP change, injected scripting addition, privileged helper, or Screen Recording requirement.

Space matching prefers a surviving UUID, then a session ID when no UUID was saved and the boot session is unchanged. If the identity is gone, Restore uses the saved ordinary-desktop position on the original monitor. This is reported as adjusted and leaves the saved assignment intact. If that position or monitor is missing, an available Space is used. No desktop is created or reordered. Manual desktop reordering can change the meaning of a position; surviving UUIDs still take priority.

Public Accessibility lists can omit inactive-Space windows. The app combines bounded root discovery with a read-only cache as the user visits Spaces. Some browser windows still need their Space visited once after launching the app. Last Result reports omissions. The reported uninspected count may include backing windows and should not be interpreted as an exact count of missing ordinary windows.

## Mac App Store

This implementation is not eligible for normal Mac App Store submission. Apple requires public APIs and sandboxing for new store apps. Accessibility client APIs used to control other applications are unsupported inside App Sandbox, independently of the private Space APIs. Removing Space restoration alone does not resolve that conflict.

See [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and [Apple's window-manager distribution guidance](https://developer.apple.com/forums/thread/805556). Some older store apps predate the sandbox requirement; their presence does not establish eligibility for a new app. No App Store submission or exception has been obtained.

## GitHub releases

The initial download is a development preview for Apple Silicon. It is ad-hoc signed and is not Developer ID–signed or notarized. macOS Gatekeeper may prevent a downloaded copy from opening. The project does not recommend disabling Gatekeeper or SIP. Developers can build from source using their own local setup.

A general-public binary release should use Developer ID signing, hardened runtime, a secure timestamp and Apple notarization, with the ticket stapled to the distribution package. See [Developer ID signing](https://developer.apple.com/developer-id/) and [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Ad-hoc rebuilds change the app signature and can invalidate an earlier Accessibility approval. Keep the app at a stable location and renew only its own permission entry through System Settings if necessary.

If the switch is enabled but the menu-bar app still reports missing permission, remove only Electro Magnet's stale entry, add the installed app again, and relaunch it. Verify Restore is enabled in the menu. A terminal-launched diagnostic process does not establish permission for the separate menu-bar process.
